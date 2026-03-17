// lib/src/highlighting/line_style.dart
import 'package:flutter/painting.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DiffLineType lives here (not in git_diff.dart) to avoid a circular import.
// git_diff.dart → line_style.dart (OK); line_style.dart must NOT import diff.
// ─────────────────────────────────────────────────────────────────────────────

enum DiffLineType {
  /// Line present in both old and new (context line).
  context,
  /// Line added in the new version.
  added,
  /// Line removed from the old version.
  removed,
  /// A modified line (pair of removed + added with high similarity).
  modified,
}

/// Custom per-line styling (icons, backgrounds, diff gutter markers).
class LineStyle {
  final Color? lineBackground;
  final Color? backgroundColor;    // alias of lineBackground for diff use
  final Color? gutterBackground;
  final dynamic sideIcon;          // IconData or Widget

  // ── Diff / git annotations ──────────────────────────────────────────────
  /// Non-null when this line carries a git-diff annotation.
  final DiffLineType? diffType;

  /// Width of the gutter marker strip in logical pixels.
  final double gutterMarkerWidth;

  /// Color of the gutter marker strip.
  final Color? gutterMarkerColor;

  const LineStyle({
    this.lineBackground,
    this.backgroundColor,
    this.gutterBackground,
    this.sideIcon,
    this.diffType,
    this.gutterMarkerColor,
    this.gutterMarkerWidth = 3.0,
  });
}
