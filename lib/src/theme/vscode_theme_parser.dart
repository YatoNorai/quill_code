// lib/src/theme/vscode_theme_parser.dart
//
// Parses VSCode color theme JSON files (dark_modern.json, GitHub Dark, Dracula,
// any tokenColors-based theme) into an EditorTheme.
//
// Supports:
//  • editor.* UI color tokens
//  • tokenColors TextMate scopes (keyword, string, comment, …)
//  • 3, 4, 6, and 8-digit hex (incl. alpha). VSCode uses RRGGBBAA; Flutter Color
//    uses AARRGGBB — this parser converts automatically.
//  • Trailing commas and // line comments (VSCode theme files use them).
//
// USAGE
//   final theme = VsCodeThemeParser.parseJson(jsonString);
//   // Then pass theme to QuillCodeEditor(theme: theme)

import 'dart:convert';
import 'package:flutter/painting.dart';
import 'editor_theme.dart';
import 'indent_program.dart';
import 'color_scheme.dart';
import 'theme_helpers.dart';

class VsCodeThemeParser {
  /// Parse a VSCode JSON color theme string into an [EditorTheme].
  /// Falls back to the default dark theme on any parse error.
  static EditorTheme parseJson(String jsonSource) {
    try {
      final cleaned = _stripComments(jsonSource);
      final Map<String, dynamic> root = json.decode(cleaned);

      final colors      = (root['colors']      as Map<String, dynamic>?) ?? const {};
      final tokenColors = (root['tokenColors'] as List<dynamic>?)         ?? const [];

      // ── Helper: resolve a color token, trying multiple keys ──────────────
      Color? c(String key, [String? fallback]) {
        final raw = (colors[key] as String?) ??
                    (fallback != null ? colors[fallback] as String? : null);
        return raw != null ? _parseHex(raw) : null;
      }

      // ── Core editor colors ───────────────────────────────────────────────
      final bg        = c('editor.background')                    ?? const Color(0xFF1E1E1E);
      final fg        = c('editor.foreground')                    ?? const Color(0xFFCCCCCC);
      final lineBg    = c('editorLineNumber.background',
                           'sideBar.background')                  ?? const Color(0xFF252526);
      final curLine   = c('editor.lineHighlightBackground')       ?? bg.withOpacity(1).withBlue(
                            (bg.blue * 1.15).clamp(0,255).round());
      final lineNum   = c('editorLineNumber.foreground')          ?? const Color(0xFF858585);
      final lineNumA  = c('editorLineNumber.activeForeground')    ?? fg;
      final sel       = c('editor.selectionBackground')           ?? const Color(0x66264F78);
      final cursorC   = c('editorCursor.foreground', 'focusBorder') ?? const Color(0xFFAEAFAD);
      final handleC   = c('editor.selectionHandleColor') ?? cursorC;
      final cursorW   = (colors['editorCursor.width'] as num?)?.toDouble() ?? 2.0;
      final findHL    = c('editor.findMatchHighlightBackground')  ?? const Color(0x33EA5C00);
      final findBg    = c('editor.findMatchBackground')           ?? const Color(0x559E6A03);
      final blkLine   = c('editorIndentGuide.background1',
                           'editorWhitespace.foreground')         ?? const Color(0xFF404040);
      final errC      = c('editorError.foreground',  'errorForeground') ?? const Color(0xFFF44747);
      final warnC     = c('editorWarning.foreground')             ?? const Color(0xFFCCA700);
      final hoverBg   = c('editorHoverWidget.background',
                           'editorWidget.background')             ?? const Color(0xFF252526);
      final hoverBdr  = c('editorHoverWidget.border',
                           'editorWidget.border')                 ?? const Color(0xFF454545);
      final compBg    = c('editorSuggestWidget.background',
                           'editorWidget.background')             ?? const Color(0xFF252526);
      final compSel   = c('editorSuggestWidget.selectedBackground') ?? const Color(0xFF094771);
      final compBdr   = c('editorSuggestWidget.border',
                           'editorWidget.border')                 ?? const Color(0xFF454545);
      final compFg    = c('editorSuggestWidget.foreground')       ?? fg;
      final compMatch = c('editorSuggestWidget.highlightForeground',
                           'editorSuggestWidget.focusHighlightForeground') ?? const Color(0xFF18A3FF);

      // ── Token colors (TextMate scopes) ───────────────────────────────────
      final tokMap = _buildTokenMap(tokenColors);

      Color tok(List<String> scopes, Color fallback) {
        for (final s in scopes) {
          final v = tokMap[s] ?? tokMap[s.split('.').first];
          if (v != null) return v;
        }
        return fallback;
      }

      final kwColor   = tok(['keyword.control','keyword'],          const Color(0xFF569CD6));
      final strColor  = tok(['string.quoted','string'],             const Color(0xFFCE9178));
      final numColor  = tok(['constant.numeric','number'],          const Color(0xFFB5CEA8));
      final cmtColor  = tok(['comment.line','comment'],             const Color(0xFF6A9955));
      final fnColor   = tok(['entity.name.function','support.function'], const Color(0xFFDCDCAA));
      final typeColor = tok(['entity.name.type','support.type'],    const Color(0xFF4EC9B0));
      final annColor  = tok(['storage.modifier','keyword.other'],   const Color(0xFF9CDCFE));
      final varColor  = tok(['variable','variable.other'],          fg);
      final opColor   = tok(['keyword.operator','operator'],        const Color(0xFFD4D4D4));
      final litColor  = tok(['constant.language','constant'],       const Color(0xFF569CD6));
      final preColor  = tok(['meta.preprocessor','keyword.preprocessor'], const Color(0xFF9B9B9B));
      final nsColor   = tok(['entity.name.namespace','namespace'],  const Color(0xFF4EC9B0));
      final attrName  = tok(['entity.other.attribute-name'],        const Color(0xFF9CDCFE));
      final attrVal   = tok(['string.other.attribute-value'],       const Color(0xFFCE9178));
      final htmlTag   = tok(['entity.name.tag'],                    const Color(0xFF4EC9B0));
      final punctC    = tok(['punctuation'],                        fg.withOpacity(0.7));

      // Ghost text: lighter than comment
      final ghostC = cmtColor.withOpacity(0.55);

      final base = DarkEditorTheme.colorScheme;
      final cs = base.copyWith(
        background:                  bg,
        lineNumberBackground:        lineBg,
        currentLineBackground:       curLine,
        selectionColor:              sel,
        searchMatchBackground:       findHL,
        searchMatchBorder:           findBg,
        textNormal:                  fg,
        lineNumber:                  lineNum,
        lineNumberCurrent:           lineNumA,
        cursor:                      cursorC,
        selectionHandle:             handleC,
        blockLine:                   blkLine,
        blockLineActive:             blkLine.withOpacity(0.6),
        problemError:                errC,
        problemWarning:              warnC,
        hoverBackground:             hoverBg,
        hoverBorder:                 hoverBdr,
        hoverText:                   fg,
        completionBackground:        compBg,
        completionItemBackground:    compBg,
        completionItemSelected:      compSel,
        completionTextPrimary:       compFg,
        completionBorder:            compBdr,
        completionTextMatched:       compMatch,
        keyword:                     kwColor,
        string:                      strColor,
        number:                      numColor,
        comment:                     cmtColor,
        function_:                   fnColor,
        type_:                       typeColor,
        annotation:                  annColor,
        identifier:                  varColor,
        operator_:                   opColor,
        literal:                     litColor,
        preprocessor:                preColor,
        namespace:                   nsColor,
        attrName:                    attrName,
        attrValue:                   attrVal,
        htmlTag:                     htmlTag,
        punctuation:                 punctC,
        ghostTextForeground:         ghostC,
      );

      // ── blockLines (indent guide theme) ────────────────────────────────
      final blockLinesJson = root['blockLines'] as Map<String, dynamic>?;
      final parsedBlockLines = blockLinesJson != null
          ? _parseBlockLineTheme(blockLinesJson)
          : null;

      // ── bracketPair ─────────────────────────────────────────────────────
      final bpJson = root['bracketPair'] as Map<String, dynamic>?;
      final parsedBracketPair = bpJson != null
          ? _parseBracketPairTheme(bpJson)
          : null;

      // ── indentDots ───────────────────────────────────────────────────────
      final idJson = root['indentDots'] as Map<String, dynamic>?;
      final parsedIndentDots = idJson != null
          ? _parseIndentDotTheme(idJson)
          : null;

      return DarkEditorTheme.theme.copyWith(
        colorScheme:  cs,
        cursorWidth:  cursorW,
        blockLines:   parsedBlockLines,
        bracketPair:  parsedBracketPair,
        indentDots:   parsedIndentDots,
      );
    } catch (e) {
      return DarkEditorTheme.theme;
    }
  }

  // ── Parse BlockLineTheme from JSON map ────────────────────────────────────

  static BlockLineTheme parseBlockLineThemePublic(Map<String, dynamic> m) => _parseBlockLineTheme(m);
  static BlockLineTheme _parseBlockLineTheme(Map<String, dynamic> m) {
    // ── Parse a style string (legacy enum) ──────────────────────────────
    BlockLineStyle? _style(String? s) => switch (s) {
      'none'        => BlockLineStyle.none,
      'solid'       => BlockLineStyle.solid,
      'dashed'      => BlockLineStyle.dashed,
      'dotted'      => BlockLineStyle.dotted,
      'squareDotted'=> BlockLineStyle.squareDotted,
      'longDash'    => BlockLineStyle.longDash,
      'doubleDash'  => BlockLineStyle.doubleDash,
      'curved'      => BlockLineStyle.curved,
      _             => null,
    };

    // ── Parse programs (Mode A: full freedom) ────────────────────────────
    final program       = IndentProgramParser.tryParse(m, 'program',       'endCap',       startCapKey: 'startCap');
    final activeProgram = IndentProgramParser.tryParse(m, 'activeProgram', 'activeEndCap', startCapKey: 'activeStartCap');

    // ── Rainbow colors ───────────────────────────────────────────────────
    List<Color> rainbow = BlockLineTheme.defaultRainbowColors;
    final rawRainbow = m['rainbowColors'];
    if (rawRainbow is List) {
      final parsed = rawRainbow
          .whereType<String>()
          .map(_parseHex)
          .whereType<Color>()
          .toList();
      if (parsed.isNotEmpty) rainbow = parsed;
    }

    return BlockLineTheme(
      color:           _parseHex(m['color']       as String? ?? '') ?? const Color(0xFF404040),
      activeColor:     _parseHex(m['activeColor']  as String? ?? '') ?? const Color(0xFF6C7086),
      width:           (m['width']           as num?)?.toDouble() ?? 1.0,
      activeWidth:     (m['activeWidth']     as num?)?.toDouble(),
      style:           _style(m['style'] as String?) ?? BlockLineStyle.solid,
      activeStyle:     _style(m['activeStyle'] as String?),
      program:         program,
      activeProgram:   activeProgram,
      colorMode:       (m['colorMode'] as String?) == 'rainbow'
                           ? BlockLineColorMode.rainbow
                           : BlockLineColorMode.single,
      rainbowColors:   rainbow,
      dashGap:         (m['dashGap']         as num?)?.toDouble() ?? 3.0,
      dashLength:      (m['dashLength']      as num?)?.toDouble() ?? 4.0,
      dotSpacing:      (m['dotSpacing']      as num?)?.toDouble() ?? 5.0,
      capLength:       (m['capLength']       as num?)?.toDouble() ?? 10.0,
      inactiveOpacity: (m['inactiveOpacity'] as num?)?.toDouble() ?? 1.0,
      curveRadius:     (m['curveRadius']     as num?)?.toDouble() ?? 7.0,
    );
  }

  static BracketPairTheme _parseBracketPairTheme(Map<String, dynamic> m) =>
    BracketPairTheme(
      fillColor:   _parseHex(m['fillColor']   as String? ?? '') ?? const Color(0x1A89B4FA),
      borderColor: _parseHex(m['borderColor'] as String? ?? '') ?? const Color(0x8089B4FA),
      borderWidth: (m['borderWidth'] as num?)?.toDouble() ?? 1.2,
      radius:      (m['radius']      as num?)?.toDouble() ?? 2.0,
    );

  static IndentDotTheme _parseIndentDotTheme(Map<String, dynamic> m) {
    final mode = (m['mode'] as String?) == 'all'
        ? IndentDotMode.all
        : IndentDotMode.indentOnly;
    return IndentDotTheme(
      visible: (m['visible'] as bool?) ?? false,
      color:   _parseHex(m['color'] as String? ?? '') ?? const Color(0x446C7086),
      size:    (m['size']    as num?)?.toDouble() ?? 1.5,
      mode:    mode,
    );
  }

  // ── Build token → color map from tokenColors array ───────────────────────

  static Map<String, Color> _buildTokenMap(List<dynamic> tokenColors) {
    final map = <String, Color>{};
    for (final entry in tokenColors) {
      if (entry is! Map) continue;
      final settings = entry['settings'] as Map<String, dynamic>?;
      final fgRaw    = settings?['foreground'] as String?;
      if (fgRaw == null) continue;
      final color = _parseHex(fgRaw);
      if (color == null) continue;
      final scope = entry['scope'];
      void add(String s) => map[s.trim()] = color;
      if (scope is String) {
        for (final s in scope.split(',')) add(s);
      } else if (scope is List) {
        for (final s in scope) add(s as String);
      }
    }
    return map;
  }

  // ── Hex parser: handles #RGB #RGBA #RRGGBB #RRGGBBAA ────────────────────
  // VSCode uses RRGGBBAA; Flutter Color uses 0xAARRGGBB.

  static Color? _parseHex(String raw) {
    try {
      var s = raw.trim();
      if (s.startsWith('#')) s = s.substring(1);
      switch (s.length) {
        case 3: s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}'; // #RGB → RRGGBB
                s = 'FF$s'; break;
        case 4: s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}${s[3]}${s[3]}'; // RGBA
                // Now 8 chars: RRGGBBAA — fall through to the 8 case below
                final r2 = s.substring(0, 2);
                final g2 = s.substring(2, 4);
                final b2 = s.substring(4, 6);
                final a2 = s.substring(6, 8);
                return Color(int.parse('$a2$r2$g2$b2', radix: 16));
        case 6: s = 'FF$s'; break;      // #RRGGBB → opaque
        case 8:                          // #RRGGBBAA (VSCode) → AARRGGBB (Flutter)
                final r = s.substring(0, 2);
                final g = s.substring(2, 4);
                final b = s.substring(4, 6);
                final a = s.substring(6, 8);
                return Color(int.parse('$a$r$g$b', radix: 16));
        default: return null;
      }
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return null;
    }
  }

  // ── Strip // comments and trailing commas (VSCode theme quirks) ──────────

  static String _stripComments(String src) {
    final sb = StringBuffer();
    bool inStr = false;
    for (int i = 0; i < src.length; i++) {
      final c = src[i];
      if (c == '"' && (i == 0 || src[i-1] != '\\')) { inStr = !inStr; sb.write(c); continue; }
      if (!inStr && c == '/' && i + 1 < src.length) {
        if (src[i+1] == '/') { while (i < src.length && src[i] != '\n') i++; continue; }
        if (src[i+1] == '*') {
          i += 2;
          while (i + 1 < src.length && !(src[i] == '*' && src[i+1] == '/')) i++;
          i++; continue;
        }
      }
      sb.write(c);
    }
    // Remove trailing commas before } or ]
    return sb.toString().replaceAllMapped(
      RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
  }
}
