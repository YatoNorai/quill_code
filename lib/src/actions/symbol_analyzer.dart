// lib/src/actions/symbol_analyzer.dart
// Extracts symbol info and definition locations from the current document.
// Purely regex-based (no AST), works offline.
import 'code_action.dart';
import '../native/quill_native.dart';
import '../core/char_position.dart';
import '../text/content.dart';
import '../text/text_range.dart';

class SymbolAnalyzer {
  // ── Declaration patterns ─────────────────────────────────────────────────
  static final _classRx    = RegExp(r'\b(class|mixin|extension|enum)\s+(\w+)');
  static final _funcRx     = RegExp(r'\b(\w[\w<>, ]*)\s+(\w+)\s*\(');
  static final _varRx      = RegExp(r'\b(?:final|var|late|const|static)\s+(?:[\w<>, ]+\s+)?(\w+)\s*[=;]');

  /// Find the word token under [position] and return its range.
  static EditorRange? wordRangeAt(Content content, CharPosition position) {
    if (position.line >= content.lineCount) return null;
    final line = content.getLineText(position.line);
    final col  = position.column.clamp(0, line.length);
    if (col >= line.length) return null;
    if (!_isWord(line.codeUnitAt(col))) return null;
    int start = col, end = col + 1;
    while (start > 0 && _isWord(line.codeUnitAt(start - 1))) start--;
    while (end < line.length && _isWord(line.codeUnitAt(end))) end++;
    return EditorRange(
      CharPosition(position.line, start),
      CharPosition(position.line, end),
    );
  }

  /// Get the word token text at [position].
  static String? wordAt(Content content, CharPosition position) {
    final r = wordRangeAt(content, position);
    if (r == null) return null;
    return content.getTextInRange(r);
  }

  /// Scan the document and find all top-level symbol declarations.
  static List<SymbolInfo> extractSymbols(Content content) {
    // Try Rust path: pure string scan, no regex engine
    final native = QuillNative.symbolScan(content);
    if (native != null) {
      return native.map((q) {
        final li = q[0]; final cs = q[1]; final ce = q[2]; final kind = q[3];
        final line = content.getLineText(li);
        final name = line.substring(cs.clamp(0, line.length), ce.clamp(0, line.length));
        final sk = kind == 0 ? SymbolKind.class_
                 : kind == 1 ? SymbolKind.mixin_
                 : kind == 2 ? SymbolKind.extension_
                 : kind == 3 ? SymbolKind.enum_
                 : kind == 4 ? SymbolKind.function_
                 :              SymbolKind.variable;
        return SymbolInfo(
          name: name, kind: sk,
          nameRange: EditorRange(CharPosition(li, cs), CharPosition(li, ce)),
          definedAtLine: li,
          signature: line.trim(),
        );
      }).toList();
    }
    // Dart fallback (regex-based)
    final results = <SymbolInfo>[];
    for (int i = 0; i < content.lineCount; i++) {
      final line = content.getLineText(i);
      // Class / mixin / enum / extension
      final cm = _classRx.firstMatch(line);
      if (cm != null) {
        final keyword = cm.group(1)!;
        final name    = cm.group(2)!;
        final col     = cm.start + keyword.length + 1;
        final kind = keyword == 'class'     ? SymbolKind.class_
                   : keyword == 'mixin'     ? SymbolKind.mixin_
                   : keyword == 'extension' ? SymbolKind.extension_
                   :                          SymbolKind.enum_;
        results.add(SymbolInfo(
          name: name, kind: kind,
          nameRange: EditorRange(CharPosition(i, col), CharPosition(i, col + name.length)),
          definedAtLine: i,
          signature: line.trim(),
        ));
        continue;
      }
      // Functions / methods (heuristic: non-blank line with () not inside class body)
      final fm = _funcRx.firstMatch(line);
      if (fm != null && !line.trimLeft().startsWith('//') && !line.contains('=')) {
        final name = fm.group(2)!;
        if (name.length > 2 && !_keywords.contains(name)) {
          final col = fm.start + (fm.group(1)?.length ?? 0) + 1;
          results.add(SymbolInfo(
            name: name, kind: SymbolKind.function_,
            nameRange: EditorRange(CharPosition(i, col), CharPosition(i, col + name.length)),
            definedAtLine: i,
            signature: line.trim().length > 80 ? line.trim().substring(0, 80) + '…' : line.trim(),
          ));
        }
      }
    }
    return results;
  }

  /// Find the definition line of [word] within the document.
  /// Returns the line index or -1.
  static int findDefinitionLine(Content content, String word) {
    // Look for class/mixin/enum/extension declaration
    final declRx = RegExp(r'\b(?:class|mixin|extension|enum)\s+' + RegExp.escape(word) + r'\b');
    for (int i = 0; i < content.lineCount; i++) {
      if (declRx.hasMatch(content.getLineText(i))) return i;
    }
    // Look for function declaration
    final funcRx = RegExp(r'\b' + RegExp.escape(word) + r'\s*\(');
    for (int i = 0; i < content.lineCount; i++) {
      final line = content.getLineText(i);
      if (funcRx.hasMatch(line) && !line.trimLeft().startsWith('//')) return i;
    }
    // Variable / field declaration
    final varRx = RegExp(r'\b(?:final|var|late|const)\s+[\w<>?, ]*\b' + RegExp.escape(word) + r'\s*[=;]');
    for (int i = 0; i < content.lineCount; i++) {
      if (varRx.hasMatch(content.getLineText(i))) return i;
    }
    return -1;
  }

  /// Get SymbolInfo for the word at [position], if it matches a declaration.
  static SymbolInfo? symbolInfoAt(Content content, CharPosition position) {
    final word = wordAt(content, position);
    if (word == null || word.length < 2) return null;
    final symbols = extractSymbols(content);
    // Find symbol whose name matches and whose nameRange contains position
    for (final s in symbols) {
      if (s.name == word && s.nameRange.start.line == position.line) {
        return s;
      }
    }
    // Also check if word is just used (not declared here) but declared elsewhere
    final defLine = findDefinitionLine(content, word);
    if (defLine >= 0) {
      // Find the symbol at that definition line
      for (final s in symbols) {
        if (s.name == word && s.definedAtLine == defLine) return s;
      }
    }
    return null;
  }

  static bool _isWord(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95;

  static const _keywords = {
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'return',
    'break', 'continue', 'new', 'this', 'super', 'null', 'true', 'false',
    'var', 'final', 'const', 'late', 'void', 'int', 'double', 'bool',
    'String', 'List', 'Map', 'Set', 'dynamic', 'Object', 'import', 'export',
    'function', 'let', 'def', 'self', 'print', 'async', 'await',
  };
}
