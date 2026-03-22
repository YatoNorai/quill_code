// lib/src/theme/color_scheme.dart
import 'package:flutter/painting.dart';

/// All color tokens used by the editor renderer.
class EditorColorScheme {
  // ── Background ────────────────────────────────────────────────────────────
  final Color background;
  final Color lineNumberBackground;
  final Color currentLineBackground;
  final Color selectionColor;
  final Color searchMatchBackground;
  final Color searchMatchBorder;
  final Color snippetActiveBackground;
  final Color snippetInactiveBackground;

  // ── Text ──────────────────────────────────────────────────────────────────
  final Color textNormal;
  final Color lineNumber;
  final Color lineNumberCurrent;
  final Color nonPrintableChar;

  // ── Syntax ────────────────────────────────────────────────────────────────
  final Color keyword;
  final Color comment;
  final Color string;
  final Color number;
  final Color operator_;
  final Color identifier;
  final Color function_;
  final Color type_;
  final Color annotation;
  final Color literal;
  final Color htmlTag;
  final Color attrName;
  final Color attrValue;
  final Color preprocessor;
  final Color constant;
  final Color namespace;
  final Color label;
  final Color punctuation;

  // ── Structural ────────────────────────────────────────────────────────────
  final Color blockLine;
  final Color blockLineActive;
  final Color lineDivider;
  final Color hardWrapMarker;
  final Color stickyScrollDivider;
  final Color selectedTextBorder;
  final Color currentRowBorder;

  // ── Cursor ────────────────────────────────────────────────────────────────
  final Color cursor;
  final Color selectionHandle;

  // ── Scrollbar ─────────────────────────────────────────────────────────────
  final Color scrollBarThumb;
  final Color scrollBarThumbPressed;
  final Color scrollBarTrack;

  // ── Delimiter highlight ───────────────────────────────────────────────────
  final Color bracketPairBorder;
  final Color bracketPairFill;
  final Color activeBlockLineHighlight;
  final Color highlightedDelimitersFg;
  final Color highlightedDelimitersUnderline;
  final Color highlightedDelimitersBg;

  // ── Diagnostics ───────────────────────────────────────────────────────────
  final Color problemError;
  final Color problemWarning;
  final Color problemTypo;
  final Color diagnosticTooltipBackground;
  final Color diagnosticTooltipText;

  // ── Completion ────────────────────────────────────────────────────────────
  final Color completionBackground;
  final Color completionItemBackground;
  final Color completionItemSelected;
  final Color completionTextPrimary;
  final Color completionTextSecondary;
  final Color completionTextMatched;
  final Color completionBorder;

  // ── Inlay hints ───────────────────────────────────────────────────────────
  final Color inlayHintForeground;
  final Color inlayHintBackground;

  // ── Hover panel ───────────────────────────────────────────────────────────
  final Color hoverBackground;
  final Color hoverBorder;
  final Color hoverText;

  // ── Signature help ────────────────────────────────────────────────────────
  final Color signatureBackground;
  final Color signatureBorder;
  final Color signatureText;
  final Color signatureHighlightedParam;

  // ── Quick actions ─────────────────────────────────────────────────────────
  final Color textActionBackground;
  final Color textActionIconColor;

  // ── Ghost text (inline AI suggestions) ───────────────────────────────────
  final Color ghostTextForeground;

  const EditorColorScheme({
    required this.background,
    required this.lineNumberBackground,
    required this.currentLineBackground,
    required this.selectionColor,
    required this.searchMatchBackground,
    required this.searchMatchBorder,
    required this.snippetActiveBackground,
    required this.snippetInactiveBackground,
    required this.textNormal,
    required this.lineNumber,
    required this.lineNumberCurrent,
    required this.nonPrintableChar,
    required this.keyword,
    required this.comment,
    required this.string,
    required this.number,
    required this.operator_,
    required this.identifier,
    required this.function_,
    required this.type_,
    required this.annotation,
    required this.literal,
    required this.htmlTag,
    required this.attrName,
    required this.attrValue,
    required this.preprocessor,
    required this.constant,
    required this.namespace,
    required this.label,
    required this.punctuation,
    required this.blockLine,
    required this.blockLineActive,
    required this.lineDivider,
    required this.hardWrapMarker,
    required this.stickyScrollDivider,
    required this.selectedTextBorder,
    required this.currentRowBorder,
    required this.cursor,
    required this.selectionHandle,
    required this.scrollBarThumb,
    required this.scrollBarThumbPressed,
    required this.scrollBarTrack,
    required this.bracketPairBorder,
    required this.bracketPairFill,
    required this.activeBlockLineHighlight,
    required this.highlightedDelimitersFg,
    required this.highlightedDelimitersUnderline,
    required this.highlightedDelimitersBg,
    required this.problemError,
    required this.problemWarning,
    required this.problemTypo,
    required this.diagnosticTooltipBackground,
    required this.diagnosticTooltipText,
    required this.completionBackground,
    required this.completionItemBackground,
    required this.completionItemSelected,
    required this.completionTextPrimary,
    required this.completionTextSecondary,
    required this.completionTextMatched,
    required this.completionBorder,
    required this.inlayHintForeground,
    required this.inlayHintBackground,
    required this.hoverBackground,
    required this.hoverBorder,
    required this.hoverText,
    required this.signatureBackground,
    required this.signatureBorder,
    required this.signatureText,
    required this.signatureHighlightedParam,
    required this.textActionBackground,
    required this.textActionIconColor,
    this.ghostTextForeground = const Color(0xFF6A6A6A),
  });

  EditorColorScheme copyWith({
    Color? background,
    Color? lineNumberBackground,
    Color? currentLineBackground,
    Color? selectionColor,
    Color? searchMatchBackground,
    Color? searchMatchBorder,
    Color? snippetActiveBackground,
    Color? snippetInactiveBackground,
    Color? textNormal,
    Color? lineNumber,
    Color? lineNumberCurrent,
    Color? nonPrintableChar,
    Color? keyword,
    Color? comment,
    Color? string,
    Color? number,
    Color? operator_,
    Color? identifier,
    Color? function_,
    Color? type_,
    Color? annotation,
    Color? literal,
    Color? htmlTag,
    Color? attrName,
    Color? attrValue,
    Color? preprocessor,
    Color? constant,
    Color? namespace,
    Color? label,
    Color? punctuation,
    Color? blockLine,
    Color? blockLineActive,
    Color? lineDivider,
    Color? hardWrapMarker,
    Color? stickyScrollDivider,
    Color? selectedTextBorder,
    Color? currentRowBorder,
    Color? cursor,
    Color? selectionHandle,
    Color? scrollBarThumb,
    Color? scrollBarThumbPressed,
    Color? scrollBarTrack,
    Color? bracketPairBorder,
    Color? bracketPairFill,
    Color? activeBlockLineHighlight,
    Color? highlightedDelimitersFg,
    Color? highlightedDelimitersUnderline,
    Color? highlightedDelimitersBg,
    Color? problemError,
    Color? problemWarning,
    Color? problemTypo,
    Color? diagnosticTooltipBackground,
    Color? diagnosticTooltipText,
    Color? completionBackground,
    Color? completionItemBackground,
    Color? completionItemSelected,
    Color? completionTextPrimary,
    Color? completionTextSecondary,
    Color? completionTextMatched,
    Color? completionBorder,
    Color? inlayHintForeground,
    Color? inlayHintBackground,
    Color? hoverBackground,
    Color? hoverBorder,
    Color? hoverText,
    Color? signatureBackground,
    Color? signatureBorder,
    Color? signatureText,
    Color? signatureHighlightedParam,
    Color? textActionBackground,
    Color? textActionIconColor,
    Color? ghostTextForeground,
  }) => EditorColorScheme(
    background:                   background                   ?? this.background,
    lineNumberBackground:         lineNumberBackground         ?? this.lineNumberBackground,
    currentLineBackground:        currentLineBackground        ?? this.currentLineBackground,
    selectionColor:               selectionColor               ?? this.selectionColor,
    searchMatchBackground:        searchMatchBackground        ?? this.searchMatchBackground,
    searchMatchBorder:            searchMatchBorder            ?? this.searchMatchBorder,
    snippetActiveBackground:      snippetActiveBackground      ?? this.snippetActiveBackground,
    snippetInactiveBackground:    snippetInactiveBackground    ?? this.snippetInactiveBackground,
    textNormal:                   textNormal                   ?? this.textNormal,
    lineNumber:                   lineNumber                   ?? this.lineNumber,
    lineNumberCurrent:            lineNumberCurrent            ?? this.lineNumberCurrent,
    nonPrintableChar:             nonPrintableChar             ?? this.nonPrintableChar,
    keyword:                      keyword                      ?? this.keyword,
    comment:                      comment                      ?? this.comment,
    string:                       string                       ?? this.string,
    number:                       number                       ?? this.number,
    operator_:                    operator_                    ?? this.operator_,
    identifier:                   identifier                   ?? this.identifier,
    function_:                    function_                    ?? this.function_,
    type_:                        type_                        ?? this.type_,
    annotation:                   annotation                   ?? this.annotation,
    literal:                      literal                      ?? this.literal,
    htmlTag:                      htmlTag                      ?? this.htmlTag,
    attrName:                     attrName                     ?? this.attrName,
    attrValue:                    attrValue                    ?? this.attrValue,
    preprocessor:                 preprocessor                 ?? this.preprocessor,
    constant:                     constant                     ?? this.constant,
    namespace:                    namespace                    ?? this.namespace,
    label:                        label                        ?? this.label,
    punctuation:                  punctuation                  ?? this.punctuation,
    blockLine:                    blockLine                    ?? this.blockLine,
    blockLineActive:              blockLineActive              ?? this.blockLineActive,
    lineDivider:                  lineDivider                  ?? this.lineDivider,
    hardWrapMarker:               hardWrapMarker               ?? this.hardWrapMarker,
    stickyScrollDivider:          stickyScrollDivider          ?? this.stickyScrollDivider,
    selectedTextBorder:           selectedTextBorder           ?? this.selectedTextBorder,
    currentRowBorder:             currentRowBorder             ?? this.currentRowBorder,
    cursor:                       cursor                       ?? this.cursor,
    selectionHandle:              selectionHandle              ?? this.selectionHandle,
    scrollBarThumb:               scrollBarThumb               ?? this.scrollBarThumb,
    scrollBarThumbPressed:        scrollBarThumbPressed        ?? this.scrollBarThumbPressed,
    scrollBarTrack:               scrollBarTrack               ?? this.scrollBarTrack,
    bracketPairBorder:            bracketPairBorder            ?? this.bracketPairBorder,
    bracketPairFill:              bracketPairFill              ?? this.bracketPairFill,
    activeBlockLineHighlight:     activeBlockLineHighlight     ?? this.activeBlockLineHighlight,
    highlightedDelimitersFg:      highlightedDelimitersFg      ?? this.highlightedDelimitersFg,
    highlightedDelimitersUnderline: highlightedDelimitersUnderline ?? this.highlightedDelimitersUnderline,
    highlightedDelimitersBg:      highlightedDelimitersBg      ?? this.highlightedDelimitersBg,
    problemError:                 problemError                 ?? this.problemError,
    problemWarning:               problemWarning               ?? this.problemWarning,
    problemTypo:                  problemTypo                  ?? this.problemTypo,
    diagnosticTooltipBackground:  diagnosticTooltipBackground  ?? this.diagnosticTooltipBackground,
    diagnosticTooltipText:        diagnosticTooltipText        ?? this.diagnosticTooltipText,
    completionBackground:         completionBackground         ?? this.completionBackground,
    completionItemBackground:     completionItemBackground     ?? this.completionItemBackground,
    completionItemSelected:       completionItemSelected       ?? this.completionItemSelected,
    completionTextPrimary:        completionTextPrimary        ?? this.completionTextPrimary,
    completionTextSecondary:      completionTextSecondary      ?? this.completionTextSecondary,
    completionTextMatched:        completionTextMatched        ?? this.completionTextMatched,
    completionBorder:             completionBorder             ?? this.completionBorder,
    inlayHintForeground:          inlayHintForeground          ?? this.inlayHintForeground,
    inlayHintBackground:          inlayHintBackground          ?? this.inlayHintBackground,
    hoverBackground:              hoverBackground              ?? this.hoverBackground,
    hoverBorder:                  hoverBorder                  ?? this.hoverBorder,
    hoverText:                    hoverText                    ?? this.hoverText,
    signatureBackground:          signatureBackground          ?? this.signatureBackground,
    signatureBorder:              signatureBorder              ?? this.signatureBorder,
    signatureText:                signatureText                ?? this.signatureText,
    signatureHighlightedParam:    signatureHighlightedParam    ?? this.signatureHighlightedParam,
    textActionBackground:         textActionBackground         ?? this.textActionBackground,
    textActionIconColor:          textActionIconColor          ?? this.textActionIconColor,
    ghostTextForeground:          ghostTextForeground          ?? this.ghostTextForeground,
  );

  Color colorForToken(String key) {
    switch (key) {
      case 'keyword':      return keyword;
      case 'comment':      return comment;
      case 'string':       return string;
      case 'number':       return number;
      case 'operator':
      case 'operator_':    return operator_;
      case 'identifier':   return identifier;
      case 'function':
      case 'function_':    return function_;
      case 'type':
      case 'type_':        return type_;
      case 'annotation':   return annotation;
      case 'literal':      return literal;
      case 'htmlTag':      return htmlTag;
      case 'attrName':     return attrName;
      case 'attrValue':    return attrValue;
      case 'preprocessor': return preprocessor;
      case 'constant':     return constant;
      case 'namespace':    return namespace;
      case 'label':        return label;
      case 'punctuation':  return punctuation;
      // BUG FIX: errorText and warningText were missing → fell back to textNormal
      case 'errorText':    return problemError;
      case 'warningText':  return problemWarning;
      default:             return textNormal;
    }
  }
}
