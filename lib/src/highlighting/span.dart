// lib/src/highlighting/span.dart
import 'package:flutter/painting.dart';

/// Token type identifiers — maps to theme colors.
enum TokenType {
  normal,
  keyword,
  comment,
  string,
  number,
  operator_,
  identifier,
  function_,
  type_,
  annotation,
  literal,
  htmlTag,
  attrName,
  attrValue,
  preprocessor,
  error_,
  warning_,
  namespace,
  constant,
  label,
  punctuation,
}

/// Style flags for a span.
class SpanStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  /// If set, overrides theme foreground color for this span.
  final Color? foregroundColor;
  /// If set, renders a colored background behind this span.
  final Color? backgroundColor;

  const SpanStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.foregroundColor,
    this.backgroundColor,
  });

  static const SpanStyle empty = SpanStyle();

  TextStyle toTextStyle(Color defaultFg) => TextStyle(
        color: foregroundColor ?? defaultFg,
        backgroundColor: backgroundColor,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: _decoration,
      );

  TextDecoration get _decoration {
    if (underline && strikethrough) {
      return TextDecoration.combine(
          [TextDecoration.underline, TextDecoration.lineThrough]);
    }
    if (underline) return TextDecoration.underline;
    if (strikethrough) return TextDecoration.lineThrough;
    return TextDecoration.none;
  }
}

/// A single styled span on a line.
/// [column] is the starting column index (inclusive).
/// Spans are terminated by the next span on the same line.
class CodeSpan {
  final int column;
  final TokenType type;
  final SpanStyle style;

  const CodeSpan({
    required this.column,
    required this.type,
    this.style = SpanStyle.empty,
  });

  CodeSpan copyWith({int? column, TokenType? type, SpanStyle? style}) =>
      CodeSpan(
        column: column ?? this.column,
        type: type ?? this.type,
        style: style ?? this.style,
      );
}
