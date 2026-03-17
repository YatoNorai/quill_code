// example/lib/app_state.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class _Prefs {
  static Map<String, dynamic> _cache = {};
  static bool _loaded = false;
  static Future<File> _file() async {
    final dir = Directory.systemTemp;
    return File('${dir.path}/quill_prefs.json');
  }
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _file();
      if (await f.exists()) {
        _cache = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    _loaded = true;
  }
  static Future<void> _save() async {
    try { final f = await _file(); await f.writeAsString(jsonEncode(_cache)); } catch (_) {}
  }
  static String?  getString(String k) => _cache[k] as String?;
  static double?  getDouble(String k) => (_cache[k] as num?)?.toDouble();
  static bool?    getBool(String k)   => _cache[k] as bool?;
  static int?     getInt(String k)    => (_cache[k] as num?)?.toInt();
  static void setString(String k, String v) { _cache[k] = v; _save(); }
  static void setDouble(String k, double v) { _cache[k] = v; _save(); }
  static void setBool(String k, bool v)     { _cache[k] = v; _save(); }
  static void setInt(String k, int v)       { _cache[k] = v; _save(); }
}

class EditorSettings {
  final String theme, language;
  final double fontSize;
  final bool wordWrap, stickyScroll, showLineNumbers, fixedGutter;
  final bool showMinimap, showLightbulb, showFoldArrows, showBlockLines;
  final bool symbolPairAutoClose, autoIndent, autoCompletion, formatOnSave;
  final bool showSymbolBar, highlightCurrentLine, useSpaces;
  final bool highlightActiveBlock;
  final String lineHighlightStyle; // 'fill' | 'stroke' | 'accentBar' | 'none'
  final int tabSize, cursorBlinkMs;
  final bool showDiagnosticIndicators;
  final bool readOnly;
  final bool showIndentDots;
  final String blockLineStyle; // 'solid' | 'dashed' | 'dotted'

  const EditorSettings({
    this.theme = 'Dark (Catppuccin)',
    this.language = 'Dart',
    this.fontSize = 14.0,
    this.wordWrap = false,
    this.stickyScroll = false,
    this.showLineNumbers = true,
    this.fixedGutter = true,
    this.showMinimap = true,
    this.showLightbulb = true,
    this.showFoldArrows = true,
    this.showBlockLines = true,
    this.symbolPairAutoClose = true,
    this.autoIndent = true,
    this.autoCompletion = true,
    this.formatOnSave = false,
    this.showSymbolBar = true,
    this.highlightCurrentLine = true,
    this.highlightActiveBlock = true,
    this.lineHighlightStyle = 'fill',
    this.tabSize = 2,
    this.useSpaces = true,
    this.cursorBlinkMs = 530,
    this.showDiagnosticIndicators = true,
    this.readOnly = false,
    this.showIndentDots = false,
    this.blockLineStyle = 'solid',
  });

  EditorSettings copyWith({
    String? theme, String? language, double? fontSize,
    bool? wordWrap, bool? stickyScroll, bool? showLineNumbers,
    bool? fixedGutter, bool? showMinimap, bool? showLightbulb,
    bool? showFoldArrows, bool? showBlockLines, bool? symbolPairAutoClose,
    bool? autoIndent, bool? autoCompletion, bool? formatOnSave,
    bool? showSymbolBar, bool? highlightCurrentLine, bool? useSpaces,
    bool? highlightActiveBlock, String? lineHighlightStyle,
    int? tabSize, int? cursorBlinkMs,
    bool? showDiagnosticIndicators, bool? readOnly,
    bool? showIndentDots, String? blockLineStyle,
  }) => EditorSettings(
    theme: theme ?? this.theme,
    language: language ?? this.language,
    fontSize: fontSize ?? this.fontSize,
    wordWrap: wordWrap ?? this.wordWrap,
    stickyScroll: stickyScroll ?? this.stickyScroll,
    showLineNumbers: showLineNumbers ?? this.showLineNumbers,
    fixedGutter: fixedGutter ?? this.fixedGutter,
    showMinimap: showMinimap ?? this.showMinimap,
    showLightbulb: showLightbulb ?? this.showLightbulb,
    showFoldArrows: showFoldArrows ?? this.showFoldArrows,
    showBlockLines: showBlockLines ?? this.showBlockLines,
    symbolPairAutoClose: symbolPairAutoClose ?? this.symbolPairAutoClose,
    autoIndent: autoIndent ?? this.autoIndent,
    autoCompletion: autoCompletion ?? this.autoCompletion,
    formatOnSave: formatOnSave ?? this.formatOnSave,
    showSymbolBar: showSymbolBar ?? this.showSymbolBar,
    highlightCurrentLine: highlightCurrentLine ?? this.highlightCurrentLine,
    highlightActiveBlock: highlightActiveBlock ?? this.highlightActiveBlock,
    lineHighlightStyle: lineHighlightStyle ?? this.lineHighlightStyle,
    useSpaces: useSpaces ?? this.useSpaces,
    tabSize: tabSize ?? this.tabSize,
    cursorBlinkMs: cursorBlinkMs ?? this.cursorBlinkMs,
    showDiagnosticIndicators: showDiagnosticIndicators ?? this.showDiagnosticIndicators,
    readOnly: readOnly ?? this.readOnly,
    showIndentDots: showIndentDots ?? this.showIndentDots,
    blockLineStyle: blockLineStyle ?? this.blockLineStyle,
  );
}

enum AgentMode { ghostText, chatAssistant, codeReview, fullAgent }

class AiSettings {
  final String geminiApiKey, geminiModel, systemPrompt;
  final AgentMode agentMode;
  final bool ghostTextEnabled;
  final int ghostDebounceMs, maxTokens;
  final double temperature;

  static const kDefaultSystem =
    'You are a senior Flutter/Dart developer. Complete the code at the cursor. '
    'Reply with ONLY the completion text — no markdown, no explanations. '
    'Keep it concise (1-5 lines). Must be valid Dart.';

  const AiSettings({
    this.geminiApiKey = '',
    this.geminiModel = 'gemini-2.0-flash',
    this.systemPrompt = kDefaultSystem,
    this.agentMode = AgentMode.fullAgent,
    this.ghostTextEnabled = true,
    this.ghostDebounceMs = 600,
    this.maxTokens = 256,
    this.temperature = 0.2,
  });

  bool get isConfigured => geminiApiKey.isNotEmpty;

  AiSettings copyWith({
    String? geminiApiKey, String? geminiModel, String? systemPrompt,
    AgentMode? agentMode, bool? ghostTextEnabled,
    int? ghostDebounceMs, int? maxTokens, double? temperature,
  }) => AiSettings(
    geminiApiKey: geminiApiKey ?? this.geminiApiKey,
    geminiModel: geminiModel ?? this.geminiModel,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    agentMode: agentMode ?? this.agentMode,
    ghostTextEnabled: ghostTextEnabled ?? this.ghostTextEnabled,
    ghostDebounceMs: ghostDebounceMs ?? this.ghostDebounceMs,
    maxTokens: maxTokens ?? this.maxTokens,
    temperature: temperature ?? this.temperature,
  );
}

class AppState extends ChangeNotifier {
  EditorSettings editor = const EditorSettings();
  AiSettings     ai     = const AiSettings();

  static final AppState instance = AppState._();
  AppState._();

  Future<void> load() async {
    await _Prefs.load();
    editor = EditorSettings(
      theme:                   _Prefs.getString('e_theme')  ?? editor.theme,
      language:                _Prefs.getString('e_lang')   ?? editor.language,
      fontSize:                _Prefs.getDouble('e_fs')     ?? editor.fontSize,
      wordWrap:                _Prefs.getBool('e_ww')       ?? editor.wordWrap,
      stickyScroll:            _Prefs.getBool('e_ss')       ?? editor.stickyScroll,
      showLineNumbers:         _Prefs.getBool('e_ln')       ?? editor.showLineNumbers,
      fixedGutter:             _Prefs.getBool('e_fg')       ?? editor.fixedGutter,
      showMinimap:             _Prefs.getBool('e_mm')       ?? editor.showMinimap,
      showLightbulb:           _Prefs.getBool('e_lb')       ?? editor.showLightbulb,
      showFoldArrows:          _Prefs.getBool('e_fa')       ?? editor.showFoldArrows,
      showBlockLines:          _Prefs.getBool('e_bl')       ?? editor.showBlockLines,
      symbolPairAutoClose:     _Prefs.getBool('e_sp')       ?? editor.symbolPairAutoClose,
      autoIndent:              _Prefs.getBool('e_ai')       ?? editor.autoIndent,
      autoCompletion:          _Prefs.getBool('e_ac')       ?? editor.autoCompletion,
      formatOnSave:            _Prefs.getBool('e_fos')      ?? editor.formatOnSave,
      showSymbolBar:           _Prefs.getBool('e_sb')       ?? editor.showSymbolBar,
      highlightCurrentLine:    _Prefs.getBool('e_hl')       ?? editor.highlightCurrentLine,
      highlightActiveBlock:    _Prefs.getBool('e_hab')      ?? editor.highlightActiveBlock,
      lineHighlightStyle:      _Prefs.getString('e_lhs')   ?? editor.lineHighlightStyle,
      tabSize:                 _Prefs.getInt('e_ts')        ?? editor.tabSize,
      useSpaces:               _Prefs.getBool('e_us')       ?? editor.useSpaces,
      cursorBlinkMs:           _Prefs.getInt('e_cb')        ?? editor.cursorBlinkMs,
      showDiagnosticIndicators:_Prefs.getBool('e_di')       ?? editor.showDiagnosticIndicators,
      readOnly:                _Prefs.getBool('e_ro')       ?? editor.readOnly,
      showIndentDots:          _Prefs.getBool('e_id')        ?? editor.showIndentDots,
      blockLineStyle:          _Prefs.getString('e_bls')    ?? editor.blockLineStyle,
    );
    ai = AiSettings(
      geminiApiKey:     _Prefs.getString('ai_key')      ?? '',
      geminiModel:      _Prefs.getString('ai_model')    ?? ai.geminiModel,
      agentMode:        AgentMode.values.firstWhere(
          (e) => e.name == _Prefs.getString('ai_mode'), orElse: () => ai.agentMode),
      ghostTextEnabled: _Prefs.getBool('ai_ghost')      ?? ai.ghostTextEnabled,
      ghostDebounceMs:  _Prefs.getInt('ai_debounce')    ?? ai.ghostDebounceMs,
      maxTokens:        _Prefs.getInt('ai_tokens')      ?? ai.maxTokens,
      temperature:      _Prefs.getDouble('ai_temp')     ?? ai.temperature,
      systemPrompt:     _Prefs.getString('ai_sys')      ?? AiSettings.kDefaultSystem,
    );
  }

  void saveEditor(EditorSettings s) {
    editor = s; notifyListeners();
    _Prefs.setString('e_theme', s.theme);
    _Prefs.setString('e_lang',  s.language);
    _Prefs.setDouble('e_fs',    s.fontSize);
    _Prefs.setBool('e_ww',      s.wordWrap);
    _Prefs.setBool('e_ss',      s.stickyScroll);
    _Prefs.setBool('e_ln',      s.showLineNumbers);
    _Prefs.setBool('e_fg',      s.fixedGutter);
    _Prefs.setBool('e_mm',      s.showMinimap);
    _Prefs.setBool('e_lb',      s.showLightbulb);
    _Prefs.setBool('e_fa',      s.showFoldArrows);
    _Prefs.setBool('e_bl',      s.showBlockLines);
    _Prefs.setBool('e_sp',      s.symbolPairAutoClose);
    _Prefs.setBool('e_ai',      s.autoIndent);
    _Prefs.setBool('e_ac',      s.autoCompletion);
    _Prefs.setBool('e_fos',     s.formatOnSave);
    _Prefs.setBool('e_sb',      s.showSymbolBar);
    _Prefs.setBool('e_hl',      s.highlightCurrentLine);
    _Prefs.setBool('e_hab',     s.highlightActiveBlock);
    _Prefs.setString('e_lhs',   s.lineHighlightStyle);
    _Prefs.setInt('e_ts',       s.tabSize);
    _Prefs.setBool('e_us',      s.useSpaces);
    _Prefs.setInt('e_cb',       s.cursorBlinkMs);
    _Prefs.setBool('e_di',      s.showDiagnosticIndicators);
    _Prefs.setBool('e_ro',      s.readOnly);
    _Prefs.setBool('e_id',      s.showIndentDots);
    _Prefs.setString('e_bls',   s.blockLineStyle);
  }

  void saveAi(AiSettings s) {
    ai = s; notifyListeners();
    _Prefs.setString('ai_key',      s.geminiApiKey);
    _Prefs.setString('ai_model',    s.geminiModel);
    _Prefs.setString('ai_mode',     s.agentMode.name);
    _Prefs.setBool('ai_ghost',      s.ghostTextEnabled);
    _Prefs.setInt('ai_debounce',    s.ghostDebounceMs);
    _Prefs.setInt('ai_tokens',      s.maxTokens);
    _Prefs.setDouble('ai_temp',     s.temperature);
    _Prefs.setString('ai_sys',      s.systemPrompt);
  }
}
