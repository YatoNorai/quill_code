// lib/src/theme/indent_program.dart
//
// ══════════════════════════════════════════════════════════════════════════════
// IndentLineProgram — a tiny drawing DSL for indent-guide lines.
//
// Instead of choosing from a fixed enum of styles (solid, dashed…),
// theme creators compose a list of "ops" (drawing operations) that the
// renderer executes sequentially, tiling them until the guide is complete.
// This gives full creative freedom from pure JSON — no code changes needed.
//
// ─── JSON format ──────────────────────────────────────────────────────────────
//
//   "blockLines": {
//     "color":          "#44475A55",
//     "activeColor":    "#BD93F9FF",
//     "width":          1.0,
//     "activeWidth":    2.0,
//     "inactiveOpacity": 0.5,
//     "colorMode":      "single",          // or "rainbow"
//     "rainbowColors":  ["#ff0000", ...],
//
//     // ── Inactive blocks ──────────────────────────────────────────────
//     "program": [
//       { "op": "line",    "length": 5 },
//       { "op": "gap",     "length": 3 }
//     ],
//     "endCap": { "type": "none" },
//
//     // ── Active block (contains cursor) ───────────────────────────────
//     "activeProgram": [
//       { "op": "line", "fill": true }
//     ],
//     "activeEndCap": { "type": "curve", "radius": 8, "tick": 12 }
//   }
//
// ─── Available ops ────────────────────────────────────────────────────────────
//
//   { "op": "line",    "length": 4 }          straight segment, N px tall
//   { "op": "line",    "fill": true }          straight segment to end of guide
//   { "op": "gap",     "length": 3 }           transparent gap, N px tall
//   { "op": "dot",     "radius": 1.5 }         filled circle
//   { "op": "dot",     "radius": 1.5, "square": true }  filled square
//   { "op": "wave",    "height": 8,  "period": 8, "amplitude": 2 }   sine wave
//   { "op": "wave",    "fill": true, "period": 8, "amplitude": 2 }   wave to end
//   { "op": "zigzag",  "height": 6,  "period": 6, "amplitude": 2 }   zigzag
//   { "op": "zigzag",  "fill": true, "period": 6, "amplitude": 2 }
//   { "op": "arrow",   "size": 4 }             tiny downward arrowhead
//   { "op": "cross",   "size": 3 }             × marker
//
// ─── Available end-caps ───────────────────────────────────────────────────────
//
//   { "type": "none" }
//   { "type": "curve",  "radius": 8, "tick": 12 }   └── style
//   { "type": "L",      "tick": 10,  "where": "bottom" }  L-shape (top/bottom/both)
//   { "type": "arrow",  "size": 6 }                 → arrowhead at bottom
//
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/painting.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Op base + subtypes
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for a single drawing instruction in an [IndentLineProgram].
sealed class IndentLineOp {
  const IndentLineOp();
}

// ── Straight segment ─────────────────────────────────────────────────────────

/// Draw a solid line segment.
///
/// - [length]: height in logical pixels (ignored when [fill] is true).
/// - [fill]: if true, extends to fill all remaining vertical space before
///   the end-cap region.
class OpLine extends IndentLineOp {
  final double length;
  final bool   fill;
  const OpLine({this.length = 4.0, this.fill = false});
}

// ── Gap (transparent space) ──────────────────────────────────────────────────

/// Skip [length] pixels without drawing anything.
class OpGap extends IndentLineOp {
  final double length;
  const OpGap({this.length = 3.0});
}

// ── Dot ──────────────────────────────────────────────────────────────────────

/// Draw a single dot and advance by its diameter.
///
/// - [radius]: logical pixels.
/// - [square]: if true, draw a filled square instead of a circle.
/// - [gap]: extra space added after the dot.
class OpDot extends IndentLineOp {
  final double radius;
  final bool   square;
  final double gap;
  const OpDot({this.radius = 1.5, this.square = false, this.gap = 2.5});
}

// ── Wave ─────────────────────────────────────────────────────────────────────

/// Draw a sine-wave path segment.
///
/// - [height] / [fill]: vertical space consumed.
/// - [period]: px per full cycle (wavelength).
/// - [amplitude]: horizontal deviation from the guide x position.
/// - [phase]: starting phase offset in radians (0 = start at centre).
class OpWave extends IndentLineOp {
  final double height;
  final bool   fill;
  final double period;
  final double amplitude;
  final double phase;
  const OpWave({
    this.height    = 8.0,
    this.fill      = false,
    this.period    = 8.0,
    this.amplitude = 2.0,
    this.phase     = 0.0,
  });
}

// ── Zigzag ───────────────────────────────────────────────────────────────────

/// Draw a zigzag (triangular wave) path segment.
class OpZigzag extends IndentLineOp {
  final double height;
  final bool   fill;
  final double period;
  final double amplitude;
  const OpZigzag({
    this.height    = 6.0,
    this.fill      = false,
    this.period    = 6.0,
    this.amplitude = 2.0,
  });
}

// ── Arrow marker ─────────────────────────────────────────────────────────────

/// Draw a small inline downward-pointing arrowhead, then a gap.
class OpArrow extends IndentLineOp {
  final double size; // half-width of the arrowhead
  final double gap;
  const OpArrow({this.size = 3.0, this.gap = 4.0});
}

// ── Cross marker ─────────────────────────────────────────────────────────────

/// Draw a small × cross marker, then a gap.
class OpCross extends IndentLineOp {
  final double size;
  final double gap;
  const OpCross({this.size = 2.5, this.gap = 4.0});
}

// ─────────────────────────────────────────────────────────────────────────────
// End-cap
// ─────────────────────────────────────────────────────────────────────────────

/// What to draw at the terminal end of an indent guide.
enum IndentCapType {
  /// Nothing.
  none,
  /// └── rounded corner down-right + horizontal tick toward `}` (end cap).
  curve,
  /// L-shape square corner + horizontal tick (end cap).
  lShape,
  /// Small → arrowhead pointing right (end cap).
  arrow,
  /// ─┐ horizontal underline from indent x rightward then corner curving DOWN.
  /// Used as a START cap: draws under the `{` line and turns downward.
  openCurve,
}

class IndentLineCap {
  final IndentCapType type;
  final double radius;   // corner radius (curve)
  final double tick;     // horizontal arm length
  final String where;    // 'top' | 'bottom' | 'both'  (lShape)
  final double size;     // arrowhead half-size

  const IndentLineCap({
    this.type   = IndentCapType.none,
    this.radius = 7.0,
    this.tick   = 10.0,
    this.where  = 'bottom',
    this.size   = 4.0,
  });

  static const IndentLineCap none   = IndentLineCap(type: IndentCapType.none);
  static const IndentLineCap curve  = IndentLineCap(type: IndentCapType.curve);
  static const IndentLineCap lShape = IndentLineCap(type: IndentCapType.lShape);
}

// ─────────────────────────────────────────────────────────────────────────────
// Program
// ─────────────────────────────────────────────────────────────────────────────

/// A complete drawing program for one indent guide line.
///
/// The renderer tiles [ops] repeatedly from top to bottom, stopping before
/// the end-cap region.  If any op has `fill: true`, tiling stops after that
/// op (the op consumes all remaining space).
class IndentLineProgram {
  final List<IndentLineOp> ops;
  final IndentLineCap      endCap;
  /// Optional cap drawn at the TOP of the guide (before ops execute).
  final IndentLineCap      startCap;

  const IndentLineProgram({
    required this.ops,
    this.endCap   = IndentLineCap.none,
    this.startCap = IndentLineCap.none,
  });

  bool get hasEndCap   => endCap.type   != IndentCapType.none;
  bool get hasStartCap => startCap.type != IndentCapType.none;

  // ── Built-in programs (generated from legacy BlockLineStyle) ─────────────

  static IndentLineProgram solid(double dashLen) =>
    const IndentLineProgram(ops: [OpLine(fill: true)]);

  static IndentLineProgram dashed(double dashLen, double dashGap) =>
    IndentLineProgram(ops: [OpLine(length: dashLen), OpGap(length: dashGap)]);

  static IndentLineProgram dotted(double spacing) =>
    IndentLineProgram(ops: [OpDot(radius: 1.5, gap: spacing - 3)]);

  static IndentLineProgram squareDotted(double spacing) =>
    IndentLineProgram(ops: [OpDot(radius: 1.5, square: true, gap: spacing - 3)]);

  static IndentLineProgram longDash(double dashLen, double dashGap) =>
    IndentLineProgram(ops: [OpLine(length: dashLen * 2.5), OpGap(length: dashGap)]);

  static IndentLineProgram doubleDash(double dashLen, double dashGap) =>
    IndentLineProgram(ops: [
      OpLine(length: dashLen),      OpGap(length: dashGap),
      OpLine(length: dashLen / 2),  OpGap(length: dashGap),
    ]);

  static IndentLineProgram curved(double radius, double tick) =>
    IndentLineProgram(
      ops: [OpLine(fill: true)],
      endCap: IndentLineCap(type: IndentCapType.curve, radius: radius, tick: tick),
    );

  static IndentLineProgram underlineCurved(double radius, double tick) =>
    IndentLineProgram(
      ops: [OpLine(fill: true)],
      startCap: IndentLineCap(type: IndentCapType.openCurve, radius: radius, tick: tick),
      endCap:   IndentLineCap(type: IndentCapType.curve, radius: radius, tick: tick),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON → Program parser
// ─────────────────────────────────────────────────────────────────────────────

/// Parses the `"program"` / `"endCap"` keys from a blockLines JSON map.
class IndentProgramParser {
  IndentProgramParser._();

  static IndentLineProgram? tryParse(Map<String, dynamic> m, String key,
      String capKey, {String startCapKey = 'startCap'}) {
    final rawOps = m[key];
    if (rawOps == null) return null;
    if (rawOps is! List) return null;

    final ops = rawOps
        .whereType<Map<String, dynamic>>()
        .map(_parseOp)
        .whereType<IndentLineOp>()
        .toList();

    final endCap   = _parseCap(m[capKey]);
    final startCap = _parseCap(m[startCapKey]);
    return IndentLineProgram(ops: ops, endCap: endCap, startCap: startCap);
  }

  static IndentLineOp? _parseOp(Map<String, dynamic> m) {
    final op = m['op'] as String?;
    return switch (op) {
      'line' => OpLine(
          length: (m['length'] as num?)?.toDouble() ?? 4.0,
          fill:   (m['fill']   as bool?) ?? false,
        ),
      'gap' => OpGap(
          length: (m['length'] as num?)?.toDouble() ?? 3.0,
        ),
      'dot' => OpDot(
          radius: (m['radius'] as num?)?.toDouble() ?? 1.5,
          square: (m['square'] as bool?) ?? false,
          gap:    (m['gap']    as num?)?.toDouble() ?? 2.5,
        ),
      'wave' => OpWave(
          height:    (m['height']    as num?)?.toDouble() ?? 8.0,
          fill:      (m['fill']      as bool?) ?? false,
          period:    (m['period']    as num?)?.toDouble() ?? 8.0,
          amplitude: (m['amplitude'] as num?)?.toDouble() ?? 2.0,
          phase:     (m['phase']     as num?)?.toDouble() ?? 0.0,
        ),
      'zigzag' => OpZigzag(
          height:    (m['height']    as num?)?.toDouble() ?? 6.0,
          fill:      (m['fill']      as bool?) ?? false,
          period:    (m['period']    as num?)?.toDouble() ?? 6.0,
          amplitude: (m['amplitude'] as num?)?.toDouble() ?? 2.0,
        ),
      'arrow' => OpArrow(
          size: (m['size'] as num?)?.toDouble() ?? 3.0,
          gap:  (m['gap']  as num?)?.toDouble() ?? 4.0,
        ),
      'cross' => OpCross(
          size: (m['size'] as num?)?.toDouble() ?? 2.5,
          gap:  (m['gap']  as num?)?.toDouble() ?? 4.0,
        ),
      _ => null,
    };
  }

  static IndentLineCap _parseCap(dynamic raw) {
    if (raw is! Map<String, dynamic>) return IndentLineCap.none;
    final type = switch (raw['type'] as String?) {
      'curve'      => IndentCapType.curve,
      'L'          => IndentCapType.lShape,
      'lShape'     => IndentCapType.lShape,
      'arrow'      => IndentCapType.arrow,
      'openCurve'  => IndentCapType.openCurve,
      _            => IndentCapType.none,
    };
    return IndentLineCap(
      type:   type,
      radius: (raw['radius'] as num?)?.toDouble() ?? 7.0,
      tick:   (raw['tick']   as num?)?.toDouble() ?? 10.0,
      where:  (raw['where']  as String?) ?? 'bottom',
      size:   (raw['size']   as num?)?.toDouble() ?? 4.0,
    );
  }
}
