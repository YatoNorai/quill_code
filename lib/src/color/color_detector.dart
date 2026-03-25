// lib/src/color/color_detector.dart
// Detects color values in source code lines and returns Color + character range.
// Supported formats:
//   #RGB  #RRGGBB  #AARRGGBB  (CSS/Android hex)
//   Color(0xAARRGGBB)  Color.fromARGB(a,r,g,b)  Color.fromRGBO(r,g,b,op)  (Flutter/Dart)
//   rgb(r,g,b)  rgba(r,g,b,a)  hsl(h,s%,l%)  hsla(h,s%,l%,a)  (CSS)
import 'dart:ui' show Color;

class ColorMatch {
  final Color  color;
  final int    start; // column index, inclusive
  final int    end;   // column index, exclusive
  final ColorFmt fmt;
  const ColorMatch(this.color, this.start, this.end, this.fmt);
}

enum ColorFmt { hex3, hex6, hex8, flutterHex, flutterArgb, flutterRgbo, cssRgb, cssRgba, cssHsl, cssHsla }

class ColorDetector {
  // ── Compiled patterns ─────────────────────────────────────────────────────

  static final _hex8       = RegExp(r'(?<![0-9A-Fa-f#])#([0-9A-Fa-f]{8})(?![0-9A-Fa-f])');
  static final _hex6       = RegExp(r'(?<![0-9A-Fa-f#])#([0-9A-Fa-f]{6})(?![0-9A-Fa-f])');
  static final _hex3       = RegExp(r'(?<![0-9A-Fa-f#])#([0-9A-Fa-f]{3})(?![0-9A-Fa-f])');
  static final _flutterHex = RegExp(r'\bColor\(\s*0x([0-9A-Fa-f]{8})\s*\)');
  static final _flutterArgb= RegExp(r'\bColor\.fromARGB\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)');
  static final _flutterRgbo= RegExp(r'\bColor\.fromRGBO\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)');
  static final _cssRgba    = RegExp(r'\brgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*([0-9.]+)\s*\)');
  static final _cssRgb     = RegExp(r'\brgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)');
  static final _cssHsla    = RegExp(r'\bhsla\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)%\s*,\s*(\d+(?:\.\d+)?)%\s*,\s*([0-9.]+)\s*\)');
  static final _cssHsl     = RegExp(r'\bhsl\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)%\s*,\s*(\d+(?:\.\d+)?)%\s*\)');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Detect all colors in [line]. Longer / more-specific matches shadow
  /// shorter ones. Results are sorted by start column.
  static List<ColorMatch> detect(String line) {
    final raw = <ColorMatch>[];

    for (final m in _flutterHex.allMatches(line)) {
      final c = _hex8ToColor(m.group(1)!);
      if (c != null) raw.add(ColorMatch(c, m.start, m.end, ColorFmt.flutterHex));
    }
    for (final m in _flutterArgb.allMatches(line)) {
      final a = int.tryParse(m.group(1)!) ?? -1;
      final r = int.tryParse(m.group(2)!) ?? -1;
      final g = int.tryParse(m.group(3)!) ?? -1;
      final b = int.tryParse(m.group(4)!) ?? -1;
      if (_ok255(a) && _ok255(r) && _ok255(g) && _ok255(b))
        raw.add(ColorMatch(Color.fromARGB(a,r,g,b), m.start, m.end, ColorFmt.flutterArgb));
    }
    for (final m in _flutterRgbo.allMatches(line)) {
      final r  = int.tryParse(m.group(1)!) ?? -1;
      final g  = int.tryParse(m.group(2)!) ?? -1;
      final b  = int.tryParse(m.group(3)!) ?? -1;
      final op = double.tryParse(m.group(4)!) ?? -1;
      if (_ok255(r) && _ok255(g) && _ok255(b) && op >= 0 && op <= 1)
        raw.add(ColorMatch(Color.fromRGBO(r,g,b,op), m.start, m.end, ColorFmt.flutterRgbo));
    }
    for (final m in _cssRgba.allMatches(line)) {
      final r = int.tryParse(m.group(1)!) ?? -1;
      final g = int.tryParse(m.group(2)!) ?? -1;
      final b = int.tryParse(m.group(3)!) ?? -1;
      final a = double.tryParse(m.group(4)!) ?? -1;
      if (_ok255(r) && _ok255(g) && _ok255(b) && a >= 0 && a <= 1)
        raw.add(ColorMatch(Color.fromRGBO(r,g,b,a), m.start, m.end, ColorFmt.cssRgba));
    }
    for (final m in _cssRgb.allMatches(line)) {
      final r = int.tryParse(m.group(1)!) ?? -1;
      final g = int.tryParse(m.group(2)!) ?? -1;
      final b = int.tryParse(m.group(3)!) ?? -1;
      if (_ok255(r) && _ok255(g) && _ok255(b))
        raw.add(ColorMatch(Color.fromARGB(255,r,g,b), m.start, m.end, ColorFmt.cssRgb));
    }
    for (final m in _cssHsla.allMatches(line)) {
      final h = double.tryParse(m.group(1)!) ?? -1;
      final s = double.tryParse(m.group(2)!) ?? -1;
      final l = double.tryParse(m.group(3)!) ?? -1;
      final a = double.tryParse(m.group(4)!) ?? -1;
      if (h >= 0 && h <= 360 && s >= 0 && s <= 100 && l >= 0 && l <= 100 && a >= 0 && a <= 1)
        raw.add(ColorMatch(_hslToColor(h,s/100,l/100,a), m.start, m.end, ColorFmt.cssHsla));
    }
    for (final m in _cssHsl.allMatches(line)) {
      final h = double.tryParse(m.group(1)!) ?? -1;
      final s = double.tryParse(m.group(2)!) ?? -1;
      final l = double.tryParse(m.group(3)!) ?? -1;
      if (h >= 0 && h <= 360 && s >= 0 && s <= 100 && l >= 0 && l <= 100)
        raw.add(ColorMatch(_hslToColor(h,s/100,l/100,1.0), m.start, m.end, ColorFmt.cssHsl));
    }
    // Hex patterns: 8-digit before 6-digit before 3-digit to avoid sub-matches
    for (final m in _hex8.allMatches(line)) {
      final c = _hex8ToColor(m.group(1)!);
      if (c != null) raw.add(ColorMatch(c, m.start, m.end, ColorFmt.hex8));
    }
    for (final m in _hex6.allMatches(line)) {
      final c = _hex6ToColor(m.group(1)!);
      if (c != null) raw.add(ColorMatch(c, m.start, m.end, ColorFmt.hex6));
    }
    for (final m in _hex3.allMatches(line)) {
      final c = _hex3ToColor(m.group(1)!);
      if (c != null) raw.add(ColorMatch(c, m.start, m.end, ColorFmt.hex3));
    }

    if (raw.isEmpty) return const [];

    // Sort by start; for same start prefer longer (more specific) match.
    raw.sort((a,b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : b.end.compareTo(a.end));

    // Deduplicate overlapping ranges — keep first (longest).
    final out = <ColorMatch>[];
    int lastEnd = -1;
    for (final m in raw) {
      if (m.start >= lastEnd) { out.add(m); lastEnd = m.end; }
    }
    return out;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _ok255(int v) => v >= 0 && v <= 255;

  static Color? _hex3ToColor(String h) {
    final v = int.tryParse('${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}', radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static Color? _hex6ToColor(String h) {
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  /// h is 8 hex digits in AARRGGBB order (Flutter/Android).
  static Color? _hex8ToColor(String h) {
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  static Color _hslToColor(double h, double s, double l, double a) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    double r, g, b;
    if      (h < 60)  { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else              { r = c; g = 0; b = x; }
    return Color.fromARGB(
      (a * 255).round().clamp(0, 255),
      ((r + m) * 255).round().clamp(0, 255),
      ((g + m) * 255).round().clamp(0, 255),
      ((b + m) * 255).round().clamp(0, 255),
    );
  }
}
