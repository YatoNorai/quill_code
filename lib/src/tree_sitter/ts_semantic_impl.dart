// lib/src/tree_sitter/ts_semantic_impl.dart
//
// Semantic operations: expand selection, symbol extraction, syntax diagnostics.
// All operations work through a shared per-language TsParser cache.

import '../core/char_position.dart';
import '../diagnostics/diagnostic_region.dart';
import '../text/text_range.dart';
import 'ts_parser.dart';
import 'ts_symbol.dart';

// ── Parser cache ──────────────────────────────────────────────────────────────
// One TsParser per language, lazily created, source kept updated.

class _CachedParser {
  final TsParser parser;
  int _cachedHash = 0;
  _CachedParser(this.parser);

  /// Parse [source] only if it changed since last call.
  void ensureParsed(String source) {
    final h = source.hashCode;
    if (h != _cachedHash) {
      parser.parseString(source);
      _cachedHash = h;
    }
  }
}

final _parsers = <String, _CachedParser>{};

_CachedParser? _getParser(String langName) {
  var cp = _parsers[langName];
  if (cp == null) {
    final p = TsParser.create(langName);
    if (p == null) return null;
    cp = _CachedParser(p);
    _parsers[langName] = cp;
  }
  return cp;
}

// ─────────────────────────────────────────────────────────────────────────────

class TsSemantic {
  const TsSemantic._();

  // ── Expand selection ─────────────────────────────────────────────────────────
  //
  // Given the current selection (startLine, startCol, endLine, endCol),
  // returns the next-larger enclosing node's range, or null if already at root.
  //
  // Returns (startLine, startCol, endLine, endCol) in 0-based line/col.
  //
  // Call repeatedly to keep expanding: word → expression → statement → block → ...

  static (int, int, int, int)? expandSelection(
      String source, String langName,
      int startLine, int startCol, int endLine, int endCol) {
    final cp = _getParser(langName);
    if (cp == null) return null;
    cp.ensureParsed(source);
    return cp.parser.expandSelection(source, startLine, startCol, endLine, endCol);
  }

  // ── Symbol extraction ─────────────────────────────────────────────────────────
  //
  // Walks the tree and collects named declarations.

  static List<TsSymbol> extractSymbols(String source, String langName) {
    final cp = _getParser(langName);
    if (cp == null) return const [];
    cp.ensureParsed(source);
    return cp.parser.extractSymbols(source);
  }

  // ── Syntax diagnostics ────────────────────────────────────────────────────────
  //
  // Returns ERROR and MISSING nodes as DiagnosticRegion(severity: error).

  static List<DiagnosticRegion> extractDiagnostics(
      String source, String langName) {
    final cp = _getParser(langName);
    if (cp == null) return const [];
    cp.ensureParsed(source);
    final errors = cp.parser.extractErrors();

    final lineStarts = _buildLineStarts(source);
    final result = <DiagnosticRegion>[];
    for (final (startByte, endByte) in errors) {
      final sLC = _byteToLC(startByte, lineStarts);
      final eLC = _byteToLC(endByte.clamp(startByte, endByte), lineStarts);
      result.add(DiagnosticRegion(
        range: EditorRange(
          CharPosition(sLC.$1, sLC.$2),
          CharPosition(eLC.$1, eLC.$2),
        ),
        severity: DiagnosticSeverity.error,
        message:  'Syntax error',
        source:   'tree-sitter',
      ));
    }
    return result;
  }

  // ── Byte helpers ─────────────────────────────────────────────────────────────

  static List<int> _buildLineStarts(String src) {
    final starts = <int>[0];
    int byte = 0;
    for (int i = 0; i < src.length; i++) {
      final c = src.codeUnitAt(i);
      if (c <= 0x7F)               { byte++; }
      else if (c <= 0x7FF)          { byte += 2; }
      else if (c >= 0xD800 && c <= 0xDBFF) { byte += 4; i++; }
      else                          { byte += 3; }
      if (c == 0x0A) starts.add(byte);
    }
    return starts;
  }

  static (int, int) _byteToLC(int byte, List<int> starts) {
    int lo = 0, hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= byte) lo = mid; else hi = mid - 1;
    }
    return (lo, byte - starts[lo]);
  }
}
