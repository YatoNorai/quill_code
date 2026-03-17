// lib/src/theme/editor_theme.dart
import 'package:flutter/painting.dart';
import 'color_scheme.dart';
import 'indent_program.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Legacy enums — kept for convenience / backward compat.
// When a JSON theme sets "program" / "activeProgram", the enums are ignored.
// ─────────────────────────────────────────────────────────────────────────────

enum BlockLineStyle {
  none, solid, dashed, dotted, squareDotted, longDash, doubleDash, curved,
}

enum BlockLineColorMode { single, rainbow }

enum BlockLineCapStyle { none, topLeft, bottomLeft, both }

// ─────────────────────────────────────────────────────────────────────────────
// BlockLineTheme
// ─────────────────────────────────────────────────────────────────────────────

/// Theme for indentation guide lines.
///
/// ### Two modes — theme creators choose either:
///
/// **Mode A — program (full freedom):**
/// Set `program` / `activeProgram` to an [IndentLineProgram] built from ops.
/// The renderer executes the program as a mini drawing VM.
/// JSON keys: `"program": [...]`, `"endCap": {...}`,
///            `"activeProgram": [...]`, `"activeEndCap": {...}`.
///
/// **Mode B — style enum (convenience):**
/// Set `style` / `activeStyle` to one of the [BlockLineStyle] values.
/// Internally converted to a program before rendering.
/// JSON keys: `"style": "dashed"`, `"activeStyle": "curved"`, etc.
///
/// Programs always win over enum styles when both are present.
class BlockLineTheme {
  // ── Colors ──────────────────────────────────────────────────────────────
  final Color color;
  final Color activeColor;

  // ── Widths ──────────────────────────────────────────────────────────────
  final double  width;
  final double? activeWidth;

  // ── Legacy enum styles (Mode B) ─────────────────────────────────────────
  final BlockLineStyle  style;
  final BlockLineStyle? activeStyle;

  // ── Programs (Mode A — overrides enum styles) ────────────────────────────
  final IndentLineProgram? program;
  final IndentLineProgram? activeProgram;

  // ── Color cycling ────────────────────────────────────────────────────────
  final BlockLineColorMode colorMode;
  final List<Color>        rainbowColors;

  // ── Shared dash/dot/curve parameters (used by both modes) ────────────────
  final double dashGap;
  final double dashLength;
  final double dotSpacing;
  final double capLength;
  final double inactiveOpacity;
  final double curveRadius;

  const BlockLineTheme({
    this.color            = const Color(0xFF3C3C3C),
    this.activeColor      = const Color(0xFF6C7086),
    this.width            = 1.0,
    this.activeWidth,
    this.style            = BlockLineStyle.solid,
    this.activeStyle,
    this.program,
    this.activeProgram,
    this.colorMode        = BlockLineColorMode.single,
    this.rainbowColors    = defaultRainbowColors,
    this.dashGap          = 3.0,
    this.dashLength       = 4.0,
    this.dotSpacing       = 5.0,
    this.capLength        = 10.0,
    this.inactiveOpacity  = 1.0,
    this.curveRadius      = 7.0,
  });

  // ── Resolved programs (lazily converts enum style if no explicit program) ─

  /// The program used to draw **inactive** guide lines.
  IndentLineProgram get resolvedProgram =>
      program ?? _styleToProgram(style);

  /// The program used to draw the **active** (cursor-containing) guide.
  IndentLineProgram get resolvedActiveProgram =>
      activeProgram ?? (activeStyle != null ? _styleToProgram(activeStyle!) : resolvedProgram);

  IndentLineProgram _styleToProgram(BlockLineStyle s) => switch (s) {
    BlockLineStyle.none        => IndentLineProgram(ops: const []),
    BlockLineStyle.solid       => IndentLineProgram.solid(dashLength),
    BlockLineStyle.dashed      => IndentLineProgram.dashed(dashLength, dashGap),
    BlockLineStyle.dotted      => IndentLineProgram.dotted(dotSpacing),
    BlockLineStyle.squareDotted=> IndentLineProgram.squareDotted(dotSpacing),
    BlockLineStyle.longDash    => IndentLineProgram.longDash(dashLength, dashGap),
    BlockLineStyle.doubleDash  => IndentLineProgram.doubleDash(dashLength, dashGap),
    BlockLineStyle.curved      => IndentLineProgram.curved(curveRadius, capLength),
  };

  double get resolvedActiveWidth => activeWidth ?? width;

  // ── Defaults ─────────────────────────────────────────────────────────────
  static const List<Color> defaultRainbowColors = [
    Color(0xFF89B4FA),
    Color(0xFFA6E3A1),
    Color(0xFFFAB387),
    Color(0xFFCBA6F7),
    Color(0xFF89DCEB),
    Color(0xFFF38BA8),
    Color(0xFFF9E2AF),
  ];

  // ── copyWith ─────────────────────────────────────────────────────────────
  BlockLineTheme copyWith({
    Color?              color,
    Color?              activeColor,
    double?             width,
    double?             activeWidth,
    BlockLineStyle?     style,
    BlockLineStyle?     activeStyle,
    IndentLineProgram?  program,
    IndentLineProgram?  activeProgram,
    BlockLineColorMode? colorMode,
    List<Color>?        rainbowColors,
    double?             dashGap,
    double?             dashLength,
    double?             dotSpacing,
    double?             capLength,
    double?             inactiveOpacity,
    double?             curveRadius,
  }) => BlockLineTheme(
    color:           color           ?? this.color,
    activeColor:     activeColor     ?? this.activeColor,
    width:           width           ?? this.width,
    activeWidth:     activeWidth     ?? this.activeWidth,
    style:           style           ?? this.style,
    activeStyle:     activeStyle     ?? this.activeStyle,
    program:         program         ?? this.program,
    activeProgram:   activeProgram   ?? this.activeProgram,
    colorMode:       colorMode       ?? this.colorMode,
    rainbowColors:   rainbowColors   ?? this.rainbowColors,
    dashGap:         dashGap         ?? this.dashGap,
    dashLength:      dashLength      ?? this.dashLength,
    dotSpacing:      dotSpacing      ?? this.dotSpacing,
    capLength:       capLength       ?? this.capLength,
    inactiveOpacity: inactiveOpacity ?? this.inactiveOpacity,
    curveRadius:     curveRadius     ?? this.curveRadius,
  );

  @override
  bool operator ==(Object o) =>
    identical(this, o) || o is BlockLineTheme &&
    o.color == color && o.activeColor == activeColor &&
    o.width == width && o.activeWidth == activeWidth &&
    o.style == style && o.activeStyle == activeStyle &&
    o.program == program && o.activeProgram == activeProgram &&
    o.colorMode == colorMode &&
    o.dashGap == dashGap && o.dashLength == dashLength &&
    o.dotSpacing == dotSpacing && o.capLength == capLength &&
    o.inactiveOpacity == inactiveOpacity && o.curveRadius == curveRadius;

  @override
  int get hashCode => Object.hash(color, activeColor, width, style,
    activeStyle, program, activeProgram, colorMode, dashGap, dashLength,
    dotSpacing, capLength, inactiveOpacity, curveRadius);
}

// ─────────────────────────────────────────────────────────────────────────────
// BracketPairTheme / IndentDotTheme / EditorTheme — unchanged
// ─────────────────────────────────────────────────────────────────────────────

class BracketPairTheme {
  final Color  fillColor;
  final Color  borderColor;
  final double borderWidth;
  final double radius;

  const BracketPairTheme({
    this.fillColor   = const Color(0x1A89B4FA),
    this.borderColor = const Color(0x8089B4FA),
    this.borderWidth = 1.2,
    this.radius      = 2.0,
  });

  BracketPairTheme copyWith({Color? fillColor, Color? borderColor,
      double? borderWidth, double? radius}) =>
    BracketPairTheme(
      fillColor:   fillColor   ?? this.fillColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      radius:      radius      ?? this.radius,
    );

  @override bool operator ==(Object o) => identical(this,o) ||
    o is BracketPairTheme && o.fillColor==fillColor &&
    o.borderColor==borderColor && o.borderWidth==borderWidth && o.radius==radius;
  @override int get hashCode => Object.hash(fillColor,borderColor,borderWidth,radius);
}

class IndentDotTheme {
  final bool        visible;
  final Color       color;
  final double      size;
  final IndentDotMode mode;

  const IndentDotTheme({
    this.visible = false,
    this.color   = const Color(0x446C7086),
    this.size    = 1.5,
    this.mode    = IndentDotMode.indentOnly,
  });

  IndentDotTheme copyWith({bool? visible, Color? color, double? size, IndentDotMode? mode}) =>
    IndentDotTheme(
      visible: visible ?? this.visible,
      color:   color   ?? this.color,
      size:    size    ?? this.size,
      mode:    mode    ?? this.mode,
    );

  @override bool operator ==(Object o) => identical(this,o) ||
    o is IndentDotTheme && o.visible==visible && o.color==color &&
    o.size==size && o.mode==mode;
  @override int get hashCode => Object.hash(visible,color,size,mode);
}

enum IndentDotMode { indentOnly, all }

class EditorTheme {
  final EditorColorScheme colorScheme;
  final String            fontFamily;
  final double            fontSize;
  final double            lineHeight;
  final double            letterSpacing;
  final double            cursorWidth;
  final BlockLineTheme    blockLines;
  final BracketPairTheme  bracketPair;
  final IndentDotTheme    indentDots;

  const EditorTheme({
    required this.colorScheme,
    this.fontFamily    = 'monospace',
    this.fontSize      = 14.0,
    this.lineHeight    = 1.5,
    this.letterSpacing = 0.0,
    this.cursorWidth   = 2.0,
    this.blockLines    = const BlockLineTheme(),
    this.bracketPair   = const BracketPairTheme(),
    this.indentDots    = const IndentDotTheme(),
  });

  double get lineHeightPx => fontSize * lineHeight;

  EditorTheme copyWith({
    EditorColorScheme? colorScheme, String? fontFamily,
    double? fontSize, double? lineHeight, double? letterSpacing,
    double? cursorWidth,
    BlockLineTheme? blockLines, BracketPairTheme? bracketPair, IndentDotTheme? indentDots,
  }) => EditorTheme(
    colorScheme:   colorScheme   ?? this.colorScheme,
    fontFamily:    fontFamily    ?? this.fontFamily,
    fontSize:      fontSize      ?? this.fontSize,
    lineHeight:    lineHeight    ?? this.lineHeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    cursorWidth:   cursorWidth   ?? this.cursorWidth,
    blockLines:    blockLines    ?? this.blockLines,
    bracketPair:   bracketPair   ?? this.bracketPair,
    indentDots:    indentDots    ?? this.indentDots,
  );

  @override bool operator ==(Object o) => identical(this,o) ||
    o is EditorTheme && o.colorScheme==colorScheme && o.fontFamily==fontFamily &&
    o.fontSize==fontSize && o.lineHeight==lineHeight && o.letterSpacing==letterSpacing &&
    o.cursorWidth==cursorWidth &&
    o.blockLines==blockLines && o.bracketPair==bracketPair && o.indentDots==indentDots;
  @override int get hashCode => Object.hash(colorScheme,fontFamily,fontSize,
    lineHeight,letterSpacing,cursorWidth,blockLines,bracketPair,indentDots);
}
