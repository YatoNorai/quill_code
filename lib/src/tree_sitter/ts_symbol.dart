// lib/src/tree_sitter/ts_symbol.dart
/// A named symbol extracted from the tree (function, class, variable…).
class TsSymbol {
  final String   name;
  final TsSymbolKind kind;
  final int      line;   // 0-based
  final int      column; // 0-based

  const TsSymbol({
    required this.name,
    required this.kind,
    required this.line,
    required this.column,
  });

  @override
  String toString() => '$kind $name @ $line:$column';
}

enum TsSymbolKind {
  class_,
  function,
  method,
  variable,
  constant,
  enum_,
  interface,
  struct,
  namespace,
}
