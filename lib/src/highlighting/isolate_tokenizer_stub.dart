// lib/src/highlighting/isolate_tokenizer_stub.dart
//
// Web stub: dart:isolate not available on web.
// Runs tokenization synchronously on the main thread (small files only).
// For large files on web, only the visible region is tokenized.

import 'dart:async';
import 'span.dart';
import 'code_block.dart';
import '../language/_regex_language.dart';

typedef SpansCallback  = void Function(int version, List<List<CodeSpan>> spans, bool isFinal, int upTo);
typedef BlocksCallback = void Function(int version, List<CodeBlock> blocks);

class IsolateTokenizer {
  final SpansCallback  onSpans;
  final BlocksCallback onBlocks;

  List<Map<String, dynamic>> _rules = const [];
  Map<String, int>           _wordMap = const {};
  bool _destroyed = false;

  IsolateTokenizer({required this.onSpans, required this.onBlocks});

  void setRules(List<Map<String, dynamic>> rules, Map<String, int> wordMap) {
    _rules   = rules;
    _wordMap = wordMap;
  }

  Future<void> tokenize(List<String> lines, int version) async {
    if (_destroyed) return;

    // Yield to allow the UI to paint before we do synchronous work.
    await Future.delayed(Duration.zero);
    if (_destroyed) return;

    // Build compiled rules from the payload map.
    final compiled = _rules
        .map((r) => (
              RegExp(r['p'] as String),
              TokenType.values[r['t'] as int]
            ))
        .toList();

    // Tokenize in chunks so the event loop gets slots between chunks.
    const chunkSize = 100;
    final spans = <List<CodeSpan>>[];
    for (int i = 0; i < lines.length; i++) {
      spans.add(_tokenizeLine(lines[i], compiled, _wordMap));
      if (i % chunkSize == chunkSize - 1 && !_destroyed) {
        onSpans(version, List.unmodifiable(spans), false, i);
        await Future.delayed(Duration.zero);
        if (_destroyed) return;
      }
    }
    if (!_destroyed) {
      // Extract blocks
      final blocks = _extractBlocks(lines);
      onBlocks(version, blocks);
      onSpans(version, List.unmodifiable(spans), true, -1);
    }
  }

  void destroy() => _destroyed = true;

  static List<CodeSpan> _tokenizeLine(
      String line,
      List<(RegExp, TokenType)> rules,
      Map<String, int> wordMap) {
    if (line.isEmpty) return const [];
    final spans = <CodeSpan>[];
    int pos = 0;
    final len = line.length;
    while (pos < len) {
      bool matched = false;
      for (final (rx, type) in rules) {
        final m = rx.matchAsPrefix(line, pos);
        if (m != null && m.end > pos) {
          spans.add(CodeSpan(column: pos, type: type));
          pos = m.end;
          matched = true;
          break;
        }
      }
      if (!matched) pos++;
    }
    return spans;
  }

  static List<CodeBlock> _extractBlocks(List<String> lines) {
    // Lightweight brace-matching block extractor.
    final blocks = <CodeBlock>[];
    final stack  = <(int line, int indent)>[];
    for (int i = 0; i < lines.length; i++) {
      final ln = lines[i];
      int indent = 0;
      while (indent < ln.length && (ln[indent] == ' ' || ln[indent] == '\t')) {
        indent++;
      }
      for (int ci = 0; ci < ln.length; ci++) {
        if (ln[ci] == '{') stack.add((i, indent));
        if (ln[ci] == '}' && stack.isNotEmpty) {
          final (startLine, startIndent) = stack.removeLast();
          if (i > startLine) {
            blocks.add(CodeBlock(
                startLine: startLine, endLine: i, indent: startIndent));
          }
        }
      }
    }
    return blocks;
  }
}
