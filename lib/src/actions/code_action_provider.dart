// lib/src/actions/code_action_provider.dart
// Generates context-aware quick actions based on cursor position + language.
import 'code_action.dart';
import 'symbol_analyzer.dart';
import '../core/char_position.dart';
import '../text/content.dart';
import '../text/text_range.dart';
import '../completion/vscode_snippets.dart';

class CodeActionProvider {
  /// Build all available actions for the current cursor position.
  static List<CodeAction> actionsAt({
    required Content content,
    required CharPosition position,
    required String languageName,
    required bool hasSelection,
    required EditorRange? selectionRange,
  }) {
    final actions = <CodeAction>[];
    if (position.line >= content.lineCount) return actions;

    final line    = content.getLineText(position.line);
    final trimmed = line.trimLeft();
    final isEmpty = trimmed.isEmpty;

    // ── 1. Selection-based actions ─────────────────────────────────────────
    if (hasSelection && selectionRange != null) {
      final selText = content.getTextInRange(selectionRange);
      actions.addAll(_selectionActions(selText, selectionRange, languageName));
    }

    // ── 2. Line-level structural actions ──────────────────────────────────
    if (!isEmpty) {
      actions.addAll(_lineActions(content, position, line, trimmed, languageName));
    }

    // ── 3. Language-specific snippet actions ──────────────────────────────
    final word = SymbolAnalyzer.wordAt(content, position) ?? '';
    actions.addAll(_snippetActions(word, languageName));

    // ── 4. Symbol-level actions (class / function under cursor) ───────────
    final sym = SymbolAnalyzer.symbolInfoAt(content, position);
    if (sym != null) {
      actions.addAll(_symbolActions(content, sym));
    }

    // ── 5. Import / surround actions ──────────────────────────────────────
    if (hasSelection && selectionRange != null) {
      actions.addAll(_surroundActions(content, selectionRange, languageName));
    }

    return actions;
  }

  // ── Selection actions ─────────────────────────────────────────────────────
  static List<CodeAction> _selectionActions(
      String selText, EditorRange sel, String lang) {
    final a = <CodeAction>[];
    // Convert case
    a.add(CodeAction(
      title: 'MAIÚSCULAS',
      kind: CodeActionKind.refactor,
      description: 'Converter seleção para maiúsculas',
      edits: [CodeActionEdit(range: sel, newText: selText.toUpperCase())],
    ));
    a.add(CodeAction(
      title: 'minúsculas',
      kind: CodeActionKind.refactor,
      description: 'Converter seleção para minúsculas',
      edits: [CodeActionEdit(range: sel, newText: selText.toLowerCase())],
    ));
    // Comment out
    final isMultiline = sel.start.line != sel.end.line;
    if (isMultiline) {
      final commentChar = _commentChar(lang);
      a.add(CodeAction(
        title: 'Comentar linhas',
        kind: CodeActionKind.refactor,
        description: 'Adicionar $commentChar a cada linha',
        edits: _commentEdits(selText, sel, commentChar),
      ));
    }
    // Trim whitespace
    if (selText != selText.trim()) {
      a.add(CodeAction(
        title: 'Remover espaços extras',
        kind: CodeActionKind.quickFix,
        edits: [CodeActionEdit(range: sel, newText: selText.trim())],
      ));
    }
    return a;
  }

  // ── Line actions ──────────────────────────────────────────────────────────
  static List<CodeAction> _lineActions(Content content, CharPosition pos,
      String line, String trimmed, String lang) {
    final a = <CodeAction>[];
    final lineRange = EditorRange(
      CharPosition(pos.line, 0),
      CharPosition(pos.line, line.length),
    );

    // Remove trailing whitespace
    if (line.endsWith(' ') || line.endsWith('\t')) {
      a.add(CodeAction(
        title: 'Remover espaços finais',
        kind: CodeActionKind.quickFix,
        edits: [CodeActionEdit(range: lineRange, newText: line.trimRight())],
      ));
    }

    // Dart: add const keyword
    if ((lang.toLowerCase().contains('dart')) &&
        (trimmed.startsWith('final ') || trimmed.startsWith('  final '))) {
      final indentLen = line.length - line.trimLeft().length;
      final newLine = line.substring(0, indentLen) + 'const ' +
          line.trimLeft().replaceFirst('final ', '');
      a.add(CodeAction(
        title: 'Adicionar const',
        kind: CodeActionKind.quickFix,
        description: 'Substituir final por const',
        edits: [CodeActionEdit(range: lineRange, newText: newLine)],
      ));
    }

    // Dart: wrap with widget
    if (lang.toLowerCase().contains('dart')) {
      a.add(CodeAction(
        title: 'Envolver com Padding',
        kind: CodeActionKind.refactor,
        description: 'Envolver linha atual com Padding widget',
        edits: [CodeActionEdit(
          range: lineRange,
          newText: _wrapWith('Padding', 'padding: const EdgeInsets.all(8.0)', line, trimmed),
        )],
      ));
      a.add(CodeAction(
        title: 'Envolver com Center',
        kind: CodeActionKind.refactor,
        description: 'Envolver com Center widget',
        edits: [CodeActionEdit(
          range: lineRange,
          newText: _wrapWith('Center', null, line, trimmed),
        )],
      ));
      a.add(CodeAction(
        title: 'Envolver com SizedBox',
        kind: CodeActionKind.refactor,
        edits: [CodeActionEdit(
          range: lineRange,
          newText: _wrapWith('SizedBox', 'width: double.infinity', line, trimmed),
        )],
      ));
      a.add(CodeAction(
        title: 'Envolver com Container',
        kind: CodeActionKind.refactor,
        edits: [CodeActionEdit(
          range: lineRange,
          newText: _wrapWith('Container', null, line, trimmed),
        )],
      ));
    }

    // JS/TS: add async
    if ((lang.toLowerCase().contains('javascript') ||
         lang.toLowerCase().contains('typescript')) &&
        trimmed.startsWith('function ') && !trimmed.startsWith('async ')) {
      a.add(CodeAction(
        title: 'Tornar async',
        kind: CodeActionKind.refactor,
        edits: [CodeActionEdit(
          range: lineRange,
          newText: line.replaceFirst('function ', 'async function '),
        )],
      ));
    }

    return a;
  }

  // ── Snippet actions ───────────────────────────────────────────────────────
  static List<CodeAction> _snippetActions(String word, String lang) {
    final snippets = VsCodeSnippets.forLanguage(lang);
    return snippets
      .where((s) => word.isEmpty || s.prefix.startsWith(word) || word.isEmpty)
      .take(6)
      .map((s) => CodeAction(
        title: '⚡ ${s.prefix}',
        description: s.description,
        kind: CodeActionKind.snippet,
        // body will be inserted via callback — stored as custom data
        edits: [], // handled specially via isSnippet
      ))
      .toList();
  }

  // ── Symbol actions ────────────────────────────────────────────────────────
  static List<CodeAction> _symbolActions(Content content, SymbolInfo sym) {
    final a = <CodeAction>[];
    if (sym.kind == SymbolKind.class_) {
      a.add(CodeAction(
        title: 'Ir para definição de ${sym.name}',
        kind: CodeActionKind.navigate,
        description: 'Linha ${sym.definedAtLine + 1}',
        edits: [],
      ));
      a.add(CodeAction(
        title: 'Renomear ${sym.name}',
        kind: CodeActionKind.refactor,
        description: 'Renomear todas as ocorrências',
        edits: [],
      ));
    }
    return a;
  }

  // ── Surround actions ──────────────────────────────────────────────────────
  static List<CodeAction> _surroundActions(
      Content content, EditorRange sel, String lang) {
    final a = <CodeAction>[];
    final selText = content.getTextInRange(sel);
    final indent  = _detectIndent(selText);

    if (lang.toLowerCase().contains('dart')) {
      a.add(CodeAction(
        title: 'Envolver seleção com if',
        kind: CodeActionKind.surroundWith,
        edits: [CodeActionEdit(
          range: sel,
          newText: 'if (\${1:condition}) {\n$indent$selText\n}',
        )],
      ));
      a.add(CodeAction(
        title: 'Envolver seleção com try/catch',
        kind: CodeActionKind.surroundWith,
        edits: [CodeActionEdit(
          range: sel,
          newText: 'try {\n$indent$selText\n} catch (e) {\n${indent}print(e);\n}',
        )],
      ));
    } else {
      a.add(CodeAction(
        title: 'Envolver com bloco try/catch',
        kind: CodeActionKind.surroundWith,
        edits: [CodeActionEdit(
          range: sel,
          newText: 'try {\n$indent$selText\n} catch (e) {\n${indent}console.error(e);\n}',
        )],
      ));
    }
    return a;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static String _commentChar(String lang) {
    final l = lang.toLowerCase();
    if (l.contains('python') || l.contains('ruby') || l.contains('bash')) return '#';
    if (l.contains('html') || l.contains('xml')) return '<!--';
    if (l.contains('css')) return '/*';
    return '//';
  }

  static List<CodeActionEdit> _commentEdits(
      String text, EditorRange sel, String char) {
    final lines = text.split('\n');
    final newLines = lines.map((l) => '$char $l').join('\n');
    return [CodeActionEdit(range: sel, newText: newLines)];
  }

  static String _wrapWith(String widget, String? extra, String line, String trimmed) {
    final indent = line.substring(0, line.length - line.trimLeft().length);
    final inner  = '$indent  child: $trimmed,';
    final extraLine = extra != null ? '\n$indent  $extra,' : '';
    return '$indent$widget($extraLine\n$inner\n$indent)';
  }

  static String _detectIndent(String text) {
    for (final line in text.split('\n')) {
      if (line.isNotEmpty) {
        int i = 0;
        while (i < line.length && (line[i] == ' ' || line[i] == '\t')) i++;
        if (i > 0) return line.substring(0, i);
      }
    }
    return '  ';
  }
}
