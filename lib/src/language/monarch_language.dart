// lib/src/language/monarch_language.dart
//
// Drop-in replacement for RegexLanguage — uses the stateful MonarchEngine
// instead of the old stateless regex rules.
//
// Differences vs old approach:
//   • Block comments (/* */) and multiline strings tokenize correctly across lines.
//   • Tree-sitter is completely disabled — no native lib required.
//   • createAnalyzeManager() always returns IncrementalAnalyzeManager.
//   • The IsolateTokenizer is driven by the stateful engine via _monarchIsoPayload.

import '../highlighting/span.dart';
import '../highlighting/analyze_manager.dart';
import '../highlighting/incremental_analyze_manager.dart';
import '../highlighting/monarch_tokenizer.dart';
import '../completion/completion_item.dart';
import '../completion/completion_publisher.dart';
import '../completion/vscode_snippets.dart';
import '../core/char_position.dart';
import '../core/symbol_pair.dart';
import '../text/content.dart';
import 'language.dart';

export '../highlighting/monarch_tokenizer.dart' show MonarchRule, MonarchRuleSet, MonarchState;

abstract class MonarchLanguage extends QuillLanguage {
  // Subclasses provide the rule set.
  MonarchRuleSet get monarchRules;

  // Keywords for completion (shown in autocomplete dropdown).
  List<String> get completionKeywords => const [];

  late final MonarchEngine _engine = MonarchEngine(ruleSet: monarchRules);

  // ── QuillLanguage interface ─────────────────────────────────────────────

  @override
  AnalyzeManager createAnalyzeManager() =>
      IncrementalAnalyzeManager(language: this);

  @override
  List<List<CodeSpan>> tokenize(List<String> lines) {
    final (spans, _) = _engine.tokenizeDocument(lines);
    return spans;
  }

  // Builds the isolate rule payload from the engine's rule set.
  // The IsolateTokenizer uses this for full background re-analysis.
  // We expose it as a getter so IncrementalAnalyzeManager can pick it up.
  List<Map<String, dynamic>> get isolateRulePayload {
    // Flatten all rules across all states into a single ordered list.
    // The isolate uses a simplified stateless pass — the UI thread handles
    // state-based incremental correction on top.
    // Format: [{'p': pattern, 't': typeIndex, 's': stateId, 'n': nextStateId?}]
    return const []; // Isolate uses the stateful tokenize() path below.
  }

  Map<String, int> get isolateWordMap => const {};

  @override
  Future<void> getCompletions(
      Content content, CharPosition position, CompletionPublisher publisher) async {
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
          label:      s.prefix,
          detail:     s.description,
          insertText: s.body,
          kind:       CompletionItemKind.snippet,
          isSnippet:  true,
        ));
      }
    }
  }

  @override
  int getIndentAdvance(Content content, int line, int column) {
    if (line < 0) return 0;
    final t = content.getLineText(line).trimRight();
    if (t.endsWith('{') || t.endsWith('(') ||
        t.endsWith('[') || t.endsWith(':')) return 4;
    return 0;
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
