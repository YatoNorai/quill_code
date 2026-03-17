// example/lib/theme_loader.dart
// Loads EditorTheme from JSON asset files in assets/themes/.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quill_code/quill_code.dart';

class ThemeLoader {
  ThemeLoader._();

  static const _assetPrefix = 'assets/themes/';

  static final Map<String, Map<String, dynamic>> _cache = {};

  static const themeFiles = {
    // ── Dark classics ──────────────────────────────────────────────────
    'Dark (Catppuccin)':    'dark_catppuccin.json',
    'Dark Modern':           'dark_modern.json',
    'GitHub Dark':           'github_dark.json',
    'GitHub Dark (Curved)':  'github_dark_curved.json',
    'Dracula':               'dracula.json',
    'Monokai':               'monokai.json',
    // ── Community dark ────────────────────────────────────────────────
    'Nord':                  'nord.json',
    'Tokyo Night':           'tokyo_night.json',
    'Solarized Dark':        'solarized_dark.json',
    'One Dark Pro':          'one_dark_pro.json',
    'Gruvbox Dark':          'gruvbox_dark.json',
    'Ayu Dark':              'ayu_dark.json',
    'Rosé Pine':             'rose_pine.json',
    'Everforest Dark':       'everforest_dark.json',
    'Poimandres':            'poimandres.json',
    'Material Ocean':        'material_ocean.json',
    'Cobalt2':               'cobalt2.json',
    'Kanagawa':              'kanagawa.json',
    'Neon Synthwave':        'neon_synthwave.json',
    // ── Light ─────────────────────────────────────────────────────────
    'GitHub':                'github_light.json',
    'Light':                 'light.json',
    'SynthCity Light':       'synth_city_light.json',
    'Ink':                   'ink.json',
    // ── Underline Arc style ───────────────────────────────────────────
    'Underline Arc':         'underline_arc.json',
    'Underline Arc (Rainbow)': 'underline_arc_rainbow.json',
    'Underline Arc Dark':    'underline_arc_dark.json',
    // ── New unique themes ─────────────────────────────────────────────
    'Abyss Dark':            'abyss_dark.json',
    'Amber Storm':           'amber_storm.json',
    'Arctic Ice':            'arctic_ice.json',
    'Ember Glow':            'ember_glow.json',
    'Forest Mist':           'forest_mist.json',
    'Laser Matrix':          'laser_matrix.json',
    'Sakura Night':          'sakura_night.json',
    'Solar Sepia':           'solar_sepia.json',
    'Crystal Cave':          'crystal_cave.json',
    'Cyberpunk Acid':        'cyberpunk_acid.json',
  };

  static Future<Map<String, dynamic>?> _loadJson(String name) async {
    if (_cache.containsKey(name)) return _cache[name];
    final file = themeFiles[name];
    if (file == null) return null;
    try {
      final str  = await rootBundle.loadString('$_assetPrefix$file');
      final json = jsonDecode(str) as Map<String, dynamic>;
      _cache[name] = json;
      return json;
    } catch (_) { return null; }
  }

  static Future<EditorTheme> buildTheme(String name, {double? fontSize}) async {
    final json = await _loadJson(name);
    if (json == null) return QuillThemeDark.build(fontSize: fontSize ?? 14);
    return _fromJson(json, fontSize: fontSize ?? 14);
  }

  static EditorTheme buildThemeSync(String name, {double? fontSize}) {
    final json = _cache[name];
    if (json == null) return QuillThemeDark.build(fontSize: fontSize ?? 14);
    return _fromJson(json, fontSize: fontSize ?? 14);
  }

  static Future<void> preloadAll() async {
    for (final name in themeFiles.keys) await _loadJson(name);
  }

  // ── JSON parsing ──────────────────────────────────────────────────────────

  static Color _hex(Map<String, dynamic> map, String key, Color fallback) {
    final v = map[key] as String?;
    if (v == null || v.length < 7) return fallback;
    try {
      final s = v.replaceFirst('#', '');
      final argb = s.length == 6 ? 'FF$s' : s;
      return Color(int.parse(argb, radix: 16));
    } catch (_) { return fallback; }
  }

  static EditorTheme _fromJson(Map<String, dynamic> j, {required double fontSize}) {
    final c    = (j['colors']      as Map<String, dynamic>?) ?? {};
    final lh   = (j['lineHighlight'] as Map<String, dynamic>?) ?? {};
    final blj  = (j['blockLines']  as Map<String, dynamic>?) ?? {};
    final bpj  = (j['bracketPair'] as Map<String, dynamic>?) ?? {};
    final idj  = (j['indentDots']  as Map<String, dynamic>?) ?? {};
    final isDark = j['dark'] as bool? ?? true;

    // ── Colors ────────────────────────────────────────────────────────────
    Color h(String k, Color fb) => _hex(c, k, fb);

    final bg      = h('background',           isDark ? const Color(0xFF1E1E2E) : Colors.white);
    final lnBg    = h('lineNumberBackground',  isDark ? const Color(0xFF181825) : const Color(0xFFF0F0F0));
    final text    = h('textNormal',            isDark ? const Color(0xFFCDD6F4) : Colors.black87);
    final ln      = h('lineNumber',            isDark ? const Color(0xFF6C7086) : Colors.grey);
    final lnCur   = h('lineNumberCurrent',     isDark ? Colors.white : Colors.black87);
    final cursor  = h('cursor',                const Color(0xFF89B4FA));
    final sel     = h('selectionColor',        const Color(0x3389B4FA));
    final kw      = h('keyword',               const Color(0xFFCBA6F7));
    final str     = h('string',                const Color(0xFFA6E3A1));
    final cmt     = h('comment',               const Color(0xFF6C7086));
    final num_    = h('number',                const Color(0xFFFAB387));
    final op      = h('operator',              const Color(0xFF89DCEB));
    final id      = h('identifier',            isDark ? const Color(0xFFCDD6F4) : Colors.black87);
    final fn      = h('function',              const Color(0xFF89B4FA));
    final ty      = h('type',                  const Color(0xFFF38BA8));
    final ann     = h('annotation',            const Color(0xFFF5C2E7));
    final blk     = h('blockLine',             isDark ? const Color(0xFF313244) : const Color(0xFFCCCCCC));
    final compBg  = h('completionBackground',  isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5));
    final ghost   = h('ghostTextForeground',   const Color(0xFF6C7086));
    final curLn   = h('currentLineBackground', isDark ? const Color(0xFF313244) : const Color(0xFFF0F0F0));
    final srchBg  = h('searchMatchBackground', isDark ? const Color(0x33F9E2AF) : const Color(0x44FFFF00));
    final srchBrd = h('searchMatchBorder',     isDark ? const Color(0xFFF9E2AF) : const Color(0xFFCCCC00));
    final handle  = h('selectionHandle',       cursor);
    final cursorW = (c['cursorWidth'] as num?)?.toDouble() ?? 2.0;

    // ── lineHighlight style ───────────────────────────────────────────────
    Color lhh(String k, Color fb) => _hex(lh, k, fb);
    final fillClr   = lhh('fillColor',       curLn);
    final strokeClr = lhh('strokeColor',     blk);
    final accentClr = lhh('accentColor',     cursor);

    final hlStyle = () {
      switch (lh['style'] as String? ?? 'fill') {
        case 'stroke':    return LineHighlightStyle.stroke;
        case 'accentBar': return LineHighlightStyle.accentBar;
        case 'none':      return LineHighlightStyle.none;
        default:          return LineHighlightStyle.fill;
      }
    }();

    // ── BlockLineTheme ────────────────────────────────────────────────────
    // Delegate entirely to VsCodeThemeParser which handles both
    // program-mode (DSL ops) and legacy style-enum mode.
    final blockLines = blj.isNotEmpty
        ? VsCodeThemeParser.parseBlockLineThemePublic(blj)
        : const BlockLineTheme();

    // ── BracketPairTheme ──────────────────────────────────────────────────
    Color bphex(String k, Color fb) => _hex(bpj, k, fb);
    final bracketPair = BracketPairTheme(
      fillColor:   bphex('fillColor',   const Color(0x1A89B4FA)),
      borderColor: bphex('borderColor', const Color(0x8089B4FA)),
      borderWidth: (bpj['borderWidth'] as num?)?.toDouble() ?? 1.2,
      radius:      (bpj['radius']      as num?)?.toDouble() ?? 2.0,
    );

    // ── IndentDotTheme ────────────────────────────────────────────────────
    Color idhex(String k, Color fb) => _hex(idj, k, fb);
    final dotMode = (idj['mode'] as String? ?? 'indentOnly') == 'all'
        ? IndentDotMode.all : IndentDotMode.indentOnly;
    final indentDots = IndentDotTheme(
      visible: idj['visible'] as bool? ?? false,
      color:   idhex('color', const Color(0x446C7086)),
      size:    (idj['size']  as num?)?.toDouble() ?? 1.5,
      mode:    dotMode,
    );

    // ── Assemble ──────────────────────────────────────────────────────────
    final base = isDark ? QuillThemeDark.build(fontSize: fontSize)
                        : QuillThemeLight.build(fontSize: fontSize);

    return base.copyWith(
      fontSize:    fontSize,
      cursorWidth: cursorW,
      blockLines:  blockLines,
      bracketPair: bracketPair,
      indentDots:  indentDots,
      colorScheme: base.colorScheme.copyWith(
        background:           bg,
        lineNumberBackground: lnBg,
        textNormal:           text,
        lineNumber:           ln,
        lineNumberCurrent:    lnCur,
        cursor:               cursor,
        selectionHandle:      handle,
        selectionColor:       sel,
        keyword:              kw,
        string:               str,
        comment:              cmt,
        number:               num_,
        operator_:            op,
        identifier:           id,
        function_:            fn,
        type_:                ty,
        annotation:           ann,
        blockLine:            blk,
        completionBackground: compBg,
        ghostTextForeground:  ghost,
        currentLineBackground:curLn,
        searchMatchBackground:srchBg,
        searchMatchBorder:    srchBrd,
      ),
    );
  }
}
