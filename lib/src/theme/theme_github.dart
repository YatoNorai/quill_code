// lib/src/theme/theme_github.dart
import 'package:flutter/painting.dart';
import 'color_scheme.dart';
import 'editor_theme.dart';

class QuillThemeGithub {
  static EditorTheme build({String fontFamily = 'monospace', double fontSize = 14.0}) =>
      EditorTheme(
        fontFamily: fontFamily, fontSize: fontSize, colorScheme: _scheme,
        blockLines: const BlockLineTheme(color: Color(0x66D0D7DE), activeColor: Color(0xCC0550AE), width: 1.0, curveRadius: 6.0),
        bracketPair: const BracketPairTheme(fillColor: Color(0x1A0550AE), borderColor: Color(0x800550AE),),
        indentDots: const IndentDotTheme(visible: false, color: Color(0x446E7781),),
      );
  static const EditorColorScheme _scheme = EditorColorScheme(
    background: Color(0xFF0D1117), lineNumberBackground: Color(0xFF010409),
    currentLineBackground: Color(0xFF161B22), selectionColor: Color(0x551F6FEB),
    searchMatchBackground: Color(0x55FFA657), searchMatchBorder: Color(0xFFFFA657),
    snippetActiveBackground: Color(0x3358A6FF), snippetInactiveBackground: Color(0x1A58A6FF),
    textNormal: Color(0xFFE6EDF3), lineNumber: Color(0xFF6E7681), lineNumberCurrent: Color(0xFFE6EDF3),
    nonPrintableChar: Color(0xFF30363D), keyword: Color(0xFFFF7B72), comment: Color(0xFF8B949E),
    string: Color(0xFFA5D6FF), number: Color(0xFF79C0FF), operator_: Color(0xFFFF7B72),
    identifier: Color(0xFFE6EDF3), function_: Color(0xFFD2A8FF), type_: Color(0xFFFFA657),
    annotation: Color(0xFFF2CC60), literal: Color(0xFF79C0FF), htmlTag: Color(0xFF7EE787),
    attrName: Color(0xFFFFA657), attrValue: Color(0xFFA5D6FF), preprocessor: Color(0xFFF2CC60),
    constant: Color(0xFF79C0FF), namespace: Color(0xFFD2A8FF), label: Color(0xFFFF7B72),
    punctuation: Color(0xFF8B949E), blockLine: Color(0xFF21262D), blockLineActive: Color(0xFF30363D),
    lineDivider: Color(0xFF21262D), hardWrapMarker: Color(0xFF30363D), stickyScrollDivider: Color(0xFF30363D),
    selectedTextBorder: Color(0xFF58A6FF), currentRowBorder: Color(0xFF30363D), cursor: Color(0xFF58A6FF),
    selectionHandle: Color(0xFF58A6FF), scrollBarThumb: Color(0xFF30363D), scrollBarThumbPressed: Color(0xFF484F58),
    scrollBarTrack: Color(0xFF0D1117), bracketPairBorder: Color(0xFF388BFD), bracketPairFill: Color(0x1A388BFD), activeBlockLineHighlight: Color(0xFF1C2128),
    highlightedDelimitersFg: Color(0xFFFFA657),
    highlightedDelimitersUnderline: Color(0xFFFFA657), highlightedDelimitersBg: Color(0x22FFA657),
    problemError: Color(0xFFF85149), problemWarning: Color(0xFFD29922), problemTypo: Color(0xFF58A6FF),
    diagnosticTooltipBackground: Color(0xFF161B22), diagnosticTooltipText: Color(0xFFE6EDF3),
    completionBackground: Color(0xFF161B22), completionItemBackground: Color(0xFF161B22),
    completionItemSelected: Color(0xFF1F2937), completionTextPrimary: Color(0xFFE6EDF3),
    completionTextSecondary: Color(0xFF8B949E), completionTextMatched: Color(0xFF58A6FF),
    completionBorder: Color(0xFF30363D), inlayHintForeground: Color(0xFF8B949E),
    inlayHintBackground: Color(0xFF21262D), hoverBackground: Color(0xFF161B22),
    hoverBorder: Color(0xFF30363D), hoverText: Color(0xFFE6EDF3),
    signatureBackground: Color(0xFF161B22), signatureBorder: Color(0xFF30363D),
    signatureText: Color(0xFFE6EDF3), signatureHighlightedParam: Color(0xFFFFA657),
    textActionBackground: Color(0xFF21262D), textActionIconColor: Color(0xFFE6EDF3),
  );
}
