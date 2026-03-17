// lib/src/tree_sitter/ts_semantic_stub.dart
import '../core/char_position.dart';
import '../diagnostics/diagnostic_region.dart';
import 'ts_symbol.dart';

/// Stub — returns empty results on platforms without dart:ffi.
class TsSemantic {
  const TsSemantic._();

  static (int, int, int, int)? expandSelection(
      String source, String langName,
      int startLine, int startCol, int endLine, int endCol) => null;

  static List<TsSymbol> extractSymbols(String source, String langName) => const [];

  static List<DiagnosticRegion> extractDiagnostics(
      String source, String langName) => const [];
}
