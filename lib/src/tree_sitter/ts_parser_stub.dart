// lib/src/tree_sitter/ts_parser_stub.dart
// Stub for platforms without dart:ffi (web). Always returns empty/null.

import '../highlighting/span.dart';
import '../highlighting/code_block.dart';
import 'ts_symbol.dart';

class TsHighlightSpan {
  final int startByte, endByte;
  final TokenType type;
  const TsHighlightSpan(this.startByte, this.endByte, this.type);
}

class TsParser {
  const TsParser._();
  static TsParser? create(String langName) => null;
  bool get hasTree => false;
  bool parseString(String source) => false;
  void editAndReparse({
    required String newSource,
    required int startByte,  required int oldEndByte, required int newEndByte,
    required int startRow,   required int startCol,
    required int oldEndRow,  required int oldEndCol,
    required int newEndRow,  required int newEndCol,
  }) {}
  List<TsHighlightSpan> highlight(String source,
      {int startRow = 0, int endRow = 0x7FFFFFFF}) => const [];
  List<CodeBlock> extractBlocks() => const [];
  List<(int, int)> extractErrors() => const [];
  (int,int,int,int)? expandSelection(
      String src, int sl, int sc, int el, int ec) => null;
  List<TsSymbol> extractSymbols(String src) => const [];
  void dispose() {}
}
