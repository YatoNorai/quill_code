// lib/src/theme/theme_monokai.dart
import 'package:flutter/painting.dart';
import 'color_scheme.dart';
import 'editor_theme.dart';

class QuillThemeMonokai {
  static EditorTheme build({String fontFamily = 'monospace', double fontSize = 14.0}) =>
      EditorTheme(
        fontFamily: fontFamily, fontSize: fontSize, colorScheme: _scheme,
        blockLines: const BlockLineTheme(color: Color(0x663E3D32), activeColor: Color(0xCCA6E22E), style: BlockLineStyle.dotted, colorMode: BlockLineColorMode.rainbow, rainbowColors: [Color(0xFFF92672), Color(0xFFA6E22E), Color(0xFFE6DB74), Color(0xFF66D9EF), Color(0xFFAE81FF), Color(0xFFFD971F)], dotSpacing: 5.0, width: 1.5, inactiveOpacity: 0.6, curveRadius: 6.0),
        bracketPair: const BracketPairTheme(fillColor: Color(0x1AA6E22E), borderColor: Color(0x80A6E22E),),
        indentDots: const IndentDotTheme(visible: true, color: Color(0x5575715E),),
      );
  static const EditorColorScheme _scheme = EditorColorScheme(
    background: Color(0xFF272822), lineNumberBackground: Color(0xFF1E1F1C),
    currentLineBackground: Color(0xFF3E3D32), selectionColor: Color(0x6649483E),
    searchMatchBackground: Color(0x55FFE792), searchMatchBorder: Color(0xFFFFE792),
    snippetActiveBackground: Color(0x33A6E22E), snippetInactiveBackground: Color(0x1AA6E22E),
    textNormal: Color(0xFFF8F8F2), lineNumber: Color(0xFF90908A), lineNumberCurrent: Color(0xFFF8F8F2),
    nonPrintableChar: Color(0xFF75715E), keyword: Color(0xFFF92672), comment: Color(0xFF75715E),
    string: Color(0xFFE6DB74), number: Color(0xFFAE81FF), operator_: Color(0xFFF92672),
    identifier: Color(0xFFF8F8F2), function_: Color(0xFFA6E22E), type_: Color(0xFF66D9EF),
    annotation: Color(0xFFA6E22E), literal: Color(0xFFAE81FF), htmlTag: Color(0xFFF92672),
    attrName: Color(0xFFA6E22E), attrValue: Color(0xFFE6DB74), preprocessor: Color(0xFFA6E22E),
    constant: Color(0xFFAE81FF), namespace: Color(0xFF66D9EF), label: Color(0xFFF92672),
    punctuation: Color(0xFFF8F8F2), blockLine: Color(0xFF3E3D32), blockLineActive: Color(0xFF49483E),
    lineDivider: Color(0xFF3E3D32), hardWrapMarker: Color(0xFF49483E), stickyScrollDivider: Color(0xFF49483E),
    selectedTextBorder: Color(0xFF66D9EF), currentRowBorder: Color(0xFF49483E),
    cursor: Color(0xFFF8F8F0), selectionHandle: Color(0xFF66D9EF),
    scrollBarThumb: Color(0xFF49483E), scrollBarThumbPressed: Color(0xFF75715E),
    scrollBarTrack: Color(0xFF272822), bracketPairBorder: Color(0xFFA6E22E), bracketPairFill: Color(0x1AA6E22E), activeBlockLineHighlight: Color(0xFF3A3A28),
    highlightedDelimitersFg: Color(0xFFFFE792),
    highlightedDelimitersUnderline: Color(0xFFFFE792), highlightedDelimitersBg: Color(0x22FFE792),
    problemError: Color(0xFFF92672), problemWarning: Color(0xFFE6DB74), problemTypo: Color(0xFF66D9EF),
    diagnosticTooltipBackground: Color(0xFF1E1F1C), diagnosticTooltipText: Color(0xFFF8F8F2),
    completionBackground: Color(0xFF1E1F1C), completionItemBackground: Color(0xFF1E1F1C),
    completionItemSelected: Color(0xFF3E3D32), completionTextPrimary: Color(0xFFF8F8F2),
    completionTextSecondary: Color(0xFF90908A), completionTextMatched: Color(0xFFA6E22E),
    completionBorder: Color(0xFF3E3D32), inlayHintForeground: Color(0xFF90908A),
    inlayHintBackground: Color(0xFF3E3D32), hoverBackground: Color(0xFF1E1F1C),
    hoverBorder: Color(0xFF3E3D32), hoverText: Color(0xFFF8F8F2),
    signatureBackground: Color(0xFF1E1F1C), signatureBorder: Color(0xFF3E3D32),
    signatureText: Color(0xFFF8F8F2), signatureHighlightedParam: Color(0xFFFFE792),
    textActionBackground: Color(0xFF3E3D32), textActionIconColor: Color(0xFFF8F8F2),
  );
}
