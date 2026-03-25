// example/lib/screens/color_decorator_demo.dart
//
// Demonstrates the color decorator feature:
//  • Color swatches appear on the left gutter for every color value
//    detected in the file (hex, Flutter Color(), CSS rgb/hsl, etc.)
//  • Tapping a swatch opens the VSCode-style color picker
//  • The Neon Night theme is used to show custom scrollbar styling
import 'package:flutter/material.dart';
import 'package:quill_code/quill_code.dart';

// ── Sample source code containing many color formats ─────────────────────────
const _sampleSource = r'''
// color_decorator_demo.dart — QuillCode color decorator showcase
// All of the values below will get a colored swatch in the gutter.

import 'package:flutter/material.dart';

// ── Flutter / Dart hex colors ──────────────────────────────────────────────

const Color primary      = Color(0xFF6C63FF);   // purple
const Color secondary    = Color(0xFF00FFCC);   // neon cyan
const Color accent       = Color(0xFFFF4081);   // hot pink
const Color warning      = Color(0xFFFFAB00);   // amber
const Color transparent  = Color(0x00000000);   // fully transparent

const Color fromArgb1    = Color.fromARGB(255, 108, 99, 255);   // same as primary
const Color fromArgb2    = Color.fromARGB(180, 0, 170, 255);    // semi-transparent blue
const Color fromRgbo1    = Color.fromRGBO(255, 64, 129, 0.75);  // accent 75%
const Color fromRgbo2    = Color.fromRGBO(0, 255, 204, 1.0);    // secondary

// ── CSS hex colors ─────────────────────────────────────────────────────────

const String cssHex3   = '#FFF';            // white (#3-digit)
const String cssHex6   = '#6C63FF';         // primary
const String cssHex8   = '#B300FFCC';       // secondary with 70% alpha (AARRGGBB)
const String cssRed    = '#FF0000';
const String cssTeal   = '#00BCD4';

// ── CSS functional colors ──────────────────────────────────────────────────

// rgb / rgba
const String cssRgb1   = 'rgb(108, 99, 255)';
const String cssRgba1  = 'rgba(255, 64, 129, 0.75)';
const String cssRgba2  = 'rgba(0, 255, 204, 1.0)';

// hsl / hsla
const String cssHsl1   = 'hsl(245, 100%, 69%)';   // primary hue
const String cssHsla1  = 'hsla(163, 100%, 60%, 0.8)';  // secondary, 80%
const String cssHsla2  = 'hsla(338, 100%, 63%, 1.0)';  // accent, full opacity

// ── Theming map ────────────────────────────────────────────────────────────

final Map<String, Color> palette = {
  'background':  const Color(0xFF0D0D14),  // neon-night bg
  'surface':     const Color(0xFF1A1A28),
  'onSurface':   const Color(0xFFE0E0FF),
  'error':       const Color(0xFFFF0055),
  'divider':     const Color(0x2200FFCC),
};

// ── Widget that uses the palette ───────────────────────────────────────────

class ThemedCard extends StatelessWidget {
  const ThemedCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1A1A28),
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Text('Hello', style: TextStyle(color: Color(0xFFE0E0FF))),
      Divider(color: Color(0x2200FFCC)),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF6C63FF)),
        onPressed: () {},
        child: const Text('Click me'),
      ),
    ]),
  );
}
''';

// ─────────────────────────────────────────────────────────────────────────────

class ColorDecoratorDemo extends StatefulWidget {
  const ColorDecoratorDemo({super.key});
  @override State<ColorDecoratorDemo> createState() => _ColorDecoratorDemoState();
}

class _ColorDecoratorDemoState extends State<ColorDecoratorDemo> {
  late final QuillCodeController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = QuillCodeController(language: DartLanguage())
      ..props.showColorDecorators = true
      ..props.showScrollbars      = true
      ..props.showLineNumbers     = true
      ..props.showBlockLines      = true
      ..props.tabSize             = 2;
    _ctrl.setText(_sampleSource);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A10),
        title: const Text(
          'Color Decorator Demo',
          style: TextStyle(color: Color(0xFF00FFCC), fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Tap a swatch to pick a color',
                style: TextStyle(
                  color: const Color(0xFF00FFCC).withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: QuillCodeEditor(
        controller: _ctrl,
        theme: QuillThemeNeon.build(),
      ),
    );
  }
}
