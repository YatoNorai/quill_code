// lib/src/widgets/color_picker_overlay.dart
// VSCode-style inline color picker: SV box, hue strip, alpha strip, format toggle.
import 'package:flutter/material.dart';

export '../color/color_detector.dart' show ColorMatch, ColorFmt;

typedef ColorCommitCallback = void Function(Color color, String text);

// ═══════════════════════════════════════════════════════════════════════════
// Main overlay widget
// ═══════════════════════════════════════════════════════════════════════════

class ColorPickerOverlay extends StatefulWidget {
  final Color initialColor;
  final String initialText;        // original source text to replace
  final ColorCommitCallback onCommit;
  final VoidCallback onDismiss;

  const ColorPickerOverlay({
    super.key,
    required this.initialColor,
    required this.initialText,
    required this.onCommit,
    required this.onDismiss,
  });

  @override
  State<ColorPickerOverlay> createState() => _ColorPickerOverlayState();
}

class _ColorPickerOverlayState extends State<ColorPickerOverlay> {
  late _HSVA _hsva;
  late _HSVA _original;
  int _fmtIdx = 0; // 0=HEX 1=RGB 2=HSL

  static const _fmts  = ['HEX', 'RGB', 'HSL'];
  static const _W     = 222.0;
  static const _SVH   = 130.0;
  static const _STRIW = 22.0;
  static const _PAD   = 8.0;
  static const _GAP   = 5.0;

  @override
  void initState() {
    super.initState();
    _hsva = _original = _HSVA.fromColor(widget.initialColor);
    final t = widget.initialText.trimLeft();
    if (t.startsWith('rgb') || t.startsWith('hsl')) _fmtIdx = 1;
  }

  void _commit() => widget.onCommit(_hsva.toColor(), _fmtText(_hsva, _fmtIdx, widget.initialText));

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF252526);
    const border = Color(0xFF454545);
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(5),
      color: bg,
      child: Container(
        width: _W,
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(5),
        ),
        padding: const EdgeInsets.all(_PAD),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ──────────────────────────────────────────────────────
          SizedBox(height: 22, child: Row(children: [
            // Format toggle
            GestureDetector(
              onTap: () => setState(() => _fmtIdx = (_fmtIdx + 1) % _fmts.length),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3C3C),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: border),
                ),
                child: Text(_fmts[_fmtIdx],
                    style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11,
                        fontFamily: 'monospace')),
              ),
            ),
            const Spacer(),
            // Original swatch (click to reset)
            GestureDetector(
              onTap: () => setState(() => _hsva = _original),
              child: _Swatch(color: _original.toColor(), tooltip: 'Reset to original'),
            ),
            const SizedBox(width: 4),
            // Current swatch
            _Swatch(color: _hsva.toColor()),
          ])),

          const SizedBox(height: _GAP),

          // ── SV box + strips ──────────────────────────────────────────────
          SizedBox(
            height: _SVH,
            child: Row(children: [
              Expanded(child: _SVBox(
                hue: _hsva.h, sat: _hsva.s, val: _hsva.v,
                onChanged: (s, v) => setState(() => _hsva = _hsva.with_(s: s, v: v)),
                onEnd: _commit,
              )),
              const SizedBox(width: _GAP),
              SizedBox(width: _STRIW, child: _HueStrip(
                hue: _hsva.h,
                onChanged: (h) => setState(() => _hsva = _hsva.with_(h: h)),
                onEnd: _commit,
              )),
              const SizedBox(width: _GAP),
              SizedBox(width: _STRIW, child: _AlphaStrip(
                color: HSVColor.fromAHSV(1, _hsva.h, _hsva.s, _hsva.v).toColor(),
                alpha: _hsva.a,
                onChanged: (a) => setState(() => _hsva = _hsva.with_(a: a)),
                onEnd: _commit,
              )),
            ]),
          ),

          const SizedBox(height: _GAP),

          // ── Value preview ────────────────────────────────────────────────
          SizedBox(
            height: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _fmtText(_hsva, _fmtIdx, widget.initialText),
                style: const TextStyle(color: Color(0xFF9CDCFE), fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ),
          ),

          const SizedBox(height: _GAP),

          // ── Buttons ──────────────────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _Btn('Cancel', onTap: widget.onDismiss),
            const SizedBox(width: 6),
            _Btn('Apply', primary: true, onTap: () { _commit(); widget.onDismiss(); }),
          ]),
        ]),
      ),
    );
  }

  // ── Format text ───────────────────────────────────────────────────────────

  static String _fmtText(_HSVA hsva, int fmt, String original) {
    final c = hsva.toColor();
    final a = c.alpha; final r = c.red; final g = c.green; final b = c.blue;
    switch (fmt) {
      case 1: // RGB/RGBA
        if (a < 255) return 'rgba($r, $g, $b, ${(a/255).toStringAsFixed(2)})';
        return 'rgb($r, $g, $b)';
      case 2: // HSL/HSLA
        final hd = hsva.h.round();
        final sd = (hsva.s * 100).round();
        final ld = _hsvL(hsva.s, hsva.v).round();
        if (a < 255) return 'hsla($hd, $sd%, $ld%, ${(a/255).toStringAsFixed(2)})';
        return 'hsl($hd, $sd%, $ld%)';
      default: // HEX
        if (original.trimLeft().startsWith('Color(')) {
          final aa = a.toRadixString(16).padLeft(2,'0').toUpperCase();
          final rr = r.toRadixString(16).padLeft(2,'0').toUpperCase();
          final gg = g.toRadixString(16).padLeft(2,'0').toUpperCase();
          final bb = b.toRadixString(16).padLeft(2,'0').toUpperCase();
          return 'Color(0x$aa$rr$gg$bb)';
        }
        final rh = r.toRadixString(16).padLeft(2,'0');
        final gh = g.toRadixString(16).padLeft(2,'0');
        final bh = b.toRadixString(16).padLeft(2,'0');
        final upper = original.contains(RegExp(r'[A-F]'));
        if (a < 255) {
          final ah = a.toRadixString(16).padLeft(2,'0');
          return '#${upper ? (ah+rh+gh+bh).toUpperCase() : (ah+rh+gh+bh)}';
        }
        final hex = '$rh$gh$bh';
        return '#${upper ? hex.toUpperCase() : hex}';
    }
  }

  static int _hsvL(double s, double v) {
    final l = v * (1 - s / 2);
    return (l * 100).round();
  }
}

// ── Small swatch widget ───────────────────────────────────────────────────────

class _Swatch extends StatelessWidget {
  final Color color;
  final String? tooltip;
  const _Swatch({required this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    Widget w = Container(
      width: 18, height: 18,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: const Color(0xFF666666)),
        borderRadius: BorderRadius.circular(2),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

// ── Button widget ─────────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _Btn(this.label, {required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF0078D4) : const Color(0xFF3C3C3C),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: primary ? const Color(0xFF0078D4) : const Color(0xFF555555)),
        ),
        child: Text(label,
            style: TextStyle(
              color: primary ? Colors.white : const Color(0xFFCCCCCC),
              fontSize: 11,
            )),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Saturation / Value 2D box
// ═══════════════════════════════════════════════════════════════════════════

class _SVBox extends StatelessWidget {
  final double hue, sat, val;
  final void Function(double s, double v) onChanged;
  final VoidCallback onEnd;
  const _SVBox({required this.hue, required this.sat, required this.val,
      required this.onChanged, required this.onEnd});

  void _update(Offset pos, Size size) {
    onChanged(
      (pos.dx / size.width ).clamp(0.0, 1.0),
      (1.0 - pos.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart:  (d) => _update(d.localPosition, context.size!),
      onPanUpdate: (d) => _update(d.localPosition, context.size!),
      onPanEnd:    (_) => onEnd(),
      child: CustomPaint(painter: _SVPainter(hue: hue, sat: sat, val: val)),
    );
  }
}

class _SVPainter extends CustomPainter {
  final double hue, sat, val;
  const _SVPainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas c, Size sz) {
    final hueC = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    // White → hue gradient (left to right)
    c.drawRect(Offset.zero & sz,
        Paint()..shader = LinearGradient(colors: [Colors.white, hueC])
            .createShader(Offset.zero & sz));
    // Transparent → black gradient (top to bottom)
    c.drawRect(Offset.zero & sz,
        Paint()..shader = const LinearGradient(
            colors: [Colors.transparent, Colors.black],
            begin: Alignment.topCenter, end: Alignment.bottomCenter)
            .createShader(Offset.zero & sz));
    // Selection circle
    final cx = sat * sz.width;
    final cy = (1 - val) * sz.height;
    c.drawCircle(Offset(cx, cy), 5.5,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override bool shouldRepaint(_SVPainter o) =>
      o.hue != hue || o.sat != sat || o.val != val;
}

// ═══════════════════════════════════════════════════════════════════════════
// Hue strip
// ═══════════════════════════════════════════════════════════════════════════

class _HueStrip extends StatelessWidget {
  final double hue;
  final void Function(double h) onChanged;
  final VoidCallback onEnd;
  const _HueStrip({required this.hue, required this.onChanged, required this.onEnd});

  void _update(Offset pos, Size size) =>
      onChanged(((pos.dy / size.height) * 360).clamp(0.0, 360.0));

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart:  (d) => _update(d.localPosition, context.size!),
    onPanUpdate: (d) => _update(d.localPosition, context.size!),
    onPanEnd:    (_) => onEnd(),
    child: CustomPaint(painter: _HuePainter(hue: hue)),
  );
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter({required this.hue});
  static final _stops = List.generate(7, (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor());

  @override
  void paint(Canvas c, Size sz) {
    c.drawRect(Offset.zero & sz,
        Paint()..shader = LinearGradient(colors: _stops,
            begin: Alignment.topCenter, end: Alignment.bottomCenter)
            .createShader(Offset.zero & sz));
    final y = hue / 360 * sz.height;
    c.drawRect(Rect.fromLTWH(0, y - 1.5, sz.width, 3),
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override bool shouldRepaint(_HuePainter o) => o.hue != hue;
}

// ═══════════════════════════════════════════════════════════════════════════
// Alpha / opacity strip
// ═══════════════════════════════════════════════════════════════════════════

class _AlphaStrip extends StatelessWidget {
  final Color  color;
  final double alpha;  // 0..1
  final void Function(double a) onChanged;
  final VoidCallback onEnd;
  const _AlphaStrip({required this.color, required this.alpha,
      required this.onChanged, required this.onEnd});

  void _update(Offset pos, Size size) =>
      onChanged((1.0 - pos.dy / size.height).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanStart:  (d) => _update(d.localPosition, context.size!),
    onPanUpdate: (d) => _update(d.localPosition, context.size!),
    onPanEnd:    (_) => onEnd(),
    child: CustomPaint(painter: _AlphaPainter(color: color, alpha: alpha)),
  );
}

class _AlphaPainter extends CustomPainter {
  final Color color;
  final double alpha;
  const _AlphaPainter({required this.color, required this.alpha});

  @override
  void paint(Canvas c, Size sz) {
    // Checkerboard for transparency
    const sq = 3.0;
    final p1 = Paint()..color = const Color(0xFFBBBBBB);
    final p2 = Paint()..color = const Color(0xFF888888);
    for (double y = 0; y < sz.height; y += sq) {
      for (double x = 0; x < sz.width; x += sq) {
        c.drawRect(Rect.fromLTWH(x, y, sq, sq),
            ((x ~/ sq + y ~/ sq) % 2 == 0) ? p1 : p2);
      }
    }
    // Color gradient (opaque at top → transparent at bottom)
    c.drawRect(Offset.zero & sz,
        Paint()..shader = LinearGradient(
            colors: [color, color.withOpacity(0)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter)
            .createShader(Offset.zero & sz));
    // Slider indicator
    final y = (1.0 - alpha) * sz.height;
    c.drawRect(Rect.fromLTWH(0, y - 1.5, sz.width, 3),
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override bool shouldRepaint(_AlphaPainter o) =>
      o.color != color || o.alpha != alpha;
}

// ═══════════════════════════════════════════════════════════════════════════
// HSVA color model
// ═══════════════════════════════════════════════════════════════════════════

class _HSVA {
  final double h; // 0..360
  final double s; // 0..1
  final double v; // 0..1
  final double a; // 0..1
  const _HSVA(this.h, this.s, this.v, this.a);

  factory _HSVA.fromColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    return _HSVA(hsv.hue, hsv.saturation, hsv.value, c.alpha / 255.0);
  }

  Color toColor() => HSVColor.fromAHSV(1, h, s, v).toColor().withOpacity(a);

  _HSVA with_({double? h, double? s, double? v, double? a}) =>
      _HSVA(h ?? this.h, s ?? this.s, v ?? this.v, a ?? this.a);
}
