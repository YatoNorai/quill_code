// lib/src/theme/theme_dracula.dart
import 'package:flutter/painting.dart';
import 'color_scheme.dart';
import 'editor_theme.dart';

class QuillThemeDracula {
  static EditorTheme build({String fontFamily = 'monospace', double fontSize = 14.0}) =>
      EditorTheme(
        fontFamily: fontFamily, fontSize: fontSize, colorScheme: _scheme,
        blockLines: const BlockLineTheme(color: Color(0x6644475A), activeColor: Color(0xCCBD93F9), style: BlockLineStyle.dashed, colorMode: BlockLineColorMode.rainbow, rainbowColors: [Color(0xFFFF79C6), Color(0xFF50FA7B), Color(0xFFF1FA8C), Color(0xFF8BE9FD), Color(0xFFBD93F9), Color(0xFFFFB86C)], dashLength: 5.0, dashGap: 3.0, inactiveOpacity: 0.55, curveRadius: 7.0),
        bracketPair: const BracketPairTheme(fillColor: Color(0x1ABD93F9), borderColor: Color(0x80BD93F9), borderWidth: 1.2, radius: 3.0),
        indentDots: const IndentDotTheme(visible: true, color: Color(0x556272A4)),
      );
  static const EditorColorScheme _scheme = EditorColorScheme(
    background: Color(0xFF282A36), lineNumberBackground: Color(0xFF21222C),
    currentLineBackground: Color(0xFF44475A), selectionColor: Color(0x5544475A),
    searchMatchBackground: Color(0x55FFB86C), searchMatchBorder: Color(0xFFFFB86C),
    snippetActiveBackground: Color(0x3350FA7B), snippetInactiveBackground: Color(0x1A50FA7B),
    textNormal: Color(0xFFF8F8F2), lineNumber: Color(0xFF6272A4), lineNumberCurrent: Color(0xFFF8F8F2),
    nonPrintableChar: Color(0xFF44475A), keyword: Color(0xFFFF79C6), comment: Color(0xFF6272A4),
    string: Color(0xFFF1FA8C), number: Color(0xFFBD93F9), operator_: Color(0xFFFF79C6),
    identifier: Color(0xFFF8F8F2), function_: Color(0xFF50FA7B), type_: Color(0xFF8BE9FD),
    annotation: Color(0xFFFFB86C), literal: Color(0xFFBD93F9), htmlTag: Color(0xFFFF79C6),
    attrName: Color(0xFF50FA7B), attrValue: Color(0xFFF1FA8C), preprocessor: Color(0xFFFFB86C),
    constant: Color(0xFFBD93F9), namespace: Color(0xFF8BE9FD), label: Color(0xFFFF79C6),
    punctuation: Color(0xFFF8F8F2), blockLine: Color(0xFF44475A), blockLineActive: Color(0xFF6272A4),
    lineDivider: Color(0xFF44475A), hardWrapMarker: Color(0xFF44475A), stickyScrollDivider: Color(0xFF44475A),
    selectedTextBorder: Color(0xFF8BE9FD), currentRowBorder: Color(0xFF44475A),
    cursor: Color(0xFFF8F8F2), selectionHandle: Color(0xFF8BE9FD),
    scrollBarThumb: Color(0xFF44475A), scrollBarThumbPressed: Color(0xFF6272A4),
    scrollBarTrack: Color(0xFF282A36), bracketPairBorder: Color(0xFFBD93F9), bracketPairFill: Color(0x1ABD93F9), activeBlockLineHighlight: Color(0xFF383A59),
    highlightedDelimitersFg: Color(0xFFFFB86C),
    highlightedDelimitersUnderline: Color(0xFFFFB86C), highlightedDelimitersBg: Color(0x22FFB86C),
    problemError: Color(0xFFFF5555), problemWarning: Color(0xFFFFB86C), problemTypo: Color(0xFF8BE9FD),
    diagnosticTooltipBackground: Color(0xFF21222C), diagnosticTooltipText: Color(0xFFF8F8F2),
    completionBackground: Color(0xFF21222C), completionItemBackground: Color(0xFF21222C),
    completionItemSelected: Color(0xFF44475A), completionTextPrimary: Color(0xFFF8F8F2),
    completionTextSecondary: Color(0xFF6272A4), completionTextMatched: Color(0xFF50FA7B),
    completionBorder: Color(0xFF44475A), inlayHintForeground: Color(0xFF6272A4),
    inlayHintBackground: Color(0xFF44475A), hoverBackground: Color(0xFF21222C),
    hoverBorder: Color(0xFF44475A), hoverText: Color(0xFFF8F8F2),
    signatureBackground: Color(0xFF21222C), signatureBorder: Color(0xFF44475A),
    signatureText: Color(0xFFF8F8F2), signatureHighlightedParam: Color(0xFFFFB86C),
    textActionBackground: Color(0xFF44475A), textActionIconColor: Color(0xFFF8F8F2),
  );
}
