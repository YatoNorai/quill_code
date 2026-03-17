// lib/src/theme/theme_dark_modern.dart
//
// VSCode Dark Modern theme — the default dark theme in VSCode 1.75+
// Colors extracted from VSCode's dark_modern.json bundled theme.
//
// Usage:
//   QuillCodeEditor(theme: QuillThemeDarkModern.build())

import 'package:flutter/painting.dart';
import 'color_scheme.dart';
import 'editor_theme.dart';

class QuillThemeDarkModern {
  static EditorTheme build({
    String fontFamily = 'monospace',
    double fontSize   = 14.0,
  }) => EditorTheme(
    fontFamily: fontFamily,
    fontSize:   fontSize,
    colorScheme: _scheme,
    blockLines: const BlockLineTheme(color: Color(0x663C3C3C), activeColor: Color(0xCC569CD6), width: 1.0, curveRadius: 6.0),
    bracketPair: const BracketPairTheme(fillColor: Color(0x1A569CD6), borderColor: Color(0x80569CD6)),
    indentDots: const IndentDotTheme(visible: false, color: Color(0x44858585)),
  );

  static const EditorColorScheme _scheme = EditorColorScheme(
    // ── Editor chrome ──────────────────────────────────────────────────────
    background:              Color(0xFF1F1F1F),   // editor.background
    lineNumberBackground:    Color(0xFF1F1F1F),
    currentLineBackground:   Color(0xFF282828),   // editor.lineHighlightBackground
    selectionColor:          Color(0x40264F78),   // editor.selectionBackground
    searchMatchBackground:   Color(0x509E6A03),   // findMatchHighlight
    searchMatchBorder:       Color(0xFFC19543),   // findMatch orange

    snippetActiveBackground:   Color(0x3306A6D2),
    snippetInactiveBackground: Color(0x1A06A6D2),

    // ── Text ───────────────────────────────────────────────────────────────
    textNormal:       Color(0xFFCCCCCC),   // editor.foreground
    lineNumber:       Color(0xFF6E7681),   // editorLineNumber.foreground
    lineNumberCurrent:Color(0xFFCCCCCC),   // editorLineNumber.activeForeground
    nonPrintableChar: Color(0xFF3D3D3D),
    cursor:           Color(0xFF0078D4),   // editorCursor.foreground (VS Blue)

    // ── Syntax tokens ──────────────────────────────────────────────────────
    keyword:      Color(0xFF569CD6),   // keyword — VS blue
    comment:      Color(0xFF6A9955),   // comment — green
    string:       Color(0xFFCE9178),   // string — salmon
    number:       Color(0xFFB5CEA8),   // number — light green
    operator_:    Color(0xFFD4D4D4),
    identifier:   Color(0xFF9CDCFE),   // variable — light blue
    function_:    Color(0xFFDCDCAA),   // function — yellow
    type_:        Color(0xFF4EC9B0),   // type — teal
    annotation:   Color(0xFF9CDCFE),
    literal:      Color(0xFF569CD6),
    htmlTag:      Color(0xFF4EC9B0),
    attrName:     Color(0xFF9CDCFE),
    attrValue:    Color(0xFFCE9178),
    preprocessor: Color(0xFFC586C0),   // preprocessor — purple
    constant:     Color(0xFF4FC1FF),
    namespace:    Color(0xFF4EC9B0),
    label:        Color(0xFFCE9178),
    punctuation:  Color(0xFFD4D4D4),

    // ── Structural ─────────────────────────────────────────────────────────
    blockLine:            Color(0xFF404040),   // editorIndentGuide
    blockLineActive:      Color(0xFF707070),
    lineDivider:          Color(0xFF404040),
    hardWrapMarker:       Color(0xFF404040),
    stickyScrollDivider:  Color(0xFF404040),
    selectedTextBorder:   Color(0xFF0078D4),
    currentRowBorder:     Color(0xFF282828),

    // ── Selection & handles ────────────────────────────────────────────────
    selectionHandle:  Color(0xFF0078D4),

    // ── Scrollbar ──────────────────────────────────────────────────────────
    scrollBarThumb:        Color(0xFF424242),
    scrollBarThumbPressed: Color(0xFF686868),
    scrollBarTrack:        Color(0xFF1F1F1F),

    // ── Brackets ──────────────────────────────────────────────────────────
    bracketPairBorder:    Color(0xFF569CD6),
    bracketPairFill:      Color(0x1A569CD6),
    activeBlockLineHighlight: Color(0xFF252526),

    // ── Delimiters ─────────────────────────────────────────────────────────
    highlightedDelimitersFg:        Color(0xFFFFD700),
    highlightedDelimitersUnderline: Color(0xFFFFD700),
    highlightedDelimitersBg:        Color(0x22FFD700),

    // ── Diagnostics ────────────────────────────────────────────────────────
    problemError:   Color(0xFFF44747),
    problemWarning: Color(0xFFCCA700),
    problemTypo:    Color(0xFF75BEFF),

    diagnosticTooltipBackground: Color(0xFF252526),
    diagnosticTooltipText:       Color(0xFFCCCCCC),

    // ── Completion ─────────────────────────────────────────────────────────
    completionBackground:      Color(0xFF252526),
    completionItemBackground:  Color(0xFF252526),
    completionItemSelected:    Color(0xFF094771),
    completionTextPrimary:     Color(0xFFCCCCCC),
    completionTextSecondary:   Color(0xFF858585),
    completionTextMatched:     Color(0xFF18A3FF),
    completionBorder:          Color(0xFF454545),

    // ── Inlay hints ────────────────────────────────────────────────────────
    inlayHintForeground: Color(0xFF858585),
    inlayHintBackground: Color(0xFF252526),

    // ── Hover ──────────────────────────────────────────────────────────────
    hoverBackground: Color(0xFF252526),
    hoverBorder:     Color(0xFF454545),
    hoverText:       Color(0xFFCCCCCC),

    // ── Signature help ─────────────────────────────────────────────────────
    signatureBackground:      Color(0xFF252526),
    signatureBorder:          Color(0xFF454545),
    signatureText:            Color(0xFFCCCCCC),
    signatureHighlightedParam:Color(0xFFFFD700),

    // ── Quick actions ──────────────────────────────────────────────────────
    textActionBackground: Color(0xFF2D2D2D),
    textActionIconColor:  Color(0xFFCCCCCC),

    // ── Ghost text ─────────────────────────────────────────────────────────
    ghostTextForeground: Color(0xFF666666),
  );
}
