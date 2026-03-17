// lib/src/tree_sitter/ts_semantic.dart
//
// Higher-level semantic operations powered by tree-sitter:
//   • expandSelection  — grow selection to enclosing syntax node
//   • extractSymbols   — list functions/classes/variables in file
//   • extractErrors    — syntax error positions as DiagnosticRegions
//
// These run on the main thread synchronously (fast enough: < 2ms).

export 'ts_semantic_stub.dart'
    if (dart.library.ffi) 'ts_semantic_impl.dart';
