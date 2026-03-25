// lib/src/core/editor_props.dart
import 'package:flutter/material.dart';

class EditorProps {
  bool autoIndent = true;
  bool deleteEmptyLineFast = true;
  bool symbolPairAutoCompletion = true;
  bool enhancedHomeAndEnd = true;
  int tabSize = 4;
  bool useSpacesForTabs = true;
  int clipboardTextLengthLimit = 512 * 1024;

  bool showLineNumbers = true;
  bool fixedLineNumbers = true;  // gutter fixed or scrolls with code
  bool showBlockLines = true;
  bool showFoldArrows = true;
  bool wordWrap = false;
  bool showDiagnosticIndicators = true;
  bool showInlayHints = true;

  bool stickyScroll = false;
  int stickyScrollMaxLines = 3;

  bool autoCompletion = true;
  bool showMinimap        = true;
  bool showScrollbars     = true;
  bool showColorDecorators = true;
  bool showLightbulb  = true;

  bool readOnly = false;

  bool formatOnSave = false;
  int cursorBlinkIntervalMs = 530;

  DiagnosticIndicatorStyle diagnosticIndicatorStyle = DiagnosticIndicatorStyle.squiggle;

  // ── Current-line highlight ────────────────────────────────────────────────
  bool highlightCurrentLine = true;
  LineHighlightStyle lineHighlightStyle = LineHighlightStyle.fill;

  // ── Block (scope) highlight ───────────────────────────────────────────────
  /// When cursor is inside a code block, highlight the enclosing block's
  /// start/end lines with a distinct color to show the active scope.
  bool highlightActiveBlock = true;

  // ── Color overrides ───────────────────────────────────────────────────────
  Color? cursorColor;
  Color? handleColor;
  Color? bracketPairFillColor;
  Color? bracketPairBorderColor;

  // ── Custom selection toolbar items ────────────────────────────────────────
  /// Extra items appended to the selection toolbar.
  /// Each item: (label, icon, callback).
  List<SelectionToolItem> extraToolItems = const [];

  /// Items to hide from the default toolbar (matched by label).
  Set<String> hiddenToolItems = const {};
}

/// A custom item to add to the selection toolbar.
class SelectionToolItem {
  final String label;
  final IconData icon;
  final void Function(String selectedText) onTap;
  const SelectionToolItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

enum DiagnosticIndicatorStyle { squiggle, underline, none }

enum LineHighlightStyle {
  fill,
  stroke,
  accentBar,
  none,
}
