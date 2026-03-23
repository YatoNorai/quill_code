// lib/src/language/_regex_language.dart
import '../native/quill_native.dart';
import '../highlighting/span.dart';
import '../highlighting/analyze_manager.dart';
import '../highlighting/incremental_analyze_manager.dart';
import '../completion/completion_item.dart';
import '../completion/completion_publisher.dart';
import '../completion/vscode_snippets.dart';
import '../core/char_position.dart';
import '../core/symbol_pair.dart';
import '../text/content.dart';
import 'language.dart';

abstract class RegexLanguage extends QuillLanguage {
  List<TokenRule> get rules;
  List<String> get completionKeywords => const [];

  /// Rule payload for the persistent isolate tokenizer.
  /// Serialises [rules] as plain maps so they can cross the isolate boundary.
  List<Map<String, dynamic>> get isolateRulePayload =>
      rules.map((r) => <String, dynamic>{'p': r.pattern.pattern, 't': r.type.index}).toList();

  /// Word → TokenType index map for O(1) keyword/type lookup in the isolate.
  /// Override in subclasses (e.g. DartLanguage) to include language keywords.
  /// Words not in the map fall back to the regex rules in the isolate.
  Map<String, int> get isolateWordMap => const {};

  @override
  AnalyzeManager createAnalyzeManager() =>
      IncrementalAnalyzeManager(language: this);

  @override
  List<List<CodeSpan>> tokenize(List<String> lines) =>
      lines.map(_tokenizeLine).toList();

  List<CodeSpan> _tokenizeLine(String line) {
    if (line.isEmpty) return const [];
    final spans = <CodeSpan>[];
    final len   = line.length;
    int pos = 0;
    while (pos < len) {
      // ── Hot-path: alphanumeric / identifier run ─────────────────────────
      // Identifiers and numbers make up ~60-80% of code characters. Scanning
      // them directly with codeUnitAt is 10-20× faster than trying each regex
      // rule for every character position.
      final c0 = line.codeUnitAt(pos);
      if ((c0 >= 65 && c0 <= 90)  ||  // A-Z
          (c0 >= 97 && c0 <= 122) ||  // a-z
          (c0 >= 48 && c0 <= 57)  ||  // 0-9
          c0 == 95) {                  // _
        // Check if a keyword/built-in rule matches here first.
        bool matched = false;
        for (final rule in rules) {
          final m = rule.pattern.matchAsPrefix(line, pos);
          if (m != null && m.start == pos && m.end > pos) {
            spans.add(CodeSpan(column: pos, type: rule.type));
            pos = m.end;
            matched = true;
            break;
          }
        }
        if (!matched) {
          // No rule matched — consume entire word as a normal token in one shot.
          if (spans.isEmpty || spans.last.type != TokenType.normal) {
            spans.add(CodeSpan(column: pos, type: TokenType.normal));
          }
          pos++;
          while (pos < len) {
            final c = line.codeUnitAt(pos);
            if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
                (c >= 48 && c <= 57) || c == 95) {
              pos++;
            } else {
              break;
            }
          }
        }
        continue;
      }
      // ── Normal path: try each rule ─────────────────────────────────────
      bool matched = false;
      for (final rule in rules) {
        final m = rule.pattern.matchAsPrefix(line, pos);
        if (m != null && m.start == pos && m.end > pos) {
          spans.add(CodeSpan(column: pos, type: rule.type));
          pos = m.end;
          matched = true;
          break;
        }
      }
      if (!matched) {
        if (spans.isEmpty || spans.last.type != TokenType.normal) {
          spans.add(CodeSpan(column: pos, type: TokenType.normal));
        }
        pos++;
      }
    }
    return spans;
  }

  @override
  Future<void> getCompletions(Content content, CharPosition position,
      CompletionPublisher publisher) async {
    final line   = content.getLineText(position.line);
    final prefix = _prefix(line, position.column);
    if (prefix.isEmpty) return;

    for (final kw in completionKeywords) {
      if (kw.startsWith(prefix) && kw != prefix) {
        publisher.addItem(CompletionItem(
            label: kw, kind: CompletionItemKind.keyword, insertText: kw));
      }
    }

    final snippets = VsCodeSnippets.forLanguage(name);
    for (final s in snippets) {
      if (s.prefix.startsWith(prefix)) {
        publisher.addItem(CompletionItem(
          label:     s.prefix,
          detail:    s.description,
          insertText: s.body,
          kind:      CompletionItemKind.snippet,
          isSnippet: true,
        ));
      }
    }
  }

  @override
  int getIndentAdvance(content, line, column) {
    if (line < 0) return 0;
    final t = content.getLineText(line);
    return QuillNative.indentAdvance(t);
  }

  String _prefix(String line, int col) {
    int i = col;
    while (i > 0 && _isWord(line.codeUnitAt(i - 1))) i--;
    return line.substring(i, col);
  }

  bool _isWord(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) || c == 95;
}

class TokenRule {
  final RegExp pattern;
  final TokenType type;
  TokenRule(String pattern, this.type) : pattern = RegExp(pattern);
}
