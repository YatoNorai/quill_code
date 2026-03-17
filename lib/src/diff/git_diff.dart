// lib/src/diff/git_diff.dart
//
// QuillCode Git Diff support.
//
// Two independent layers:
//
//  1. [DiffEngine]   — pure Dart Myers diff algorithm. Computes the minimal
//                      edit script between two lists of strings (lines) in
//                      O((N + M)·D) time where D is the number of edits.
//
//  2. [GitDiffDecoration] — bridges DiffEngine to the editor by annotating the
//                           [Styles.lineStyles] so the renderer paints coloured
//                           gutters, ▲/▼/─ markers and optional inline diffs.
//
//  3. [DiffHunk] / [DiffLine] — rich data model for a unified diff.
//
// QUICK START
//   // 1. Parse a unified diff string (e.g. from `git diff`):
//   final hunks = UnifiedDiffParser.parse(diffString);
//
//   // 2. Or compute a diff between two strings at runtime:
//   final hunks = DiffEngine.diffStrings(original, modified);
//
//   // 3. Decorate the controller's line-styles:
//   GitDiffDecoration.apply(controller, hunks);
//
//   // 4. The QuillCodeEditor will automatically paint gutter markers.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../highlighting/line_style.dart';
import '../core/editor_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

/// A single annotated line inside a diff hunk.
class DiffLine {
  final DiffLineType type;
  final String       text;

  /// Line number in the *new* file (null for pure deletions).
  final int? newLine;

  /// Line number in the *old* file (null for pure additions).
  final int? oldLine;

  const DiffLine({
    required this.type,
    required this.text,
    this.newLine,
    this.oldLine,
  });

  bool get isAdded   => type == DiffLineType.added;
  bool get isRemoved => type == DiffLineType.removed;
  bool get isContext => type == DiffLineType.context;

  @override
  String toString() {
    final prefix = switch (type) {
      DiffLineType.added    => '+',
      DiffLineType.removed  => '-',
      DiffLineType.modified => '~',
      DiffLineType.context  => ' ',
    };
    return '$prefix$text';
  }
}

/// A contiguous block of changed lines.
class DiffHunk {
  final int          oldStart;
  final int          oldCount;
  final int          newStart;
  final int          newCount;
  final List<DiffLine> lines;
  final String?      header; // e.g. "void myFunction() {"

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
    this.header,
  });

  /// All *added* lines in this hunk.
  Iterable<DiffLine> get added   => lines.where((l) => l.isAdded);

  /// All *removed* lines in this hunk.
  Iterable<DiffLine> get removed => lines.where((l) => l.isRemoved);

  @override
  String toString() => '@@ -$oldStart,$oldCount +$newStart,$newCount @@'
      '${header != null ? ' $header' : ''}\n'
      '${lines.join('\n')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Myers diff engine
// ─────────────────────────────────────────────────────────────────────────────

/// Computes the shortest edit script between two sequences.
/// Returns a list of [DiffLine]s covering both added and removed lines
/// (context lines are omitted from raw output; [toHunks] adds them back).
class DiffEngine {
  DiffEngine._();

  /// Compute a diff between [original] lines and [modified] lines.
  /// Context lines around each change are controlled by [contextLines].
  static List<DiffHunk> diffLists(
    List<String> original,
    List<String> modified, {
    int contextLines = 3,
  }) {
    final edits = _myers(original, modified);
    return _buildHunks(original, modified, edits, contextLines);
  }

  /// Convenience: split [original] and [modified] by newline and diff them.
  static List<DiffHunk> diffStrings(
    String original,
    String modified, {
    int contextLines = 3,
  }) =>
      diffLists(
        original.split('\n'),
        modified.split('\n'),
        contextLines: contextLines,
      );

  /// Async variant — runs the diff in a [Future] so the main thread
  /// is not blocked. Suitable for live diffs triggered by keystrokes.
  static Future<List<DiffHunk>> diffStringsAsync(
    String original,
    String modified, {
    int contextLines = 3,
  }) =>
      Future(() => diffStrings(original, modified, contextLines: contextLines));

  /// Async variant of [diffLists].
  static Future<List<DiffHunk>> diffListsAsync(
    List<String> original,
    List<String> modified, {
    int contextLines = 3,
  }) =>
      Future(() => diffLists(original, modified, contextLines: contextLines));

  // ── Myers algorithm ────────────────────────────────────────────────────────

  /// Returns a list of edit operations as (type, oldIdx, newIdx) triples.
  /// type: 0 = keep, 1 = insert (into new), -1 = delete (from old).
  static List<(int type, int oi, int ni)> _myers(
      List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    final max = n + m;
    if (max == 0) return [];

    // v[k] = furthest x reached on diagonal k.
    final v = List<int>.filled(2 * max + 2, 0);
    // trace[d] = snapshot of v after d edits.
    final trace = <List<int>>[];

    outer:
    for (int d = 0; d <= max; d++) {
      trace.add(List<int>.from(v));
      for (int k = -d; k <= d; k += 2) {
        final ki = k + max; // index into v
        int x;
        if (k == -d || (k != d && v[ki - 1] < v[ki + 1])) {
          x = v[ki + 1]; // move down
        } else {
          x = v[ki - 1] + 1; // move right
        }
        int y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++; y++; // snake
        }
        v[ki] = x;
        if (x >= n && y >= m) break outer;
      }
    }

    // Back-track through trace to recover the edit path.
    final edits = <(int, int, int)>[];
    int x = n, y = m;
    for (int d = trace.length - 1; d >= 0; d--) {
      final vd = trace[d];
      final k  = x - y;
      final ki = k + max;
      int prevK;
      if (k == -d || (k != d && vd[ki - 1] < vd[ki + 1])) {
        prevK = k + 1;
      } else {
        prevK = k - 1;
      }
      final prevX = vd[prevK + max];
      final prevY = prevX - prevK;
      // Snakes (equals)
      while (x > prevX + (k > prevK ? 1 : 0) &&
             y > prevY + (k < prevK ? 1 : 0)) {
        edits.add((0, x - 1, y - 1));
        x--; y--;
      }
      if (d > 0) {
        if (k > prevK) { edits.add((-1, x - 1, y)); x--; }  // delete
        else           { edits.add((1,  x, y - 1)); y--; }  // insert
      }
    }

    return edits.reversed.toList();
  }

  // ── Build hunks with context ───────────────────────────────────────────────

  static List<DiffHunk> _buildHunks(
    List<String> a,
    List<String> b,
    List<(int, int, int)> edits,
    int ctx,
  ) {
    if (edits.isEmpty) return [];

    // Mark changed positions in old and new.
    final changedA = <int>{};
    final changedB = <int>{};
    for (final (type, oi, ni) in edits) {
      if (type == -1) changedA.add(oi);
      if (type ==  1) changedB.add(ni);
    }

    if (changedA.isEmpty && changedB.isEmpty) return [];

    // Collect ranges of changed lines (in new-file coordinates).
    final ranges = <(int, int)>[];
    // Use new-file index when possible; fall back to old-file for deletions.
    final allChanged = <int>{...changedB};
    // Map old-file changed lines to nearest new-file positions.
    for (final (type, oi, ni) in edits) {
      if (type == -1) allChanged.add(ni); // ni is the insertion point
    }

    if (allChanged.isEmpty) return [];
    final sorted = allChanged.toList()..sort();

    // Merge nearby changes into hunks.
    final hunkRanges = <(int, int)>[];
    int hStart = math.max(0, sorted.first - ctx);
    int hEnd   = math.min(b.length - 1, sorted.first + ctx);
    for (final idx in sorted.skip(1)) {
      if (idx - ctx <= hEnd + 1) {
        hEnd = math.min(b.length - 1, idx + ctx);
      } else {
        hunkRanges.add((hStart, hEnd));
        hStart = math.max(0, idx - ctx);
        hEnd   = math.min(b.length - 1, idx + ctx);
      }
    }
    hunkRanges.add((hStart, hEnd));

    // Build DiffHunk objects from edits.
    final hunks = <DiffHunk>[];
    for (final (hs, he) in hunkRanges) {
      final lines = <DiffLine>[];
      int oi = 0, ni = hs;
      int oldStart = 0, newStart = hs + 1;
      bool firstEdit = true;

      for (final (type, eoi, eni) in edits) {
        if (eni < hs && type != -1) continue;
        if (eni > he && type != -1) break;

        if (type == 0) {
          if (eni >= hs && eni <= he) {
            lines.add(DiffLine(type: DiffLineType.context, text: b[eni], newLine: eni + 1, oldLine: eoi + 1));
            if (firstEdit) { oldStart = eoi + 1; newStart = eni + 1; firstEdit = false; }
          }
        } else if (type == -1) {
          if (eoi >= hs && eoi <= he) {
            lines.add(DiffLine(type: DiffLineType.removed, text: a[eoi], oldLine: eoi + 1));
            if (firstEdit) { oldStart = eoi + 1; newStart = eni + 1; firstEdit = false; }
          }
        } else {
          if (eni >= hs && eni <= he) {
            lines.add(DiffLine(type: DiffLineType.added, text: b[eni], newLine: eni + 1));
            if (firstEdit) { oldStart = 0; newStart = eni + 1; firstEdit = false; }
          }
        }
      }

      if (lines.any((l) => !l.isContext)) {
        final oldCount = lines.where((l) => !l.isAdded).length;
        final newCount = lines.where((l) => !l.isRemoved).length;
        hunks.add(DiffHunk(
          oldStart: oldStart,
          oldCount: oldCount,
          newStart: newStart,
          newCount: newCount,
          lines: lines,
        ));
      }
    }

    return hunks;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified diff parser  (parses output of `git diff` or `diff -u`)
// ─────────────────────────────────────────────────────────────────────────────

class UnifiedDiffParser {
  UnifiedDiffParser._();

  static final _hunkHeader = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$');

  /// Parse a unified diff string into a list of [DiffHunk]s.
  static List<DiffHunk> parse(String diffText) {
    final hunks = <DiffHunk>[];
    final lines = diffText.split('\n');

    DiffHunk? current;
    List<DiffLine>? currentLines;
    int oldLine = 0, newLine = 0;

    for (final raw in lines) {
      final m = _hunkHeader.firstMatch(raw);
      if (m != null) {
        if (current != null && currentLines != null) {
          hunks.add(current);
        }
        oldLine = int.parse(m.group(1)!);
        newLine = int.parse(m.group(3)!);
        final oldCount = int.tryParse(m.group(2) ?? '1') ?? 1;
        final newCount = int.tryParse(m.group(4) ?? '1') ?? 1;
        currentLines = [];
        current = DiffHunk(
          oldStart: oldLine,
          oldCount: oldCount,
          newStart: newLine,
          newCount: newCount,
          lines: currentLines,
          header: m.group(5)?.trim(),
        );
        continue;
      }
      if (currentLines == null) continue;

      if (raw.startsWith('+') && !raw.startsWith('+++')) {
        currentLines.add(DiffLine(type: DiffLineType.added,   text: raw.substring(1), newLine: newLine++));
      } else if (raw.startsWith('-') && !raw.startsWith('---')) {
        currentLines.add(DiffLine(type: DiffLineType.removed, text: raw.substring(1), oldLine: oldLine++));
      } else if (raw.startsWith(' ')) {
        currentLines.add(DiffLine(type: DiffLineType.context, text: raw.substring(1), newLine: newLine++, oldLine: oldLine++));
      }
    }
    if (current != null) hunks.add(current);
    return hunks;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GitDiffDecoration — applies diff markers to the editor
// ─────────────────────────────────────────────────────────────────────────────

/// Theme for how diff markers are painted in the editor gutter.
class DiffGutterTheme {
  final Color addedColor;
  final Color removedColor;
  final Color modifiedColor;
  final double markerWidth;
  final bool showBackground;
  final Color addedBackground;
  final Color removedBackground;
  final Color modifiedBackground;

  const DiffGutterTheme({
    this.addedColor      = const Color(0xFF3FB950),
    this.removedColor    = const Color(0xFFF85149),
    this.modifiedColor   = const Color(0xFFE3B341),
    this.markerWidth     = 3.0,
    this.showBackground  = true,
    this.addedBackground    = const Color(0x1A3FB950),
    this.removedBackground  = const Color(0x1AF85149),
    this.modifiedBackground = const Color(0x1AE3B341),
  });

  static const DiffGutterTheme github = DiffGutterTheme();
  static const DiffGutterTheme subtle = DiffGutterTheme(
    showBackground: false,
    addedColor:   Color(0xFF4CAF50),
    removedColor: Color(0xFFE53935),
    modifiedColor:Color(0xFFFFB300),
    markerWidth: 2.0,
  );
  static const DiffGutterTheme vibrant = DiffGutterTheme(
    addedColor:        Color(0xFF00E676),
    removedColor:      Color(0xFFFF1744),
    modifiedColor:     Color(0xFFFFD740),
    addedBackground:   Color(0x2200E676),
    removedBackground: Color(0x22FF1744),
    modifiedBackground:Color(0x22FFD740),
    markerWidth: 4.0,
  );
}

/// Applies a list of [DiffHunk]s to an editor controller by mutating its
/// [LineStyle] map so the renderer paints gutter diff markers automatically.
class GitDiffDecoration {
  GitDiffDecoration._();

  /// Apply diff hunks to [controller].
  ///
  /// Lines in [hunks] that fall within the current document are annotated.
  /// The [theme] controls gutter marker colors.
  /// Call again with an empty [hunks] list to clear all markers.
  static void apply(
    QuillCodeController controller,
    List<DiffHunk> hunks, {
    DiffGutterTheme theme = const DiffGutterTheme(),
  }) {
    // Build a fresh line-style map by merging existing non-diff styles.
    final existing = Map<int, LineStyle>.from(controller.styles.lineStyles)
      ..removeWhere((_, s) => s.diffType != null);

    final additions = <int, LineStyle>{};

    for (final hunk in hunks) {
      for (final line in hunk.lines) {
        if (line.isContext) continue;
        final lineNum = (line.newLine ?? line.oldLine);
        if (lineNum == null) continue;
        final idx = lineNum - 1; // 0-based
        if (idx < 0 || idx >= controller.content.lineCount) continue;

        Color gutterColor;
        Color? bgColor;
        DiffLineType dtype;

        switch (line.type) {
          case DiffLineType.added:
            gutterColor = theme.addedColor;
            bgColor     = theme.showBackground ? theme.addedBackground : null;
            dtype       = DiffLineType.added;
          case DiffLineType.removed:
            gutterColor = theme.removedColor;
            bgColor     = theme.showBackground ? theme.removedBackground : null;
            dtype       = DiffLineType.removed;
          case DiffLineType.modified:
            gutterColor = theme.modifiedColor;
            bgColor     = theme.showBackground ? theme.modifiedBackground : null;
            dtype       = DiffLineType.modified;
          case DiffLineType.context:
            continue;
        }

        additions[idx] = LineStyle(
          gutterMarkerColor: gutterColor,
          gutterMarkerWidth: theme.markerWidth,
          backgroundColor:   bgColor,
          diffType:          dtype,
        );
      }
    }

    // Merge existing + diff styles, then notify.
    final merged = {...existing, ...additions};
    controller.setLineStyles(merged);
  }

  /// Clear all diff decorations from [controller].
  static void clear(QuillCodeController controller) {
    final cleaned = Map<int, LineStyle>.from(controller.styles.lineStyles)
      ..removeWhere((_, s) => s.diffType != null);
    controller.setLineStyles(cleaned);
  }
}
