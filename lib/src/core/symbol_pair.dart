// lib/src/core/symbol_pair.dart

class SymbolPair {
  final String open;
  final String close;

  const SymbolPair(this.open, this.close);
}

class SymbolPairMatch {
  final List<SymbolPair> pairs;

  const SymbolPairMatch(this.pairs);

  static const SymbolPairMatch defaults = SymbolPairMatch([
    SymbolPair('(', ')'),
    SymbolPair('[', ']'),
    SymbolPair('{', '}'),
    SymbolPair('"', '"'),
    SymbolPair("'", "'"),
    SymbolPair('`', '`'),
  ]);

  String? getClosingFor(String open) {
    for (final p in pairs) {
      if (p.open == open) return p.close;
    }
    return null;
  }

  bool isOpenSymbol(String char) =>
      pairs.any((p) => p.open == char);

  bool isCloseSymbol(String char) =>
      pairs.any((p) => p.close == char);
}
