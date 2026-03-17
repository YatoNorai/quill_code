// lib/src/theme/theme_github_dark.dart
//
// GitHub Dark theme — matches github.com's dark mode code display exactly.
// Colors sourced from github/github-vscode-theme.
//
// Usage:
//   QuillCodeEditor(theme: QuillThemeGitHubDark.build())

import 'package:flutter/painting.dart';
import 'color_scheme.dart';
import 'editor_theme.dart';

class QuillThemeGitHubDark {
  static EditorTheme build({
    String fontFamily = 'monospace',
    double fontSize   = 14.0,
  }) => EditorTheme(
    fontFamily: fontFamily,
    fontSize:   fontSize,
    colorScheme: _scheme,
    blockLines: const BlockLineTheme(color: Color(0x6621262D), activeColor: Color(0xCC58A6FF), colorMode: BlockLineColorMode.rainbow, rainbowColors: [Color(0xFF58A6FF), Color(0xFFA5D6FF), Color(0xFFFF7B72), Color(0xFFFFA657), Color(0xFF3FB950), Color(0xFFD2A8FF)], capLength: 5.0, inactiveOpacity: 0.5, curveRadius: 6.0),
    bracketPair: const BracketPairTheme(fillColor: Color(0x1A58A6FF), borderColor: Color(0x8058A6FF)),
    indentDots: const IndentDotTheme(visible: false, color: Color(0x446E7681)),
  );

  static const EditorColorScheme _scheme = EditorColorScheme(
    // ── Editor chrome ──────────────────────────────────────────────────────
    background:              Color(0xFF0D1117),   // GitHub dark bg
    lineNumberBackground:    Color(0xFF0D1117),
    currentLineBackground:   Color(0xFF161B22),   // subtle highlight
    selectionColor:          Color(0x402EA6E8),
    searchMatchBackground:   Color(0x50FFDF5D),
    searchMatchBorder:       Color(0xFFFFDF5D),   // GitHub yellow

    snippetActiveBackground:   Color(0x302EA6E8),
    snippetInactiveBackground: Color(0x152EA6E8),

    // ── Text ───────────────────────────────────────────────────────────────
    textNormal:        Color(0xFFC9D1D9),   // GitHub default text
    lineNumber:        Color(0xFF6E7681),
    lineNumberCurrent: Color(0xFFC9D1D9),
    nonPrintableChar:  Color(0xFF21262D),
    cursor:            Color(0xFF58A6FF),   // GitHub blue

    // ── Syntax tokens ──────────────────────────────────────────────────────
    keyword:      Color(0xFFFF7B72),   // keyword — red/orange
    comment:      Color(0xFF8B949E),   // comment — grey
    string:       Color(0xFFA5D6FF),   // string — light blue
    number:       Color(0xFF79C0FF),   // number — blue
    operator_:    Color(0xFFC9D1D9),
    identifier:   Color(0xFFC9D1D9),
    function_:    Color(0xFFD2A8FF),   // function — purple
    type_:        Color(0xFFFFA657),   // type — orange
    annotation:   Color(0xFF79C0FF),
    literal:      Color(0xFF79C0FF),   // literal — blue
    htmlTag:      Color(0xFF7EE787),   // html tag — green
    attrName:     Color(0xFFD2A8FF),
    attrValue:    Color(0xFFA5D6FF),
    preprocessor: Color(0xFFFF7B72),
    constant:     Color(0xFF79C0FF),
    namespace:    Color(0xFFFFA657),
    label:        Color(0xFFA5D6FF),
    punctuation:  Color(0xFFC9D1D9),

    // ── Structural ─────────────────────────────────────────────────────────
    blockLine:            Color(0xFF21262D),
    blockLineActive:      Color(0xFF30363D),
    lineDivider:          Color(0xFF21262D),
    hardWrapMarker:       Color(0xFF21262D),
    stickyScrollDivider:  Color(0xFF21262D),
    selectedTextBorder:   Color(0xFF58A6FF),
    currentRowBorder:     Color(0xFF161B22),
    selectionHandle:      Color(0xFF58A6FF),

    // ── Scrollbar ──────────────────────────────────────────────────────────
    scrollBarThumb:        Color(0xFF30363D),
    scrollBarThumbPressed: Color(0xFF484F58),
    scrollBarTrack:        Color(0xFF0D1117),

    // ── Brackets ──────────────────────────────────────────────────────────
    bracketPairBorder:    Color(0xFF58A6FF),
    bracketPairFill:      Color(0x1A58A6FF),
    activeBlockLineHighlight: Color(0xFF161B22),

    // ── Delimiters ─────────────────────────────────────────────────────────
    highlightedDelimitersFg:        Color(0xFFFFA657),
    highlightedDelimitersUnderline: Color(0xFFFFA657),
    highlightedDelimitersBg:        Color(0x22FFA657),

    // ── Diagnostics ────────────────────────────────────────────────────────
    problemError:   Color(0xFFF85149),
    problemWarning: Color(0xFFE3B341),
    problemTypo:    Color(0xFF79C0FF),

    diagnosticTooltipBackground: Color(0xFF161B22),
    diagnosticTooltipText:       Color(0xFFC9D1D9),

    // ── Completion ─────────────────────────────────────────────────────────
    completionBackground:      Color(0xFF161B22),
    completionItemBackground:  Color(0xFF161B22),
    completionItemSelected:    Color(0xFF1F6FEB),
    completionTextPrimary:     Color(0xFFC9D1D9),
    completionTextSecondary:   Color(0xFF6E7681),
    completionTextMatched:     Color(0xFF58A6FF),
    completionBorder:          Color(0xFF30363D),

    // ── Inlay hints ────────────────────────────────────────────────────────
    inlayHintForeground: Color(0xFF6E7681),
    inlayHintBackground: Color(0xFF161B22),

    // ── Hover ──────────────────────────────────────────────────────────────
    hoverBackground: Color(0xFF161B22),
    hoverBorder:     Color(0xFF30363D),
    hoverText:       Color(0xFFC9D1D9),

    // ── Signature help ─────────────────────────────────────────────────────
    signatureBackground:       Color(0xFF161B22),
    signatureBorder:           Color(0xFF30363D),
    signatureText:             Color(0xFFC9D1D9),
    signatureHighlightedParam: Color(0xFFFFA657),

    // ── Quick actions ──────────────────────────────────────────────────────
    textActionBackground: Color(0xFF21262D),
    textActionIconColor:  Color(0xFFC9D1D9),

    // ── Ghost text ─────────────────────────────────────────────────────────
    ghostTextForeground: Color(0xFF484F58),
  );
}
