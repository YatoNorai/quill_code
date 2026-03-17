// example/lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quill_code/quill_code.dart';
import 'app_state.dart';
import 'theme_loader.dart';
import 'ai/gemini_service.dart';
import 'screens/settings_screen.dart';
import 'screens/git_diff_screen.dart';
import 'widgets/ai_panel.dart';
import 'stress_test_sample.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  await ThemeLoader.preloadAll();
  runApp(const QuillCodeExampleApp());
}

class QuillCodeExampleApp extends StatelessWidget {
  const QuillCodeExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QuillCode Demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF1E1E2E),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF89B4FA),
        secondary: Color(0xFFCBA6F7),
        surface: Color(0xFF181825),
      ),
    ),
    home: const EditorPage(),
  );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _appState = AppState.instance;
  late QuillCodeController _ctrl;
  GeminiService? _geminiSvc;
  bool _showAiPanel   = false;
  bool _ghostActive   = false;
  bool _diagnosticsOn = false;

  // Search state
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();
  int _searchResultCount = 0;
  int _searchCurrentIdx  = 0;
  StreamSubscription<List<EditorRange>>? _searchSub;

  static final _langBuilders = <String, QuillLanguage Function()>{
    'Dart':       DartLanguage.new,
    'JavaScript': JavaScriptLanguage.new,
    'Python':     PythonLanguage.new,
    'Kotlin':     KotlinLanguage.new,
    'Rust':       RustLanguage.new,
    'C++':        CppLanguage.new,
    'HTML':       HtmlLanguage.new,
    'CSS':        CssLanguage.new,
    'JSON':       JsonLanguage.new,
    'YAML':       YamlLanguage.new,
    'Bash':       BashLanguage.new,
    'XML':        XmlLanguage.new,
    'Plain Text': PlainTextLanguage.new,
    'StressTest': DartLanguage.new,
  };

  static const _samples = <String, String>{
    'Dart': r'''import 'dart:async';

/// QuillCode Demo — Dart com AI Ghost Text ativo!
/// Pressione Tab para aceitar sugestões. Configure sua
/// chave Gemini API nas ⚙️ Configurações para ativar.

class Repository<T extends Entity> {
  final Map<String, T> _store = {};
  final _events = StreamController<RepositoryEvent<T>>.broadcast();

  Stream<RepositoryEvent<T>> get events => _events.stream;

  Future<T?> findById(String id) async {
    await Future.delayed(const Duration(milliseconds: 10));
    return _store[id];
  }

  Future<T> save(T entity) async {
    _store[entity.id] = entity;
    _events.add(RepositoryEvent(type: EventType.updated, entity: entity));
    return entity;
  }

  Future<bool> delete(String id) async {
    final removed = _store.remove(id);
    if (removed != null) {
      _events.add(RepositoryEvent(type: EventType.deleted, entity: removed));
    }
    return removed != null;
  }

  List<T> findAll({bool Function(T)? where}) =>
      _store.values.where(where ?? (_) => true).toList();

  void dispose() => _events.close();
}

abstract class Entity {
  String get id;
}

enum EventType { created, updated, deleted }

class RepositoryEvent<T> {
  final EventType type;
  final T entity;
  const RepositoryEvent({required this.type, required this.entity});
}

void main() async {
  final repo = Repository<User>();
  repo.events.listen((e) => print('[${e.type.name}] ${e.entity}'));

  final alice = await repo.save(User(id: 'u1', name: 'Alice Silva', email: 'alice@example.com'));
  await repo.save(User(id: 'u2', name: 'Bob Moura', email: 'bob@example.com'));

  print('Total: ${repo.findAll().length}');
  repo.dispose();
}
''',
    'JavaScript': r'''// QuillCode JS Demo — ES2024
class EventBus {
  #handlers = new Map();
  on(event, handler) {
    if (!this.#handlers.has(event)) this.#handlers.set(event, new Set());
    this.#handlers.get(event).add(handler);
    return () => this.#handlers.get(event)?.delete(handler);
  }
  emit(event, data) {
    this.#handlers.get(event)?.forEach(h => h(data));
  }
}

const fibonacci = (n, memo = {}) => {
  if (n in memo) return memo[n];
  if (n <= 1) return n;
  return memo[n] = fibonacci(n - 1, memo) + fibonacci(n - 2, memo);
};

console.log([...Array(10).keys()].map(fibonacci));
''',
    'Python': r'''from dataclasses import dataclass, field
from typing import Generic, TypeVar, Iterator

T = TypeVar('T')

@dataclass
class Node(Generic[T]):
    value: T
    children: list['Node[T]'] = field(default_factory=list)

class Tree(Generic[T]):
    def __init__(self, root: T) -> None:
        self.root = Node(root)

    def bfs(self) -> Iterator[T]:
        from collections import deque
        q: deque[Node[T]] = deque([self.root])
        while q:
            node = q.popleft()
            yield node.value
            q.extend(node.children)

tree: Tree[int] = Tree(1)
tree.root.children = [Node(2), Node(3)]
print("BFS:", list(tree.bfs()))
''',
    'JSON': '{\n  "name": "quill_code",\n  "version": "0.2.0",\n  "themes": ["catppuccin", "dark_modern", "github_dark", "monokai", "dracula"],\n  "languages": ["dart", "javascript", "python", "rust", "kotlin"]\n}\n',
    'Bash': r'''#!/usr/bin/env bash
set -euo pipefail
ok()    { echo "✓ $*"; }
error() { echo "✗ $*" >&2; exit 1; }

check_deps() {
  for cmd in flutter dart git; do
    command -v "$cmd" &>/dev/null && ok "$cmd" || error "$cmd not found"
  done
}

check_deps && flutter pub get && flutter build apk --release
''',
    'StressTest': kStressTestSample,
    'YAML': r'''name: quill_code
description: "A new Flutter package project."
version: 0.0.1
homepage:

environment:
  sdk: ^3.11.0
  flutter: ">=1.17.0"

dependencies:
  flutter:
    sdk: flutter
  characters: ^1.3.0
  collection: ^1.18.0
  ffi: ^2.1.0
  # Uncomment when ready to use tree-sitter
  # tree_sitter: ^0.2.1


dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0


flutter:
  uses-material-design: true
  plugin:
    platforms:
      android:
        package: dev.quillcode.quill_code
        pluginClass: QuillCodePlugin
        ffiPlugin: true    # ← aqui

  ''',
  };

  String get _lang  => _appState.editor.language;
  String get _theme => _appState.editor.theme;

  EditorTheme get _editorTheme {
    final s    = _appState.editor;
    final base = ThemeLoader.buildThemeSync(s.theme, fontSize: s.fontSize);

    // The JSON theme's `program` / `activeProgram` take full priority.
    // The legacy "style" dropdown in Settings is only applied when the theme
    // has NO explicit program — i.e. it's a pure enum-style theme.
    final hasProgram = base.blockLines.program != null ||
                       base.blockLines.activeProgram != null;

    final newBlockLines = hasProgram
        // Theme defines DSL programs → respect them completely, only
        // allow the user to toggle indentDots.
        ? base.blockLines
        // Legacy theme → let the Settings dropdown override the style enum.
        : base.blockLines.copyWith(style: _parseBlockLineStyle(s.blockLineStyle));

    return base.copyWith(
      indentDots: base.indentDots.copyWith(visible: s.showIndentDots),
      blockLines: newBlockLines,
    );
  }

  BlockLineStyle _parseBlockLineStyle(String s) {
    switch (s) {
      case 'dashed':       return BlockLineStyle.dashed;
      case 'dotted':       return BlockLineStyle.dotted;
      case 'squareDotted': return BlockLineStyle.squareDotted;
      case 'longDash':     return BlockLineStyle.longDash;
      case 'curved':       return BlockLineStyle.curved;
      default:             return BlockLineStyle.solid;
    }
  }

  LineHighlightStyle _parseHlStyle(String s) {
    switch (s) {
      case 'stroke':    return LineHighlightStyle.stroke;
      case 'accentBar': return LineHighlightStyle.accentBar;
      case 'none':      return LineHighlightStyle.none;
      default:          return LineHighlightStyle.fill;
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = _buildCtrl(_lang);
    _appState.addListener(_onSettingsChanged);
    _setupGhostText();
    _subscribeSearcher();
  }

  @override
  void dispose() {
    _appState.removeListener(_onSettingsChanged);
    _searchSub?.cancel();
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _subscribeSearcher() {
    _searchSub?.cancel();
    _searchSub = _ctrl.searcher.resultsStream.listen((results) {
      if (mounted) setState(() {
        _searchResultCount = results.length;
        _searchCurrentIdx  = _ctrl.searcher.currentResultIndex;
      });
    });
  }

  void _setupGhostText() {
    final ai = _appState.ai;
    if (ai.isConfigured && ai.ghostTextEnabled) {
      _geminiSvc = GeminiService(
        apiKey: ai.geminiApiKey,
        model: ai.geminiModel,
        maxTokens: ai.maxTokens,
        temperature: ai.temperature,
        systemPrompt: ai.systemPrompt,
      );
      _ctrl.setGhostTextProvider(_geminiSvc!.ghostProvider);
      if (mounted) setState(() => _ghostActive = true);
    } else {
      // Snippet provider as fallback (offline, no API needed)
      _ctrl.setGhostTextProvider(
          SnippetGhostProvider(languageId: _lang.toLowerCase()).call);
      _geminiSvc = null;
      if (mounted) setState(() => _ghostActive = false);
    }
  }

  void _onSettingsChanged() {
    _applyProps();
    _setupGhostText();
    if (mounted) setState(() {});
  }

  void _applyProps([QuillCodeController? c]) {
    final s = _appState.editor;
    (c ?? _ctrl).props
      ..wordWrap              = s.wordWrap
      ..stickyScroll          = s.stickyScroll
      ..showLineNumbers       = s.showLineNumbers
      ..fixedLineNumbers      = s.fixedGutter
      ..showMinimap           = s.showMinimap
      ..showLightbulb         = s.showLightbulb
      ..showFoldArrows        = s.showFoldArrows
      ..showBlockLines        = s.showBlockLines
      ..symbolPairAutoCompletion = s.symbolPairAutoClose
      ..autoIndent            = s.autoIndent
      ..autoCompletion        = s.autoCompletion
      ..formatOnSave          = s.formatOnSave
      ..highlightCurrentLine  = s.highlightCurrentLine
      ..highlightActiveBlock  = s.highlightActiveBlock
      ..lineHighlightStyle    = _parseHlStyle(s.lineHighlightStyle)
      ..tabSize               = s.tabSize
      ..useSpacesForTabs      = s.useSpaces
      ..cursorBlinkIntervalMs = s.cursorBlinkMs
      ..showDiagnosticIndicators = s.showDiagnosticIndicators
      ..readOnly              = s.readOnly;
    // Notify so RenderBox picks up prop changes (gutter width, etc.)
    (c ?? _ctrl).notifyListeners();
  }

  QuillCodeController _buildCtrl(String lang) {
    final language = _langBuilders[lang]?.call() ?? DartLanguage();
    final c = QuillCodeController(
      text: _samples[lang] ?? '// Start typing…\n',
      language: language,
    );
    _applyProps(c);
    return c;
  }

  void _switchLang(String lang) {
    final old = _ctrl;
    _ctrl = _buildCtrl(lang);
    _setupGhostText();
    _subscribeSearcher();
    _appState.saveEditor(_appState.editor.copyWith(language: lang));
    old.dispose();
    setState(() {});
  }

  void _switchTheme(String t) {
    _appState.saveEditor(_appState.editor.copyWith(theme: t));
    setState(() {});
  }

  // ── Search ────────────────────────────────────────────────────────────────
  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      _ctrl.searcher.stopSearch();
      setState(() { _searchResultCount = 0; _searchCurrentIdx = 0; });
      return;
    }
    _ctrl.searcher.search(query, const SearchOptions());
    // Results delivered via _searchSub stream subscription
  }

  void _searchNext() {
    final pos = _ctrl.cursor.position;
    final r = _ctrl.searcher.gotoNext(pos);
    if (r != null) {
      _ctrl.setCursor(r.start);
    }
    setState(() => _searchCurrentIdx = _ctrl.searcher.currentResultIndex);
  }

  void _searchPrev() {
    final pos = _ctrl.cursor.position;
    final r = _ctrl.searcher.gotoPrevious(pos);
    if (r != null) {
      _ctrl.setCursor(r.start);
    }
    setState(() => _searchCurrentIdx = _ctrl.searcher.currentResultIndex);
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchCtrl.clear();
        _ctrl.searcher.stopSearch();
        _searchResultCount = 0;
        _searchCurrentIdx  = 0;
      }
    });
  }

  void _toggleDiagnostics() {
    setState(() => _diagnosticsOn = !_diagnosticsOn);
    if (_diagnosticsOn) {
      _ctrl.setDiagnostics([
        DiagnosticRegion(
          range: EditorRange(const CharPosition(2, 4), const CharPosition(2, 18)),
          severity: DiagnosticSeverity.error,
          message: 'Undefined name "Repository" — missing import?',
          source: 'quill-demo',
        ),
        DiagnosticRegion(
          range: EditorRange(const CharPosition(5, 0), const CharPosition(5, 12)),
          severity: DiagnosticSeverity.warning,
          message: 'Unused import.',
          source: 'quill-demo',
        ),
      ]);
    } else {
      _ctrl.clearDiagnostics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _editorTheme;
    final cs    = theme.colorScheme;
    final s     = _appState.editor;

    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) => Scaffold(
        backgroundColor: cs.background,
        body: SafeArea(
          child: Column(children: [
            _buildAppBar(cs, theme),
            _buildToolbar(context, cs, theme, s),
            if (_searchVisible) _buildSearchBar(cs, theme),
            Expanded(
              child: Row(children: [
                Expanded(
                  child: QuillCodeEditor(
                    controller: _ctrl,
                    theme: theme,
                    showSymbolBar: s.showSymbolBar,
                    autofocus: true,
                    onChanged: (_) {},
                    onSave: () => _snack(
                        s.formatOnSave ? '✅ Salvo e formatado' : '✅ Salvo'),
                  ),
                ),
                if (_showAiPanel)
                  AiPanel(
                    state: _appState,
                    currentCode: _ctrl.text,
                    currentLanguage: _lang,
                    onClose: () => setState(() => _showAiPanel = false),
                  ),
              ]),
            ),
            _buildStatusBar(cs, theme),
          ]),
        ),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────
  Widget _buildSearchBar(EditorColorScheme cs, EditorTheme theme) {
    final hasResults = _searchResultCount > 0;
    return Container(
      color: cs.lineNumberBackground,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(children: [
        Icon(Icons.search, size: 16, color: cs.lineNumber),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: TextStyle(color: cs.textNormal, fontSize: theme.fontSize * 0.9),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Pesquisar…',
              hintStyle: TextStyle(color: cs.lineNumber),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.blockLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.blockLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.cursor),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              suffixIcon: hasResults
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${_searchCurrentIdx + 1}/$_searchResultCount',
                      style: TextStyle(color: cs.lineNumber, fontSize: 11),
                    ),
                  )
                : null,
              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _iconBtn(Icons.keyboard_arrow_up, 'Anterior', cs,
            hasResults ? _searchPrev : null),
        _iconBtn(Icons.keyboard_arrow_down, 'Próximo', cs,
            hasResults ? _searchNext : null),
        _iconBtn(Icons.close, 'Fechar pesquisa', cs, _toggleSearch),
      ]),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar(EditorColorScheme cs, EditorTheme theme) => Container(
    color: cs.lineNumberBackground,
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        // Logo + title
        Center(child: Icon(Icons.edit_note, size: 20, color: cs.cursor)),
        const SizedBox(width: 6),
        Center(child: Text('QuillCode', style: TextStyle(
            color: cs.textNormal, fontSize: 14,
            fontWeight: FontWeight.w700, fontFamily: theme.fontFamily))),
        const SizedBox(width: 4),
        Center(child: _badge('v0.2', cs.cursor, theme)),
        const SizedBox(width: 10),
        // Pickers
        Center(child: _Picker(value: _lang, options: _langBuilders.keys.toList(),
            cs: cs, fs: theme.fontSize, onChanged: _switchLang)),
        const SizedBox(width: 8),
        Center(child: _Picker(value: _theme, options: ThemeLoader.themeFiles.keys.toList(),
            cs: cs, fs: theme.fontSize, onChanged: _switchTheme)),
        const SizedBox(width: 4),
        // Actions
        Center(child: _ghostPill(cs)),
        _iconBtn(Icons.text_decrease, 'Fonte −', cs, () =>
            _appState.saveEditor(_appState.editor.copyWith(
                fontSize: (_appState.editor.fontSize - 1).clamp(8, 32)))),
        _iconBtn(Icons.text_increase, 'Fonte +', cs, () =>
            _appState.saveEditor(_appState.editor.copyWith(
                fontSize: (_appState.editor.fontSize + 1).clamp(8, 32)))),
        _iconBtn(Icons.psychology,
            _showAiPanel ? 'Fechar painel IA' : 'Painel IA',
            cs, () => setState(() => _showAiPanel = !_showAiPanel),
            color: _appState.ai.isConfigured ? cs.cursor : cs.lineNumber),
        _iconBtn(Icons.settings, 'Configurações', cs, () =>
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => SettingsScreen(state: _appState)))),
        _iconBtn(Icons.difference_outlined, 'Git Diff Demo', cs, () =>
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const GitDiffScreen()))),
      ],
    ),
  );

  // ── Toolbar ───────────────────────────────────────────────────────────────
  Widget _buildToolbar(BuildContext ctx, EditorColorScheme cs, EditorTheme theme,
      EditorSettings s) => Container(
    color: cs.lineNumberBackground,
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _chip('Wrap',        s.wordWrap,         cs, theme, () { _ctrl.props.wordWrap = !s.wordWrap; _appState.saveEditor(s.copyWith(wordWrap: !s.wordWrap)); }),
        _chip('Sticky',      s.stickyScroll,     cs, theme, () { _ctrl.props.stickyScroll = !s.stickyScroll; _appState.saveEditor(s.copyWith(stickyScroll: !s.stickyScroll)); }),
        _chip('Ln Nums',     s.showLineNumbers,  cs, theme, () { _ctrl.props.showLineNumbers = !s.showLineNumbers; _appState.saveEditor(s.copyWith(showLineNumbers: !s.showLineNumbers)); }),
        _chip('Minimap',     s.showMinimap,      cs, theme, () { _ctrl.props.showMinimap = !s.showMinimap; _appState.saveEditor(s.copyWith(showMinimap: !s.showMinimap)); }),
        _chip('SymBar',      s.showSymbolBar,    cs, theme, () => _appState.saveEditor(s.copyWith(showSymbolBar: !s.showSymbolBar))),
        _chip('Fmt/Save',    s.formatOnSave,     cs, theme, () { _ctrl.props.formatOnSave = !s.formatOnSave; _appState.saveEditor(s.copyWith(formatOnSave: !s.formatOnSave)); }),
        _chip('Diag.',       _diagnosticsOn,     cs, theme, _toggleDiagnostics),
        _vdiv(cs),
        _toolBtn(ctx, Icons.undo,                'Desfazer',    _ctrl.undo,          cs),
        _toolBtn(ctx, Icons.redo,                'Refazer',     _ctrl.redo,          cs),
        _toolBtn(ctx, Icons.select_all,          'Sel. tudo',   _ctrl.selectAll,     cs),
        _toolBtn(ctx, Icons.snippet_folder,      'Snippet',     _insertSnippet,      cs),
        _toolBtn(ctx, Icons.delete_sweep,        'Del. linha',  _deleteLine,         cs),
        _toolBtn(ctx, Icons.content_copy,        'Dupl. linha', _duplicateLine,      cs),
        _toolBtn(ctx, Icons.wrap_text,           'Comentar',    _toggleComment,      cs),
        _toolBtn(ctx, Icons.format_indent_increase, 'Indentar', () => _ctrl.insertTab(), cs),
        _toolBtn(ctx, Icons.compress,            'Fold All',    _foldAll,            cs),
        _toolBtn(ctx, Icons.expand,              'Unfold All',  _unfoldAll,          cs),
        _vdiv(cs),
        // Search button
        _toolBtn(ctx, Icons.search, 'Pesquisar (Ctrl+F)',
            _toggleSearch, cs, color: _searchVisible ? cs.cursor : cs.lineNumber),
        _vdiv(cs),
        _toolBtn(ctx, Icons.terminal, 'Paleta (Ctrl+⇧+P)',
            () => QuillActionsMenu.show(ctx, _ctrl, _editorTheme), cs,
            color: cs.cursor),
      ]),
    ),
  );

  void _deleteLine() {
    final l = _ctrl.cursor.line;
    _ctrl.selectLine();
    if (_ctrl.cursor.hasSelection) {
      _ctrl.deleteSelection();
      if (l < _ctrl.content.lineCount) _ctrl.deleteCharBefore();
    }
  }

  void _duplicateLine() {
    final l = _ctrl.cursor.line;
    final t = _ctrl.content.getLineText(l);
    _ctrl.insertText('\n$t');
  }

  void _toggleComment() {
    final l = _ctrl.cursor.line;
    final t = _ctrl.content.getLineText(l);
    final tr = t.trimLeft();
    if (tr.startsWith('//')) {
      final idx = t.indexOf('//');
      _ctrl.selectLine();
      _ctrl.insertText(t.substring(0, idx) + t.substring(idx + 2).trimLeft());
    } else {
      final ind = t.length - tr.length;
      _ctrl.selectLine();
      _ctrl.insertText('${t.substring(0, ind)}// $tr');
    }
  }

  void _foldAll() {
    for (final b in _ctrl.styles.codeBlocks) {
      if (b.isFoldable && !_ctrl.isFolded(b.startLine)) _ctrl.toggleFold(b.startLine);
    }
  }

  void _unfoldAll() {
    for (final sl in List.of(_ctrl.foldedBlocks)) _ctrl.toggleFold(sl);
  }

  // ── Status bar ─────────────────────────────────────────────────────────────
  Widget _buildStatusBar(EditorColorScheme cs, EditorTheme theme) =>
    ListenableBuilder(
      listenable: _ctrl,
      builder: (_, __) {
        final cur = _ctrl.cursor;
        final con = _ctrl.content;
        return Container(
          color: cs.cursor.withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: Row(children: [
            // Left side: scrollable info (shrinks/clips on narrow screens)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _sitem('Ln ${cur.line + 1}, Col ${cur.column + 1}', cs, theme),
                  _sdiv(cs), _sitem('${con.lineCount} linhas', cs, theme),
                  _sdiv(cs), _sitem(_ctrl.language.name, cs, theme),
                  _sdiv(cs), _sitem('UTF-8', cs, theme),
                  _sdiv(cs),
                  Row(children: [
                    Icon(
                      _ghostActive ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                      color: _ghostActive ? const Color(0xFFA6E3A1) : cs.lineNumber,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _ghostActive ? 'AI Ghost ON' :
                      _appState.ai.isConfigured ? 'Ghost OFF' : 'Sem API',
                      style: TextStyle(
                        color: _ghostActive ? const Color(0xFFA6E3A1) : cs.lineNumber,
                        fontSize: theme.fontSize * 0.75,
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            // Right side: fixed items
            if (_ctrl.diagnostics.hasErrors) ...[
              Icon(Icons.error_outline, color: cs.problemError, size: 13),
              const SizedBox(width: 4),
              Text('Erros', style: TextStyle(color: cs.problemError,
                  fontSize: theme.fontSize * 0.75)),
              _sdiv(cs),
            ],
            _sitem('Tab: ${_ctrl.props.tabSize}', cs, theme),
            _sdiv(cs),
            _sitem('QuillCode', cs, theme),
          ]),
        );
      },
    );

  // ── Widget helpers ─────────────────────────────────────────────────────────

  Widget _ghostPill(EditorColorScheme cs) {
    final ai = _appState.ai;
    if (!ai.isConfigured) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => setState(() => _showAiPanel = !_showAiPanel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _ghostActive
              ? const Color(0xFFA6E3A1).withOpacity(0.12)
              : cs.lineNumber.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _ghostActive
              ? const Color(0xFFA6E3A1).withOpacity(0.5)
              : cs.lineNumber.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            _ghostActive ? Icons.auto_awesome : Icons.auto_awesome_outlined,
            size: 13,
            color: _ghostActive ? const Color(0xFFA6E3A1) : cs.lineNumber,
          ),
          const SizedBox(width: 5),
          Text(_ghostActive ? 'AI Ghost ON' : 'Ghost OFF',
            style: TextStyle(
              color: _ghostActive ? const Color(0xFFA6E3A1) : cs.lineNumber,
              fontSize: 12, fontWeight: FontWeight.w600,
            )),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color color, EditorTheme theme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11,
        fontFamily: theme.fontFamily)),
  );

  Widget _chip(String label, bool active, EditorColorScheme cs,
      EditorTheme theme, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? cs.cursor.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? cs.cursor : cs.blockLine),
        ),
        child: Text(label, style: TextStyle(
          color: active ? cs.cursor : cs.lineNumber,
          fontSize: theme.fontSize * 0.78,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );

  Widget _toolBtn(BuildContext ctx, IconData icon, String tooltip,
      VoidCallback onTap, EditorColorScheme cs, {Color? color}) =>
    Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(icon, color: color ?? cs.lineNumber, size: 16),
        ),
      ),
    );

  Widget _iconBtn(IconData icon, String tooltip, EditorColorScheme cs,
      VoidCallback? onTap, {Color? color}) =>
    IconButton(
      icon: Icon(icon, color: onTap != null ? (color ?? cs.lineNumber) : cs.lineNumber.withOpacity(0.3), size: 19),
      onPressed: onTap,
      tooltip: tooltip,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );

  Widget _vdiv(EditorColorScheme cs) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    width: 1, height: 16,
    color: cs.blockLine.withOpacity(0.5),
  );

  Widget _sitem(String t, EditorColorScheme cs, EditorTheme theme) =>
    Text(t, style: TextStyle(color: cs.lineNumber,
        fontSize: theme.fontSize * 0.75, fontFamily: 'monospace'));

  Widget _sdiv(EditorColorScheme cs) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    width: 1, height: 12, color: cs.blockLine.withOpacity(0.5));

  void _insertSnippet() => _ctrl.insertSnippet(
    r'for (int ${1:i} = 0; $1 < ${2:count}; $1++) {'
    '\n  \${3:// body}\n}',
    variables: const {'TM_FILENAME': 'example.dart'},
  );

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg),
      backgroundColor: const Color(0xFF313244),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Picker extends StatelessWidget {
  final String value;
  final List<String> options;
  final EditorColorScheme cs;
  final double fs;
  final ValueChanged<String> onChanged;
  const _Picker({required this.value, required this.options,
    required this.cs, required this.fs, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    value: options.contains(value) ? value : options.first,
    dropdownColor: cs.completionBackground,
    underline: const SizedBox(), isDense: true,
    style: TextStyle(color: cs.textNormal, fontSize: fs * 0.85),
    items: options.map((o) => DropdownMenuItem(value: o,
        child: Text(o, style: TextStyle(color: cs.textNormal, fontSize: fs * 0.85)))).toList(),
    onChanged: (v) { if (v != null) onChanged(v); },
  );
}
