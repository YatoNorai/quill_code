// lib/src/highlighting/isolate_tokenizer_stub.dart
//
// Web stub: dart:isolate not available on web.
// Mirrors the IsolateTokenizer.shared singleton API from the real impl.
// Tokenization runs synchronously on the main thread in small chunks.

import 'dart:async';
import 'span.dart';
import 'code_block.dart';

typedef SpansCallback  = void Function(int version, List<List<CodeSpan>> spans, bool isFinal, int upTo);
typedef BlocksCallback = void Function(int version, List<CodeBlock> blocks);

class _ManagerEntry {
  final SpansCallback  onSpans;
  final BlocksCallback onBlocks;
  String  langName = '';
  List<Map<String, dynamic>> rules   = const [];
  Map<String, int>           wordMap = const {};
  int currentVersion = -1;
  bool destroyed = false;

  _ManagerEntry({required this.onSpans, required this.onBlocks});
}

class IsolateTokenizer {
  static final IsolateTokenizer shared = IsolateTokenizer._();
  IsolateTokenizer._();

  final Map<String, _ManagerEntry> _managers = {};
  int _nextId = 0;

  String registerManager({
    required SpansCallback  onSpans,
    required BlocksCallback onBlocks,
  }) {
    final id = (_nextId++).toString();
    _managers[id] = _ManagerEntry(onSpans: onSpans, onBlocks: onBlocks);
    return id;
  }

  void unregisterManager(String managerId) {
    _managers[managerId]?.destroyed = true;
    _managers.remove(managerId);
  }

  void setRules(String managerId, String langName,
      List<Map<String, dynamic>> rules, Map<String, int> wordMap) {
    final entry = _managers[managerId];
    if (entry == null) return;
    entry.langName = langName;
    entry.rules    = rules;
    entry.wordMap  = wordMap;
  }

  Future<void> tokenize(String managerId, List<String> lines, int version) async {
    final entry = _managers[managerId];
    if (entry == null) return;
    entry.currentVersion = version;

    await Future.delayed(Duration.zero);
    if (_managers[managerId] == null || entry.currentVersion != version) return;

    final compiled = entry.rules
        .map((r) => (RegExp(r['p'] as String), TokenType.values[r['t'] as int]))
        .toList();

    const chunkSize = 100;
    final spans = <List<CodeSpan>>[];
    for (int i = 0; i < lines.length; i++) {
      spans.add(_tokenizeLine(lines[i], compiled, entry.wordMap));
      if (i % chunkSize == chunkSize - 1) {
        final e = _managers[managerId];
        if (e == null || e.currentVersion != version) return;
        e.onSpans(version, List.unmodifiable(spans), false, i);
        await Future.delayed(Duration.zero);
      }
    }
    final e = _managers[managerId];
    if (e == null || e.currentVersion != version) return;
    final blocks = _extractBlocks(lines);
    e.onBlocks(version, blocks);
    e.onSpans(version, List.unmodifiable(spans), true, -1);
  }

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
    final blocks = <CodeBlock>[];
    final stack  = <(int, int)>[];
    for (int i = 0; i < lines.length; i++) {
      final ln = lines[i];
      int indent = 0;
      while (indent < ln.length && (ln[indent] == ' ' || ln[indent] == '\t')) indent++;
      for (int ci = 0; ci < ln.length; ci++) {
        if (ln[ci] == '{') stack.add((i, indent));
        if (ln[ci] == '}' && stack.isNotEmpty) {
          final (sl, si) = stack.removeLast();
          if (i > sl) blocks.add(CodeBlock(startLine: sl, endLine: i, indent: si));
        }
      }
    }
    return blocks;
  }
}
