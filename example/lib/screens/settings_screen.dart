// example/lib/screens/settings_screen.dart
//
// Tela de Configurações completa:
//   • Aparência do editor (tema, fonte, etc.)
//   • Comportamento (auto-indent, word wrap, tab size, etc.)
//   • Funcionalidades visuais (minimap, lightbulb, line numbers, etc.)
//   • Agente de IA (modo, ghost text, debounce, temperatura)
//   • Chave de API Gemini (com campo seguro + botão de validação)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../ai/gemini_service.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late EditorSettings _editor;
  late AiSettings     _ai;


  bool _keyVisible   = false;
  bool _keyValidating = false;
  bool? _keyValid;
  String _validationMsg = '';

  static const _bg     = Color(0xFF1E1E2E);
  static const _surface = Color(0xFF181825);
  static const _surface2 = Color(0xFF24243A);
  static const _accent = Color(0xFF89B4FA);
  static const _accent2 = Color(0xFFCBA6F7);
  static const _text   = Color(0xFFCDD6F4);
  static const _subtext = Color(0xFF9399B2);
  static const _green  = Color(0xFFA6E3A1);
  static const _red    = Color(0xFFF38BA8);
  static const _yellow = Color(0xFFF9E2AF);

  @override
  void initState() {
    super.initState();
    _tabs   = TabController(length: 3, vsync: this);
    _editor = widget.state.editor;
    _ai     = widget.state.ai;
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  void _saveAll() {
    widget.state.saveEditor(_editor);
    widget.state.saveAi(_ai);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _validateKey() async {
    setState(() { _keyValidating = true; _keyValid = null; _validationMsg = ''; });
    final svc = GeminiService(
      apiKey: _ai.geminiApiKey, model: _ai.geminiModel);
    final ok = await svc.validateKey();
    setState(() {
      _keyValidating = false;
      _keyValid      = ok;
      _validationMsg = ok ? 'Chave válida ✓' : 'Chave inválida ou sem conexão';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _subtext, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Configurações',
            style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: _subtext,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.code, size: 16), text: 'Editor'),
            Tab(icon: Icon(Icons.visibility, size: 16), text: 'Visual'),
            Tab(icon: Icon(Icons.psychology, size: 16), text: 'IA Agent'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.check, color: _green, size: 18),
            label: const Text('Salvar', style: TextStyle(color: _green)),
            onPressed: _saveAll,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildEditorTab(),
          _buildVisualTab(),
          _buildAiTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Editor ─────────────────────────────────────────────────────────

  Widget _buildEditorTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _section('Aparência', [
        _dropdownRow('Tema', _editor.theme, _themes, (v) {
          setState(() => _editor = _editor.copyWith(theme: v)); }),
        _dropdownRow('Linguagem padrão', _editor.language, _languages, (v) {
          setState(() => _editor = _editor.copyWith(language: v)); }),
        _sliderRow('Tamanho da fonte', _editor.fontSize, 8, 32, (v) {
          setState(() => _editor = _editor.copyWith(fontSize: v)); },
          valueLabel: '${_editor.fontSize.round()}px'),
      ]),

      _section('Comportamento', [
        _switchRow('Word Wrap', _editor.wordWrap, (v) {
          setState(() => _editor = _editor.copyWith(wordWrap: v)); },
          subtitle: 'Quebra de linha automática'),
        _switchRow('Auto-indent', _editor.autoIndent, (v) {
          setState(() => _editor = _editor.copyWith(autoIndent: v)); },
          subtitle: 'Mantém indentação automática'),
        _switchRow('Auto-completar pares', _editor.symbolPairAutoClose, (v) {
          setState(() => _editor = _editor.copyWith(symbolPairAutoClose: v)); },
          subtitle: 'Fecha ( { [ " \' automaticamente'),
        _switchRow('Auto-completion', _editor.autoCompletion, (v) {
          setState(() => _editor = _editor.copyWith(autoCompletion: v)); },
          subtitle: 'Popup de sugestões de código'),
        _switchRow('Formatar ao salvar (Ctrl+S)', _editor.formatOnSave, (v) {
          setState(() => _editor = _editor.copyWith(formatOnSave: v)); },
          subtitle: 'Aplica DartFormatter no Ctrl+S'),
        _switchRow('Sticky Scroll', _editor.stickyScroll, (v) {
          setState(() => _editor = _editor.copyWith(stickyScroll: v)); },
          subtitle: 'Mantém escopo visível no topo'),
      ]),

      _section('Indentação', [
        _dropdownRow('Tamanho do Tab', _editor.tabSize.toString(),
            ['2', '4', '8'], (v) {
          setState(() => _editor = _editor.copyWith(tabSize: int.parse(v))); }),
        _switchRow('Usar espaços (não tabs)', _editor.useSpaces, (v) {
          setState(() => _editor = _editor.copyWith(useSpaces: v)); }),
      ]),

      _section('Cursor', [
        _sliderRow('Velocidade do cursor (ms)', _editor.cursorBlinkMs.toDouble(),
            200, 1000, (v) {
          setState(() => _editor = _editor.copyWith(cursorBlinkMs: v.round())); },
          valueLabel: '${_editor.cursorBlinkMs}ms'),
      ]),
    ],
  );

  // ── Tab 2: Visual ─────────────────────────────────────────────────────────

  Widget _buildVisualTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _section('Interface', [
        _switchRow('Números de linha', _editor.showLineNumbers, (v) {
          setState(() => _editor = _editor.copyWith(showLineNumbers: v)); }),
        _switchRow('Gutter fixo', _editor.fixedGutter, (v) {
          setState(() => _editor = _editor.copyWith(fixedGutter: v)); },
          subtitle: 'Números de linha não rolam com o código'),
        _switchRow('Minimap', _editor.showMinimap, (v) {
          setState(() => _editor = _editor.copyWith(showMinimap: v)); },
          subtitle: 'Painel de preview do código (direita)'),
        _switchRow('Symbol Bar', _editor.showSymbolBar, (v) {
          setState(() => _editor = _editor.copyWith(showSymbolBar: v)); },
          subtitle: 'Barra de símbolos para mobile ({ } ; = ...)'),
        _switchRow('Lightbulb (ações)', _editor.showLightbulb, (v) {
          setState(() => _editor = _editor.copyWith(showLightbulb: v)); },
          subtitle: 'Ícone de ações rápidas ao selecionar código'),
      ]),

      _section('Estrutura de código', [
        _switchRow('Setas de fold', _editor.showFoldArrows, (v) {
          setState(() => _editor = _editor.copyWith(showFoldArrows: v)); },
          subtitle: 'Setas para dobrar blocos de código'),
        _switchRow('Linhas de bloco', _editor.showBlockLines, (v) {
          setState(() => _editor = _editor.copyWith(showBlockLines: v)); },
          subtitle: 'Linhas verticais de indentação'),
        _dropdownRow('Estilo das linhas (legado)', _editor.blockLineStyle,
            ['solid', 'dashed', 'dotted', 'squareDotted', 'longDash', 'curved'], (v) {
          setState(() => _editor = _editor.copyWith(blockLineStyle: v)); }),
        _infoCard(
          'Temas com "program" no JSON ignoram este dropdown.\n'
          'Para customizar o estilo, edite os campos "program", '
          '"activeProgram", "endCap" e "activeEndCap" no arquivo do tema.',
        ),
      ]),

      _section('Pontos de indentação', [
        _switchRow('Mostrar pontos de indentação', _editor.showIndentDots, (v) {
          setState(() => _editor = _editor.copyWith(showIndentDots: v)); },
          subtitle: 'Pontos antes do 1º caractere de cada linha (estilo VSCode)'),
        _infoCard(
          'Os pontos são configuráveis por tema JSON.\n'
          'Edite o campo "indentDots" no arquivo de tema.',
        ),
      ]),

      _section('Linha atual', [
        _switchRow('Destaque da linha atual', _editor.highlightCurrentLine, (v) {
          setState(() => _editor = _editor.copyWith(highlightCurrentLine: v)); }),
        _switchRow('Destaque do bloco ativo', _editor.highlightActiveBlock, (v) {
          setState(() => _editor = _editor.copyWith(highlightActiveBlock: v)); },
          subtitle: 'Linha atual muda de cor dentro de um bloco de código'),
        _dropdownRow('Estilo do destaque', _editor.lineHighlightStyle,
            ['fill', 'stroke', 'accentBar', 'none'], (v) {
          setState(() => _editor = _editor.copyWith(lineHighlightStyle: v)); }),
      ]),

      _section('Avançado', [
        _switchRow('Indicadores de diagnóstico', _editor.showDiagnosticIndicators, (v) {
          setState(() => _editor = _editor.copyWith(showDiagnosticIndicators: v)); },
          subtitle: 'Sublinhados de erro e aviso'),
        _switchRow('Somente leitura', _editor.readOnly, (v) {
          setState(() => _editor = _editor.copyWith(readOnly: v)); },
          subtitle: 'Desativa toda edição no editor'),
      ]),

      _section('Temas disponíveis', [
        ...(_themes.map((t) => _themePreviewRow(t))),
      ]),
    ],
  );

  Widget _themePreviewRow(String name) {
    final isSelected = _editor.theme == name;
    return GestureDetector(
      onTap: () => setState(() => _editor = _editor.copyWith(theme: name)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _accent.withOpacity(0.12) : _surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSelected ? _accent : Colors.transparent, width: 1.5),
        ),
        child: Row(children: [
          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? _accent : _subtext, size: 18),
          const SizedBox(width: 12),
          Text(name, style: TextStyle(
              color: isSelected ? _accent : _text, fontSize: 14)),
          const Spacer(),
          ..._themeColorDots(name),
        ]),
      ),
    );
  }

  List<Widget> _themeColorDots(String name) {
    final colors = _themeColors[name] ?? [_accent, _accent2, _green];
    return colors.map((c) => Container(
      width: 12, height: 12,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    )).toList();
  }

  // ── Tab 3: IA ─────────────────────────────────────────────────────────────

  Widget _buildAiTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // API Key card
      _apiKeyCard(),
      const SizedBox(height: 8),

      _section('Modo do Agente', [
        ..._agentModes.entries.map((e) => _agentModeRow(e.key, e.value.$1, e.value.$2)),
      ]),

      _section('Ghost Text (sugestões inline)', [
        _switchRow('Ativar Ghost Text', _ai.ghostTextEnabled, (v) {
          setState(() => _ai = _ai.copyWith(ghostTextEnabled: v)); },
          subtitle: 'Sugestões de código estilo Copilot enquanto digita'),
        _sliderRow('Debounce (ms)', _ai.ghostDebounceMs.toDouble(), 200, 2000, (v) {
          setState(() => _ai = _ai.copyWith(ghostDebounceMs: v.round())); },
          valueLabel: '${_ai.ghostDebounceMs}ms',
          subtitle: 'Tempo de espera após parar de digitar'),
        _sliderRow('Max tokens', _ai.maxTokens.toDouble(), 64, 1024, (v) {
          setState(() => _ai = _ai.copyWith(maxTokens: v.round())); },
          valueLabel: '${_ai.maxTokens}'),
        _sliderRow('Temperatura', _ai.temperature, 0.0, 1.0, (v) {
          setState(() => _ai = _ai.copyWith(temperature: double.parse(v.toStringAsFixed(1)))); },
          valueLabel: _ai.temperature.toStringAsFixed(1),
          subtitle: '0=determinístico · 1=criativo'),
      ]),

      _section('Modelo Gemini', [
        _dropdownRow('Modelo', _ai.geminiModel, _geminiModels, (v) {
          setState(() => _ai = _ai.copyWith(geminiModel: v)); }),
        _infoCard(
          '💡 Recomendado: gemini-2.5-flash-preview (melhor custo-benefício)\n'
          'Melhor custo-benefício para completions de código. '
          'Gemini 2.5 Pro é mais preciso mas mais lento.',
        ),
      ]),

      _section('System Prompt', [
        _systemPromptEditor(),
      ]),

      _section('Atalhos de teclado', [
        _shortcutRow('Tab', 'Aceitar sugestão completa'),
        _shortcutRow('Alt + →', 'Aceitar próxima palavra'),
        _shortcutRow('Escape', 'Descartar sugestão'),
        _shortcutRow('Ctrl + Shift + P', 'Paleta de comandos'),
        _shortcutRow('Ctrl + S', 'Salvar (+ formatar se ativo)'),
        _shortcutRow('Ctrl + F', 'Buscar / substituir'),
        _shortcutRow('Ctrl + Z / Y', 'Desfazer / Refazer'),
        _shortcutRow('Ctrl + /', 'Comentar linha'),
        _shortcutRow('Alt + ↑/↓', 'Mover linha'),
      ]),
    ],
  );

  Widget _apiKeyCard() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_surface2, _surface2.withBlue(60)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _ai.isConfigured ? _green.withOpacity(0.4) : _accent.withOpacity(0.3),
        width: 1.5,
      ),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('🔑', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        const Text('Chave de API Gemini',
            style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (_ai.isConfigured)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _green.withOpacity(0.4)),
            ),
            child: const Text('Configurada',
                style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 4),
      const Text('Obtenha sua chave gratuita em aistudio.google.com',
          style: TextStyle(color: _subtext, fontSize: 12)),
      const SizedBox(height: 14),
      TextField(
        controller: TextEditingController(text: _ai.geminiApiKey)
          ..selection = TextSelection.collapsed(offset: _ai.geminiApiKey.length),
        obscureText: !_keyVisible,
        style: const TextStyle(color: _text, fontSize: 13, fontFamily: 'monospace'),
        onChanged: (v) => setState(() => _ai = _ai.copyWith(geminiApiKey: v)),
        decoration: InputDecoration(
          hintText: 'AIzaSy...',
          hintStyle: TextStyle(color: _subtext.withOpacity(0.5)),
          filled: true,
          fillColor: _bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _subtext.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _subtext.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _accent),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility,
                  color: _subtext, size: 18),
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
            ),
            if (_ai.geminiApiKey.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, color: _subtext, size: 18),
                onPressed: () => setState(() => _ai = _ai.copyWith(geminiApiKey: '')),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent.withOpacity(0.15),
              foregroundColor: _accent,
              side: const BorderSide(color: _accent),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _keyValidating
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
              : const Icon(Icons.verified, size: 16),
            label: Text(_keyValidating ? 'Validando...' : 'Validar chave'),
            onPressed: _ai.geminiApiKey.isEmpty || _keyValidating ? null : _validateKey,
          ),
        ),
        if (_keyValid != null) ...[
          const SizedBox(width: 12),
          Icon(_keyValid! ? Icons.check_circle : Icons.error,
              color: _keyValid! ? _green : _red),
          const SizedBox(width: 6),
          Text(_validationMsg,
              style: TextStyle(color: _keyValid! ? _green : _red, fontSize: 12)),
        ],
      ]),
    ]),
  );

  Widget _agentModeRow(AgentMode mode, String label, String desc) {
    final selected = _ai.agentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _ai = _ai.copyWith(agentMode: mode)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _accent2.withOpacity(0.10) : _surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _accent2 : Colors.transparent, width: 1.5),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? _accent2 : _subtext, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: selected ? _accent2 : _text,
                fontWeight: FontWeight.w600, fontSize: 14)),
            Text(desc, style: const TextStyle(color: _subtext, fontSize: 12)),
          ])),
        ]),
      ),
    );
  }

  Widget _systemPromptEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: TextEditingController(text: _ai.systemPrompt),
        onChanged: (v) => setState(() => _ai = _ai.copyWith(systemPrompt: v)),
        maxLines: 6,
        style: const TextStyle(color: _text, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          filled: true, fillColor: _surface2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _subtext.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _subtext.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent)),
          contentPadding: const EdgeInsets.all(12),
          hintText: 'Instrução de sistema para o modelo de IA...',
          hintStyle: TextStyle(color: _subtext.withOpacity(0.5)),
        ),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: () => setState(() => _ai = _ai.copyWith(systemPrompt: AiSettings.kDefaultSystem)),
        child: const Text('↩ Restaurar padrão', style: TextStyle(color: _subtext, fontSize: 12)),
      ),
    ],
  );

  // ── Common widgets ─────────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: _subtext, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      Container(
        decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, color: _bg.withOpacity(0.8)),
          ],
        ]),
      ),
    ],
  );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged, {String? subtitle}) =>
    SwitchListTile(
      value: value, onChanged: onChanged,
      activeColor: _accent,
      title: Text(label, style: const TextStyle(color: _text, fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: _subtext, fontSize: 12))
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );

  Widget _dropdownRow(String label, String value, List<String> options, ValueChanged<String> onChanged) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: _text, fontSize: 14))),
        DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          dropdownColor: _surface,
          underline: const SizedBox(),
          isDense: true,
          style: const TextStyle(color: _accent, fontSize: 13),
          items: options.map((o) => DropdownMenuItem(value: o,
              child: Text(o, style: const TextStyle(color: _accent)))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ]),
    );

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {required String valueLabel, String? subtitle}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: _text, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
            child: Text(valueLabel, style: const TextStyle(color: _accent, fontSize: 12,
                fontWeight: FontWeight.w600, fontFamily: 'monospace')),
          ),
        ]),
        if (subtitle != null) Text(subtitle,
            style: const TextStyle(color: _subtext, fontSize: 11)),
        Slider(
          value: value.clamp(min, max), min: min, max: max,
          activeColor: _accent, inactiveColor: _subtext.withOpacity(0.3),
          onChanged: onChanged,
        ),
      ]),
    );

  Widget _shortcutRow(String key, String desc) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _subtext.withOpacity(0.4)),
        ),
        child: Text(key, style: const TextStyle(
            color: _yellow, fontSize: 12, fontFamily: 'monospace',
            fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 12),
      Text(desc, style: const TextStyle(color: _subtext, fontSize: 13)),
    ]),
  );

  Widget _infoCard(String text) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _yellow.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _yellow.withOpacity(0.3)),
    ),
    child: Text(text, style: const TextStyle(color: _yellow, fontSize: 12)),
  );

  // ── Static data ───────────────────────────────────────────────────────────

  static const _themes = [
    'Dark (Catppuccin)', 'Dark Modern', 'GitHub Dark',
    'GitHub', 'Monokai', 'Dracula', 'Light',
  ];

  static const _languages = [
    'Dart', 'JavaScript', 'Python', 'Rust', 'Kotlin',
    'C++', 'HTML', 'CSS', 'JSON', 'YAML', 'Bash', 'XML', 'Plain Text',
  ];

  static const _geminiModels = [
    'gemini-2.5-flash-preview-04-17',
    'gemini-2.5-pro-preview-03-25',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
  ];

  static const _agentModes = <AgentMode, (String, String)>{
    AgentMode.fullAgent: ('🤖 Agente Completo', 'Ghost text + Chat + Code Review ativos'),
    AgentMode.ghostText: ('👻 Apenas Ghost Text', 'Sugestões inline enquanto digita'),
    AgentMode.chatAssistant: ('💬 Apenas Chat', 'Painel de chat com o assistente'),
    AgentMode.codeReview: ('🔍 Apenas Code Review', 'Análise e revisão de código'),
  };

  static const _themeColors = <String, List<Color>>{
    'Dark (Catppuccin)': [Color(0xFF89B4FA), Color(0xFFCBA6F7), Color(0xFFA6E3A1)],
    'Dark Modern':       [Color(0xFF569CD6), Color(0xFF4EC9B0), Color(0xFF6A9955)],
    'GitHub Dark':       [Color(0xFF58A6FF), Color(0xFFFF7B72), Color(0xFFA5D6FF)],
    'GitHub':            [Color(0xFF0550AE), Color(0xFF8250DF), Color(0xFF1A7F37)],
    'Monokai':           [Color(0xFFF92672), Color(0xFFA6E22E), Color(0xFFE6DB74)],
    'Dracula':           [Color(0xFFBD93F9), Color(0xFFFF79C6), Color(0xFF50FA7B)],
    'Light':             [Color(0xFF0000FF), Color(0xFF007700), Color(0xFF795E26)],
  };


}
