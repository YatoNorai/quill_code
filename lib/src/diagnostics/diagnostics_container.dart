// lib/src/diagnostics/diagnostics_container.dart
//
// Auto-shift strategy (inspired by Sora Editor's DiagnosticsContainer):
//
//  • When lines are inserted, diagnostics BELOW the insert point are shifted
//    down by the number of added lines — squiggles follow their code.
//  • When lines are deleted, diagnostics whose range falls entirely inside
//    the deleted region are removed; the rest are shifted up.
//  • Single-line edits (no newlines) shift column positions on the affected
//    line when the edit is before the diagnostic column.
//  • This means squiggles remain accurate between LSP pushes — no ghost
//    squiggles on wrong lines after typing Enter/Backspace.
import 'diagnostic_region.dart';
import '../core/char_position.dart';
import '../text/text_range.dart';

class DiagnosticsContainer {
  List<DiagnosticRegion> _regions = [];

  List<DiagnosticRegion> get all => List.unmodifiable(_regions);

  bool get hasErrors   => _regions.any((r) => r.severity == DiagnosticSeverity.error);
  bool get hasWarnings => _regions.any((r) => r.severity == DiagnosticSeverity.warning);
  bool get isEmpty     => _regions.isEmpty;

  void setDiagnostics(List<DiagnosticRegion> regions) {
    _regions = List.of(regions)
      ..sort((a, b) => a.range.start.line.compareTo(b.range.start.line));
  }

  void clear() => _regions = [];

  // ── Auto-shift: called from editor controller _shiftLineSets ─────────────

  /// Called when [linesAdded] lines were inserted starting at [atLine+1].
  /// Diagnostics whose startLine is strictly after [atLine] are shifted down.
  void shiftOnInsert(int atLine, int linesAdded) {
    if (_regions.isEmpty || linesAdded <= 0) return;
    _regions = _regions.map((r) {
      if (r.range.start.line > atLine) {
        return _shiftRegion(r, linesAdded);
      }
      return r;
    }).toList();
  }

  /// Called when [linesRemoved] lines were deleted from [atLine+1] to
  /// [atLine+linesRemoved]. Diagnostics inside that range are dropped;
  /// diagnostics below are shifted up.
  void shiftOnDelete(int atLine, int linesRemoved) {
    if (_regions.isEmpty || linesRemoved <= 0) return;
    final delStart = atLine + 1;
    final delEnd   = atLine + linesRemoved;
    final kept = <DiagnosticRegion>[];
    for (final r in _regions) {
      final sl = r.range.start.line;
      // Drop diagnostics whose start is inside the deleted lines
      if (sl >= delStart && sl <= delEnd) continue;
      // Shift diagnostics below the deleted range up
      if (sl > delEnd) {
        kept.add(_shiftRegion(r, -linesRemoved));
      } else {
        kept.add(r);
      }
    }
    _regions = kept;
  }

  /// Called for single-line insert (no newlines): shift columns on [line]
  /// that are at or after [column] by [charDelta] (positive=insert,
  /// negative=delete).
  void shiftColumnsOnLine(int line, int column, int charDelta) {
    if (_regions.isEmpty) return;
    _regions = _regions.map((r) {
      if (r.range.start.line != line) return r;
      final start = r.range.start;
      final end   = r.range.end;
      if (start.column < column) return r; // edit is after diagnostic start
      final newStart = CharPosition(line, (start.column + charDelta).clamp(0, 99999));
      final newEnd   = end.line == line
          ? CharPosition(line, (end.column + charDelta).clamp(newStart.column, 99999))
          : end;
      return DiagnosticRegion(
        range:      EditorRange(newStart, newEnd),
        severity:   r.severity,
        message:    r.message,
        source:     r.source,
        code:       r.code,
        quickFixes: r.quickFixes,
      );
    }).toList();
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  List<DiagnosticRegion> forLine(int line) =>
      _regions.where((r) => r.range.start.line == line).toList();

  /// Returns the first diagnostic whose range contains [pos], or null.
  ///
  /// The tooltip must only appear when the cursor is **inside** the error
  /// span — i.e. there are still characters after the cursor that belong to
  /// the squiggle.  When the cursor sits exactly at the end column the user
  /// has moved past the error token, so we return null.
  DiagnosticRegion? atPosition(CharPosition pos) {
    for (final r in _regions) {
      final sl = r.range.start.line;
      final el = r.range.end.line;
      if (pos.line < sl || pos.line > el) continue;

      if (sl == el) {
        // Single-line diagnostic: cursor must be >= start col AND strictly
        // < end col (cursor AT end means no characters of the token remain
        // after it → tooltip must NOT appear).
        if (pos.column >= r.range.start.column &&
            pos.column <  r.range.end.column) {
          return r;
        }
      } else {
        // Multi-line diagnostic.
        if (pos.line == sl && pos.column < r.range.start.column) continue;
        if (pos.line == el && pos.column >= r.range.end.column)  continue;
        return r;
      }
    }
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static DiagnosticRegion _shiftRegion(DiagnosticRegion r, int lineDelta) {
    final newStart = CharPosition(r.range.start.line + lineDelta, r.range.start.column);
    final newEnd   = CharPosition(r.range.end.line   + lineDelta, r.range.end.column);
    return DiagnosticRegion(
      range:      EditorRange(newStart, newEnd),
      severity:   r.severity,
      message:    r.message,
      source:     r.source,
      code:       r.code,
      quickFixes: r.quickFixes,
    );
  }
}