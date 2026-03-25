// lib/src/widgets/quill_code_editor.dart
// ─────────────────────────────────────────────────────────────────────────────
// PERFORMANCE ARCHITECTURE
//   • setState() only called for: zoom change, search bar toggle
//   • Cursor/selection position → _cursorTick (ValueNotifier<int>) → only
//     handle overlay and layers 3-6 rebuild (never the full widget tree)
//   • Gutter scroll sync: _vCtrl.addListener → _gutterScrollY.value++ →
//     ValueListenableBuilder repaint only the gutter CustomPaint
//   • TextPainter line cache: keyed by (lineIndex, docVersion, folded),
//     max 256 entries with FIFO eviction — avoids re-layout every frame
//   • _visibleLines() cached until document or fold version changes
//   • markNeedsLayout only on content change; cursor/blink → markNeedsPaint
//   • RepaintBoundary on every independent layer
//   • GestureDetectors stable across builds (no key reassignment)
//
// SELECTION TOOLBAR (appears on long-press / double-tap selection):
//   Cut • Copy • Paste • Select Word • Select Line • Select All •
//   Indent • Unindent • Comment/Uncomment • UPPERCASE • lowercase •
//   Undo • Redo
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show ClipOp;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../core/editor_controller.dart';
import '../core/char_position.dart';
import '../text/content.dart' show ContentChangeEvent;
import '../core/editor_props.dart';
import '../text/text_range.dart';
import '../theme/editor_theme.dart';
import '../theme/indent_program.dart';
import '../theme/theme_dark.dart';
import '../theme/color_scheme.dart';
import '../highlighting/span.dart';
import '../highlighting/code_block.dart';
import '../diagnostics/diagnostic_region.dart';
import 'completion_popup.dart';
import 'search_bar_widget.dart';
import 'symbol_input_bar.dart';
import 'minimap_widget.dart';
import '../actions/code_action.dart';
import '../language/dart_formatter.dart';
import 'actions_menu_widget.dart';
import '../actions/code_action_provider.dart';
import '../actions/lightbulb_widget.dart';
import '../text/bracket_matcher.dart';
import '../color/color_detector.dart';
import 'color_picker_overlay.dart';
import '../actions/symbol_analyzer.dart';
import '../actions/symbol_info_panel.dart';
import '../lsp/lsp_bridge.dart';
import '../lsp/lsp_controller_mixin.dart';
import '../lsp/lsp_hover_panel.dart';
import '../lsp/lsp_signature_panel.dart';
import '../lsp/quill_lsp_config.dart';
import '../lsp/lsp_stdio_client.dart';
import '../native/quill_native.dart';
import '../lsp/lsp_socket_client.dart';
import '../completion/vscode_snippets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Virtual identity list — fold-free optimisation
// ─────────────────────────────────────────────────────────────────────────────
// When there are no folds, the "visible lines" list is just [0, 1, …, n-1].
// _IdentityList wraps a single integer instead of allocating n integers, so
// a 100 k-line document avoids the ~800 KB allocation every time the document
// version ticks (i.e. every keystroke).

class _IdentityList extends ListBase<int> {
  final int _len;
  const _IdentityList(this._len);
  @override int get length => _len;
  @override int operator[](int i) => i;
  @override void operator[]=(int i, int v) => throw UnsupportedError('immutable');
  @override set length(int v)              => throw UnsupportedError('immutable');
}

// ═══════════════════════════════════════════════════════════════════════════
// Public widget
// ═══════════════════════════════════════════════════════════════════════════
class QuillCodeEditor extends StatefulWidget {
  final QuillCodeController  controller;
  final EditorTheme?         theme;
  final bool showSymbolBar;
  final bool autofocus;
  final FocusNode?           focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback?        onSave;
  /// Optional LSP client — when provided the editor auto-attaches and
  /// wires completions, diagnostics and code actions through it.
  final LspClient?           lspClient;
  /// High-level LSP config — use instead of [lspClient] for automatic
  /// setup. Supports stdio and WebSocket transports.
  ///
  /// ```dart
  /// QuillCodeEditor(
  ///   controller: ctrl,
  ///   lspConfig: QuillLspStdioConfig(
  ///     executable: 'pyright-langserver',
  ///     args: ['--stdio'],
  ///     workspacePath: '/my/project',
  ///     languageId: 'python',
  ///   ),
  /// )
  /// ```
  final QuillLspConfig?      lspConfig;
  /// File URI passed to the LSP server (e.g. 'file:///path/to/file.dart')
  final String?              fileUri;
  /// Called when LSP go-to-definition resolves to a different file.
  final void Function(String uri, int line, int column)? onNavigateToFile;

  const QuillCodeEditor({
    super.key,
    required this.controller,
    this.theme,
    this.showSymbolBar = true,
    this.autofocus     = false,
    this.focusNode,
    this.onChanged,
    this.onSave,
    this.lspClient,
    this.lspConfig,
    this.fileUri,
    this.onNavigateToFile,
  });

  @override
  State<QuillCodeEditor> createState() => _QCEState();
}

// ═══════════════════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════════════════
class _QCEState extends State<QuillCodeEditor> with TickerProviderStateMixin implements TextInputClient {

  // ── Focus / cursor blink ───────────────────────────────────────────────
  late FocusNode           _focus;
  TextInputConnection?     _inputConn;   // Android IME connection for clipboard paste
  late AnimationController _blink;

  // ── Scroll ────────────────────────────────────────────────────────────
  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();

  // ── Keyboard height tracking — for auto-scroll when virtual keyboard opens ──
  double _prevKbHeight = 0.0;
  /// Viewport dimension quando o teclado está fechado (kbHeight ≈ 0).
  /// Usado para detectar se o Scaffold já redimensionou o viewport ao abrir o
  /// teclado (resizeToAvoidBottomInset:true), evitando dupla subtração de kbHeight.
  double _noKbViewportDimension = 0.0;

  // ── Granular notifiers — drive targeted repaints with NO setState ──────
  /// Bumped on every cursor/selection/content change → handle layer + overlays
  final ValueNotifier<int>    _cursorTick    = ValueNotifier(0);
  /// Driven directly by _vCtrl → gutter painter only
  final ValueNotifier<double> _gutterScrollY = ValueNotifier(0);
  final ValueNotifier<int>    _foldN         = ValueNotifier(0); // bumped on every fold toggle
  /// Driven directly by _hCtrl → gutter shadow only
  final ValueNotifier<double> _hScrollN      = ValueNotifier(0);
  /// Bumped when handle visibility changes → handle layer only
  final ValueNotifier<int>    _handleTick    = ValueNotifier(0);
  /// Driven directly by _EBox pinch — zero setState, used to sync overlay positions
  final ValueNotifier<double> _zoomN         = ValueNotifier(1.0);
  /// Gutter width driven by _EBox — updates immediately when zoom changes
  final ValueNotifier<double> _gwN           = ValueNotifier(0.0);
  // Word-wrap: row Y offsets shared from _EBox → _GutterPainter
  final ValueNotifier<List<double>> _wrapOffsetsN = ValueNotifier(const []);
  // Ghost layout shared from _EBox → _GutterPainter so fold arrows stay in sync
  final ValueNotifier<int> _ghostInsertViN  = ValueNotifier(-1);
  final ValueNotifier<int> _ghostExtraRowsN = ValueNotifier(0);

  // ── Pre-built Listenables — allocated once, not on every build() ─────────
  // Listenable.merge() allocates a new list + object every call.
  // Storing them as fields eliminates those allocs from the hot build path.
  late final Listenable _gutterListenable;
  late final Listenable _handleListenable;
  late final Listenable _toolbarListenable;
  late final Listenable _magnifierListenable;
  late final Listenable _scrollListenable;
  double get _zoom => _zoomN.value;
  /// Toolbar show/hide
  final ValueNotifier<bool>   _toolbarVisible   = ValueNotifier(false);
  final ValueNotifier<bool>   _lightbulbVisible = ValueNotifier(false);
  SymbolInfo?                 _hoveredSymbol;    // symbol under cursor (for info panel)
  String?                     _lspHoverText;     // LSP hover contents (shown on long-press)
  bool                        _lspHoverVisible = false;
  // Signature help — shown when user types '(' or ','
  LspSignatureHelp?           _lspSigHelp;
  bool                        _lspSigVisible = false;
  BracketPair?                _activeBracketPair; // bracket pair under/adjacent to cursor
  int                         _activeBlockDepth = 0; // nesting depth of cursor's codeblock
  bool                        _symbolPanelVisible = false;

  // ── Layout (written in LayoutBuilder, read in helpers) ────────────────
  Size   _vpSize = Size.zero;
  double _gw     = 0;
  static const double _minimapWidth = 80.0; // VSCode-style minimap panel width

  // ── Handle state (mutated directly; drives _handleTick not setState) ──
  String? _drag;
  bool    _cursorHandleVisible = false;
  bool    _selHandlesVisible   = false;
  Timer?  _cursorHandleTimer;
  Timer?  _edgeTimer;
  // Scroll-end detection: hide handles+toolbar during scroll, restore after 400ms idle
  Timer?  _scrollEndTimer;
  bool    _handlesHiddenByScroll = false;
  bool    _toolbarHiddenByScroll = false;

  // ── Scrollbar fade animation + drag ──────────────────────────────────
  late AnimationController _scrollbarFade;
  Timer?  _scrollbarHideTimer;
  // Track initial pixels when a scrollbar drag starts
  double _sbVDragStartPx    = 0;
  double _sbVDragStartLocal = 0;
  double _sbHDragStartPx    = 0;
  double _sbHDragStartLocal = 0;

  // ── Color decorator picker state ─────────────────────────────────────
  Offset?     _colorPickerAnchor;
  ColorMatch? _colorPickerMatch;
  int         _colorPickerLine = -1;
  final Map<int, List<ColorMatch>> _colorCache = {};
  int _colorCacheVersion = -1;

  // ── Magnifier (shown above finger during cursor-handle drag) ──────────
  Offset? _magnifierPos; // local position of magnified point; null = hidden

  // ── Misc ──────────────────────────────────────────────────────────────
  bool _searchVisible  = false;
  int  _completionIdx  = 0;
  double _lastTapLx = 0, _lastTapLy = 0;
  // Throttle flag: avoids calling setState for every zoom PointerMoveEvent.
  bool _gwSetStatePending = false;

  // ── Fold cache ────────────────────────────────────────────────────────
  List<int>?   _cachedVis;
  Map<int,int> _cachedVisIdx  = {};
  int          _cachedFoldKey = -1;
  int          _lastContentVersion = -1;
  /// True when there are no active folds — vis[i] == i for all i (identity mapping).
  /// Allows O(1) reverse lookup without a HashMap.
  bool         _cachedFoldFree = true;

  // ── Theme ─────────────────────────────────────────────────────────────
  // Mutable copy — updated by _onZoomChanged so _lh/_cw/_gw are always in sync
  late EditorTheme _effectiveTheme;
  EditorTheme get _theme => _effectiveTheme;
  double get _lh => _effectiveTheme.lineHeightPx;
  double get _cw => _effectiveTheme.fontSize * 0.601;

  double _calcGw() {
    final ctrl     = widget.controller;
    final digits   = ctrl.content.lineCount.toString().length;
    final fs       = _effectiveTheme.fontSize;
    // Números usam o mesmo fontSize do código para garantir alinhamento perfeito
    // em qualquer nível de zoom — sem multiplicador separado.
    final numCharW = fs * 0.601;
    double w = 0;
    if (ctrl.props.showLineNumbers) w = numCharW * digits + 4;
    if (ctrl.props.showFoldArrows)  w += 18;
    if (w < 4) return 0;
    return w;
  }

  // ── Visible-lines with invalidation cache ─────────────────────────────
  List<int> _visibleLines() {
    final ctrl = widget.controller;
    // Combine foldedBlocks identity hash + documentVersion for a collision-resistant key
    final key = Object.hash(ctrl.content.documentVersion, ctrl.foldedBlocks.fold<int>(0, (h, v) => h ^ v.hashCode));
    if (_cachedFoldKey == key && _cachedVis != null) return _cachedVis!;

    final total  = ctrl.content.lineCount;
    if (total == 0) {
      _cachedVis = []; _cachedVisIdx = {}; _cachedFoldFree = true;
      _cachedFoldKey = key; return [];
    }

    // ── Fast path: no folds ───────────────────────────────────────────────
    // When there are no folds, vis is the identity sequence [0, 1, ..., n-1].
    // We use a zero-allocation _IdentityList that maps index i → i without
    // any backing array.  Crucially, we reuse the same object as long as the
    // line count hasn't changed, so setVis() in _EBox sees an identical object
    // and skips the structural update entirely on pure-content keystrokes.
    if (ctrl.foldedBlocks.isEmpty) {
      if (_cachedFoldFree && _cachedVis?.length == total) {
        // Same line count, no folds: the identity mapping is still correct.
        // Update the fold key so future checks still short-circuit at the top.
        _cachedFoldKey = key;
        return _cachedVis!;
      }
      _cachedVis      = _IdentityList(total);
      _cachedVisIdx   = const {}; // not used when fold-free
      _cachedFoldFree = true;
      _cachedFoldKey  = key;
      return _cachedVis!;
    }

    // ── Slow path: has active folds ───────────────────────────────────────
    _cachedFoldFree = false;
    final folded = ctrl.foldedBlocks;
    final blocks = ctrl.styles.codeBlocks;
    final foldMap = <int, int>{};
    for (final b in blocks) {
      if (folded.contains(b.startLine) && b.isFoldable) foldMap[b.startLine] = b.endLine;
    }
    final out = <int>[];
    int i = 0;
    while (i < total) {
      out.add(i);
      final end = foldMap[i]; if (end != null) i = end + 1; else i++;
    }
    _cachedVis    = out;
    _cachedVisIdx = { for (int k = 0; k < out.length; k++) out[k]: k };
    _cachedFoldKey = key;
    return out;
  }

  /// O(1) vis-index lookup — identity mapping when fold-free, HashMap otherwise.
  int _visLineIndex(int docLine) {
    _visibleLines(); // ensure cache is warm
    if (_cachedFoldFree) return docLine; // O(1) no map lookup
    return _cachedVisIdx[docLine] ?? -1;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _effectiveTheme = widget.theme ?? QuillThemeDark.build();
    _focus = widget.focusNode ?? FocusNode();
    _blink = AnimationController(vsync: this, duration: Duration(milliseconds: widget.controller.props.cursorBlinkIntervalMs))
      ..addStatusListener((s) {
        if (!mounted) return;
        if (s == AnimationStatus.completed) _blink.reverse();
        if (s == AnimationStatus.dismissed) _blink.forward();
      });
    _scrollbarFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 0.0,
    );
    _focus.addListener(_onFocusChange);
    widget.controller.addListener(_onCtrl);
    widget.controller.scrollResetVersion.addListener(_onScrollReset);
    // Direct notifier updates — zero setState
    _vCtrl.addListener(_onVScroll);
    _hCtrl.addListener(_onHScroll);
    // Zoom changes → recalculate gutter width (setState needed so LayoutBuilder rebuilds)
    _zoomN.addListener(_onZoomChanged);
    _gwN.addListener(_onGwChanged);

    // Pre-build composite listenables (avoids repeated allocation in build)
    _gutterListenable     = Listenable.merge([_gutterScrollY, _hScrollN, _zoomN, _gwN, _wrapOffsetsN, _foldN, _ghostInsertViN, _ghostExtraRowsN, widget.controller]);
    _handleListenable     = Listenable.merge([_cursorTick, _handleTick, _zoomN]);
    _toolbarListenable    = Listenable.merge([_toolbarVisible, _zoomN]);
    _magnifierListenable  = Listenable.merge([_handleTick, _cursorTick]);
    _scrollListenable     = Listenable.merge([widget.controller, _blink, _handleTick]);
    if (widget.autofocus) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showKbd(); });
    // Attach LSP if provided
    if (widget.lspClient != null || widget.lspConfig != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        LspClient? client = widget.lspClient;
        final cfg = widget.lspConfig;
        if (client == null && cfg != null) {
          // Auto-build client from config
          if (cfg is QuillLspStdioConfig) {
            client = await LspStdioClient.start(
              executable:    cfg.executable,
              args:          cfg.args,
              workspacePath: cfg.workspacePath,
              languageId:    cfg.languageId,
              environment:   cfg.environment,
            );
          } else if (cfg is QuillLspSocketConfig) {
            final sc = LspSocketClient(
              serverUrl:     cfg.url,
              workspacePath: cfg.workspacePath,
              languageId:    cfg.languageId,
            );
            await sc.connect();
            client = sc;
          }
        }
        if (!mounted || client == null) return;
        final langId = widget.lspConfig?.languageId
            ?? widget.controller.language.name;
        widget.controller.attachLsp(
          client,
          uri:        widget.fileUri ?? 'file:///untitled.$langId',
          languageId: langId,
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Detect when the virtual keyboard opens/changes height: viewInsets.bottom grows.
    // Usamos jumpTo (instant: true) para que o scroll seja instantâneo a cada frame
    // da animação do teclado — evita que o cursor fique oculto atrás do teclado
    // durante a abertura. O scroll animado causaria defasagem visível porque
    // didChangeDependencies dispara múltiplas vezes enquanto o teclado sobe.
    final kbH = MediaQuery.of(context).viewInsets.bottom;
    if (kbH > _prevKbHeight) {
      _ensureCursorVisible(instant: true);
    }
    _prevKbHeight = kbH;
  }

  @override
  void didUpdateWidget(QuillCodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onCtrl);
      old.controller.scrollResetVersion.removeListener(_onScrollReset);
      widget.controller.addListener(_onCtrl);
      widget.controller.scrollResetVersion.addListener(_onScrollReset);
      // When the controller itself is swapped (e.g. user creates new controller
      // per file), treat it exactly like setText(): reset scroll + gutter.
      _onScrollReset();
    }
    // Se o host mudou o tema externamente (ex: troca de arquivo/linguagem),
    // adota as novas cores/fontes MAS preserva o fontSize atual do usuário,
    // A menos que o próprio tema tenha mudado o fontSize (ex: usuário clicou
    // nos botões + / − de fonte), caso em que adotamos o novo tamanho.
    if (old.theme != widget.theme) {
      final newBase   = widget.theme ?? QuillThemeDark.build();
      final oldBase   = old.theme;
      // Detecta se o fontSize base mudou externamente (botões +/−).
      final baseFsChanged = oldBase != null &&
          (newBase.fontSize - oldBase.fontSize).abs() > 0.5;
      _effectiveTheme = baseFsChanged
          ? newBase                                          // usuário mudou via +/−
          : newBase.copyWith(fontSize: _effectiveTheme.fontSize); // preserva zoom do pinch
      // Sincroniza _zoomN para que _onZoomChanged → _calcGw → _gwN fiquem coerentes.
      if (!baseFsChanged) _zoomN.value = _effectiveTheme.fontSize;
    }
  }

  @override
  void dispose() {
    // ── Step 1: remove all listeners FIRST so no callbacks fire during teardown ──
    widget.controller.removeListener(_onCtrl);
    widget.controller.scrollResetVersion.removeListener(_onScrollReset);
    _focus.removeListener(_onFocusChange);
    _vCtrl.removeListener(_onVScroll);
    _hCtrl.removeListener(_onHScroll);
    _zoomN.removeListener(_onZoomChanged);
    _gwN.removeListener(_onGwChanged);

    // ── Step 2: cancel timers & close IME ──
    _cursorHandleTimer?.cancel();
    _edgeTimer?.cancel();
    _scrollEndTimer?.cancel();
    _scrollbarHideTimer?.cancel();
    _inputConn?.close();
    _inputConn = null;

    // ── Step 3: stop & dispose animation/notifiers ──
    _blink.stop();
    _blink.clearListeners();
    _blink.clearStatusListeners();
    _blink.dispose();
    _scrollbarFade.dispose();
    _cursorTick.dispose();
    _gutterScrollY.dispose();
    _foldN.dispose();
    _hScrollN.dispose();
    _handleTick.dispose();
    _toolbarVisible.dispose();
    _lightbulbVisible.dispose();
    _zoomN.dispose();
    _gwN.dispose();
    _wrapOffsetsN.dispose();
    _ghostInsertViN.dispose();
    _ghostExtraRowsN.dispose();

    // ── Step 4: dispose scroll controllers ──
    _vCtrl.dispose();
    _hCtrl.dispose();

    // ── Step 5: focus & LSP ──
    if (widget.focusNode == null) _focus.dispose();
    if (widget.lspClient != null || widget.lspConfig != null) widget.controller.detachLsp();

    super.dispose();
  }

  void _showKbd() {
    if (widget.controller.props.readOnly) {
      // In readOnly: allow focus (for blink + key events) but never open IME.
      _focus.requestFocus();
      return;
    }
    _focus.requestFocus();
    // Reattach if the connection was closed (e.g. after dismissing keyboard)
    if (_inputConn == null || !_inputConn!.attached) {
      _inputConn = TextInput.attach(this, const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
      ));
    }
    // Tell the IME the current editing state so Android enables the
    // clipboard paste button on the keyboard toolbar.
    _inputConn!.setEditingState(_imeInit);
    _inputConn!.show();
  }

  // ── Scroll listeners: hide all overlays + sync gutter ────────────────
  /// Called once when setText() is called on the controller (or when the
  /// controller is replaced). Resets scroll to top, clears cached fold state,
  /// and forces a setState so the LayoutBuilder rebuilds with the new lineCount
  /// → _calcGw() recalculates gutter digit-width immediately.
  void _onScrollReset() {
    if (!mounted) return;
    _cachedVis = null; // fold cache is stale for the new content
    _activeBracketPair = null; // stale pair highlight must be cleared for the new file

    // Attempt immediate scroll reset — works if the scroll controller is
    // already attached. This covers the common case where we are NOT in the
    // middle of a layout pass (e.g. called from a button tap handler).
    if (_vCtrl.hasClients) _vCtrl.jumpTo(0);
    if (_hCtrl.hasClients) _hCtrl.jumpTo(0);

    // Deferred fallback: ensures scroll is at 0 even if the first jumpTo
    // fired before the new content's scroll extent was applied by performLayout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_vCtrl.hasClients) _vCtrl.jumpTo(0);
      if (_hCtrl.hasClients) _hCtrl.jumpTo(0);
    });

    // Recalcula _gw imediatamente com o novo lineCount do arquivo/controller.
    // Atualiza _gwN para que o _EBox e o GutterPainter repintem com a nova
    // largura antes mesmo do LayoutBuilder rodar — evita o frame com números
    // cortados quando o arquivo novo tem mais dígitos que o anterior.
    final newGw = _calcGw();
    if ((newGw - _gw).abs() > 0.5) {
      _gwN.value = newGw;
    }
    setState(() { _gw = newGw; });
  }

  void _onVScroll() {
    if (!mounted) return;
    _gutterScrollY.value = _vCtrl.hasClients ? _vCtrl.offset : 0;
    _lightbulbVisible.value = false;
    if (_symbolPanelVisible) { _symbolPanelVisible = false; _cursorTick.value++; }
    _onScrollActive();
    if (widget.controller.isCompletionVisible) {
      widget.controller.hideCompletion();
    }
    // Inform the analyze manager which lines are now visible so it can
    // prioritize tokenizing them first for progressive highlighting.
    if (_vCtrl.hasClients && _lh > 0) {
      final sY  = _vCtrl.offset;
      final lc  = widget.controller.content.lineCount.clamp(1, 1 << 30);
      final fl  = (sY / _lh).floor().clamp(0, lc - 1);
      final ll  = ((sY + _vpSize.height) / _lh).ceil().clamp(0, lc - 1);
      widget.controller.notifyVisibleRange(fl, ll);
    }
  }

  void _onHScroll() {
    if (!mounted) return;
    _hScrollN.value = _hCtrl.hasClients ? _hCtrl.offset : 0;
    _onScrollActive();
    if (widget.controller.isCompletionVisible) {
      widget.controller.hideCompletion();
    }
  }

  /// Called on every scroll event. Hides handles + toolbar immediately,
  /// then schedules them to reappear 400 ms after scrolling stops.
  void _onScrollActive() {
    // Hide handles and toolbar while scrolling
    if (_cursorHandleVisible || _selHandlesVisible || _toolbarVisible.value) {
      if (!_handlesHiddenByScroll) {
        _handlesHiddenByScroll = _cursorHandleVisible || _selHandlesVisible;
        _toolbarHiddenByScroll = _toolbarVisible.value;
      }
      _cursorHandleVisible  = false;
      _selHandlesVisible    = false;
      _toolbarVisible.value = false;
      _handleTick.value++;
    }
    // Reset the idle timer on every scroll event
    _scrollEndTimer?.cancel();
    _scrollEndTimer = Timer(const Duration(milliseconds: 400), _onScrollEnded);
    // Show scrollbars and reset the auto-hide timer
    _onScrollbarActivity();
  }

  void _onScrollbarActivity() {
    if (!widget.controller.props.showScrollbars) return;
    final secs = _effectiveTheme.scrollbar.autoHideSeconds;
    _scrollbarFade.forward();
    _scrollbarHideTimer?.cancel();
    if (secs > 0) {
      _scrollbarHideTimer = Timer(
        Duration(milliseconds: (secs * 1000).round()),
        () { if (mounted) _scrollbarFade.reverse(); },
      );
    }
  }

  /// Called 400 ms after the last scroll event. Restores handles + toolbar.
  void _onScrollEnded() {
    if (!mounted) return;
    final ctrl = widget.controller;
    // Restore toolbar if selection is still active
    if (_toolbarHiddenByScroll && ctrl.cursor.hasSelection) {
      _toolbarVisible.value = true;
    }
    // Restore selection handles if selection is still active
    if (_handlesHiddenByScroll && ctrl.cursor.hasSelection) {
      _selHandlesVisible = true;
      _handleTick.value++;
    }
    _handlesHiddenByScroll = false;
    _toolbarHiddenByScroll = false;
  }

  /// Font size changed in _EBox — sync state theme + gutter width.
  void _onZoomChanged() {
    final newFs = _zoomN.value;
    // Guard: only update _effectiveTheme if fontSize actually changed.
    // Without this, copyWith() creates a new object on every call even when
    // the value is identical — causing updateRenderObject to see a "new" theme
    // object and call _lc.clear() + markNeedsLayout() a second time.
    if (newFs > 0 && (newFs - _effectiveTheme.fontSize).abs() > 0.1) {
      _effectiveTheme = _effectiveTheme.copyWith(fontSize: newFs);
      // Only recompute gutter width when fontSize changes — not every zoom callback.
      final newGw = _calcGw();
      if ((newGw - _gwN.value).abs() > 0.5) _gwN.value = newGw;
    }
  }

  /// _gw notifier changed — sync the cached _gw field used by hit-test helpers.
  /// Throttled: only one setState per frame regardless of how many PointerMoveEvents
  /// arrive during a pinch gesture (can be 60-120 per frame on some devices).
  void _onGwChanged() {
    if (!mounted || _gwSetStatePending) return;
    _gwSetStatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gwSetStatePending = false;
      if (mounted) setState(() { _gw = _gwN.value; });
    });
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus) _blink.forward();
    else { _blink.stop(); _blink.value = 1.0; widget.controller.hideCompletion(); }
    _cursorTick.value++;
  }

  void _onCtrl() {
    if (!mounted) return;
    _cachedVis = null; // invalidate fold cache on any change
    _cursorTick.value++;
    final ctrl = widget.controller;
    // Sync blink interval when props change
    final blinkDur = Duration(milliseconds: ctrl.props.cursorBlinkIntervalMs);
    if (_blink.duration != blinkDur) _blink.duration = blinkDur;
    // Recalculate gutter width whenever props change (showLineNumbers,
    // showFoldArrows, etc.). Se a largura mudou, aciona setState para que
    // o LayoutBuilder reconstrua imediatamente — sem precisar de pinça.
    final newGw = _calcGw();
    if ((newGw - _gw).abs() > 0.5) {
      _gwN.value = newGw;
      setState(() { _gw = newGw; });
    }
    // Only fire onChanged when the text actually changed (not style updates)
    final newVer = ctrl.content.documentVersion;
    if (newVer != _lastContentVersion) {
      _lastContentVersion = newVer;
      widget.onChanged?.call(ctrl.text);
      if (_lspHoverVisible) setState(() => _lspHoverVisible = false);
      // Dismiss signature help when content changes via non-trigger edits
      // (e.g. backspace after `(` — the ) handler below covers the `)` case)
      // Recalculate bracket pair + block depth so deleting '}' immediately
      // clears the pair highlight without waiting for the next cursor move.
      _updateLightbulbAndSymbol();
    }
    _ensureCursorVisible();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Coordinate helpers
  // ═══════════════════════════════════════════════════════════════════════
  static const double _codePad = 6.0; // matches _EBox._codePad

  CharPosition _localToChar(Offset local) {
    final ctrl = widget.controller;
    final sY   = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
    final sX   = _hCtrl.hasClients ? _hCtrl.offset : 0.0;
    final vis  = _visibleLines();
    // coords are already in screen space — lh/cw already reflect current fontSize
    final docY = local.dy + sY;
    // When wordWrap is active, the _EBox has _wrapOffsets but we can't
    // access them from the state; use lineHeight which is uniform per visual
    // row (good enough for hit-testing since each row is still ≥1 lh tall).
    final visI = (docY / _lh).floor().clamp(0, math.max(0, vis.length - 1)).toInt();
    final line = vis.isEmpty ? 0 : vis[visI];
    final docX = (local.dx - _gw - _codePad + sX).clamp(0.0, double.infinity);
    final col  = (docX / _cw).round().clamp(0, ctrl.content.getLineLength(line));
    return CharPosition(line, col);
  }

  CharPosition _globalToChar(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return _localToChar(box?.globalToLocal(global) ?? global);
  }

  Offset _charToLocal(CharPosition pos) {
    final sY  = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
    final sX  = _hCtrl.hasClients ? _hCtrl.offset : 0.0;
    final vi  = _visLineIndex(pos.line);
    final eff = vi >= 0 ? vi : pos.line;
    return Offset(_gw + _codePad + pos.column * _cw - sX, (eff + 1) * _lh - sY);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Ensure cursor visible after edit
  // ═══════════════════════════════════════════════════════════════════════

  /// Garante que o cursor esteja visível no viewport.
  /// Quando [instant] é true, usa jumpTo (sem animação) — necessário durante
  /// a animação de abertura do teclado para resposta frame-a-frame.
  ///
  /// IMPORTANTE — dupla subtração:
  /// O LayoutBuilder já recebe bc.maxHeight SEM a área do teclado quando
  /// Scaffold usa resizeToAvoidBottomInset:true (padrão). Portanto
  /// vp.viewportDimension já exclui o teclado e NÃO deve ter kbHeight
  /// subtraído novamente.
  /// Para o caso resizeToAvoidBottomInset:false, o viewport NÃO shrink e
  /// aí sim precisamos subtrair — detectamos isso comparando com
  /// _noKbViewportDimension (baseline sem teclado).
  void _ensureCursorVisible({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vCtrl.hasClients) return;
      final kbHeight = MediaQuery.of(context).viewInsets.bottom;
      final vp   = _vCtrl.position;
      final line = widget.controller.cursor.line;
      final col  = widget.controller.cursor.column;
      final curY = line * _lh;

      // Atualiza baseline quando o teclado está fechado
      if (kbHeight < 10) _noKbViewportDimension = vp.viewportDimension;

      // Detecta se o Scaffold já encolheu o viewport pelo teclado.
      // Se sim, vp.viewportDimension já é a altura visível correta — não subtrai.
      // Se não (resizeToAvoidBottomInset:false), subtrai kbHeight manualmente.
      final scaffoldResized = _noKbViewportDimension > 0 &&
          (_noKbViewportDimension - vp.viewportDimension) >= kbHeight * 0.6;
      final visH = scaffoldResized
          ? vp.viewportDimension
          : math.max(40.0, vp.viewportDimension - kbHeight);

      if (curY < vp.pixels) {
        final target = curY.clamp(0.0, vp.maxScrollExtent);
        if (instant) {
          _vCtrl.jumpTo(target);
        } else {
          _vCtrl.animateTo(target,
              duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
        }
      } else if (curY + _lh > vp.pixels + visH) {
        final target = (curY + _lh - visH).clamp(0.0, vp.maxScrollExtent);
        if (instant) {
          _vCtrl.jumpTo(target);
        } else {
          _vCtrl.animateTo(target,
              duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
        }
      }
      if (_hCtrl.hasClients) {
        final hp  = _hCtrl.position;
        final curX = col * _cw;
        final gutterW = widget.controller.props.fixedLineNumbers ? _gw + _codePad : _codePad;
        const rightMargin = 8.0 * 8;
        final visLeft  = hp.pixels;
        final minimapW = widget.controller.props.showMinimap ? _minimapWidth : 0.0;
        final visRight = hp.pixels + hp.viewportDimension - gutterW - minimapW;
        final curRight = curX + rightMargin;
        if (curX < visLeft + gutterW) {
          _hCtrl.jumpTo((curX - gutterW - _cw).clamp(0.0, hp.maxScrollExtent));
        } else if (curRight > visRight) {
          _hCtrl.jumpTo((curRight - (hp.viewportDimension - gutterW - minimapW)).clamp(0.0, hp.maxScrollExtent));
        }
      }
    });
  }

  /// Chamado quando o usuário toca numa linha para abrir o teclado.
  /// Agenda verificações extras para cobrir o momento em que o teclado
  /// termina de abrir (~250-400ms) — o didChangeDependencies cobre cada frame
  /// da animação, e os Timers garantem o frame final estabilizado.
  void _ensureCursorVisibleAfterTap() {
    _ensureCursorVisible(instant: true);
    // Teclado Android leva ~250-350ms para abrir completamente.
    // Verificamos em 300ms e 500ms para garantir que o cursor fique visível
    // mesmo se algum frame intermediário for perdido.
    Timer(const Duration(milliseconds: 300), () {
      if (mounted) _ensureCursorVisible(instant: true);
    });
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) _ensureCursorVisible(instant: true);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Handle helpers
  // ═══════════════════════════════════════════════════════════════════════
  void _showCursorHandle() {
    _cursorHandleTimer?.cancel();
    _cursorHandleVisible = true; _selHandlesVisible = false;
    _toolbarVisible.value = false;
    _handleTick.value++;
    _cursorHandleTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_drag != 'cursor') { _cursorHandleVisible = false; _handleTick.value++; }
    });
  }

  void _showSelHandles() {
    _cursorHandleTimer?.cancel();
    _cursorHandleVisible = false; _selHandlesVisible = true;
    _handleTick.value++;
    _toolbarVisible.value = true;
  }

  void _hideAllHandles() {
    _cursorHandleTimer?.cancel();
    _cursorHandleVisible = false; _selHandlesVisible = false;
    _toolbarVisible.value = false;
    _handleTick.value++;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Lightbulb + Symbol info
  // ═══════════════════════════════════════════════════════════════════════

  void _updateLightbulbAndSymbol() {
    final ctrl = widget.controller;
    final pos  = ctrl.cursor.position;

    // ── Symbol info ────────────────────────────────────────────────────
    final sym = SymbolAnalyzer.symbolInfoAt(ctrl.content, pos);
    final wasVisible = _symbolPanelVisible;
    _hoveredSymbol      = sym;
    _symbolPanelVisible = sym != null;

    // ── Bracket pair ───────────────────────────────────────────────────
    _activeBracketPair = BracketMatcher.findPair(ctrl.content, pos);
    // Guard: if the open bracket is the startLine of a known foldable
    // codeblock, the close MUST match that block's endLine.
    // Without this, deleting '}' causes _findForward to latch onto
    // a different '}' further in the file — the "ghost" pair highlight.
    if (_activeBracketPair != null) {
      final bp = _activeBracketPair!;
      for (final b in ctrl.styles.codeBlocks) {
        if (!b.isFoldable) continue;
        if (b.startLine == bp.open.line) {
          // open is the head of a codeblock — close must be the block's endLine
          if (bp.close.line != b.endLine) _activeBracketPair = null;
          break;
        }
        if (b.endLine == bp.close.line) {
          // close is the tail of a codeblock — open must be the block's startLine
          if (bp.open.line != b.startLine) _activeBracketPair = null;
          break;
        }
      }
    }

    // ── Active block depth ─────────────────────────────────────────────
    // Count how many codeblocks contain the cursor line
    int depth = 0;
    for (final b in ctrl.styles.codeBlocks) {
      if (pos.line > b.startLine && pos.line <= b.endLine) depth++;
    }
    _activeBlockDepth = depth;

    // ── Lightbulb ──────────────────────────────────────────────────────
    bool showBulb = false;
    if (pos.line < ctrl.content.lineCount) {
      final line = ctrl.content.getLineText(pos.line);
      showBulb = line.trim().isNotEmpty || ctrl.cursor.hasSelection;
    }
    _lightbulbVisible.value = showBulb && ctrl.props.showLightbulb;
    if (_symbolPanelVisible || wasVisible) _cursorTick.value++;
  }

  /// Fetch and show LSP hover documentation at the cursor position.
  /// Only fires if an LSP client is attached. Dismissed on next tap/edit.
  void _fetchLspHover() {
    final ctrl = widget.controller;
    if (!ctrl.hasLsp) return;
    final pos = ctrl.cursor.position;
    ctrl.lspHoverAt(pos).then((hover) {
      if (!mounted || hover == null || hover.contents.trim().isEmpty) return;
      setState(() {
        _lspHoverText    = hover.contents.trim();
        _lspHoverVisible = true;
      });
    });
  }

  /// Fetch and show LSP signature help at the cursor position.
  /// Called automatically when user types `(` or `,`.
  void _triggerSignatureHelp({String? triggerChar}) {
    final ctrl = widget.controller;
    if (!ctrl.hasLsp) return;
    final pos = ctrl.cursor.position;
    ctrl.lspSignatureHelpAt(pos, triggerChar: triggerChar).then((sig) {
      if (!mounted) return;
      if (sig == null || sig.label.isEmpty) {
        if (_lspSigVisible) setState(() => _lspSigVisible = false);
        return;
      }
      setState(() {
        _lspSigHelp    = sig;
        _lspSigVisible = true;
      });
    });
  }

  Future<void> _onActionSelected(CodeAction action) async {
    if (!mounted) return;
    final ctrl = widget.controller;
    _lightbulbVisible.value = false;
    _symbolPanelVisible = false;

    if (action.kind == CodeActionKind.navigate) {
      // Try LSP definition first, fall back to local regex
      final pos = ctrl.cursor.position;
      final lspLocs = await ctrl.lspDefinitionAt(pos);
      if (!mounted) return;
      if (lspLocs.isNotEmpty) {
        final loc = lspLocs.first;
        final currentUri = widget.fileUri ?? '';
        if (loc.uri == currentUri || currentUri.isEmpty) {
          // Same file — scroll to definition
          ctrl.setCursor(loc.range.start);
          _scrollToLine(loc.range.start.line);
          _cursorTick.value++;
        } else {
          // Different file — notify host app
          widget.onNavigateToFile?.call(
            loc.uri, loc.range.start.line, loc.range.start.column);
        }
      } else {
        // Local search fallback
        final word = SymbolAnalyzer.wordAt(ctrl.content, pos);
        if (word != null) {
          final defLine = SymbolAnalyzer.findDefinitionLine(ctrl.content, word);
          if (defLine >= 0) {
            ctrl.setCursor(CharPosition(defLine, 0));
            _scrollToLine(defLine);
            _cursorTick.value++;
          }
        }
      }
      return;
    }

    if (action.kind == CodeActionKind.snippet) {
      final prefix   = action.title.replaceFirst('⚡ ', '');
      final snippets = VsCodeSnippets.forLanguage(ctrl.language.name);
      final snip     = snippets.where((s) => s.prefix == prefix).firstOrNull;
      if (snip != null) { ctrl.insertSnippet(snip.body); _cursorTick.value++; }
      return;
    }

    if (action.edits.isNotEmpty) {
      for (final edit in action.edits) {
        ctrl.content.delete(edit.range);
        ctrl.content.insert(edit.range.start, edit.newText);
      }
      ctrl.setCursor(action.edits.last.range.start);
      _cursorTick.value++;
      _bump();
    }
    action.callback?.call();
  }

  void _scrollToLine(int targetLine) {
    if (!_vCtrl.hasClients) return;
    final y = (targetLine * _lh - _vpSize.height / 3)
        .clamp(0.0, _vCtrl.position.maxScrollExtent);
    _vCtrl.animateTo(y,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }


  // ═══════════════════════════════════════════════════════════════════════
  // Edge scroll
  // ═══════════════════════════════════════════════════════════════════════
  void _edgeScroll(Offset local) {
    const z = 52.0, s = 16.0;
    if (_vCtrl.hasClients) {
      final p = _vCtrl.position;
      if (local.dy < z) _vCtrl.jumpTo((p.pixels - s).clamp(0.0, p.maxScrollExtent));
      else if (local.dy > _vpSize.height - z) _vCtrl.jumpTo((p.pixels + s).clamp(0.0, p.maxScrollExtent));
    }
    if (_hCtrl.hasClients) {
      final p = _hCtrl.position;
      if (local.dx < _gw + z) _hCtrl.jumpTo((p.pixels - s).clamp(0.0, p.maxScrollExtent));
      else if (local.dx > _vpSize.width - z) _hCtrl.jumpTo((p.pixels + s).clamp(0.0, p.maxScrollExtent));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Gestures
  // ═══════════════════════════════════════════════════════════════════════
  // Manual double-tap state — avoids Flutter's 300ms wait
  DateTime?  _lastTapTime;
  Offset     _lastTapPos = Offset.zero;

  void _onTapDown(TapDownDetails d) {
    final now   = DateTime.now();
    final loc   = d.localPosition;

    // ── Guard: if a handle is active and tap is near it, let the handle's
    //    GestureDetector win — do NOT reset cursor/selection. ─────────────
    if (_isNearHandle(loc)) return;

    // ── Double-tap detection ──────────────────────────────────────────
    final isDoubleTap = _lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 350) &&
        (_lastTapPos - loc).distance < 30.0;

    _lastTapTime = now;
    _lastTapPos  = loc;
    _lastTapLx   = loc.dx;
    _lastTapLy   = loc.dy;

    if (isDoubleTap) {
      _onDoubleTap();
      _lastTapTime = null;
      return;
    }

    widget.controller.hideCompletion();
    _toolbarVisible.value = false;

    // Tap always dismisses ghost text (accept = Tab/Enter, cancel = tap elsewhere).
    if (widget.controller.ghostText.isVisible) {
      widget.controller.ghostText.dismiss();
    }

    // Color swatch tap: toggle inline color picker
    {
      final cm = _colorSwatchAt(loc);
      if (cm != null) {
        final sY = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
        final vis = _visibleLines();
        final vi  = ((loc.dy + sY) / _lh).floor().clamp(0, math.max(0, vis.length - 1)).toInt();
        final docLine = vi < vis.length ? vis[vi] : _colorPickerLine;
        setState(() {
          if (_colorPickerLine == docLine && _colorPickerMatch?.start == cm.start) {
            _colorPickerAnchor = null; _colorPickerMatch = null; _colorPickerLine = -1;
          } else {
            _colorPickerAnchor = loc; _colorPickerMatch = cm; _colorPickerLine = docLine;
          }
        });
        return;
      }
    }

    // Gutter: fold arrow zone (right 22px) or breakpoint area
    if (loc.dx < _gw) {
      if (loc.dx > _gw - 22) _tryFold(loc);
      return;
    }

    _showKbd();

    widget.controller.setCursor(_localToChar(loc));
    _selHandlesVisible = false;
    _handleTick.value++;
    _cursorTick.value++;
    _showCursorHandle();
    _updateLightbulbAndSymbol();
    // Garante scroll instantâneo caso o teclado virtual vá cobrir a linha tocada.
    // didChangeDependencies já cobre cada frame da animação do teclado, mas
    // _ensureCursorVisibleAfterTap agenda checks extras no frame seguinte para
    // capturar o momento em que o teclado atinge a altura final.
    _ensureCursorVisibleAfterTap();
  }

  /// Returns true if [tap] is within the hit-zone of any currently visible handle.
  bool _isNearHandle(Offset tap) {
    // Native Material handles render BELOW the anchor point.
    // Handle body is ~22px wide, ~44px tall (line below cursor).
    // We use an enlarged hit rect that covers both above and below the anchor.
    // Keep hit zone tight: only block taps directly on the handle thumb.
    // Taps 1-2 chars away should move the cursor, not get swallowed.
    const hitW = 16.0;      // horizontal half-width (was 36)
    const hitHAbove = 6.0;  // px above anchor (was 10)
    const hitHBelow = 36.0; // px below anchor — handle body (was 50)
    final ctrl = widget.controller;

    bool nearAnchor(Offset anchor) {
      return tap.dx >= anchor.dx - hitW &&
             tap.dx <= anchor.dx + hitW &&
             tap.dy >= anchor.dy - hitHAbove &&
             tap.dy <= anchor.dy + hitHBelow;
    }

    if (!ctrl.cursor.hasSelection && (_cursorHandleVisible || _drag == 'cursor')) {
      if (nearAnchor(_charToLocal(ctrl.cursor.position))) return true;
    }
    if (ctrl.cursor.hasSelection && (_selHandlesVisible || _drag != null)) {
      if (nearAnchor(_charToLocal(ctrl.cursor.selection.start))) return true;
      if (nearAnchor(_charToLocal(ctrl.cursor.selection.end))) return true;
    }
    return false;
  }

  void _tryFold(Offset local) {
    final sY  = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
    final vis = _visibleLines();
    final vi  = ((local.dy + sY) / _lh).floor().clamp(0, math.max(0, vis.length - 1)).toInt();
    if (vis.isEmpty) return;
    final line = vis[vi];
    for (final b in widget.controller.styles.codeBlocks) {
      if (b.startLine == line && b.isFoldable) {
        _cachedVis = null;   // invalidate before toggleFold fires notifyListeners
        _foldN.value++;      // force gutter repaint regardless of listener order
        widget.controller.toggleFold(line);
        _cursorTick.value++;
        return;
      }
    }
  }

  void _onDoubleTap() {
    if (_lastTapLx < _gw) {
      final sY  = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
      final vis = _visibleLines();
      final vi  = ((_lastTapLy + sY) / _lh).floor().clamp(0, math.max(0, vis.length - 1)).toInt();
      if (vis.isNotEmpty) widget.controller.toggleBreakpoint(vis[vi]);
      _cursorTick.value++; return;
    }
    widget.controller.selectWord(); _cursorTick.value++; _showSelHandles();
    _updateLightbulbAndSymbol();
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (d.localPosition.dx < _gw) return;
    _showKbd();
    final pos = _localToChar(d.localPosition);

    // ── If user presses on already-selected text: show toolbar, don't clear ──
    final ctrl = widget.controller;
    if (ctrl.cursor.hasSelection) {
      final sel = ctrl.cursor.selection;
      // Check if the long-press landed inside the existing selection
      if (_positionIsInsideSelection(pos, sel)) {
        HapticFeedback.selectionClick();
        _showSelHandles();
        return;
      }
    }

    // Dismiss LSP hover and signature panels on any tap
    if (_lspHoverVisible) setState(() => _lspHoverVisible = false);
    if (_lspSigVisible) setState(() => _lspSigVisible = false);
    ctrl.setCursor(pos);
    // On empty line: don't select word, just show toolbar at cursor
    final lineText = ctrl.content.getLineText(pos.line);
    if (lineText.trim().isEmpty) {
      HapticFeedback.selectionClick();
      _cursorTick.value++;
      _toolbarVisible.value = true;
      return;
    }
    ctrl.selectWord();
    HapticFeedback.selectionClick();
    _cursorTick.value++; _showSelHandles();
  }

  /// Returns true if [pos] falls within (or on the boundary of) [sel].
  bool _positionIsInsideSelection(CharPosition pos, EditorRange sel) {
    final start = sel.start;
    final end   = sel.end;
    if (pos.line < start.line || pos.line > end.line) return false;
    if (pos.line == start.line && pos.column < start.column) return false;
    if (pos.line == end.line   && pos.column > end.column)   return false;
    return true;
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (d.localPosition.dx < _gw) return;
    widget.controller.setCursor(_localToChar(d.localPosition), select: true);
    _edgeScroll(d.localPosition); _cursorTick.value++;
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _edgeTimer?.cancel();
    if (widget.controller.cursor.hasSelection) _showSelHandles();
    _updateLightbulbAndSymbol();
    _fetchLspHover();
  }

  // ── Handle drag — global→local conversion ─────────────────────────────
  Offset _g2l(Offset g) => (context.findRenderObject() as RenderBox?)?.globalToLocal(g) ?? g;

  void _cDragStart(DragStartDetails d) {
    _drag = 'cursor'; _cursorHandleTimer?.cancel();
    _magnifierPos = _g2l(d.globalPosition);
    _handleTick.value++;
  }
  void _cDragUpdate(DragUpdateDetails d) {
    final local = _g2l(d.globalPosition);
    widget.controller.setCursor(_globalToChar(d.globalPosition));
    _edgeScroll(local);
    _magnifierPos = local;
    _cursorTick.value++;
  }
  void _cDragEnd(DragEndDetails _) {
    _drag = null; _edgeTimer?.cancel();
    _magnifierPos = null;
    _showCursorHandle();
  }

  void _ssDragStart(DragStartDetails _) => _drag = 'selStart';
  void _ssDragUpdate(DragUpdateDetails d) {
    final pos = _globalToChar(d.globalPosition);
    final end = widget.controller.cursor.selection.end;
    if (pos < end) { widget.controller.cursor.setSelection(pos, end); _cursorTick.value++; }
    _edgeScroll(_g2l(d.globalPosition));
  }
  void _ssDragEnd(DragEndDetails _) { _drag = null; _edgeTimer?.cancel(); _showSelHandles(); }

  void _seDragStart(DragStartDetails _) => _drag = 'selEnd';
  void _seDragUpdate(DragUpdateDetails d) {
    final pos   = _globalToChar(d.globalPosition);
    final start = widget.controller.cursor.selection.start;
    if (pos > start) { widget.controller.cursor.setSelection(start, pos); _cursorTick.value++; }
    _edgeScroll(_g2l(d.globalPosition));
  }
  void _seDragEnd(DragEndDetails _) { _drag = null; _edgeTimer?.cancel(); _showSelHandles(); }

  // ═══════════════════════════════════════════════════════════════════════
  // Keyboard
  // ═══════════════════════════════════════════════════════════════════════
  KeyEventResult _onKey(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final ctrl    = widget.controller;
    final key     = ev.logicalKey;
    final isCtrl  = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt   = HardwareKeyboard.instance.isAltPressed;
    _hideAllHandles();
    if (key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown &&
        key != LogicalKeyboardKey.enter && key != LogicalKeyboardKey.tab)
      ctrl.hideCompletion();

    // ── Ctrl / Cmd shortcuts (VSCode-compatible) ──────────────────────
    if (isCtrl) {
      switch (key) {
        // ── Undo / Redo ─────────────────────────────────────────────
        case LogicalKeyboardKey.keyZ:
          isShift ? ctrl.redo() : ctrl.undo(); _bump(); return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY:
          ctrl.redo(); _bump(); return KeyEventResult.handled;

        // ── Clipboard ───────────────────────────────────────────────
        case LogicalKeyboardKey.keyA:
          ctrl.selectAll(); _bump(); return KeyEventResult.handled;
        case LogicalKeyboardKey.keyC:
          final t = ctrl.copyText(); if (t != null) Clipboard.setData(ClipboardData(text: t));
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyX:
          final t = ctrl.cutText(); if (t != null) Clipboard.setData(ClipboardData(text: t));
          _bump(); return KeyEventResult.handled;
        case LogicalKeyboardKey.keyV:
          Clipboard.getData('text/plain').then((d) {
            if (!mounted || d?.text == null) return;
            ctrl.pasteText(d!.text!); _bump();
          });
          return KeyEventResult.handled;

        // ── File operations ─────────────────────────────────────────
        case LogicalKeyboardKey.keyS:
          // Format on save if enabled
          if (ctrl.props.formatOnSave) {
            final formatted = DartFormatter.formatHeuristic(ctrl.text);
            if (formatted != ctrl.text) ctrl.setText(formatted);
          }
          widget.onSave?.call(); return KeyEventResult.handled;

        // ── Search ──────────────────────────────────────────────────
        case LogicalKeyboardKey.keyF:
          setState(() => _searchVisible = !_searchVisible); return KeyEventResult.handled;

        // ── Command Palette (Ctrl+Shift+P) ──────────────────────────
        case LogicalKeyboardKey.keyP:
          if (isShift) {
            QuillActionsMenu.show(context, ctrl, widget.theme ?? QuillThemeDark.build());
            return KeyEventResult.handled;
          }
          break;

        // ── VSCode: Select line (Ctrl+L) ────────────────────────────
        case LogicalKeyboardKey.keyL:
          ctrl.selectLine(); _bump(); _showSelHandles(); return KeyEventResult.handled;

        // ── VSCode: Duplicate line / selection down (Ctrl+D selects next occurrence
        //    in VSCode; here we map it to select-line for usability on mobile) ──
        case LogicalKeyboardKey.keyD:
          ctrl.selectLine(); _bump(); return KeyEventResult.handled;

        // ── VSCode: Delete line (Ctrl+Shift+K) ─────────────────────
        case LogicalKeyboardKey.keyK:
          if (isShift) { _deleteLine(); _bump(); return KeyEventResult.handled; }
          break;

        // ── VSCode: Toggle comment (Ctrl+/) ─────────────────────────
        case LogicalKeyboardKey.slash:
          _toggleComment(); _bump(); return KeyEventResult.handled;

        // ── VSCode: Indent / outdent (Ctrl+] / Ctrl+[) ──────────────
        case LogicalKeyboardKey.bracketRight:
          _doIndent(); _bump(); return KeyEventResult.handled;
        case LogicalKeyboardKey.bracketLeft:
          _doUnindent(); _bump(); return KeyEventResult.handled;

        // ── VSCode: Move cursor to line start/end (Ctrl+Home/End) ────
        case LogicalKeyboardKey.home:
          ctrl.cursor.moveTo(const CharPosition(0, 0));
          ctrl.setCursor(const CharPosition(0, 0), select: isShift);
          _bump(); return KeyEventResult.handled;
        case LogicalKeyboardKey.end:
          final last = ctrl.content.lineCount - 1;
          final lastCol = ctrl.content.getLineLength(last);
          ctrl.cursor.moveTo(CharPosition(last, lastCol));
          ctrl.setCursor(CharPosition(last, lastCol), select: isShift);
          _bump(); return KeyEventResult.handled;

        // ── VSCode: Duplicate line down (Ctrl+Shift+D) ───────────────
        case LogicalKeyboardKey.keyP:
          if (isShift) { _doDuplicateLineDown(); _bump(); return KeyEventResult.handled; }
          break;

        // ── VSCode: Join lines (Ctrl+J — compact version) ────────────
        case LogicalKeyboardKey.keyJ:
          _joinLines(); _bump(); return KeyEventResult.handled;

        // ── VSCode: Go to line beginning (Ctrl+G placeholder — no dialog on mobile) ──
        case LogicalKeyboardKey.keyG:
          return KeyEventResult.handled; // swallow, could open go-to-line UI later

        default: break;
      }
    }

    // ── Alt shortcuts (VSCode: move lines up/down) ─────────────────────
    if (isAlt && !isCtrl) {
      switch (key) {
        // Alt+Up — move line(s) up
        case LogicalKeyboardKey.arrowUp:
          if (ctrl.cursor.hasSelection) _moveLinesUp();
          else _moveCurrentLineUp();
          _bump(); return KeyEventResult.handled;
        // Alt+Down — move line(s) down
        case LogicalKeyboardKey.arrowDown:
          if (ctrl.cursor.hasSelection) _moveLinesDown();
          else _moveCurrentLineDown();
          _bump(); return KeyEventResult.handled;
        // Alt+Shift+Up — duplicate line above (VSCode: Ctrl+Shift+Alt+Up)
        case LogicalKeyboardKey.arrowLeft:
          ctrl.cursor.moveLeft(select: isShift, byWord: true);
          ctrl.setCursor(ctrl.cursor.position, select: isShift);
          _bump(); return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          ctrl.cursor.moveRight(select: isShift, byWord: true);
          ctrl.setCursor(ctrl.cursor.position, select: isShift);
          _bump(); return KeyEventResult.handled;
        default: break;
      }
    }

    // ── Completion navigation ──────────────────────────────────────────
    if (ctrl.isCompletionVisible) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _completionIdx = (_completionIdx - 1).clamp(0, ctrl.completionItems.length - 1);
        ctrl.resolveCompletionItem(_completionIdx); // lazy-resolve on navigation
        _bump(); return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _completionIdx = (_completionIdx + 1).clamp(0, ctrl.completionItems.length - 1);
        ctrl.resolveCompletionItem(_completionIdx); // lazy-resolve on navigation
        _bump(); return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        if (ctrl.completionItems.isNotEmpty) { ctrl.selectCompletionItem(ctrl.completionItems[_completionIdx]); _bump(); return KeyEventResult.handled; }
      }
      if (key == LogicalKeyboardKey.escape) { ctrl.hideCompletion(); _bump(); return KeyEventResult.handled; }
    }

    // ── Arrow / navigation keys ────────────────────────────────────────
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:  ctrl.cursor.moveLeft(select: isShift, byWord: isAlt);  ctrl.setCursor(ctrl.cursor.position, select: isShift); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight: ctrl.cursor.moveRight(select: isShift, byWord: isAlt); ctrl.setCursor(ctrl.cursor.position, select: isShift); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:    ctrl.cursor.moveUp(select: isShift);    ctrl.setCursor(ctrl.cursor.position, select: isShift); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:  ctrl.cursor.moveDown(select: isShift);  ctrl.setCursor(ctrl.cursor.position, select: isShift); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.home: ctrl.cursor.moveToLineStart(select: isShift); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.end:  ctrl.cursor.moveToLineEnd(select: isShift);   _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        // VSCode: Ctrl+PageUp = scroll one page up
        if (_vCtrl.hasClients) {
          final p = _vCtrl.position;
          _vCtrl.jumpTo((p.pixels - p.viewportDimension).clamp(0.0, p.maxScrollExtent));
        }
        _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        if (_vCtrl.hasClients) {
          final p = _vCtrl.position;
          _vCtrl.jumpTo((p.pixels + p.viewportDimension).clamp(0.0, p.maxScrollExtent));
        }
        _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace: ctrl.deleteCharBefore(); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:    ctrl.deleteCharAfter();  _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (ctrl.ghostText.isVisible) { ctrl.acceptGhostText(); _bump(); return KeyEventResult.handled; }
        ctrl.insertNewline(); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        // Ghost text: Tab accepts the full suggestion (VSCode Copilot behaviour).
        if (!isShift && ctrl.ghostText.isVisible) {
          ctrl.acceptGhostText(); _bump(); return KeyEventResult.handled;
        }
        if (isShift) _unindentLine(); else ctrl.insertTab(); _bump(); return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Dismiss ghost text first (VSCode: Escape dismisses it before other actions)
        if (ctrl.ghostText.isVisible) { ctrl.ghostText.dismiss(); _bump(); return KeyEventResult.handled; }
        // Dismiss completion / search / selection
        if (ctrl.isCompletionVisible) { ctrl.hideCompletion(); _bump(); return KeyEventResult.handled; }
        if (_searchVisible) { setState(() => _searchVisible = false); return KeyEventResult.handled; }
        if (ctrl.cursor.hasSelection) { ctrl.cursor.clearSelection(); _hideAllHandles(); _bump(); return KeyEventResult.handled; }
        break;
      default: break;
    }

    if (ev.character != null && ev.character!.isNotEmpty && !ev.character!.codeUnits.any((c) => c < 32)) {
      ctrl.insertText(ev.character!); _bump();
      // Trigger signature help on '(' and ','
      if (ev.character == '(' || ev.character == ',') {
        _triggerSignatureHelp(triggerChar: ev.character);
      } else if (ev.character == ')') {
        // Dismiss signature help on closing paren
        if (_lspSigVisible) setState(() => _lspSigVisible = false);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _bump() => _cursorTick.value++;

  // ── Color decorator helpers ────────────────────────────────────────────
  List<ColorMatch> _colorsForLine(int line) {
    final ver = widget.controller.content.documentVersion;
    if (ver != _colorCacheVersion) { _colorCache.clear(); _colorCacheVersion = ver; }
    return _colorCache.putIfAbsent(line,
        () => ColorDetector.detect(widget.controller.content.getLineText(line)));
  }

  /// If [local] is over a color swatch, return the match; else null.
  ColorMatch? _colorSwatchAt(Offset local) {
    if (!widget.controller.props.showColorDecorators) return null;
    final sY  = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
    final sX  = _hCtrl.hasClients ? _hCtrl.offset : 0.0;
    final vis = _visibleLines();
    if (vis.isEmpty) return null;
    final vi = ((local.dy + sY) / _lh).floor().clamp(0, vis.length - 1).toInt();
    if (vi >= vis.length) return null;
    for (final m in _colorsForLine(vis[vi])) {
      final textX = _gw + _codePad + m.start * _cw - sX;
      final sx    = textX - _EBox._swatchSize - _EBox._swatchRightGap - _EBox._swatchLeftGap;
      if (local.dx >= sx - 2 && local.dx <= sx + _EBox._swatchSize + 2) return m;
    }
    return null;
  }

  void _unindentLine() {
    final ctrl = widget.controller; final line = ctrl.cursor.line;
    final text = ctrl.content.getLineText(line);
    if (text.startsWith('    ')) {
      ctrl.content.delete(EditorRange(CharPosition(line, 0), CharPosition(line, 4)));
      ctrl.cursor.moveTo(CharPosition(line, (ctrl.cursor.column - 4).clamp(0, ctrl.content.getLineLength(line))));
    } else if (text.startsWith('\t')) {
      ctrl.content.delete(EditorRange(CharPosition(line, 0), CharPosition(line, 1)));
      ctrl.cursor.moveTo(CharPosition(line, (ctrl.cursor.column - 1).clamp(0, ctrl.content.getLineLength(line))));
    }
  }

  void _toggleComment() {
    final ctrl   = widget.controller;
    final prefix = ctrl.language.lineCommentPrefix;
    if (prefix.isEmpty) return;
    final hasSel = ctrl.cursor.hasSelection;
    final sl = hasSel ? ctrl.cursor.selection.start.line : ctrl.cursor.line;
    final el = hasSel ? ctrl.cursor.selection.end.line   : ctrl.cursor.line;
    for (int line = sl; line <= el; line++) {
      final text = ctrl.content.getLineText(line);
      if (text.trimLeft().startsWith(prefix)) {
        final idx = text.indexOf(prefix);
        ctrl.content.delete(EditorRange(CharPosition(line, idx), CharPosition(line, idx + prefix.length)));
      } else {
        ctrl.content.insert(CharPosition(line, 0), prefix);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TextInputClient — lets the Android IME paste from clipboard
  // ═══════════════════════════════════════════════════════════════════════

  // ── IME (Android soft keyboard) ──────────────────────────────────────────
  // We keep a two-character sentinel "​​" (zero-width spaces) so:
  //  • Android shows the clipboard paste button (needs non-empty text)
  //  • We can detect deletions: if new text has fewer sentinel chars → backspace
  //  • We can detect insertions: extra chars after sentinel → typed text
  // The sentinel is at positions [0,1]; cursor is at offset 2 normally.
  static const String _imeSentinel = '​​'; // two zero-width spaces
  static TextEditingValue get _imeInit => TextEditingValue(
    text: _imeSentinel,
    selection: TextSelection.collapsed(offset: _imeSentinel.length),
  );
  TextEditingValue _imeValue = _imeInit;

  @override
  TextEditingValue get currentTextEditingValue => _imeValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    final ctrl = widget.controller;
    final newText = value.text;

    // Case 1: Text is now SHORTER than sentinel — user pressed backspace/delete.
    if (newText.length < _imeSentinel.length) {
      final deleted = _imeSentinel.length - newText.length;
      for (int i = 0; i < deleted; i++) ctrl.deleteCharBefore();
      _bump();
      _resetImeState();
      return;
    }

    // Case 2: Text equals sentinel exactly — user deleted all inserted text
    // (e.g. autocorrect replaced then deleted). No-op.
    if (newText == _imeSentinel) {
      _resetImeState();
      return;
    }

    // Case 3: Extra content after sentinel = inserted text (typing/paste/space/enter).
    final extra = newText.startsWith(_imeSentinel)
        ? newText.substring(_imeSentinel.length)
        : newText.replaceAll('​', ''); // strip stray sentinels

    if (extra.isEmpty) { _resetImeState(); return; }

    // Handle newline from soft keyboard (Android sends \n for Enter).
    // When ghost text is visible, Enter accepts the suggestion (like Tab on desktop).
    if (extra == '\n') {
      if (ctrl.ghostText.isVisible) {
        ctrl.acceptGhostText(); _bump(); _resetImeState(); return;
      }
      ctrl.insertNewline(); _bump(); _resetImeState(); return;
    }
    // Handle tab
    if (extra == '\t') {
      ctrl.insertTab(); _bump(); _resetImeState(); return;
    }
    // Everything else: typed text or paste
    ctrl.pasteText(extra);
    _bump();
    _resetImeState();
  }

  void _resetImeState() {
    _imeValue = _imeInit;
    _inputConn?.setEditingState(_imeInit);
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline || action == TextInputAction.done) {
      final ctrl = widget.controller;
      if (ctrl.ghostText.isVisible) {
        ctrl.acceptGhostText(); _bump();
      } else {
        ctrl.insertNewline(); _bump();
      }
    }
  }

  // Android keyboards (Gboard, Samsung, etc.) often call deleteSurroundingText
  // instead of updateEditingValue when backspace is pressed.
  @override
  void deleteSurroundingText(int beforeLength, int afterLength) {
    final ctrl = widget.controller;
    for (int i = 0; i < beforeLength; i++) ctrl.deleteCharBefore();
    for (int i = 0; i < afterLength; i++) ctrl.deleteCharAfter();
    if (beforeLength > 0 || afterLength > 0) { _bump(); _resetImeState(); }
  }

  @override
  void deleteSurroundingTextInCodeUnits(int beforeLength, int afterLength) {
    deleteSurroundingText(beforeLength, afterLength);
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // Fallback: some keyboards send backspace as a private command
    if (action == 'android.widget.EditText.actionBackspace' ||
        action == 'androidx.appcompat.widget.AppCompatEditText.actionBackspace') {
      widget.controller.deleteCharBefore();
      _bump();
    }
  }

  @override
  void insertTextPlaceholder(Size size) {}
  @override
  void removeTextPlaceholder() {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}
  @override
  void connectionClosed() { _inputConn = null; }
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void insertContent(KeyboardInsertedContent content) {}
  @override
  void performSelector(String selectorName) {}
  @override
  void showToolbar() {}

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD — setState only for zoom + searchBar
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final ctrl  = widget.controller;
    final theme = _theme;
    final cs    = theme.colorScheme;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(children: [
        if (_searchVisible)
          Material(
            color: Colors.transparent,
            child: QuillSearchBar(controller: ctrl, theme: theme,
                onClose: () => setState(() => _searchVisible = false)),
          ),
        Expanded(child: LayoutBuilder(builder: (ctx, bc) {
          // bc.maxHeight already excludes keyboard because Scaffold's
          // resizeToAvoidBottomInset:true shrinks the layout before LayoutBuilder.
          // Do NOT subtract viewInsets.bottom again — that double-subtracts.
          _vpSize = Size(
            bc.maxWidth - (ctrl.props.showMinimap ? _minimapWidth : 0),
            math.max(40.0, bc.maxHeight),
          );
          _gw = _calcGw();

          return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // NOTE: We do NOT use onDoubleTap — it adds a 300ms delay to every
              // single tap while Flutter waits to see if a second tap follows.
              // Instead we implement our own <350ms double-tap detection in _onTapDown.
              onTapDown: _onTapDown,
              onLongPressStart: _onLongPressStart,
              onLongPressMoveUpdate: _onLongPressMoveUpdate,
              onLongPressEnd: _onLongPressEnd,
              child: ClipRect(child: Stack(children: [

                // ── Layer 1: Code canvas ─────────────────────────────
                SizedBox.expand(
                  child: RepaintBoundary(child: _buildScrollable(ctrl, _effectiveTheme)),
                ),

                // ── Layer 2: Fixed gutter — only when fixedLineNumbers=true ──
                if (ctrl.props.fixedLineNumbers && _gw > 0)
                  ListenableBuilder(
                    listenable: _gutterListenable,
                    builder: (_, __) {
                      // _gwN.value is authoritative after zoom; fall back to _gw (from LayoutBuilder)
                      final gw   = _gwN.value > 1.0 ? _gwN.value : _gw;
                      final lhS  = _effectiveTheme.lineHeightPx;
                      final sY   = _gutterScrollY.value;
                      final vis  = _visibleLines();
                      return Positioned(
                        left: 0, top: 0, bottom: 0, width: gw,
                        child: CustomPaint(
                          isComplex: false,
                          willChange: true,
                          painter: _GutterPainter(
                            controller: ctrl, theme: _effectiveTheme, gw: gw,
                            scrollY: sY,
                            elevation: (_hScrollN.value / 40.0).clamp(0.0, 1.0),
                            vis: vis,
                            zoom: _effectiveTheme.fontSize,
                            lineHeightZoomed: lhS,
                            wrapOffsets: _wrapOffsetsN.value,
                            ghostInsertVi:  _ghostInsertViN.value,
                            ghostExtraRows: _ghostExtraRowsN.value,
                          ),
                        ),
                      );
                    },
                  ),

                // ── Layer 3: Handles (cursor/selection) ───────────────
                RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: _handleListenable,
                    builder: (_, __) => _buildHandleLayer(ctrl, cs),
                  ),
                ),

                // ── Layer 4: Selection toolbar ────────────────────────
                ListenableBuilder(
                  listenable: _toolbarListenable,
                  builder: (_, __) {
                    if (!_toolbarVisible.value) return const SizedBox.shrink();
                    return _buildToolbar(ctrl, theme, cs);
                  },
                ),

                // ── Layer 5: Minimap panel ────────────────────────────
                // Rendered BELOW all popups so completion/tooltip/lightbulb
                // appear on top of the minimap rather than behind it.
                if (ctrl.props.showMinimap)
                  Positioned(
                    right: 0, top: 0, bottom: 0,
                    width: _minimapWidth,
                    child: MinimapWidget(
                      controller: ctrl,
                      theme:      theme,
                      vCtrl:      _vCtrl,
                      viewportH:  bc.maxHeight,
                      lineHeight: _lh, // always unzoomed — minimap has its own scale
                    ),
                  ),

                // ── Layer 6: Completion popup ─────────────────────────
                // Hidden when ghost text is active (they would overlap).
                // Hidden in readOnly mode.
                ValueListenableBuilder<int>(
                  valueListenable: _cursorTick,
                  builder: (_, __, ___) {
                    final visible = !ctrl.props.readOnly &&
                        ctrl.isCompletionVisible &&
                        !ctrl.ghostText.isVisible;
                    if (!visible) return const SizedBox.shrink();
                    final pos     = _charToLocal(ctrl.cursor.position);
                    // Compact size for mobile screens; CompletionPopup is intrinsically sized
                    const popupW  = 320.0;
                    const popupH  = 160.0;
                    const pad     = 4.0;
                    final kbH     = MediaQuery.of(context).viewInsets.bottom;
                    final usableH = _vpSize.height - kbH;
                    final minimapW = ctrl.props.showMinimap ? _minimapWidth + pad : 0.0;
                    final availW  = _vpSize.width - minimapW - pad * 2;
                    // _charToLocal returns (eff+1)*_lh - sY, i.e. the BOTTOM of the
                    // cursor line. Derive top so we never overlap the cursor itself.
                    final cursorTop    = pos.dy - _lh;     // top edge of cursor line
                    final cursorBottom = pos.dy;           // bottom edge of cursor line
                    final spaceBelow   = usableH - cursorBottom - pad;
                    final spaceAbove   = cursorTop - pad;
                    double top;
                    // Prefer below (VSCode behaviour) — only go above when below has no room.
                    if (spaceBelow >= popupH) {
                      top = cursorBottom + pad;            // fits below (preferred)
                    } else if (spaceAbove >= popupH) {
                      top = cursorTop - popupH - pad;      // fits above (fallback)
                    } else if (spaceBelow >= spaceAbove) {
                      top = cursorBottom + pad;            // more room below
                    } else {
                      top = (cursorTop - popupH - pad).clamp(0.0, double.maxFinite);
                    }
                    // Horizontal: start at cursor x; shift left if it would overflow right.
                    final left = pos.dx.clamp(pad, math.max(pad, availW - popupW)).toDouble();
                    return Positioned(
                      left: left, top: top,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: availW, maxHeight: popupH), // popupH = 160
                        child: CompletionPopup(
                            controller: ctrl, theme: theme, selectedIndex: _completionIdx),
                      ),
                    );
                  },
                ),

                // ── Layer 7: Diagnostic tooltip ───────────────────────
                ValueListenableBuilder<int>(
                  valueListenable: _cursorTick,
                  builder: (_, __, ___) {
                    if (ctrl.props.readOnly) return const SizedBox.shrink();
                    if (ctrl.cursor.hasSelection) return const SizedBox.shrink();
                    // Never show diagnostic tooltip at the same time as completion popup
                    if (ctrl.isCompletionVisible) return const SizedBox.shrink();
                    final diag = ctrl.diagnostics.atPosition(ctrl.cursor.position);
                    if (diag == null) return const SizedBox.shrink();
                    return _diagTooltip(diag, ctrl.cursor.position, theme, cs);
                  },
                ),

                // ── Layer 8: Cursor magnifier (shown while dragging handle) ──
                ListenableBuilder(
                  listenable: _magnifierListenable,
                  builder: (_, __) {
                    final mp = _magnifierPos;
                    if (mp == null || _drag != 'cursor') return const SizedBox.shrink();
                    return _buildMagnifier(mp, ctrl, theme, cs);
                  },
                ),

                // ── Layer 9: Lightbulb ────────────────────────────────
                ValueListenableBuilder<bool>(
                  valueListenable: _lightbulbVisible,
                  builder: (_, visible, __) {
                    if (!visible || ctrl.props.readOnly || ctrl.cursor.hasSelection) return const SizedBox.shrink();
                    return ValueListenableBuilder<int>(
                      valueListenable: _cursorTick,
                      builder: (_, __, ___) {
                        final pos = ctrl.cursor.position;
                        if (pos.line >= ctrl.content.lineCount) return const SizedBox.shrink();
                        final anchor = _charToLocal(pos);
                        return LightbulbWidget(
                          controller:    ctrl,
                          theme:         theme,
                          cursorLocal:   anchor,
                          gutterWidth:   _gw,
                          lineHeight:    _lh,
                          viewportWidth: _vpSize.width,
                          viewportHeight: bc.maxHeight,
                          onAction:      (a) => _onActionSelected(a),
                        );
                      },
                    );
                  },
                ),

                // ── Layer 10: Symbol info panel ───────────────────────
                ValueListenableBuilder<int>(
                  valueListenable: _cursorTick,
                  builder: (_, __, ___) {
                    if (ctrl.props.readOnly || !_symbolPanelVisible || _hoveredSymbol == null) {
                      return const SizedBox.shrink();
                    }
                    final sym    = _hoveredSymbol!;
                    final anchor = _charToLocal(sym.nameRange.start);
                    return SymbolInfoPanel(
                      symbol:         sym,
                      theme:          theme,
                      anchorLocal:    anchor,
                      lineHeight:     _lh,
                      viewportWidth:  _vpSize.width,
                      viewportHeight: bc.maxHeight,
                      onGoToDefinition: () {
                        _symbolPanelVisible = false;
                        _cursorTick.value++;
                        if (sym.definedAtLine >= 0) {
                          ctrl.setCursor(CharPosition(sym.definedAtLine, 0));
                          _scrollToLine(sym.definedAtLine);
                          _cursorTick.value++;
                        }
                      },
                      onDismiss: () {
                        _symbolPanelVisible = false;
                        _lightbulbVisible.value = false;
                        _cursorTick.value++;
                      },
                    );
                  },
                ),

                // ── Layer 11: LSP hover panel ─────────────────────────
                if (!ctrl.props.readOnly && _lspHoverVisible && _lspHoverText != null)
                  ValueListenableBuilder<int>(
                    valueListenable: _cursorTick,
                    builder: (_, __, ___) {
                      final pos = ctrl.cursor.position;
                      final anchor = _charToLocal(pos);
                      return LspHoverPanel(
                        contents:       _lspHoverText!,
                        theme:          theme,
                        anchorLocal:    anchor,
                        lineHeight:     _lh,
                        viewportWidth:  _vpSize.width,
                        viewportHeight: bc.maxHeight,
                        onDismiss: () => setState(() => _lspHoverVisible = false),
                      );
                    },
                  ),

                // ── Layer 12: LSP signature help panel ────────────────
                if (!ctrl.props.readOnly && _lspSigVisible && _lspSigHelp != null)
                  ValueListenableBuilder<int>(
                    valueListenable: _cursorTick,
                    builder: (_, __, ___) {
                      final pos = ctrl.cursor.position;
                      final anchor = _charToLocal(pos);
                      return LspSignaturePanel(
                        sigHelp:        _lspSigHelp!,
                        theme:          theme,
                        anchorLocal:    anchor,
                        lineHeight:     _lh,
                        viewportWidth:  _vpSize.width,
                        viewportHeight: bc.maxHeight,
                        onDismiss: () => setState(() => _lspSigVisible = false),
                      );
                    },
                  ),

                // ── Layer 13: Scrollbars ──────────────────────────────
                if (ctrl.props.showScrollbars) _buildScrollbars(cs),

                // ── Layer 14: Color picker ────────────────────────────
                if (_colorPickerAnchor != null && _colorPickerMatch != null)
                  _buildColorPickerLayer(),

              ])         // Stack children
            ),           // ClipRect
          );             // GestureDetector (return)
        })),
        // SymbolInputBar uses the BASE theme (non-zoomed fontSize) so
        // pinch-zoom on the code canvas never resizes the symbol bar.
        if (widget.showSymbolBar) SymbolInputBar(
          controller: ctrl,
          theme: widget.theme ?? QuillThemeDark.build(),
        ),
      ]),
    );
  }

  // ── Scrollbars ─────────────────────────────────────────────────────────
  Widget _buildScrollbars(EditorColorScheme cs) {
    final sb     = _effectiveTheme.scrollbar;
    final thick  = sb.thickness;
    final thumbC = sb.thumbColor ?? cs.scrollBarThumb;
    final trackC = sb.trackColor ?? cs.scrollBarTrack;
    // Horizontal bar left offset: if gutter is fixed it starts after the gutter.
    final ctrl   = widget.controller;
    final gutterLeft = (ctrl.props.fixedLineNumbers && _gw > 0)
        ? (_gwN.value > 1.0 ? _gwN.value : _gw)
        : 0.0;

    return AnimatedBuilder(
      animation: _scrollbarFade,
      builder: (_, __) {
        final opacity = _scrollbarFade.value;
        if (opacity == 0) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: Listenable.merge([_vCtrl, _hCtrl]),
          builder: (_, __) {
            final vPos   = _vCtrl.positions.firstOrNull;
            final hPos   = _hCtrl.positions.firstOrNull;
            final vReady = vPos != null && vPos.hasContentDimensions && vPos.hasPixels;
            final hReady = hPos != null && hPos.hasContentDimensions && hPos.hasPixels;
            final showV  = vReady && vPos!.maxScrollExtent > 0;
            final showH  = hReady && hPos!.maxScrollExtent > 0;
            if (!showV && !showH) return const SizedBox.shrink();
            return Opacity(
              opacity: opacity,
              child: Stack(children: [
                // ── Vertical bar ─────────────────────────────────────────
                if (showV) Positioned(
                  right: 0, top: 0, bottom: showH ? thick : 0, width: thick,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (d) {
                      _sbVDragStartLocal = d.localPosition.dy;
                      _sbVDragStartPx    = vPos!.pixels;
                      _onScrollbarActivity();
                    },
                    onVerticalDragUpdate: (d) {
                      final pos        = vPos!;
                      final trackLen   = math.max(1.0, pos.viewportDimension - (showH ? thick : 0));
                      final total      = pos.viewportDimension + pos.maxScrollExtent;
                      final minLen     = math.min(sb.minThumbLength, trackLen);
                      final thumbLen   = (pos.viewportDimension / total * trackLen)
                          .clamp(minLen, trackLen);
                      final avail      = trackLen - thumbLen;
                      if (avail <= 0) return;
                      final ratio      = pos.maxScrollExtent / avail;
                      final delta      = d.localPosition.dy - _sbVDragStartLocal;
                      final newPx      = (_sbVDragStartPx + delta * ratio)
                          .clamp(0.0, pos.maxScrollExtent);
                      _vCtrl.jumpTo(newPx);
                      _onScrollbarActivity();
                    },
                    onVerticalDragEnd: (_) => _onScrollbarActivity(),
                    child: CustomPaint(painter: _ScrollbarThumbPainter(
                      position: vPos!.pixels, maxExtent: vPos.maxScrollExtent,
                      viewportExtent: vPos.viewportDimension,
                      thumbColor: thumbC, trackColor: trackC,
                      borderColor: sb.borderColor, borderWidth: sb.borderWidth,
                      radius: sb.radius, showTrack: sb.showTrack,
                      minThumbLength: sb.minThumbLength, vertical: true)),
                  ),
                ),
                // ── Horizontal bar ───────────────────────────────────────
                if (showH) Positioned(
                  left: gutterLeft, bottom: 0,
                  right: showV ? thick : 0, height: thick,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) {
                      _sbHDragStartLocal = d.localPosition.dx;
                      _sbHDragStartPx    = hPos!.pixels;
                      _onScrollbarActivity();
                    },
                    onHorizontalDragUpdate: (d) {
                      final pos        = hPos!;
                      final trackLen   = math.max(1.0, pos.viewportDimension - (showV ? thick : 0));
                      final total      = pos.viewportDimension + pos.maxScrollExtent;
                      final minLen     = math.min(sb.minThumbLength, trackLen);
                      final thumbLen   = (pos.viewportDimension / total * trackLen)
                          .clamp(minLen, trackLen);
                      final avail      = trackLen - thumbLen;
                      if (avail <= 0) return;
                      final ratio      = pos.maxScrollExtent / avail;
                      final delta      = d.localPosition.dx - _sbHDragStartLocal;
                      final newPx      = (_sbHDragStartPx + delta * ratio)
                          .clamp(0.0, pos.maxScrollExtent);
                      _hCtrl.jumpTo(newPx);
                      _onScrollbarActivity();
                    },
                    onHorizontalDragEnd: (_) => _onScrollbarActivity(),
                    child: CustomPaint(painter: _ScrollbarThumbPainter(
                      position: hPos!.pixels, maxExtent: hPos.maxScrollExtent,
                      viewportExtent: hPos.viewportDimension,
                      thumbColor: thumbC, trackColor: trackC,
                      borderColor: sb.borderColor, borderWidth: sb.borderWidth,
                      radius: sb.radius, showTrack: sb.showTrack,
                      minThumbLength: sb.minThumbLength, vertical: false)),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  // ── Color picker overlay ────────────────────────────────────────────────
  Widget _buildColorPickerLayer() {
    final anchor = _colorPickerAnchor!;
    final match  = _colorPickerMatch!;
    final line   = _colorPickerLine;
    const pickerW = 238.0;
    const pickerH = 256.0;
    const pad = 4.0;
    double left = (anchor.dx - 10).clamp(pad, math.max(pad, _vpSize.width - pickerW - pad));
    double top  = anchor.dy + _lh + 2;
    if (top + pickerH > _vpSize.height - pad) top = (anchor.dy - pickerH - 2).clamp(pad, double.infinity);
    return Positioned(
      left: left, top: top,
      child: ColorPickerOverlay(
        initialColor: match.color,
        initialText:  () {
          final t = widget.controller.content.getLineText(line);
          if (match.end > t.length) return t; // stale match — just show whole text
          return t.substring(match.start, match.end);
        }(),
        onCommit: (_, newText) {
          final ctrl = widget.controller;
          final old  = ctrl.content.getLineText(line);
          final neo  = old.substring(0, match.start) + newText + old.substring(match.end);
          final len  = ctrl.content.getLineLength(line);
          ctrl.content.delete(EditorRange(CharPosition(line, 0), CharPosition(line, len)));
          ctrl.content.insert(CharPosition(line, 0), neo);
          _colorCache.remove(line);
          _bump();
        },
        onDismiss: () => setState(() {
          _colorPickerAnchor = null;
          _colorPickerMatch  = null;
          _colorPickerLine   = -1;
        }),
      ),
    );
  }

  Widget _buildMagnifier(Offset fingerLocal, QuillCodeController ctrl,
      EditorTheme theme, EditorColorScheme cs) {
    const magW = 130.0, magH = 50.0;
    const magnification = 1.8;

    double left = fingerLocal.dx - magW / 2;
    double top  = fingerLocal.dy - magH - 60.0;
    left = left.clamp(4.0, (_vpSize.width  - magW - 4).clamp(4.0, double.infinity));
    top  = top .clamp(4.0, (_vpSize.height - magH - 4).clamp(4.0, double.infinity));

    final cursorLocal  = _charToLocal(ctrl.cursor.position);
    final box          = context.findRenderObject() as RenderBox?;
    if (box == null) return const SizedBox.shrink();

    final magnifierCenterGlobal = box.localToGlobal(Offset(left + magW / 2, top + magH / 2));
    final focalGlobal = box.localToGlobal(
      Offset(cursorLocal.dx, cursorLocal.dy - _lh / 2),
    );
    final offset = focalGlobal - magnifierCenterGlobal;

    return Positioned(
      left: left, top: top,
      child: IgnorePointer(
        child: RawMagnifier(
          magnificationScale: magnification,
          focalPointOffset: offset,
          decoration: MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: cs.cursor.withOpacity(0.55), width: 1.5),
            ),
          ),
          size: const Size(magW, magH),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Selection & cursor handles — uses Flutter's native Material handles
  // (same teardrops used by TextField/EditableText).
  // ═══════════════════════════════════════════════════════════════════════

  /// Shared Material handle controls instance (stateless, safe to reuse).
  static final _nativeHandles = MaterialTextSelectionControls();

  Widget _buildHandleLayer(QuillCodeController ctrl, EditorColorScheme cs) {
    final hasSel = ctrl.cursor.hasSelection;
    return Stack(clipBehavior: Clip.none, children: [
      if (!ctrl.props.readOnly && !hasSel && (_cursorHandleVisible || _drag == 'cursor'))
        _mkHandle(
          anchor:  _charToLocal(ctrl.cursor.position),
          type:    TextSelectionHandleType.collapsed,
          onStart: _cDragStart,
          onUpdate: _cDragUpdate,
          onEnd:   _cDragEnd,
        ),
      if (hasSel && (_selHandlesVisible || _drag == 'selStart' || _drag == 'selEnd')) ...[
        // Start handle — left teardrop, body LEFT of anchor
        _mkHandle(
          anchor:  _charToLocal(ctrl.cursor.selection.start),
          type:    TextSelectionHandleType.left,
          onStart: _ssDragStart,
          onUpdate: _ssDragUpdate,
          onEnd:   _ssDragEnd,
        ),
        // End handle — right teardrop, body RIGHT of anchor
        _mkHandle(
          anchor:  _charToLocal(ctrl.cursor.selection.end),
          type:    TextSelectionHandleType.right,
          onStart: _seDragStart,
          onUpdate: _seDragUpdate,
          onEnd:   _seDragEnd,
        ),
      ],
    ]);
  }

  Widget _mkHandle({
    required Offset anchor,
    required TextSelectionHandleType type,
    required GestureDragStartCallback onStart,
    required GestureDragUpdateCallback onUpdate,
    required GestureDragEndCallback onEnd,
  }) {
    // Native handle size: Material spec is 22×22 circle with 22px line = ~44 total
    const handleSize = Size(22.0, 22.0);
    final lineHeight = _lh;

    // Build the native Material handle widget, optionally with custom color
    final handleCol = widget.controller.props.handleColor
        ?? _effectiveTheme.colorScheme.selectionHandle;
    final handleWidget = Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionHandleColor: handleCol,
        ),
      ),
      child: Builder(builder: (innerCtx) =>
        _nativeHandles.buildHandle(innerCtx, type, lineHeight),
      ),
    );

    // Determine Positioned offsets so the tip of the handle sits at the anchor.
    // For TextSelectionHandleType:
    //   .collapsed → tip at top-center  → offset by (-handleSize.width/2, 0)
    //   .left       → tip at top-right   → offset by (-handleSize.width, 0)
    //   .right      → tip at top-left    → offset by (0, 0)
    final double left;
    switch (type) {
      case TextSelectionHandleType.collapsed:
        left = anchor.dx - handleSize.width / 2;
        break;
      case TextSelectionHandleType.left:
        left = anchor.dx - handleSize.width;
        break;
      case TextSelectionHandleType.right:
        left = anchor.dx;
        break;
    }
    final top = anchor.dy; // tip at bottom of cursor line

    // Extra invisible padding to enlarge the tap/drag target
    const pad = 16.0;

    return Positioned(
      left: (left - pad).clamp(-pad, _vpSize.width),
      top:  (top  - pad).clamp(-pad, _vpSize.height),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart:  onStart,
        onPanUpdate: onUpdate,
        onPanEnd:    onEnd,
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: handleWidget,
        ),
      ),
    );
  }


  // ════════════════════════════════════════════════════════════════════════
  // Selection context toolbar — Sora-editor style
  // Groups: Primary (cut/copy/paste) | Select | Format | Transform | History
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildToolbar(QuillCodeController ctrl, EditorTheme theme, EditorColorScheme cs) {
    final hasSel      = ctrl.cursor.hasSelection;
    final selText     = hasSel ? ctrl.content.getTextInRange(ctrl.cursor.selection) : '';
    final isMultiLine = hasSel && ctrl.cursor.selection.start.line != ctrl.cursor.selection.end.line;
    final hidden      = ctrl.props.hiddenToolItems;

    final readOnly = ctrl.props.readOnly;
    // In readOnly mode: only show Copy (when selection exists). No editing items.
    final groups = readOnly
        ? <List<_ToolItem>>[
            // ReadOnly: copy (when selection exists) + select line + select all
            [
              if (hasSel && !hidden.contains('Copiar'))  _ToolItem('Copiar', Icons.content_copy, _doCopy),
            ],
            [
              if (!hidden.contains('Linha')) _ToolItem('Linha', Icons.wrap_text,  () { ctrl.selectLine(); _cursorTick.value++; _showSelHandles(); }),
              if (!hidden.contains('Tudo'))  _ToolItem('Tudo',  Icons.select_all, () { ctrl.selectAll();  _cursorTick.value++; _showSelHandles(); }),
            ],
          ]
        : <List<_ToolItem>>[
            [
              if (hasSel && !hidden.contains('Recortar')) _ToolItem('Recortar',   Icons.content_cut,          _doCut),
              if (hasSel && !hidden.contains('Copiar'))   _ToolItem('Copiar',     Icons.content_copy,         _doCopy),
              if (!hidden.contains('Colar'))              _ToolItem('Colar',      Icons.content_paste,        _doPaste),
            ],
            [
              if (hasSel && !hidden.contains('Desel.'))  _ToolItem('Desel.',    Icons.highlight_off,          () { ctrl.cursor.clearSelection(); _hideAllHandles(); _cursorTick.value++; }),
              if (!hidden.contains('Palavra'))            _ToolItem('Palavra',   Icons.spellcheck,             () { ctrl.selectWord();  _cursorTick.value++; _showSelHandles(); }),
              if (!hidden.contains('Linha'))              _ToolItem('Linha',     Icons.wrap_text,              () { ctrl.selectLine();  _cursorTick.value++; _showSelHandles(); }),
              if (!hidden.contains('Tudo'))               _ToolItem('Tudo',      Icons.select_all,             () { ctrl.selectAll();   _cursorTick.value++; _showSelHandles(); }),
              if (hasSel && !isMultiLine && !hidden.contains('Expandir')) _ToolItem('Expandir', Icons.zoom_out_map, _expandSelection),
            ],
            if (hasSel) [
              if (!hidden.contains('Indentar')) _ToolItem('Indentar',  Icons.format_indent_increase,  _doIndent),
              if (!hidden.contains('Recuar'))   _ToolItem('Recuar',    Icons.format_indent_decrease,  _doUnindent),
            ],
            if (hasSel) [
              if (!hidden.contains('Comentar')) _ToolItem('Comentar',  Icons.code,               () { _toggleComment(); _bump(); }),
              if (!hidden.contains('Duplicar')) _ToolItem('Duplicar',  Icons.file_copy,           _doDuplicate),
              if (!hidden.contains('Mover ↑'))  _ToolItem('Mover ↑',   Icons.arrow_upward,        _moveLinesUp),
              if (!hidden.contains('Mover ↓'))  _ToolItem('Mover ↓',   Icons.arrow_downward,      _moveLinesDown),
            ],
            if (hasSel && selText.isNotEmpty) [
              if (!hidden.contains('MAIÚSC.'))  _ToolItem('MAIÚSC.',   Icons.text_fields,               _doUpper),
              if (!hidden.contains('minúsc.'))  _ToolItem('minúsc.',   Icons.text_format,               _doLower),
              if (!hidden.contains('Título'))   _ToolItem('Título',    Icons.title,                     _doTitleCase),
              if (!hidden.contains('Trim'))     _ToolItem('Trim',      Icons.auto_fix_high,             _doTrimWhitespace),
            ],
            [
              if (!hidden.contains('Cp. linha'))  _ToolItem('Cp. linha', Icons.content_copy,          _copyLine),
              if (!hidden.contains('Ct. linha'))  _ToolItem('Ct. linha', Icons.remove_circle_outline, _cutLine),
              if (!hidden.contains('Del. linha')) _ToolItem('Del. linha',Icons.delete_outline,        _deleteLine),
            ],
            [
              if (!hidden.contains('Desfazer')) _ToolItem('Desfazer',  Icons.undo,  () { ctrl.undo(); _bump(); }),
              if (!hidden.contains('Refazer'))  _ToolItem('Refazer',   Icons.redo,  () { ctrl.redo(); _bump(); }),
            ],
            if (ctrl.props.extraToolItems.isNotEmpty)
              ctrl.props.extraToolItems
                  .where((e) => !hidden.contains(e.label))
                  .map((e) => _ToolItem(
                        e.label, e.icon,
                        () => e.onTap(hasSel ? selText : ''),
                      ))
                  .toList(),
          ];
    final groups_ = groups.where((g) => g.isNotEmpty).toList();

    final allItems = <_ToolItem?>[];
    for (int gi = 0; gi < groups_.length; gi++) {
      allItems.addAll(groups_[gi]);
      if (gi < groups_.length - 1) allItems.add(null); // divider
    }

    const itemW   = 50.0;
    const iconSz  = 19.0;
    const labelSz = 9.0;

    final selAnchor = hasSel
        ? _charToLocal(ctrl.cursor.selection.start)
        : _charToLocal(ctrl.cursor.position);

    // Position: above the top of the selection text
    final selTop = selAnchor.dy - _lh;
    // Toolbar is ~60px tall. Place bottom edge 8px above selTop.
    // If not enough room, place below the selection end.
    const toolbarH = 60.0;
    double barTop = selTop - toolbarH - 8;
    if (barTop < 4) {
      final selEnd = hasSel ? _charToLocal(ctrl.cursor.selection.end) : selAnchor;
      barTop = selEnd.dy + 8;
    }
    barTop = barTop.clamp(4.0, (_vpSize.height - toolbarH - 4).clamp(4.0, double.infinity));

    // When minimap is active, shrink toolbar to not overlap it
    final minimapOff = widget.controller.props.showMinimap ? _minimapWidth + 4 : 4.0;
    return Positioned(
      left: 4, right: minimapOff, top: barTop,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // Shrink toolbar away from minimap when it's visible.
              // Clamp to >= 100 to prevent a negative-maxWidth layout crash
              // when the viewport is extremely narrow (e.g. during resize).
              maxWidth: math.max(100.0, math.min(700.0,
                _vpSize.width - 8 - (widget.controller.props.showMinimap ? _minimapWidth + 4 : 0))),
              maxHeight: toolbarH,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.completionBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.09), width: 0.8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.40), blurRadius: 18, offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: allItems.map<Widget>((it) {
                      if (it == null) {
                        return Container(
                          width: 1, height: 30,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          color: Colors.white.withOpacity(0.14),
                        );
                      }
                      return InkWell(
                        onTap: it.action,
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: itemW,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(it.icon, size: iconSz, color: cs.lineNumberCurrent),
                                const SizedBox(height: 2),
                                Text(
                                  it.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: labelSz,
                                    color: cs.lineNumber,
                                    fontFamily: _theme.fontFamily,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Toolbar actions ───────────────────────────────────────────────────
  void _doCut()   { final t = widget.controller.cutText(); if (t != null) Clipboard.setData(ClipboardData(text: t)); _toolbarVisible.value = false; _bump(); }
  void _doCopy()  { final t = widget.controller.copyText(); if (t != null) Clipboard.setData(ClipboardData(text: t)); }
  void _doPaste() {
    Clipboard.getData('text/plain').then((d) { if (!mounted || d?.text == null) return; widget.controller.pasteText(d!.text!); _bump(); });
    _toolbarVisible.value = false;
  }

  void _doIndent() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    final ind  = ctrl.props.useSpacesForTabs ? ' ' * ctrl.props.tabSize : '\t';
    for (int l = sel.start.line; l <= sel.end.line; l++) ctrl.content.insert(CharPosition(l, 0), ind);
    _bump();
  }

  void _doUnindent() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    for (int l = sel.start.line; l <= sel.end.line; l++) {
      final t = ctrl.content.getLineText(l);
      if (t.startsWith('    '))    ctrl.content.delete(EditorRange(CharPosition(l, 0), CharPosition(l, 4)));
      else if (t.startsWith('\t')) ctrl.content.delete(EditorRange(CharPosition(l, 0), CharPosition(l, 1)));
    }
    _bump();
  }

  void _doUpper() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    final text = ctrl.content.getTextInRange(sel);
    ctrl.content.delete(sel); ctrl.content.insert(sel.start, text.toUpperCase());
    ctrl.cursor.setSelection(sel.start, CharPosition(sel.end.line, sel.end.column));
    _bump();
  }

  void _doLower() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    final text = ctrl.content.getTextInRange(sel);
    ctrl.content.delete(sel); ctrl.content.insert(sel.start, text.toLowerCase());
    ctrl.cursor.setSelection(sel.start, CharPosition(sel.end.line, sel.end.column));
    _bump();
  }

  void _doTitleCase() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    final text = ctrl.content.getTextInRange(sel);
    final titled = text.replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
    ctrl.content.delete(sel); ctrl.content.insert(sel.start, titled);
    ctrl.cursor.setSelection(sel.start, CharPosition(sel.end.line, sel.end.column));
    _bump();
  }

  void _doTrimWhitespace() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    final text = ctrl.content.getTextInRange(sel);
    final trimmed = text.split('\n').map((l) => l.trimRight()).join('\n');
    ctrl.content.delete(sel); ctrl.content.insert(sel.start, trimmed);
    ctrl.cursor.setSelection(sel.start, CharPosition(sel.end.line, sel.end.column));
    _bump();
  }

  void _doDuplicate() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    final text  = ctrl.content.getTextInRange(sel);
    ctrl.content.insert(sel.end, text);
    ctrl.cursor.setSelection(sel.end, CharPosition(sel.end.line + (text.contains('\n') ? text.split('\n').length - 1 : 0), sel.end.column));
    _bump();
  }

  void _moveLinesUp() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    if (sel.start.line == 0) return;
    final prevText = ctrl.content.getLineText(sel.start.line - 1);
    final prevLen  = ctrl.content.getLineLength(sel.start.line - 1);
    ctrl.content.delete(EditorRange(CharPosition(sel.start.line - 1, 0), CharPosition(sel.start.line - 1, prevLen)));
    ctrl.content.insert(CharPosition(sel.end.line, ctrl.content.getLineLength(sel.end.line)), '\n$prevText');
    ctrl.cursor.setSelection(CharPosition(sel.start.line - 1, sel.start.column), CharPosition(sel.end.line - 1, sel.end.column));
    _bump();
  }

  void _moveLinesDown() {
    final ctrl = widget.controller; final sel = ctrl.cursor.selection;
    if (sel.end.line >= ctrl.content.lineCount - 1) return;
    final nextText = ctrl.content.getLineText(sel.end.line + 1);
    final nextLen  = ctrl.content.getLineLength(sel.end.line + 1);
    ctrl.content.delete(EditorRange(CharPosition(sel.end.line + 1, 0), CharPosition(sel.end.line + 1, nextLen)));
    ctrl.content.insert(CharPosition(sel.start.line, 0), '$nextText\n');
    ctrl.cursor.setSelection(CharPosition(sel.start.line + 1, sel.start.column), CharPosition(sel.end.line + 1, sel.end.column));
    _bump();
  }

  /// VSCode Alt+Up — move current single line (no selection) up by one.
  void _moveCurrentLineUp() {
    final ctrl = widget.controller;
    final line = ctrl.cursor.line;
    if (line == 0) return;
    final curText  = ctrl.content.getLineText(line);
    final prevText = ctrl.content.getLineText(line - 1);
    final curLen   = ctrl.content.getLineLength(line);
    final prevLen  = ctrl.content.getLineLength(line - 1);
    ctrl.content.delete(EditorRange(CharPosition(line, 0),     CharPosition(line,     curLen)));
    ctrl.content.delete(EditorRange(CharPosition(line - 1, 0), CharPosition(line - 1, prevLen)));
    ctrl.content.insert(CharPosition(line - 1, 0), curText);
    ctrl.content.insert(CharPosition(line,     0), prevText);
    ctrl.cursor.moveTo(CharPosition(line - 1, ctrl.cursor.column.clamp(0, curText.length)));
  }

  /// VSCode Alt+Down — move current single line (no selection) down by one.
  void _moveCurrentLineDown() {
    final ctrl = widget.controller;
    final line = ctrl.cursor.line;
    if (line >= ctrl.content.lineCount - 1) return;
    final curText  = ctrl.content.getLineText(line);
    final nextText = ctrl.content.getLineText(line + 1);
    final curLen   = ctrl.content.getLineLength(line);
    final nextLen  = ctrl.content.getLineLength(line + 1);
    ctrl.content.delete(EditorRange(CharPosition(line + 1, 0), CharPosition(line + 1, nextLen)));
    ctrl.content.delete(EditorRange(CharPosition(line,     0), CharPosition(line,     curLen)));
    ctrl.content.insert(CharPosition(line,     0), nextText);
    ctrl.content.insert(CharPosition(line + 1, 0), curText);
    ctrl.cursor.moveTo(CharPosition(line + 1, ctrl.cursor.column.clamp(0, curText.length)));
  }

  /// VSCode Ctrl+Shift+D — duplicate current line below.
  void _doDuplicateLineDown() {
    final ctrl = widget.controller;
    final line = ctrl.cursor.line;
    final text = ctrl.content.getLineText(line);
    final len  = ctrl.content.getLineLength(line);
    ctrl.content.insert(CharPosition(line, len), '\n$text');
    ctrl.cursor.moveTo(CharPosition(line + 1, ctrl.cursor.column.clamp(0, text.length)));
  }

  /// VSCode Ctrl+J — join next line onto current line.
  void _joinLines() {
    final ctrl = widget.controller;
    final line = ctrl.cursor.line;
    if (line >= ctrl.content.lineCount - 1) return;
    final curLen  = ctrl.content.getLineLength(line);
    final nextLen = ctrl.content.getLineLength(line + 1);
    // Delete the newline between line and line+1
    ctrl.content.delete(EditorRange(CharPosition(line, curLen), CharPosition(line + 1, 0)));
    // Add a space separator if needed
    final joined = ctrl.content.getLineText(line);
    if (curLen > 0 && !joined.endsWith(' ') && nextLen > 0) {
      ctrl.content.insert(CharPosition(line, curLen), ' ');
    }
    ctrl.cursor.moveTo(CharPosition(line, curLen));
  }

  void _copyLine() {
    final ctrl = widget.controller; final line = ctrl.cursor.line;
    final text  = ctrl.content.getLineText(line);
    Clipboard.setData(ClipboardData(text: text));
  }

  void _cutLine() {
    final ctrl = widget.controller; final line = ctrl.cursor.line;
    final len  = ctrl.content.getLineLength(line);
    final text = ctrl.content.getLineText(line);
    Clipboard.setData(ClipboardData(text: text));
    ctrl.content.delete(EditorRange(CharPosition(line, 0), CharPosition(line, len)));
    _bump();
  }

  void _deleteLine() {
    final ctrl = widget.controller; final line = ctrl.cursor.line;
    final len  = ctrl.content.getLineLength(line);
    ctrl.content.delete(EditorRange(CharPosition(line, 0), CharPosition(line, len)));
    if (line < ctrl.content.lineCount) {
      ctrl.content.delete(EditorRange(CharPosition(line, 0), CharPosition(line, 0)));
    }
    ctrl.cursor.moveTo(CharPosition(math.min(line, ctrl.content.lineCount - 1), 0));
    _bump();
  }

  void _expandSelection() {
    final ctrl = widget.controller;
    ctrl.expandSemanticSelection();
    _cursorTick.value++; _showSelHandles();
  }

  // ── 2D Scrollable ─────────────────────────────────────────────────────
  Widget _buildScrollable(QuillCodeController ctrl, EditorTheme theme) {
    final wordWrap = ctrl.props.wordWrap;
    return TwoDimensionalScrollable(
      // word-wrap: restrict to vertical-only scrolling
      diagonalDragBehavior: wordWrap
          ? DiagonalDragBehavior.weightedEvent   // wordWrap: vertical only
          : DiagonalDragBehavior.free,
      horizontalDetails: ScrollableDetails.horizontal(
        controller: _hCtrl,
        physics: wordWrap ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      ),
      verticalDetails:   ScrollableDetails.vertical(controller: _vCtrl),
      viewportBuilder: (ctx, vOff, hOff) {
        return ListenableBuilder(
          listenable: _scrollListenable,
          builder: (_, __) => _EditorViewport(
            controller:       ctrl,
            theme:            theme,
            gw:               _gw,
            vOff:             vOff,
            hOff:             hOff,
            // Don't blink while the cursor handle is visible or being dragged —
            // a pulsing cursor behind a handle is visually confusing.
            cursorAlpha:      (_focus.hasFocus && !_cursorHandleVisible && _drag != 'cursor')
                                  ? _blink.value : 1.0,
            showCursor:       !ctrl.props.readOnly && !ctrl.cursor.hasSelection,
            vpSize:           _vpSize,
            vis:              _visibleLines(),
            visFoldFree:      _cachedFoldFree,
            symbolHighlight:  _symbolPanelVisible ? _hoveredSymbol?.nameRange : null,
            bracketPair:      _activeBracketPair,
            activeBlockDepth: _activeBracketPair != null ? 1 : _activeBlockDepth,
            zoomNotifier:          _zoomN,
            gwNotifier:            _gwN,
            wrapOffsetsNotifier:   _wrapOffsetsN,
            scrollCtrl:            _vCtrl,
            gutterScrollNotifier:  _gutterScrollY,
            ghostInsertViNotifier: _ghostInsertViN,
            ghostExtraRowsNotifier:_ghostExtraRowsN,
          ),
        );
      },
    );
  }

  // ── Diagnostic tooltip ────────────────────────────────────────────────
  Widget _diagTooltip(DiagnosticRegion diag, CharPosition pos, EditorTheme theme, EditorColorScheme cs) {
    final lp    = _charToLocal(pos);
    final color = diag.severity == DiagnosticSeverity.error   ? cs.problemError
                : diag.severity == DiagnosticSeverity.warning ? cs.problemWarning
                : cs.problemTypo;
    const ovW = 200.0; const ovH = 150.0; const pad = 4.0;
    final kbH = MediaQuery.of(context).viewInsets.bottom;
    final usableH = _vpSize.height - kbH;
    final minimapW = widget.controller.props.showMinimap ? _minimapWidth + pad : 0.0;
    // _charToLocal returns (eff+1)*_lh - sY, i.e. the BOTTOM of the cursor line.
    final cursorTop    = lp.dy - _lh;   // top edge of cursor line
    final cursorBottom = lp.dy;         // bottom edge of cursor line
    final spaceBelow   = usableH - cursorBottom - pad;
    final spaceAbove   = cursorTop - pad;
    double top;
    if (spaceBelow >= ovH) {
      top = cursorBottom + pad;          // preferred: below cursor
    } else if (spaceAbove >= ovH) {
      top = cursorTop - ovH - pad;       // fallback: above cursor
    } else if (spaceBelow >= spaceAbove) {
      top = cursorBottom + pad;
    } else {
      top = (cursorTop - ovH - pad).clamp(pad, double.maxFinite);
    }
    final maxTop = usableH - ovH - pad;
    if (top > maxTop && maxTop >= pad) top = maxTop;
    final left = lp.dx.clamp(pad, (_vpSize.width - ovW - minimapW - pad).clamp(pad, double.maxFinite)).toDouble();
    return Positioned(
      left: left, top: top, width: ovW, height: ovH,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(6),
        color: cs.diagnosticTooltipBackground,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(diag.severity == DiagnosticSeverity.error
                    ? Icons.error_outline : Icons.warning_amber_outlined,
                    color: color, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(diag.message,
                  style: TextStyle(color: cs.diagnosticTooltipText,
                      fontSize: theme.fontSize * 0.82),
                  overflow: TextOverflow.ellipsis, maxLines: 6)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════════
// Scrollbar thumb painter
// ═══════════════════════════════════════════════════════════════════════════
class _ScrollbarThumbPainter extends CustomPainter {
  final double  position;
  final double  maxExtent;
  final double  viewportExtent;
  final Color   thumbColor;
  final Color   trackColor;
  final Color?  borderColor;
  final double  borderWidth;
  final double  radius;
  final bool    showTrack;
  final double  minThumbLength;
  final bool    vertical;
  const _ScrollbarThumbPainter({
    required this.position, required this.maxExtent,
    required this.viewportExtent,
    required this.thumbColor, required this.trackColor,
    required this.vertical,
    this.borderColor, this.borderWidth = 0.0,
    this.radius = 3.0, this.showTrack = true, this.minThumbLength = 20.0,
  });
  @override
  void paint(Canvas c, Size sz) {
    final trackLen = math.max(1.0, vertical ? sz.height : sz.width);
    final total    = viewportExtent + maxExtent;
    final minLen   = math.min(minThumbLength, trackLen);
    final thumbLen = (viewportExtent / total * trackLen).clamp(minLen, trackLen);
    final avail    = math.max(0.0, trackLen - thumbLen);
    final pct      = maxExtent > 0 ? position / maxExtent : 0.0;
    final start    = (pct * avail).clamp(0.0, avail);
    if (showTrack) c.drawRect(Offset.zero & sz, Paint()..color = trackColor);
    final r = vertical
        ? Rect.fromLTWH(1, start, sz.width - 2, thumbLen)
        : Rect.fromLTWH(start, 1, thumbLen, sz.height - 2);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    c.drawRRect(rr, Paint()..color = thumbColor);
    if (borderColor != null && borderWidth > 0) {
      c.drawRRect(rr, Paint()
        ..color = borderColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth);
    }
  }
  @override
  bool shouldRepaint(_ScrollbarThumbPainter o) =>
      o.position != position || o.maxExtent != maxExtent ||
      o.viewportExtent != viewportExtent || o.thumbColor != thumbColor ||
      o.borderColor != borderColor || o.borderWidth != borderWidth ||
      o.radius != radius || o.showTrack != showTrack;
}

// ═══════════════════════════════════════════════════════════════════════════
class _ToolItem { final String label; final IconData icon; final VoidCallback action; const _ToolItem(this.label, this.icon, this.action); }

// ═══════════════════════════════════════════════════════════════════════════
// Teardrop handle painter
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// Viewport widget
// ═══════════════════════════════════════════════════════════════════════════
class _EditorViewport extends LeafRenderObjectWidget {
  final QuillCodeController controller;
  final EditorTheme theme;
  final double gw;
  final ViewportOffset vOff, hOff;
  final double cursorAlpha;
  final bool showCursor;
  final Size vpSize;
  final List<int> vis;
  final bool visFoldFree; // passed from State._cachedFoldFree — avoids O(n) _isIdentitySeq in _EBox
  final EditorRange? symbolHighlight;
  final BracketPair?  bracketPair;
  final int           activeBlockDepth;
  final ValueNotifier<double> zoomNotifier;
  final ValueNotifier<double> gwNotifier;
  final ValueNotifier<List<double>> wrapOffsetsNotifier;
  final ScrollController scrollCtrl;
  final ValueNotifier<double> gutterScrollNotifier;
  final ValueNotifier<int> ghostInsertViNotifier;
  final ValueNotifier<int> ghostExtraRowsNotifier;
  const _EditorViewport({required this.controller, required this.theme, required this.gw, required this.vOff, required this.hOff, required this.cursorAlpha, required this.showCursor, required this.vpSize, required this.vis, required this.visFoldFree, this.symbolHighlight, this.bracketPair, this.activeBlockDepth = 0, required this.zoomNotifier, required this.gwNotifier, required this.wrapOffsetsNotifier, required this.scrollCtrl, required this.gutterScrollNotifier, required this.ghostInsertViNotifier, required this.ghostExtraRowsNotifier});
  @override
  _EBox createRenderObject(BuildContext ctx) => _EBox(ctrl: controller, theme: theme, gw: gw, vOff: vOff, hOff: hOff, cursorAlpha: cursorAlpha, showCursor: showCursor, vpSize: vpSize, vis: vis, visFoldFree: visFoldFree, zoomNotifier: zoomNotifier, gwNotifier: gwNotifier, wrapOffsetsNotifier: wrapOffsetsNotifier, scrollCtrl: scrollCtrl, gutterScrollNotifier: gutterScrollNotifier, ghostInsertViNotifier: ghostInsertViNotifier, ghostExtraRowsNotifier: ghostExtraRowsNotifier)
    .._symbolHighlight = symbolHighlight
    .._bracketPair = bracketPair
    .._activeBlockDepth = activeBlockDepth;
  @override
  void updateRenderObject(BuildContext ctx, _EBox ro) {
    ro.ctrl            = controller;
    ro.theme           = theme;
    ro.gw              = gw;
    ro.vOff            = vOff;
    ro.hOff            = hOff;
    ro.cursorAlpha     = cursorAlpha;
    ro.showCursor      = showCursor;
    ro.vpSize          = vpSize;
    ro.setVis(vis, visFoldFree); // atomic: sets vis + visFoldFree, skips _isIdentitySeq O(n)
    ro.symbolHighlight = symbolHighlight;
    ro.bracketPair     = bracketPair;
    ro.activeBlockDepth = activeBlockDepth;
    ro._scrollCtrl              = scrollCtrl;
    ro._gutterScrollNotifier    = gutterScrollNotifier;
    ro._wrapOffsetsNotifier     = wrapOffsetsNotifier;
    ro._ghostInsertViNotifier   = ghostInsertViNotifier;
    ro._ghostExtraRowsNotifier  = ghostExtraRowsNotifier;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Core RenderBox with TextPainter line cache + native pinch-zoom
//
// Zoom architecture:
//  • _zoom is stored here — no setState() anywhere in the widget tree.
//  • Touch: two-pointer ScaleGestureRecognizer runs INSIDE the RenderBox via
//    handleEvent() → _ZoomGestureHandler (a lightweight recogniser wrapper).
//  • Mouse/trackpad: PointerScrollEvent with Ctrl held → ctrl+scroll zoom.
//  • All coordinate helpers (localToChar, charToLocal) account for _zoom.
//  • layout/contentDimensions are re-applied whenever zoom changes so the
//    TwoDimensionalScrollable adjusts its extents correctly.
//  • _zoomNotifier is poked after every zoom change so overlay layers
//    (handles, toolbar, lightbulb) can reposition without setState.
// ═══════════════════════════════════════════════════════════════════════════
  class _EBox extends RenderBox {
  QuillCodeController _ctrl; EditorTheme _theme; double _gw;
  ViewportOffset _vOff, _hOff; double _alpha; bool _showCursor; Size _vpSize; List<int> _vis;
  Map<int, int> _visIdx = {}; // O(1) doc-line → vis-index reverse lookup (folds only)
  /// True when vis is the identity sequence [0..n-1] (no active folds).
  /// When true, _vi(line) == line — no HashMap lookup needed.
  bool _visFoldFree = true;
  EditorRange? _symbolHighlight;
  BracketPair?  _bracketPair;
  int           _activeBlockDepth = 0;

  // ── Pinch-zoom state (fontSize only — no scroll, no canvas transform) ──
  double _fontSizeBase = 14.0;  // fontSize at pinch-start
  double _baseSpan     = 0.0;   // finger distance at pinch-start
  int    _activePtrs   = 0;
  final Map<int, Offset> _ptrs = {};

  static const double _fontSizeMin = 8.0;
  static const double _fontSizeMax = 40.0;

  final ValueNotifier<double> _zoomNotifier;
  final ValueNotifier<double> _gwNotifier;
  ValueNotifier<List<double>> _wrapOffsetsNotifier;
  ScrollController _scrollCtrl;
  ValueNotifier<double>? _gutterScrollNotifier;
  ValueNotifier<int>? _ghostInsertViNotifier;
  ValueNotifier<int>? _ghostExtraRowsNotifier;

  // Line TextPainter cache
  // LRU TextPainter cache: LinkedHashMap preserves insertion order;
  // on hit we remove-then-reinsert to promote to MRU (true LRU in O(1)).
  final LinkedHashMap<_LCK, TextPainter> _lc = LinkedHashMap();
  static const int _lcMax = 1024;

  // ── _paintBlocks depth + active-block cache ────────────────────────────
  // Depths are O(N log N) to compute; cache by blocks-list identity so we
  // only recompute when styles are pushed (not every paint frame).
  List<CodeBlock>? _depthCacheBlocks;
  List<int>        _depthCache = const [];
  // Active block depends on cursor line; recompute only when either changes.
  List<CodeBlock>? _activeCacheBlocks;
  int              _activeCacheCursor = -1;
  CodeBlock?       _activeCacheResult;

  // ── Cached Paint objects — reused every frame, never re-allocated ────────
  final Paint _pBg       = Paint();
  final Paint _pSel      = Paint();
  final Paint _pSearch   = Paint();
  final Paint _pHl       = Paint();
  final Paint _pBlock    = Paint()..strokeWidth = 1.0;
  final Paint _pCursor   = Paint()..style = PaintingStyle.stroke; // strokeWidth set per-paint from theme
  final Paint _pSymH1    = Paint();
  final Paint _pSymH2    = Paint()..strokeWidth = 1.5;
  final Paint _pBracket1 = Paint();
  final Paint _pBracket2 = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2;
  final Paint _pDiag     = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4;
  final Paint _pGutter   = Paint();
  final Paint _pLnDiv    = Paint()..strokeWidth = 1.0;
  final Paint _pBp1      = Paint()..color = const Color(0xFFEF5350);
  final Paint _pBp2      = Paint()..color = const Color(0xFFB71C1C)..style = PaintingStyle.stroke..strokeWidth = 1.2;
  final Paint _pArrow    = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;

  // ── Cached derived colors — rebuilt only when cs/alpha changes ──────────
  // Avoids Color.withOpacity() allocation on every frame in paint().
  EditorColorScheme? _cachedCs;
  double _cachedAlpha = -1.0;
  Color _cachedCursorColor    = const Color(0xFF000000);
  Color _cachedSelColor       = const Color(0x33000000);
  Color _cachedSearchBgColor  = const Color(0x33000000);
  Color _cachedSearchFgColor  = const Color(0xFF000000);
  Color _cachedSymH1Color     = const Color(0x33000000);
  Color _cachedSymH2Color     = const Color(0xFF000000);
  Color _cachedBpBgColor      = const Color(0x33000000);
  Color _cachedGhostBgColor   = const Color(0x0F000000);

  void _rebuildCachedColors(EditorColorScheme cs, double alpha) {
    if (identical(cs, _cachedCs) && (_cachedAlpha - alpha).abs() < 0.01) return;
    _cachedCs    = cs;
    _cachedAlpha = alpha;
    _cachedCursorColor   = (_ctrl.props.cursorColor ?? cs.cursor).withOpacity(alpha.clamp(0.0, 1.0));
    _cachedSelColor      = cs.selectionColor;
    _cachedSearchBgColor = cs.searchMatchBackground;
    _cachedSearchFgColor = cs.searchMatchBorder.withOpacity(0.35);
    _cachedSymH1Color    = cs.type_.withOpacity(0.22);
    _cachedSymH2Color    = cs.type_.withOpacity(0.7);
    _cachedBpBgColor     = cs.ghostTextForeground.withOpacity(0.04);
    _cachedGhostBgColor  = cs.ghostTextForeground.withOpacity(0.04);
  }

  // Word-wrap: accumulated Y offset for each visual index.
  // Empty when wordWrap is off — rowY(vi) falls back to vi*lh.
  // Rebuilt in performLayout whenever wordWrap is on.
  List<double> _wrapOffsets = const [];  // length == _vis.length+1; [vi] = top of row vi

  // ── Word-wrap incremental height cache ───────────────────────────────────
  // Stores the pixel height of each visual row (index = vis-index).
  // On a single-line keystroke only one entry is re-measured; the remaining
  // 99 999 entries (for a 100k-line file) are reused → O(vc) prefix-sum
  // rebuild instead of O(vc) full TextPainter re-layout.
  //
  //  _wrapHeights        — per-vis-index heights, length == _vis.length
  //  _wrapHeightsDirtyVi — vis-index of the changed line (-1 = full rebuild)
  List<double> _wrapHeights         = const [];
  int          _wrapHeightsDirtyVi  = -1;  // -1 means full rebuild needed

  /// Y offset (in content space) for the top of visual row [vi].
  /// Ghost text virtual rows are injected between _ghostInsertVi and _ghostInsertVi+1,
  /// so all rows after the ghost cursor line are shifted down by extraRows*lh.
  double _rowY(int vi) {
    if (_wrapOffsets.isNotEmpty) {
      final base = _wrapOffsets[vi.clamp(0, _wrapOffsets.length - 1)];
      return _ghostInsertVi >= 0 && vi > _ghostInsertVi
          ? base + _ghostExtraRows * lh
          : base;
    }
    return _ghostInsertVi >= 0 && vi > _ghostInsertVi
        ? vi * lh + _ghostExtraRows * lh
        : vi * lh;
  }

  /// Height of visual row [vi] (may be >lh when word-wrapped).
  double _rowH(int vi) {
    if (_wrapOffsets.isEmpty) return lh;
    final a = vi.clamp(0, _wrapOffsets.length - 1);
    final b = (vi + 1).clamp(0, _wrapOffsets.length - 1);
    final h = _wrapOffsets[b] - _wrapOffsets[a];
    return h > 0 ? h : lh;
  }

  // Ghost virtual row state — updated whenever ghost text changes.
  int _ghostInsertVi  = -1;   // vi of the cursor line (ghost rows go BELOW it)
  int _ghostExtraRows = 0;    // number of extra virtual rows = ghostLines.length - 1

  void _updateGhostLayout() {
    final ghost = _ctrl.ghostText;
    if (!ghost.isVisible || ghost.extraRows == 0) {
      if (_ghostInsertVi != -1 || _ghostExtraRows != 0) {
        _ghostInsertVi  = -1;
        _ghostExtraRows = 0;
        _ghostInsertViNotifier?.value  = -1;
        _ghostExtraRowsNotifier?.value = 0;
        markNeedsLayout();
      }
      return;
    }
    final vi    = _vi(ghost.atLine);
    final extra = ghost.extraRows;
    if (vi != _ghostInsertVi || extra != _ghostExtraRows) {
      _ghostInsertVi  = vi;
      _ghostExtraRows = extra;
      _ghostInsertViNotifier?.value  = vi;
      _ghostExtraRowsNotifier?.value = extra;
      markNeedsLayout();
    }
  }

  /// Visual index at document-space Y (used in hit-testing).
  /// Ghost virtual rows are "above" the shifted real rows, so we subtract
  /// the ghost block height before computing the vi when Y is in the shifted zone.
  int _viAtDocY(double docY) {
    // Adjust docY: if Y falls in the ghost virtual block, clamp it to the end
    // of the cursor row; otherwise subtract the ghost offset for rows below.
    double adjustedY = docY;
    if (_ghostInsertVi >= 0 && _ghostExtraRows > 0 && _wrapOffsets.isEmpty) {
      final ghostBlockStart = (_ghostInsertVi + 1) * lh;
      final ghostBlockEnd   = ghostBlockStart + _ghostExtraRows * lh;
      if (docY >= ghostBlockStart && docY < ghostBlockEnd) {
        // Click inside virtual ghost block → treat as click on cursor line
        adjustedY = _ghostInsertVi * lh;
      } else if (docY >= ghostBlockEnd) {
        // Click below ghost block → shift back
        adjustedY = docY - _ghostExtraRows * lh;
      }
    }
    if (_wrapOffsets.isEmpty || _vis.isEmpty) {
      return (adjustedY / lh).floor().clamp(0, math.max(0, _vis.length - 1)).toInt();
    }
    // Binary search in _wrapOffsets (wordWrap mode — ghost not active in wrap mode)
    int lo = 0, hi = _vis.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_wrapOffsets[mid] <= docY) lo = mid; else hi = mid - 1;
    }
    return lo.clamp(0, _vis.length - 1);
  }

  /// Codewidth available for text (excludes gutter and padding).
  double get _codeWidth => math.max(64.0, _vpSize.width - _gw - _codePad);

  _EBox({
    required QuillCodeController ctrl,
    required EditorTheme theme,
    required double gw,
    required ViewportOffset vOff,
    required ViewportOffset hOff,
    required double cursorAlpha,
    required bool showCursor,
    required Size vpSize,
    required List<int> vis,
    required bool visFoldFree,
    required ValueNotifier<double> zoomNotifier,
    required ValueNotifier<double> gwNotifier,
    required ValueNotifier<List<double>> wrapOffsetsNotifier,
    required ScrollController scrollCtrl,
    ValueNotifier<double>? gutterScrollNotifier,
    ValueNotifier<int>? ghostInsertViNotifier,
    ValueNotifier<int>? ghostExtraRowsNotifier,
  }) : _ctrl = ctrl, _theme = theme, _gw = gw,
       _vOff = vOff, _hOff = hOff, _alpha = cursorAlpha,
       _showCursor = showCursor, _vpSize = vpSize, _vis = vis,
       _visFoldFree = visFoldFree,
       _zoomNotifier = zoomNotifier, _gwNotifier = gwNotifier,
       _wrapOffsetsNotifier = wrapOffsetsNotifier,
       _scrollCtrl = scrollCtrl {
    // Build reverse-lookup map only when folds are active.
    _visIdx = visFoldFree ? const {} : { for (int i = 0; i < vis.length; i++) vis[i]: i };
    _gutterScrollNotifier     = gutterScrollNotifier;
    _ghostInsertViNotifier    = ghostInsertViNotifier;
    _ghostExtraRowsNotifier   = ghostExtraRowsNotifier;
    _vOff.addListener(markNeedsPaint);
    _hOff.addListener(markNeedsPaint);
    // Content listener MUST be registered before the controller listener so
    // _onContentChange runs (and records the dirty vis-index) before _dirty()
    // is called (which schedules the layout).
    _ctrl.content.addListener(_onContentChange);
    _ctrl.addListener(_dirty);
    // Style-only updates (tokenization frames) bump decorVersion, not the full
    // controller. Subscribe directly so we get markNeedsPaint without triggering
    // _dirty (no layout needed — spans don't change scroll extent or line count).
    _ctrl.decorVersion.addListener(markNeedsPaint);
    // tokenizationVersion bumps ONCE when background tokenization finishes.
    // Clears the TextPainter cache so all visible lines rebuild with correct
    // spans — without this, lines painted before their spans arrived would
    // stay stale (cache hit returns the old no-color painter).
    _ctrl.tokenizationVersion.addListener(_onTokenizationDone);
    _ctrl.ghostText.addListener(_onGhostChanged);
  }

  void _onGhostChanged() {
    _updateGhostLayout();
    markNeedsPaint();
  }

  /// Called once when background tokenization completes.
  /// Evicts all stale TextPainter cache entries (built with empty spans)
  /// and schedules one repaint — cost: O(1) clear + O(visible lines) rebuild.
  void _onTokenizationDone() {
    _lc.clear();
    markNeedsPaint();
  }

  double _calcGw() {
    final digits   = _ctrl.content.lineCount.toString().length;
    final fs       = _theme.fontSize;
    final numCharW = fs * 0.601;
    double w = 0;
    if (_ctrl.props.showLineNumbers) w = numCharW * digits + 4;
    if (_ctrl.props.showFoldArrows)  w += 18;
    if (w < 4) return 0;
    return w;
  }

  /// Focal point (local coords) capturado no início do pinch — usado para
  /// reposicionar o scroll e manter o ponto de zoom visível.
  Offset _pinchFocal = Offset.zero;

  /// Change font size only — repositions scroll so [_pinchFocal] stays fixed.
  void _applyFontSize(double newFs) {
    newFs = newFs.clamp(_fontSizeMin, _fontSizeMax);
    if ((newFs - _theme.fontSize).abs() < 0.1) return;

    final oldLh = lh;
    final oldCw = cw;
    final oldSY = _vOff.pixels;
    final oldSX = _hOff.pixels;

    // Content coordinate of the focal point at OLD font size
    final contentLine   = (_pinchFocal.dy + oldSY) / oldLh;
    final contentColumn = (_pinchFocal.dx - _gw - _codePad + oldSX) / oldCw;

    _theme = _theme.copyWith(fontSize: newFs);
    _lc.clear();
    _wrapHeights        = const [];
    _wrapHeightsDirtyVi = -1;

    // New gutter width after font change
    final newGw = _calcGw();
    if ((newGw - _gw).abs() > 0.5) {
      _gw = newGw;
      _gwNotifier.value = newGw;
    }

    // Reposition scroll so the same content coordinate is under focal point
    final newLh = lh; final newCw = cw;
    final newSY = (contentLine   * newLh - _pinchFocal.dy).clamp(0.0, double.infinity);
    final newSX = (contentColumn * newCw + _gw + _codePad - _pinchFocal.dx).clamp(0.0, double.infinity);

    _vOff.correctBy(newSY - oldSY);
    _hOff.correctBy(newSX - oldSX);

    // Update _gutterScrollNotifier SYNCHRONOUSLY so the gutter builder
    // reads newSY in the same frame as the canvas — no 1-frame drift.
    _gutterScrollNotifier?.value = newSY;

    // Also sync the ScrollController (used by minimap and edge-scroll)
    // via postFrameCallback since jumpTo requires the scroll position
    // to be fully attached, which may not be the case mid-layout.
    // IMPORTANTE: captura o controller atual — se o usuário trocar de arquivo
    // antes deste callback disparar, _ctrl será diferente e o jump é cancelado.
    // Sem isso, o jump do zoom sobrescreveria o jumpTo(0) do _onScrollReset,
    // deslocando o código para baixo do gutter após a troca de arquivo.
    final targetSY   = newSY;
    final zoomCtrl   = _ctrl;   // snapshot do controller no momento do zoom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Se o controller foi trocado (arquivo novo), não repositiona.
        if (!identical(_ctrl, zoomCtrl)) return;
        if (_scrollCtrl.hasClients &&
            (_scrollCtrl.offset - targetSY).abs() > 0.5) {
          _scrollCtrl.jumpTo(
            targetSY.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
          );
        }
      } catch (_) {}
    });

    _zoomNotifier.value = newFs;
    markNeedsLayout();
  }

  // ── Content-change granular listener ──────────────────────────────────────
  // Called BEFORE _dirty() (registered first in ctrl setter) so that by the
  // time _dirty() runs we already know which visual row is dirty.
  void _onContentChange(ContentChangeEvent e) {
    if (!_ctrl.props.wordWrap) return; // height cache only used in wordWrap mode
    // Map the affected doc-line to a vis-index.
    final vi = _visFoldFree ? e.affectedLine : (_visIdx[e.affectedLine] ?? -1);
    if (vi < 0) { _wrapHeightsDirtyVi = -1; return; } // line is folded or unknown
    // -2 = heights are current, no prior dirty line this frame.
    // vi = same as current dirty line → still one dirty line.
    // Anything else → escalate to full rebuild (-1).
    if (_wrapHeightsDirtyVi == -2 || _wrapHeightsDirtyVi == vi) {
      _wrapHeightsDirtyVi = vi;
    } else if (_wrapHeightsDirtyVi != -1) {
      _wrapHeightsDirtyVi = -1;
    }
  }

  void _dirty() {
    _lc.clear();
    // Invalidate gutter TP cache when content changes (line count may change).
    for (final tp in _gutterTpCache.values) tp.dispose();
    _gutterTpCache.clear();
    _wrapOffsets  = const [];
    // _wrapHeights is preserved: performLayout will do incremental rebuild
    // using _wrapHeightsDirtyVi (set by _onContentChange before this call).
    markNeedsLayout();
  }

  set ctrl(QuillCodeController v) {
    if (_ctrl == v) return;
    _ctrl.content.removeListener(_onContentChange);
    _ctrl.removeListener(_dirty);
    _ctrl.decorVersion.removeListener(markNeedsPaint);
    _ctrl.tokenizationVersion.removeListener(_onTokenizationDone);
    _ctrl.ghostText.removeListener(_onGhostChanged);
    _ctrl = v;
    _ctrl.content.addListener(_onContentChange);  // must be first (before _dirty)
    _ctrl.addListener(_dirty);
    _ctrl.decorVersion.addListener(markNeedsPaint);
    _ctrl.tokenizationVersion.addListener(_onTokenizationDone);
    _ctrl.ghostText.addListener(_onGhostChanged);
    _lc.clear();
    _wrapHeights        = const [];
    _wrapHeightsDirtyVi = -1;
    markNeedsLayout();
  }
  set theme(EditorTheme v)        { if (_theme == v) return; _theme = v; _lc.clear(); _wrapOffsets = const []; _wrapHeights = const []; _wrapHeightsDirtyVi = -1; markNeedsLayout(); }
  set gw(double v)                { if (_gw == v) return; _gw = v; markNeedsLayout(); }
  set vOff(ViewportOffset v)      { if (_vOff == v) return; _vOff.removeListener(markNeedsPaint); _vOff = v; _vOff.addListener(markNeedsPaint); markNeedsPaint(); }
  set hOff(ViewportOffset v)      { if (_hOff == v) return; _hOff.removeListener(markNeedsPaint); _hOff = v; _hOff.addListener(markNeedsPaint); markNeedsPaint(); }
  set cursorAlpha(double v)       { if (_alpha == v) return; _alpha = v; markNeedsPaint(); }
  set symbolHighlight(EditorRange? v) { if (_symbolHighlight == v) return; _symbolHighlight = v; markNeedsPaint(); }
  set bracketPair(BracketPair? v) {
    if (_bracketPair?.open == v?.open && _bracketPair?.close == v?.close) return;
    _bracketPair = v; markNeedsPaint();
  }
  set activeBlockDepth(int v) { if (_activeBlockDepth == v) return; _activeBlockDepth = v; markNeedsPaint(); }
  set showCursor(bool v)          { if (_showCursor == v) return; _showCursor = v; markNeedsPaint(); }
  set vpSize(Size v)              { if (_vpSize == v) return; _vpSize = v; markNeedsLayout(); }
  /// Atomic vis + visFoldFree update — called from updateRenderObject.
  ///
  /// Accepts the fold-free flag pre-computed by the State (from _cachedFoldFree),
  /// eliminating the O(n) _isIdentitySeq scan that the old `set vis` performed
  /// on every build.  The HashMap is only built when folds are actually active.
  void setVis(List<int> v, bool foldFree) {
    if (identical(_vis, v) && _visFoldFree == foldFree) return;
    final sizeChanged = _vis.length != v.length;
    _vis         = v;
    _visFoldFree = foldFree;
    _visIdx      = foldFree ? const {} : { for (int i = 0; i < v.length; i++) v[i]: i };
    if (sizeChanged) {
      _lc.clear();
      _wrapOffsets        = const [];
      _wrapHeights        = const [];
      _wrapHeightsDirtyVi = -1;
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  /// O(1) doc-line → visual-index lookup.
  /// Fold-free: direct identity (no map). With folds: HashMap lookup.
  int _vi(int docLine) =>
      _visFoldFree ? docLine : (_visIdx[docLine] ?? -1);

  // lh and cw now derived purely from fontSize — no zoom multiplier
  double get lh => _theme.lineHeightPx;
  double get cw => _theme.fontSize * 0.601;
  static const double _codePad      = 6.0;
  static const double _swatchSize   = 9.0;
  static const double _swatchRightGap = 5.0;
  static const double _swatchLeftGap  = 5.0;

  // ── Pointer / gesture handling ──────────────────────────────────────────

  @override
  // Isolates the canvas from overlay repaint triggers (cursor blink, etc.)
  bool get isRepaintBoundary => true;

  @override
  bool hitTestSelf(Offset p) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    // Ctrl+Scroll → font size up/down
    if (event is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        final newFs = (_theme.fontSize - event.scrollDelta.dy.sign)
            .clamp(_fontSizeMin, _fontSizeMax);
        _applyFontSize(newFs);
      }
      return;
    }

    if (event is PointerDownEvent) {
      _ptrs[event.pointer] = event.localPosition;
      _activePtrs = _ptrs.length;
      if (_activePtrs == 2) {
        _fontSizeBase = _theme.fontSize;
        final pts = _ptrs.values.toList();
        _baseSpan   = (pts[0] - pts[1]).distance;
        // Ponto médio entre os dois dedos = focal do pinch
        _pinchFocal = (pts[0] + pts[1]) / 2;
      }
      return;
    }

    if (event is PointerMoveEvent) {
      _ptrs[event.pointer] = event.localPosition;
      if (_activePtrs >= 2 && _ptrs.length >= 2 && _baseSpan > 0) {
        final pts    = _ptrs.values.toList();
        final span   = (pts[0] - pts[1]).distance;
        // Atualiza o focal para o ponto médio atual dos dedos
        _pinchFocal  = (pts[0] + pts[1]) / 2;
        final newFs  = (_fontSizeBase * span / _baseSpan)
            .clamp(_fontSizeMin, _fontSizeMax);
        _applyFontSize(newFs);
      }
      return;
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _ptrs.remove(event.pointer);
      _activePtrs = _ptrs.length;
      if (_activePtrs < 2) {
        _baseSpan = 0;
        _fontSizeBase = _theme.fontSize;
      }
      return;
    }
  }

  // ── Layout ──────────────────────────────────────────────────────────────

  @override
  void performLayout() {
    final vc      = _vis.length;
    final wordWrap = _ctrl.props.wordWrap;
    size = constraints.biggest;

    if (wordWrap && vc > 0) {
      // ── Incremental wrap-height rebuild ────────────────────────────────
      // _wrapHeights[vi] = pixel height of visual row vi (may be > lh when
      // the line wraps).  On a single-line keystroke only the edited row is
      // re-measured; all others reuse the cached value → O(1) TextPainter
      // layout per keystroke instead of O(vc).  After measuring, we do one
      // O(vc) pass to compute the prefix-sum (cheap float additions).
      final maxW = _codeWidth;
      final cs   = _theme.colorScheme;
      final docV = _ctrl.content.documentVersion;

      // Determine which vis-index needs a fresh TextPainter measurement.
      // -1 means "every row is dirty" (first layout, theme change, etc.).
      final dirtyVi = (_wrapHeights.length == vc) ? _wrapHeightsDirtyVi : -1;

      // Grow / shrink the heights array only when vc changes.
      if (_wrapHeights.length != vc) {
        _wrapHeights = List<double>.filled(vc, lh, growable: false);
      }

      // Measure only the dirty row(s).
      void measureVi(int vi) {
        final ln      = _vis[vi];
        final folded  = _ctrl.isFolded(ln);
        final txt     = _ctrl.content.getLineText(ln);
        final key     = _LCK(ln, docV, folded);
        TextPainter? tp = _lc.remove(key);
        if (tp == null || tp.maxIntrinsicWidth > maxW) {
          tp?.dispose();
          tp = _buildTpWrap(txt, folded,
              _ctrl.styles.spansForLine(folded ? -1 : ln), cs, maxW);
          if (_lc.length >= _lcMax) { final fk = _lc.keys.first; _lc[fk]?.dispose(); _lc.remove(fk); }
        }
        _lc[key] = tp;
        _wrapHeights[vi] = math.max(lh, tp.height);
      }

      if (dirtyVi == -1) {
        // Full rebuild — measure every visible line (first layout / theme change).
        for (int vi = 0; vi < vc; vi++) measureVi(vi);
      } else if (dirtyVi >= 0) {
        // Incremental — measure only the one changed line.
        measureVi(dirtyVi);
      }
      // else dirtyVi == -2 means heights are fresh — just rebuild prefix-sum.
      _wrapHeightsDirtyVi = -2; // heights array is now current

      // Build prefix-sum from the heights array (O(vc) cheap additions).
      final offsets = List<double>.filled(vc + 1, 0.0);
      double acc = 0.0;
      for (int vi = 0; vi < vc; vi++) {
        offsets[vi] = acc;
        acc += _wrapHeights[vi];
      }
      offsets[vc] = acc;
      _wrapOffsets = offsets;
      // Notify gutter painter so it uses the same row heights
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _wrapOffsetsNotifier.value = List<double>.unmodifiable(offsets);
      });

      final totalH = acc + 250;
      _vOff.applyViewportDimension(size.height);
      _vOff.applyContentDimensions(0, math.max(0, totalH - size.height));
      _hOff.applyViewportDimension(size.width);
      _hOff.applyContentDimensions(0, 0); // no horizontal scroll in wrap mode
    } else {
      _wrapOffsets = const [];
      if (_wrapOffsetsNotifier.value.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _wrapOffsetsNotifier.value = const [];
        });
      }
      // Use the larger of _vis.length and actual lineCount so the scroll
      // extent is never stale if _vis hasn't been updated yet after setText().
      // Folds can only REDUCE visible rows, never increase them beyond lineCount.
      final scrollRows = math.max(vc, _ctrl.content.lineCount);
      final totalH = lh * scrollRows + lh * _ghostExtraRows + 250;
      // Max line width: Content.maxLineLength is O(1) amortised — it lazily
      // rescans only when documentVersion advances, cached inside Content itself.
      // No per-layout O(n) scan here at all (the old _cachedMaxLineVersion guard
      // is no longer needed — Content owns the cache now).
      final totalW = _gw + _codePad + _ctrl.content.maxLineLength.toDouble() * cw + 250;
      _vOff.applyViewportDimension(size.height);
      _vOff.applyContentDimensions(0, math.max(0, totalH - size.height));
      _hOff.applyViewportDimension(size.width);
      _hOff.applyContentDimensions(0, math.max(0, totalW - size.width));
    }
  }

  @override
  void paint(PaintingContext ctx, Offset off) {
    final c  = ctx.canvas; final cs = _theme.colorScheme;
    final sY = _vOff.pixels; final sX = _hOff.pixels;
    _rebuildCachedColors(cs, _alpha);
    final vc = _vis.length;
    if (vc == 0) { _pBg.color = cs.background; c.drawRect(off & size, _pBg); return; }

    // Over-scan by 4 rows on each edge — guards against keyboard-resize lag
    // where scroll position briefly lags behind the new viewport height.
    final fl = (_viAtDocY(sY) - 4).clamp(0, vc - 1);
    // size.height is always current (constraints.biggest from performLayout).
    final viewH = size.height;
    final ll = (_viAtDocY(sY + viewH) + 4).clamp(0, vc - 1);

    c.save();
    final vpRect = Rect.fromLTWH(off.dx, off.dy, size.width, viewH);
    c.clipRect(vpRect);

    _pBg.color = cs.background; c.drawRect(vpRect, _pBg);

    // ── Git-diff / per-line style backgrounds ────────────────────────────────
    if (_ctrl.styles.lineStyles.isNotEmpty) _paintLineStyles(c, off, cs, sY, sX, fl, ll);

    if (_ctrl.props.highlightCurrentLine && !_ctrl.cursor.hasSelection) {
      final ci = _vi(_ctrl.cursor.line);
      if (ci >= fl && ci <= ll) {
        final style = _ctrl.props.lineHighlightStyle;
        // Use the active-block highlight color only when highlightActiveBlock is enabled
        final useBlockColor = _activeBlockDepth > 0 && _ctrl.props.highlightActiveBlock;
        final baseColor = useBlockColor
            ? cs.activeBlockLineHighlight : cs.currentLineBackground;
        final rowRect = Rect.fromLTWH(
            off.dx, off.dy + _rowY(ci) - sY, size.width, _rowH(ci));
        switch (style) {
          case LineHighlightStyle.fill:
            _pHl.color = baseColor;
            _pHl.style = PaintingStyle.fill;
            c.drawRect(rowRect, _pHl);
            break;
          case LineHighlightStyle.stroke:
            _pHl.color = useBlockColor ? baseColor : cs.currentRowBorder;
            _pHl.style = PaintingStyle.stroke;
            _pHl.strokeWidth = 1.0;
            c.drawRect(rowRect.deflate(0.5), _pHl);
            _pHl.style = PaintingStyle.fill; // restore default
            break;
          case LineHighlightStyle.accentBar:
            _pHl.color = useBlockColor ? baseColor : cs.cursor;
            _pHl.style = PaintingStyle.fill;
            c.drawRect(Rect.fromLTWH(
                off.dx + _gw, off.dy + _rowY(ci) - sY, 2.0, _rowH(ci)), _pHl);
            break;
          case LineHighlightStyle.none:
            break;
        }
      }
    }
    if (_ctrl.cursor.hasSelection) _paintSel(c, off, cs, sY, sX, fl, ll);
    _paintSearch(c, off, cs, sY, sX, fl, ll);
    if (_symbolHighlight != null) _paintSymbolHighlight(c, off, cs, sY, sX, fl, ll);
    if (_bracketPair != null)     _paintBracketPair(c, off, cs, sY, sX, fl, ll);
    if (_ctrl.props.showBlockLines) _paintBlocks(c, off, cs, sY, sX, fl, ll);
    _paintIndentDots(c, off, sY, sX, fl, ll);
    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= vc) break;
      if (_ctrl.props.showColorDecorators) {
        final matches = _colorMatchesForVi(vi);
        if (matches.isNotEmpty) {
          // Clip-exclude the swatch + gap zones so text is never drawn there.
          // This creates genuine blank space without erasing any background.
          c.save();
          for (final m in matches) {
            final textX  = off.dx + _gw + _codePad + m.start * cw - sX;
            // Exclude: from leftGap before swatch to color-text start.
            final zoneL  = math.max(textX - _swatchSize - _swatchRightGap - _swatchLeftGap,
                                    off.dx + _gw);
            final zoneR  = textX;
            if (zoneR > zoneL) {
              c.clipRect(Rect.fromLTRB(zoneL, off.dy, zoneR, off.dy + size.height),
                         clipOp: ClipOp.difference);
            }
          }
          _paintLine(c, off, cs, vi, sY, sX);
          c.restore();
          continue;
        }
      }
      _paintLine(c, off, cs, vi, sY, sX);
    }
    if (_ctrl.props.showDiagnosticIndicators) _paintDiag(c, off, cs, sY, sX, fl, ll);
    _paintGhostText(c, off, cs, sY, sX, fl, ll);
    if (_showCursor) {
      final ci = _vi(_ctrl.cursor.line);
      if (ci >= fl && ci <= ll) _paintCursor(c, off, cs, sY, sX, ci);
    }
    if (!_ctrl.props.fixedLineNumbers && _gw > 0) _paintGutter(c, off, cs, sY, sX, fl, ll);
    _paintColorDecorators(c, off, sY, sX, fl, ll);
    c.restore();
  }


  /// Paints per-line backgrounds and gutter marker strips from [controller.styles.lineStyles].
  /// Called once per frame before selection/text so backgrounds stay below text.
  void _paintLineStyles(Canvas c, Offset off, EditorColorScheme cs,
      double sY, double sX, int fl, int ll) {
    final ls = _ctrl.styles.lineStyles;
    if (ls.isEmpty) return;
    final vc = _vis.length;
    _pHl.style = PaintingStyle.fill;
    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= vc) break;
      final line  = _vis[vi];
      final style = ls[line];
      if (style == null) continue;
      final y  = off.dy + _rowY(vi) - sY;
      final rh = _rowH(vi);

      // Full-width background tint across code area (right of gutter).
      final bg = style.lineBackground ?? style.backgroundColor;
      if (bg != null) {
        _pHl.color = bg;
        c.drawRect(Rect.fromLTWH(off.dx + _gw, y, size.width - _gw, rh), _pHl);
      }

      // Narrow vertical strip at the right edge of the gutter (like Monaco/VSCode).
      final mc = style.gutterMarkerColor;
      if (mc != null) {
        final mw = style.gutterMarkerWidth.clamp(1.0, 6.0);
        // Gutter slides with horizontal scroll when non-fixed; fixed gutter is a
        // separate RenderObject so the strip is omitted there (it paints its own bg).
        final ox = _ctrl.props.fixedLineNumbers ? off.dx : off.dx - sX;
        _pHl.color = mc;
        c.drawRect(Rect.fromLTWH(ox + _gw - mw, y, mw, rh), _pHl);
      }
    }
    _pHl.style = PaintingStyle.fill; // restore default (was never changed, but be explicit)
  }

  void _paintGutter(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int fl, int ll) {
    // ox: gutter slides LEFT with the horizontal scroll — disappears off-screen
    // when the user scrolls right, exactly like a real non-fixed gutter.
    final ox = off.dx - sX;
    _pGutter.color = cs.lineNumberBackground;
    c.drawRect(Rect.fromLTWH(ox, off.dy, _gw, size.height), _pGutter);
    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= _vis.length) break;
      _gRow(c, ox, off.dy + _rowY(vi) - sY, _vis[vi], cs, _rowH(vi));
    }
    _pLnDiv.color = cs.lineDivider;
    c.drawLine(Offset(ox + _gw, off.dy), Offset(ox + _gw, off.dy + size.height), _pLnDiv);
  }

  // Gutter TextPainter cache: keyed by (line_number, font_size_int, normal_color_value).
  // Avoids creating and laying out a TextPainter for EVERY visible line EVERY frame.
  // Capacity: 512 entries covers a full screen at any reasonable font size.
  final Map<int, TextPainter> _gutterTpCache = {};
  static const int _gutterTpMax = 512;
  int _gutterCacheFs = 0; // invalidate when fontSize changes
  int _gutterCacheColor = 0; // invalidate when theme color changes

  void _gRow(Canvas c, double ox, double y, int line, EditorColorScheme cs, [double? rowHeight]) {
    final rh    = rowHeight ?? lh;
    final hasBP = _ctrl.hasBreakpoint(line);
    final fs    = _theme.fontSize; // mesmo tamanho do código
    final nr    = _ctrl.props.showFoldArrows ? _gw - 18 : _gw - 2;

    if (_ctrl.props.showLineNumbers) {
      final isCur  = line == _ctrl.cursor.line;
      final color  = hasBP ? Colors.white : (isCur ? cs.lineNumberCurrent : cs.lineNumber);
      // Invalidate entire cache when fontSize or base color changes (theme/zoom).
      final fsInt = fs.toInt();
      final colorVal = cs.lineNumber.value;
      if (fsInt != _gutterCacheFs || colorVal != _gutterCacheColor) {
        for (final tp in _gutterTpCache.values) tp.dispose();
        _gutterTpCache.clear();
        _gutterCacheFs    = fsInt;
        _gutterCacheColor = colorVal;
      }
      // Cache key encodes: line number + whether it's current line + has breakpoint.
      // Current line uses a different color so gets its own entry.
      final cacheKey = line * 4 + (isCur ? 1 : 0) + (hasBP ? 2 : 0);
      TextPainter? tp = _gutterTpCache[cacheKey];
      if (tp == null) {
        tp = TextPainter(
          text: TextSpan(text: '${line + 1}', style: TextStyle(
            color: color,
            fontSize: fs, fontFamily: _theme.fontFamily, height: 1.0,
          )),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(4.0, nr - ox));
        if (_gutterTpCache.length >= _gutterTpMax) {
          // Evict oldest entry
          final oldest = _gutterTpCache.keys.first;
          _gutterTpCache[oldest]?.dispose();
          _gutterTpCache.remove(oldest);
        }
        _gutterTpCache[cacheKey] = tp;
      }

      // Mesma fórmula de _paintLine: rowTop + (rowHeight - tp.height) / 2
      // Garante alinhamento perfeito independente de diferenças de métricas.
      final numX = math.max(ox, ox + nr - tp.width);
      final numY = y + (rh - tp.height) / 2;

      if (hasBP) {
        // Circle behind the number, centred on it
        const bpR  = 9.0;
        final bpCy = y + rh / 2;
        final bpCx = numX + tp.width / 2;
        c.drawCircle(Offset(bpCx, bpCy), bpR, _pBp1);
        c.drawCircle(Offset(bpCx, bpCy), bpR, _pBp2);
      }

      c.save();
      c.clipRect(Rect.fromLTWH(ox, y, _gw - 1, rh));
      tp.paint(c, Offset(numX, numY));
      c.restore();
    } else if (hasBP) {
      const bpR = 9.0;
      final cy = y + rh / 2;
      c.drawCircle(Offset(ox + _gw / 2, cy), bpR, _pBp1);
      c.drawCircle(Offset(ox + _gw / 2, cy), bpR, _pBp2);
    }
    if (_ctrl.props.showFoldArrows) _drawArrow(c, ox, y, line, cs, rh);
  }

  void _drawArrow(Canvas c, double ox, double y, int line, EditorColorScheme cs, [double? rowHeight]) {
    final rh = rowHeight ?? lh;
    CodeBlock? blk;
    for (final b in _ctrl.styles.codeBlocks) {
      if (b.startLine == line && b.isFoldable) {
        if (blk == null || b.lineCount > blk.lineCount) blk = b;
      }
    }
    if (blk == null) return;
    final folded = _ctrl.isFolded(line);
    final ax = ox + _gw - 10.0; final ay = y + lh / 2;
    _pArrow.color = cs.lineNumber; final p = _pArrow;
    final path = Path();
    if (folded) { path..moveTo(ax - 3, ay - 4)..lineTo(ax + 3, ay)..lineTo(ax - 3, ay + 4); }
    else        { path..moveTo(ax - 4, ay - 2)..lineTo(ax, ay + 3)..lineTo(ax + 4, ay - 2); }
    c.drawPath(path, p);
  }

  void _paintLine(Canvas c, Offset off, EditorColorScheme cs, int vi, double sY, double sX) {
    final line   = _vis[vi];
    final folded = _ctrl.isFolded(line);
    var   txt    = _ctrl.content.getLineText(line);
    if (txt.isEmpty && !folded) return;
    final key = _LCK(line, _ctrl.content.documentVersion, folded);
    var tp = _lc.remove(key); // LRU: remove first, reinsert as MRU below
    if (tp == null) {
      tp = _ctrl.props.wordWrap
          ? _buildTpWrap(txt, folded, _ctrl.styles.spansForLine(folded ? -1 : line), cs, _codeWidth)
          : _buildTp(txt, folded, _ctrl.styles.spansForLine(folded ? -1 : line), cs);
      if (_lc.length >= _lcMax) { final fk = _lc.keys.first; _lc[fk]?.dispose(); _lc.remove(fk); }
    }
    _lc[key] = tp; // (re)insert as most-recently-used
    final rowTop = off.dy + _rowY(vi) - sY;
    // In word-wrap mode paint at gutter edge (no sX offset — no horiz scroll)
    final textX = _ctrl.props.wordWrap
        ? off.dx + _gw + _codePad
        : off.dx + _gw + _codePad - sX;
    tp.paint(c, Offset(textX, rowTop + (_rowH(vi) - tp.height) / 2));
  }

  /// Strips the trailing block-opener character(s) from a fold's startLine text
  /// so the fold indicator reads "void main()  •••" instead of "void main() {  •••".
  /// Removes the last '{', '(' or ':' and any surrounding whitespace.
  static String _stripFoldOpener(String txt) =>
      QuillNative.stripFoldOpener(txt) ?? _stripFoldOpenerDart(txt);

  static String _stripFoldOpenerDart(String txt) {
    int end = txt.length - 1;
    while (end >= 0 && (txt.codeUnitAt(end) == 32 || txt.codeUnitAt(end) == 9)) end--;
    if (end < 0) return txt;
    final last = txt.codeUnitAt(end);
    if (last == 123 || last == 40 || last == 58) {
      end--;
      while (end >= 0 && (txt.codeUnitAt(end) == 32 || txt.codeUnitAt(end) == 9)) end--;
      return end < 0 ? '' : txt.substring(0, end + 1);
    }
    return txt;
  }

  TextPainter _buildTp(String txt, bool folded, List<CodeSpan> spans, EditorColorScheme cs) {
    final ts = <TextSpan>[];
    if (folded) {
      // Strip trailing block-opener ('{', ':', '(') so e.g. "void main() {"
      // becomes "void main()" — the delimiters are hidden inside the fold.
      txt = _stripFoldOpener(txt);
      if (txt.length > 50) txt = txt.substring(0, 50);
    }
    if (spans.isEmpty) {
      ts.add(TextSpan(text: txt, style: TextStyle(color: cs.textNormal, fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0, letterSpacing: _theme.letterSpacing)));
    } else {
      if (spans.first.column > 0) {
        final pre = txt.substring(0, spans.first.column.clamp(0, txt.length));
        if (pre.isNotEmpty) ts.add(TextSpan(text: pre, style: TextStyle(color: cs.textNormal, fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0, letterSpacing: _theme.letterSpacing)));
      }
      for (int i = 0; i < spans.length; i++) {
        final sp = spans[i]; final nc = i + 1 < spans.length ? spans[i+1].column : txt.length;
        if (sp.column >= txt.length) break; final end = nc.clamp(sp.column, txt.length); if (end <= sp.column) continue;
        ts.add(TextSpan(text: txt.substring(sp.column, end), style: TextStyle(color: _tc(sp.type, cs), fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0, letterSpacing: _theme.letterSpacing, fontWeight: sp.style.bold ? FontWeight.bold : FontWeight.normal, fontStyle: sp.style.italic ? FontStyle.italic : FontStyle.normal)));
      }
    }
    if (folded) ts.add(TextSpan(text: '  •••', style: TextStyle(color: cs.lineNumber.withOpacity(0.6), fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0)));
    if (ts.isEmpty) ts.add(TextSpan(text: ' ', style: TextStyle(fontSize: _theme.fontSize)));
    return TextPainter(text: TextSpan(children: ts), textDirection: TextDirection.ltr)..layout();
  }

  // Variant for word-wrap: lays out with a max width so the text engine wraps.
  TextPainter _buildTpWrap(String txt, bool folded, List<CodeSpan> spans,
      EditorColorScheme cs, double maxWidth) {
    final ts = <TextSpan>[];
    if (folded) {
      txt = _stripFoldOpener(txt);
      if (txt.length > 50) txt = txt.substring(0, 50);
    }
    if (spans.isEmpty) {
      ts.add(TextSpan(text: txt, style: TextStyle(color: cs.textNormal, fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0, letterSpacing: _theme.letterSpacing)));
    } else {
      if (spans.first.column > 0) {
        final pre = txt.substring(0, spans.first.column.clamp(0, txt.length));
        if (pre.isNotEmpty) ts.add(TextSpan(text: pre, style: TextStyle(color: cs.textNormal, fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0, letterSpacing: _theme.letterSpacing)));
      }
      for (int i = 0; i < spans.length; i++) {
        final sp = spans[i]; final nc = i + 1 < spans.length ? spans[i+1].column : txt.length;
        if (sp.column >= txt.length) break; final end = nc.clamp(sp.column, txt.length); if (end <= sp.column) continue;
        ts.add(TextSpan(text: txt.substring(sp.column, end), style: TextStyle(color: _tc(sp.type, cs), fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0, letterSpacing: _theme.letterSpacing, fontWeight: sp.style.bold ? FontWeight.bold : FontWeight.normal, fontStyle: sp.style.italic ? FontStyle.italic : FontStyle.normal)));
      }
    }
    if (folded) ts.add(TextSpan(text: '  •••', style: TextStyle(color: cs.lineNumber.withOpacity(0.6), fontSize: _theme.fontSize, fontFamily: _theme.fontFamily, height: 1.0)));
    if (ts.isEmpty) ts.add(TextSpan(text: ' ', style: TextStyle(fontSize: _theme.fontSize)));
    return TextPainter(text: TextSpan(children: ts), textDirection: TextDirection.ltr)
      ..layout(maxWidth: maxWidth);
  }

  void _paintSel(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int fl, int ll) {
    final sel = _ctrl.cursor.selection; _pSel.color = cs.selectionColor; final p = _pSel;
    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= _vis.length) break; final line = _vis[vi];
      if (line < sel.start.line || line > sel.end.line) continue;
      final ll2 = _ctrl.content.getLineLength(line);
      double x1 = off.dx + _gw + _codePad - sX, x2 = off.dx + _gw + _codePad + ll2 * cw - sX;
      if (line == sel.start.line) x1 = off.dx + _gw + _codePad + sel.start.column * cw - sX;
      if (line == sel.end.line)   x2 = off.dx + _gw + _codePad + sel.end.column   * cw - sX;
      c.drawRect(Rect.fromLTWH(x1, off.dy + _rowY(vi) - sY, (x2 - x1).abs().clamp(2.0, 1e9), _rowH(vi)), p);
    }
  }

  void _paintSearch(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int fl, int ll) {
    final results = _ctrl.searcher.results;
    final curIdx  = _ctrl.searcher.currentResultIndex;
    for (int i = 0; i < results.length; i++) {
      final r  = results[i];
      final vi = _vi(r.start.line); if (vi < fl || vi > ll || vi < 0) continue;
      final x  = off.dx + _gw + _codePad + r.start.column * cw - sX;
      final y  = off.dy + _rowY(vi) - sY;
      final w  = ((r.end.column - r.start.column) * cw).clamp(4.0, 1e9);
      final h  = _rowH(vi);
      final rect = Rect.fromLTWH(x, y, w, h);
      if (i == curIdx) {
        // Current match: brighter fill + border (Monaco-style orange box)
        c.drawRect(rect, _pSearch..style = PaintingStyle.fill..color = cs.searchMatchBorder.withOpacity(0.35));
        c.drawRect(rect, _pSearch..style = PaintingStyle.stroke..strokeWidth = 1.5..color = cs.searchMatchBorder);
        _pSearch.style = PaintingStyle.fill; // reset
      } else {
        c.drawRect(rect, _pSearch..style = PaintingStyle.fill..color = cs.searchMatchBackground);
      }
    }
  }

  // ── Block / indent guide lines — Program VM ─────────────────────────────────

  void _paintBlocks(Canvas c, Offset off, EditorColorScheme cs,
      double sY, double sX, int fl, int ll) {
    final blt    = _theme.blockLines;
    final blocks = _ctrl.styles.codeBlocks;
    if (blocks.isEmpty) return;

    final cursorLine = _ctrl.cursor.line;
    // Use a generous llDocLine so blocks starting near the bottom are never
    // accidentally skipped by the early-exit break.
    final llExtra    = math.min(_vis.length - 1, ll + 10);
    final llDocLine  = _vis.isEmpty ? 0 : _vis[llExtra.clamp(0, _vis.length - 1)];

    // ── Pre-compute active block (O(N) once, not O(N) × visible_blocks) ────
    if (!identical(blocks, _activeCacheBlocks) || _activeCacheCursor != cursorLine) {
      _activeCacheBlocks = blocks;
      _activeCacheCursor = cursorLine;
      _activeCacheResult = _activeBlockForLine(blocks, cursorLine);
    }
    final activeBlock = _activeCacheResult;

    // ── Pre-compute depths (O(N log N) once when blocks change) ────────────
    // Avoids the O(total²) nested loop that was running every paint frame.
    if (!identical(blocks, _depthCacheBlocks)) {
      _depthCacheBlocks = blocks;
      final n = blocks.length;
      final d = List<int>.filled(n, 0);
      // Sort indices by (startLine ASC, endLine DESC) — outer blocks first.
      final idxs = List<int>.generate(n, (i) => i)
        ..sort((ia, ib) {
          final c = blocks[ia].startLine.compareTo(blocks[ib].startLine);
          return c != 0 ? c : blocks[ib].endLine.compareTo(blocks[ia].endLine);
        });
      // One-pass stack sweep: stack holds endLines of active containers.
      final endStack = <int>[];
      for (final idx in idxs) {
        final bl = blocks[idx];
        while (endStack.isNotEmpty && endStack.last < bl.startLine) endStack.removeLast();
        d[idx] = endStack.length;
        endStack.add(bl.endLine);
      }
      _depthCache = d;
    }

    for (int bi = 0; bi < blocks.length; bi++) {
      final b = blocks[bi];
      // Don't break early — blocks might not be strictly sorted and
      // a block starting after llDocLine could still be partially visible.
      if (b.startLine > llDocLine) continue;
      // Don't draw indent guides for folded blocks — their body is hidden and
      // evi returns -1, which would cause the guide to bleed to the bottom of
      // the viewport.
      if (_ctrl.isFolded(b.startLine)) continue;

      final svi = _vi(b.startLine);
      // If the block's start line is hidden inside a folded parent, skip it.
      if (svi < 0) continue;
      final evi = _vi(b.endLine);
      // Skip block only when it's entirely outside the visible range.
      // evi can be -1 when the end line is inside a fold — treat as just-outside.
      final sviClamped = svi;
      final eviClamped = evi < 0 ? ll + 1 : evi;
      if (eviClamped < fl || sviClamped > ll) continue;

      // X position aligned to first non-whitespace character of the opener
      final startText = _ctrl.content.getLineText(b.startLine);
      int firstCharCol = 0;
      for (int ci = 0; ci < startText.length; ci++) {
        if (startText[ci] != ' ' && startText[ci] != '\t') { firstCharCol = ci; break; }
      }
      final x = off.dx + _gw + _codePad + firstCharCol * cw - sX;
      // Y coordinates — use the actual visual row, clamped to what exists.
      // Negative y1 / y2 > viewport-height are fine; canvas.clipRect handles them.
      final startViActual = svi >= 0 ? svi : 0;
      final endViActual   = evi >= 0 ? math.min(evi, _vis.length - 1)
                                      : math.min(ll, _vis.length - 1);
      // Guide starts at BOTTOM of the opener row (below the `{`)
      final y1 = off.dy + _rowY(startViActual) + _rowH(startViActual) - sY;
      // Guide ends at the TOP of the closer row
      final y2 = off.dy + _rowY(endViActual) - sY;
      if (y2 <= y1) continue;

      // ── Active block and depth (pre-computed before loop) ───────────
      final isActive = identical(b, activeBlock);
      final depth    = bi < _depthCache.length ? _depthCache[bi] : 0;

      Color lineColor;
      if (isActive) {
        // Use the scheme's semantic "active block line" color — it is already
        // calibrated per-theme to be distinct from the cursor color.
        lineColor = cs.blockLineActive;
      } else if (blt.colorMode == BlockLineColorMode.rainbow && blt.rainbowColors.isNotEmpty) {
        lineColor = blt.rainbowColors[depth % blt.rainbowColors.length];
        lineColor = lineColor.withOpacity((lineColor.opacity * blt.inactiveOpacity).clamp(0.0, 1.0));
      } else {
        lineColor = blt.color.withOpacity((blt.color.opacity * blt.inactiveOpacity).clamp(0.0, 1.0));
      }

      final strokeWidth = isActive ? blt.resolvedActiveWidth : blt.width;
      final prog = isActive ? blt.resolvedActiveProgram : blt.resolvedProgram;

      // Skip only if the entire guide (including any openCurve underline) is off-screen left.
      final xMax = x + (prog.hasStartCap ? lh * 20.0 : 0.0);
      if (xMax < off.dx) continue;

      if (prog.ops.isEmpty && !prog.hasEndCap) continue;

      final paint = Paint()
        ..color       = lineColor
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round;

      // ── Smart endCap: only draw arc+tick when } is to the RIGHT of x ───
      // Get the indent column of the closing `}` line.
      final closerText = _ctrl.content.getLineText(b.endLine);
      int closerCol = 0;
      for (int ci = 0; ci < closerText.length; ci++) {
        if (closerText[ci] != ' ' && closerText[ci] != '\t') { closerCol = ci; break; }
      }
      final closerX = off.dx + _gw + _codePad + closerCol * cw - sX;

      // If `}` is AT or LEFT of guide x → strip the endCap.
      final bool stripEndCap = prog.hasEndCap && closerX <= x + 1.0;

      // For openCurve startCap: compute the ACTUAL tick so the underline
      // extends from x all the way to below the last char of the opener line.
      // openerLineLen * cw = pixel width of the opener text.
      IndentLineProgram effectiveProg = prog;
      if (prog.hasStartCap && prog.startCap.type == IndentCapType.openCurve) {
        final openerLen  = _ctrl.content.getLineLength(b.startLine);
        // xEnd of text = x + (openerLen - firstCharCol) * cw
        // tick = (openerLen - firstCharCol) * cw, clamped to at least radius
        final dynamicTick = ((openerLen - firstCharCol) * cw)
            .clamp(prog.startCap.radius + 2.0, double.infinity).toDouble();
        final newStartCap = IndentLineCap(
          type:   IndentCapType.openCurve,
          radius: prog.startCap.radius,
          tick:   dynamicTick,
        );
        effectiveProg = IndentLineProgram(
          ops:      prog.ops,
          startCap: newStartCap,
          endCap:   stripEndCap ? IndentLineCap.none : prog.endCap,
        );
      } else if (stripEndCap) {
        effectiveProg = IndentLineProgram(
          ops:      prog.ops,
          endCap:   IndentLineCap.none,
          startCap: prog.startCap,
        );
      }

      // ── Guide "cut" logic ───────────────────────────────────────────────
      // Only inspect rows that are actually visible (clamped to [fl, ll]).
      // Rows outside the viewport are clipped by the canvas anyway, so
      // iterating them would burn CPU for zero visual benefit — and for
      // blocks that span the entire file this was O(lineCount) per block!
      final segs = <(double, double)>[];
      {
        double segStart = y1;
        bool drawing = true;
        final viStart = math.max(startViActual + 1, fl);
        final viEnd   = math.min(endViActual, ll + 1);
        for (int vi = viStart; vi < viEnd; vi++) {
          if (vi >= _vis.length) break;
          final lt = _ctrl.content.getLineText(_vis[vi]);
          final blocked = firstCharCol < lt.length &&
              lt[firstCharCol] != ' ' && lt[firstCharCol] != '\t';
          final rowTop = off.dy + _rowY(vi) - sY;
          final rowBot = rowTop + _rowH(vi);
          if (blocked) {
            if (drawing && segStart < rowTop) segs.add((segStart, rowTop));
            drawing = false;
            segStart = rowBot;
          } else if (!drawing) {
            segStart = rowTop;
            drawing = true;
          }
        }
        if (drawing && segStart < y2) segs.add((segStart, y2));
      }
      if (segs.isEmpty) segs.add((y1, y2));

      for (int si = 0; si < segs.length; si++) {
        final sy = segs[si].$1;
        final ey = segs[si].$2;
        if (ey <= sy) continue;
        final isFirst = si == 0;
        final isLast  = si == segs.length - 1;
        final segProg = (isFirst && isLast)
            ? effectiveProg
            : IndentLineProgram(
                ops:      effectiveProg.ops,
                startCap: isFirst ? effectiveProg.startCap : IndentLineCap.none,
                endCap:   isLast  ? effectiveProg.endCap   : IndentLineCap.none,
              );
        _execProgram(c, x, sy, ey, segProg, paint, closerX: closerX);
      }
    }
  }

  // ── Active block helper ──────────────────────────────────────────────────────

  /// Returns the SINGLE block that should be highlighted as active for [cursorLine].
  ///
  /// Rules (in priority order):
  ///   1. Cursor strictly inside (start < cursor < end): innermost (smallest span) wins.
  ///   2. Cursor on the OPENER line (==startLine): that block is active.
  ///   3. Cursor on the CLOSER line (==endLine): the ENCLOSING block is active
  ///      (cursor is "outside" this block).
  ///   4. No match: returns null (all lines inactive).
  CodeBlock? _activeBlockForLine(List<CodeBlock> blocks, int cursorLine) {
    // Collect blocks where cursor is strictly inside or on the opener.
    CodeBlock? best;
    int bestSpan = 1 << 30;

    for (final b in blocks) {
      final onOpener     = cursorLine == b.startLine;
      final strictInside = cursorLine > b.startLine && cursorLine < b.endLine;
      if (!onOpener && !strictInside) continue;

      final span = b.endLine - b.startLine;
      if (span < bestSpan) {
        bestSpan = span;
        best     = b;
      }
    }
    return best;
  }

    // ── Program executor ───────────────────────────────────────────────────────

  void _execProgram(Canvas c, double x, double y1, double y2,
      IndentLineProgram prog, Paint paint, {double closerX = double.infinity}) {
    // capReserve = arc radius so fill stops at y2-r.
    // The arc (x,y2-r)→(x+r,y2) and tick fit entirely above/at y2 — no overlap with `}`.
    final capReserve = (prog.hasEndCap && prog.endCap.type == IndentCapType.curve)
        ? prog.endCap.radius.clamp(2.0, lh * 0.4)
        : 0.0;
    final drawEnd = (y2 - capReserve).clamp(y1, y2);

    // Draw start cap FIRST (e.g. underline + corner at opener row).
    // For openCurve, the arc ends at y1+r — ops must start there, not y1.
    double yOpsStart = y1;
    if (prog.hasStartCap) {
      _execStartCap(c, x, y1, prog.startCap, paint);
      if (prog.startCap.type == IndentCapType.openCurve) {
        yOpsStart = y1 + prog.startCap.radius.clamp(2.0, lh * 0.45);
      }
    }

    if (prog.ops.isEmpty) {
      if (prog.hasEndCap) _execEndCap(c, x, y2, drawEnd, closerX, prog.endCap, paint);
      return;
    }

    final hasFill = prog.ops.any((o) => switch (o) {
      OpLine(:final fill) when fill   => true,
      OpWave(:final fill) when fill   => true,
      OpZigzag(:final fill) when fill => true,
      _ => false,
    });

    double y = yOpsStart;
    bool done = false;
    int guard = 0;
    while (!done && y < drawEnd - 0.5 && guard++ < 2000) {
      for (final op in prog.ops) {
        if (done || y >= drawEnd - 0.5) break;
        _execOp(c, x, y, drawEnd, op, paint, (ny, d) { y = ny; if (d) done = true; });
      }
      if (hasFill) done = true;
    }

    if (prog.hasEndCap) _execEndCap(c, x, y2, drawEnd, closerX, prog.endCap, paint);
  }

  void _execOp(Canvas c, double x, double y, double yMax, IndentLineOp op,
      Paint paint, void Function(double, bool) advance) {
    switch (op) {
      case OpLine(:final fill, :final length):
        final len = fill ? yMax - y : math.min(length, yMax - y);
        if (len > 0) c.drawLine(Offset(x, y), Offset(x, y + len), paint);
        advance(y + len, fill);

      case OpGap(:final length):
        advance(y + math.min(length, yMax - y), false);

      case OpDot(:final radius, :final square, :final gap):
        final cy = y + radius;
        if (cy + radius <= yMax) {
          final dp = Paint()..color = paint.color..style = PaintingStyle.fill;
          if (square) {
            c.drawRect(Rect.fromCenter(center: Offset(x, cy), width: radius*2, height: radius*2), dp);
          } else {
            c.drawCircle(Offset(x, cy), radius, dp);
          }
        }
        advance(y + radius * 2 + gap, false);

      case OpWave(:final fill, :final height, :final period, :final amplitude, :final phase):
        final h = fill ? yMax - y : math.min(height, yMax - y);
        if (h > 0) {
          // Ensure at least 8 samples per wavelength to avoid aliasing on tall blocks.
          final steps = math.max(32, (h / period * 8).ceil());
          final path = Path()..moveTo(x, y);
          for (int i = 1; i <= steps; i++) {
            final t = i / steps;
            path.lineTo(
              x + math.sin(phase + t * 2 * math.pi * h / period) * amplitude,
              y + h * t,
            );
          }
          c.drawPath(path, paint);
        }
        advance(y + h, fill);

      case OpZigzag(:final fill, :final height, :final period, :final amplitude):
        final h = fill ? yMax - y : math.min(height, yMax - y);
        if (h > 0) {
          final path = Path()..moveTo(x, y);
          double cy = y; bool right = true; final half = period / 2;
          while (cy < y + h) {
            final ny = math.min(cy + half, y + h);
            path.lineTo(x + (right ? amplitude : -amplitude), ny);
            cy = ny; right = !right;
          }
          c.drawPath(path, paint);
        }
        advance(y + h, fill);

      case OpArrow(:final size, :final gap):
        final ay = y + size;
        if (ay + size <= yMax) {
          c.drawPath(Path()
            ..moveTo(x - size, ay - size)
            ..lineTo(x, ay)
            ..lineTo(x + size, ay - size), paint);
        }
        advance(y + size * 2 + gap, false);

      case OpCross(:final size, :final gap):
        final cy = y + size;
        if (cy + size <= yMax) {
          c.drawLine(Offset(x - size, cy - size), Offset(x + size, cy + size), paint);
          c.drawLine(Offset(x + size, cy - size), Offset(x - size, cy + size), paint);
        }
        advance(y + size * 2 + gap, false);
    }
  }

  void _execEndCap(Canvas c, double x, double y2, double fillEnd,
      double closerX, IndentLineCap cap, Paint paint) {
    switch (cap.type) {
      case IndentCapType.none:
        return;

      case IndentCapType.curve:
        // The arc+tick end at the VERTICAL MIDDLE of the `}` row (yMid = y2 + lh*0.5).
        // Space available for a horizontal tick = closerX - (x + r) - 2px margin.
        // Three tiers based on available horizontal space:
        //
        //  NO space  (space <= 0):  arc only, ends exactly at (x+r, yMid). No tick.
        //  1 char    (space > 0):   arc + short tick proportional to space.
        //  Full      (space >= cap.tick): arc + full tick.
        //
        // The arc:  (x, y2-r) --CCW--> (x+r, yMid)
        //   This is a quarter-ellipse from the bottom of the vertical line
        //   to the midpoint of the `}` row. Uses arcToPoint with large arc
        //   since y-delta (lh*0.5) ≠ x-delta (r) — we use cubicTo for smooth curve.
        //
        // Actually: to hit BOTH (x+r, yMid) with a smooth curve from (x, y2-r):
        //   Use quadraticBezierTo: control=(x,yMid), end=(x+r,yMid)
        //   This gives a smooth quarter-curve hugging the corner.
        final r    = cap.radius.clamp(2.0, lh * 0.4);
        final yMid = y2 + lh * 0.5;          // vertical middle of `}` row
        final arcEndX  = x + r;               // where arc ends horizontally
        final margin   = 2.0;                 // px before `}` character
        final maxRight = closerX.isFinite
            ? closerX - margin               // stop before `}` 
            : x + r + cap.tick;              // or theme max
        final spaceForTick = maxRight - arcEndX;  // available horizontal space

        // Build path: fill line connects, arc curves, tick extends into space.
        final path = Path()..moveTo(x, y2 - r);
        // Smooth curve from (x, y2-r) to (x+r, yMid) using quadratic bezier.
        // Control point at (x, yMid) gives a clean rounded corner.
        // Cubic bezier gives a much smoother, rounder corner than quadratic.
        // cp1 pulls straight down, cp2 transitions smoothly rightward.
        path.cubicTo(x, yMid, x + r * 0.5, yMid, arcEndX, yMid);

        if (spaceForTick > 0.5) {
          // Has some horizontal space: draw tick, clamped to available space.
          final tickLen = math.min(spaceForTick, cap.tick.toDouble());
          path.lineTo(arcEndX + tickLen, yMid);
        }
        // If spaceForTick <= 0, arc ends at (arcEndX, yMid) — no tick needed.

        c.drawPath(path, paint);

      case IndentCapType.lShape:
        final yMid = y2 - _rowH(0) * 0.5;
        final drawTop = cap.where == 'top'    || cap.where == 'both';
        final drawBot = cap.where == 'bottom' || cap.where == 'both';
        if (drawTop) c.drawLine(Offset(x, y2 - _rowH(0)), Offset(x + cap.tick, y2 - _rowH(0)), paint);
        if (drawBot) c.drawLine(Offset(x, yMid), Offset(x + cap.tick, yMid), paint);

      case IndentCapType.arrow:
        // Arrow points to the MIDDLE of the `}` row.
        // y2 = TOP of `}` row → middle = y2 + lh*0.5
        final yMid = y2 + lh * 0.5;
        final s    = cap.size;
        c.drawPath(Path()
          ..moveTo(x, yMid - s)
          ..lineTo(x + s * 1.5, yMid)
          ..lineTo(x, yMid + s), paint);

      case IndentCapType.openCurve:
        return; // openCurve is a startCap only — no-op when used as endCap
    }
  }


  void _execStartCap(Canvas c, double x, double y1,
      IndentLineCap cap, Paint paint) {
    switch (cap.type) {
      case IndentCapType.none:
      case IndentCapType.curve:
      case IndentCapType.lShape:
      case IndentCapType.arrow:
        return; // these are end-caps only — no-op when used as startCap

      case IndentCapType.openCurve:
        // Draws the underline + top-left corner of the indent guide:
        //
        //   code: void main() {           ← opener row
        //         ─────────────┐          ← underline at BOTTOM of opener row,
        //                      │            from x+tick (right) going LEFT to x,
        //                      │            then CW arc turning DOWN at (x, y1+r)
        //                      │          ← ops (OpLine fill) continue here
        //
        //  y1 = bottom of opener row (= just below the `{` character)
        //  Underline: (x+tick, y1) ──── (x+r, y1)
        //  Arc CW:    (x+r, y1) → (x, y1+r)
        //    centre = (x, y1); start=0°(east); end=90°(south-in-screen) → CW ✓
        final r    = cap.radius.clamp(2.0, lh * 0.45);
        final xEnd = x + cap.tick;  // right end of underline
        c.drawPath(Path()
          ..moveTo(xEnd, y1)         // start at right end of underline
          ..lineTo(x + r, y1)        // go LEFT along underline to arc start
          ..arcToPoint(              // CW 90°: right→down = top-left corner ┐
              Offset(x, y1 + r),
              radius: Radius.circular(r),
              clockwise: false,      // CCW with center (x+r,y1+r): gives ┐ shape ✓
            ),
          paint);
    }
  }

    /// Paints whitespace indicator dots before the first non-whitespace character
  /// of each visible line, using the IndentDotTheme settings.
  void _paintIndentDots(Canvas c, Offset off, double sY, double sX, int fl, int ll) {
    final idt = _theme.indentDots;
    if (!idt.visible) return;

    final dotPaint = Paint()..color = idt.color..style = PaintingStyle.fill;
    final r = idt.size / 2;

    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= _vis.length) break;
      final line    = _vis[vi];
      final lineText = _ctrl.content.getLineText(line);
      if (lineText.isEmpty) continue;

      final rowTop = off.dy + _rowY(vi) - sY;
      final midY   = rowTop + _rowH(vi) / 2;

      int limit;
      if (idt.mode == IndentDotMode.indentOnly) {
        // Only leading whitespace up to first non-whitespace char
        limit = 0;
        while (limit < lineText.length &&
               (lineText[limit] == ' ' || lineText[limit] == '\t')) {
          limit++;
        }
      } else {
        limit = lineText.length;
      }

      for (int ci = 0; ci < limit; ci++) {
        final ch = lineText[ci];
        if (ch != ' ' && ch != '\t') break;
        // Draw a dot centered at the column position
        final cx = off.dx + _gw + _codePad + ci * cw - sX + cw / 2;
        // Avoid drawing outside left boundary
        if (cx < off.dx + _gw) continue;
        c.drawCircle(Offset(cx, midY), r, dotPaint);
      }
    }
  }

  void _paintDiag(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int fl, int ll) {
    for (final d in _ctrl.diagnostics.all) {
      final vi = _vi(d.range.start.line); if (vi < fl || vi > ll || vi < 0) continue;
      final y  = off.dy + _rowY(vi) - sY + lh * 0.84;
      final x1 = off.dx + _gw + _codePad + d.range.start.column * cw - sX;
      final ec = d.range.end.column > d.range.start.column ? d.range.end.column : d.range.start.column + 4;
      final col = d.severity == DiagnosticSeverity.error ? cs.problemError
          : d.severity == DiagnosticSeverity.warning ? cs.problemWarning : cs.problemTypo;
      _squig(c, x1, off.dx + _gw + _codePad + ec * cw - sX, y, col);
    }
  }

  void _squig(Canvas c, double x1, double x2, double y, Color col) {
    const wl = 4.5, amp = 1.8; final path = Path()..moveTo(x1, y);
    bool up = false; double x = x1;
    while (x < x2) { final nx = math.min(x + wl, x2); path.quadraticBezierTo((x+nx)/2, y+(up?-amp:amp), nx, y); up=!up; x=nx; }
    _pDiag.color = col; c.drawPath(path, _pDiag);
  }

  // ── Color decorators ──────────────────────────────────────────────────────
  // Per-line color cache (in RenderBox to avoid extra prop plumbing).
  final Map<int, List<ColorMatch>> _colorDecoCache = {};
  int _colorDecoCacheVer = -1;

  List<ColorMatch> _colorMatchesForVi(int vi) {
    if (vi >= _vis.length) return const [];
    final line = _vis[vi];
    final ver  = _ctrl.content.documentVersion;
    if (ver != _colorDecoCacheVer) { _colorDecoCache.clear(); _colorDecoCacheVer = ver; }
    return _colorDecoCache.putIfAbsent(line,
        () => ColorDetector.detect(_ctrl.content.getLineText(line)));
  }

  void _paintColorDecorators(Canvas c, Offset off, double sY, double sX, int fl, int ll) {
    if (!_ctrl.props.showColorDecorators) return;
    final fill   = Paint()..style = PaintingStyle.fill;
    final border = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.7
        ..color = const Color(0x66000000);
    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= _vis.length) break;
      final matches = _colorMatchesForVi(vi);
      if (matches.isEmpty) continue;
      final rowTop = off.dy + _rowY(vi) - sY;
      final cy     = rowTop + (_rowH(vi) - _swatchSize) / 2;
      for (final m in matches) {
        final textX = off.dx + _gw + _codePad + m.start * cw - sX;
        final sx    = textX - _swatchSize - _swatchRightGap - _swatchLeftGap;
        if (sx + _swatchSize < off.dx + _gw) continue; // scrolled behind gutter
        // Text in [sx - leftGap .. textX] was already clipped out in the paint
        // loop above, so no erase needed — just draw the swatch.
        final rect = Rect.fromLTWH(sx, cy, _swatchSize, _swatchSize);
        final rr   = RRect.fromRectAndRadius(rect, const Radius.circular(2));
        fill.color = m.color;
        c.drawRRect(rr, fill);
        c.drawRRect(rr, border);
      }
    }
  }

  void _paintCursor(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int vi) {
    final x = off.dx + _gw + _codePad + _ctrl.cursor.column * cw - sX;
    final y = off.dy + _rowY(vi) - sY;
    _pCursor.color       = _cachedCursorColor;
    _pCursor.strokeWidth = _theme.cursorWidth;
    c.drawLine(Offset(x, y + 1), Offset(x, y + _rowH(vi) - 1), _pCursor);
  }

  // ── Ghost text (inline suggestions) ─────────────────────────────────────
  //
  // VSCode Copilot-style multi-line ghost text:
  //
  //   Line 0 (cursor line):  drawn after the cursor, on the same row.
  //   Lines 1..N (extra):    drawn in VIRTUAL rows inserted below the cursor line.
  //                          _rowY() already shifts real content down by N*lh,
  //                          so ghost lines occupy exactly that gap.
  //
  // The first ghost line only shows the COMPLETION (linePrefix already stripped
  // by GhostTextController._stripPrefix), so there is no duplication of what
  // the user already typed.
  void _paintGhostText(Canvas c, Offset off, EditorColorScheme cs,
      double sY, double sX, int fl, int ll) {
    final ghost = _ctrl.ghostText;
    if (!ghost.isVisible) return;

    final atLine = ghost.atLine;
    final vi     = _vi(atLine);
    if (vi < 0) return;

    final lines    = ghost.ghostLines;
    final ghostCol = ghost.atColumn;
    final fgColor  = cs.ghostTextForeground;
    final textStyle = TextStyle(
      color:      fgColor,
      fontSize:   _theme.fontSize,
      fontFamily: _theme.fontFamily,
      fontStyle:  FontStyle.italic,
    );

    // Background tint for multi-line ghost block (helps distinguish from real code).
    _pBg.color = _cachedGhostBgColor; // reuse cached paint — no alloc

    for (int gi = 0; gi < lines.length; gi++) {
      final ghostLine = lines[gi];

      double y;
      double x;

      if (gi == 0) {
        // ── Cursor line: render completion after cursor position ──────────
        if (vi < fl || vi > ll) continue;
        y = off.dy + _rowY(vi) - sY;
        x = off.dx + _gw + _codePad + ghostCol * cw - sX;
      } else {
        // ── Virtual lines: occupy the gap created by _rowY shift ──────────
        // These rows sit at vi*lh + gi*lh in content space (shifted below
        // the cursor line, before the first real line after the cursor).
        final virtualY = _rowY(vi) + gi * lh;   // content-space Y
        y = off.dy + virtualY - sY;
        x = off.dx + _gw + _codePad - sX;

        // Clip: don't paint outside the visible viewport
        if (y + lh < off.dy || y > off.dy + size.height) continue;

        // Tint the background of virtual rows
        c.drawRect(
          Rect.fromLTWH(off.dx + _gw, y, size.width - _gw, lh),
          _pBg,
        );
      }

      if (ghostLine.isEmpty) continue;   // empty line — tint already drawn

      final tp = TextPainter(
        text: TextSpan(text: ghostLine, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(x, y + (lh - tp.height) / 2));
    }

    // Hint pill: drawn ABOVE the cursor line so it never overlaps ghost code.
    // Rendered only when the cursor row is visible.
    if (lines.isNotEmpty && vi >= fl && vi <= ll) {
      final hint = lines.length > 1
          ? "Tab: aceitar  •  Esc: cancelar  •  ${lines.length} linhas"
          : "Tab: aceitar  •  Esc: cancelar";
      final hintStyle = TextStyle(
        color:      cs.ghostTextForeground.withOpacity(0.75),
        fontSize:   _theme.fontSize * 0.68,
        fontFamily: _theme.fontFamily,
        fontStyle:  FontStyle.normal,
        fontWeight: FontWeight.w500,
      );
      final hintTp = TextPainter(
        text: TextSpan(text: hint, style: hintStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      const padH = 6.0;
      const padV = 3.0;
      final pillW = hintTp.width  + padH * 2;
      final pillH = hintTp.height + padV * 2;

      // Position: top-right corner of the viewport, 8px margin from edges.
      final pillX = off.dx + size.width - pillW - 10;
      final pillY = off.dy + 6;

      // Pill background
      final pillPaint = Paint()
        ..color = cs.lineNumberBackground.withOpacity(0.92);
      final borderPaint = Paint()
        ..color = cs.ghostTextForeground.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillW, pillH),
        const Radius.circular(4),
      );
      c.drawRRect(rrect, pillPaint);
      c.drawRRect(rrect, borderPaint);
      hintTp.paint(c, Offset(pillX + padH, pillY + padV));
    }
  }

  void _paintSymbolHighlight(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int fl, int ll) {
    final r = _symbolHighlight; if (r == null) return;
    final vi = _vi(r.start.line);
    if (vi < 0 || vi < fl || vi > ll) return;
    final y  = off.dy + _rowY(vi) - sY;
    final x1 = off.dx + _gw + _codePad + r.start.column * cw - sX;
    final x2 = off.dx + _gw + _codePad + r.end.column   * cw - sX;
    if (x2 <= x1) return;
    _pSymH1.color = _cachedSymH1Color;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x1, y + 2, x2 - x1, _rowH(vi) - 4), const Radius.circular(3)), _pSymH1);
    _pSymH2.color = _cachedSymH2Color;
    c.drawLine(Offset(x1, y + lh - 2), Offset(x2, y + lh - 2), _pSymH2);
  }

  void _paintBracketPair(Canvas c, Offset off, EditorColorScheme cs, double sY, double sX, int fl, int ll) {
    final bp  = _bracketPair; if (bp == null) return;
    final bpt = _theme.bracketPair;
    // Props can still override theme for per-instance customisation.
    final fillColor   = _ctrl.props.bracketPairFillColor   ?? bpt.fillColor;
    final borderColor = _ctrl.props.bracketPairBorderColor ?? bpt.borderColor;
    final radius      = Radius.circular(bpt.radius);

    _pBracket2.strokeWidth = bpt.borderWidth;

    void drawBracketRect(CharPosition pos) {
      final vi = _vi(pos.line);
      if (vi < fl || vi > ll || vi < 0) return;
      final y    = off.dy + _rowY(vi) - sY;
      final x    = off.dx + _gw + _codePad + pos.column * cw - sX;
      final rect = Rect.fromLTWH(x, y + 1, cw, _rowH(vi) - 2);
      _pBracket1.color = fillColor;
      c.drawRRect(RRect.fromRectAndRadius(rect, radius), _pBracket1);
      _pBracket2.color = borderColor;
      c.drawRRect(RRect.fromRectAndRadius(rect, radius), _pBracket2);
    }
    drawBracketRect(bp.open);
    drawBracketRect(bp.close);
  }

  // Direct TokenType → Color, no String allocation, no double dispatch.
  Color _tc(TokenType t, EditorColorScheme cs) {
    switch (t) {
      case TokenType.keyword:     return cs.keyword;
      case TokenType.comment:     return cs.comment;
      case TokenType.string:      return cs.string;
      case TokenType.number:      return cs.number;
      case TokenType.operator_:   return cs.operator_;
      case TokenType.identifier:  return cs.identifier;
      case TokenType.function_:   return cs.function_;
      case TokenType.type_:       return cs.type_;
      case TokenType.annotation:  return cs.annotation;
      case TokenType.literal:     return cs.literal;
      case TokenType.htmlTag:     return cs.htmlTag;
      case TokenType.attrName:    return cs.attrName;
      case TokenType.attrValue:   return cs.attrValue;
      case TokenType.preprocessor:return cs.preprocessor;
      case TokenType.constant:    return cs.constant;
      case TokenType.namespace:   return cs.namespace;
      case TokenType.label:       return cs.label;
      case TokenType.punctuation: return cs.punctuation;
      default:                    return cs.textNormal;
    }
  }

  @override
  void dispose() {
    _vOff.removeListener(markNeedsPaint); _hOff.removeListener(markNeedsPaint);
    _ctrl.content.removeListener(_onContentChange);
    _ctrl.removeListener(_dirty);
    _ctrl.decorVersion.removeListener(markNeedsPaint);
    _ctrl.tokenizationVersion.removeListener(_onTokenizationDone);
    _ctrl.ghostText.removeListener(_onGhostChanged);
    for (final tp in _lc.values) tp.dispose(); _lc.clear();
    for (final tp in _gutterTpCache.values) tp.dispose(); _gutterTpCache.clear();
    super.dispose();
  }
}

class _LCK { final int line, v; final bool folded; const _LCK(this.line, this.v, this.folded); @override bool operator ==(Object o) => o is _LCK && o.line == line && o.v == v && o.folded == folded; @override int get hashCode => Object.hash(line, v, folded); }

// ═══════════════════════════════════════════════════════════════════════════
// Fixed gutter painter
// ═══════════════════════════════════════════════════════════════════════════
class _GutterPainter extends CustomPainter {
  final QuillCodeController controller;
  final EditorTheme theme;
  final double gw, scrollY, elevation;
  final List<int> vis;
  final double zoom;
  final double lineHeightZoomed;
  final List<double> wrapOffsets; // empty = no wrap
  // Ghost text layout — keeps fold-arrow Y in sync with the canvas
  final int ghostInsertVi;
  final int ghostExtraRows;

  // Cached Paints — allocated once per painter instance (not const-constructed)
  final _pBg   = Paint();
  final _pDiv  = Paint()..strokeWidth = 1.0;
  final _pBp1  = Paint()..color = const Color(0xFFEF5350);
  final _pBp2  = Paint()..color = const Color(0xFFB71C1C)..style = PaintingStyle.stroke..strokeWidth = 1.2;
  final _pArr  = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
  final _pElev = Paint();
  double _cachedElevation = -1;
  Rect?  _cachedElevRect;

  _GutterPainter({
    required this.controller, required this.theme, required this.gw,
    required this.scrollY,
    required this.elevation, required this.vis,
    required this.zoom, required this.lineHeightZoomed,
    this.wrapOffsets = const [],
    this.ghostInsertVi  = -1,
    this.ghostExtraRows = 0,
  });

  double get lhU => theme.lineHeightPx; // unscaled line height

  /// Row Y in screen space, matching _EBox._rowY logic.
  double _rowY(int vi, double lhS) {
    if (wrapOffsets.length > vi) {
      final base = wrapOffsets[vi];
      return (ghostInsertVi >= 0 && vi > ghostInsertVi
          ? base + ghostExtraRows * lhS
          : base) - scrollY;
    }
    return (ghostInsertVi >= 0 && vi > ghostInsertVi
        ? vi * lhS + ghostExtraRows * lhS
        : vi * lhS) - scrollY;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cs  = theme.colorScheme;
    // zoom carries the actual fontSize; derive screen line height from it
    final lhS = zoom * theme.lineHeight;

    _pBg.color = cs.lineNumberBackground; canvas.drawRect(Offset.zero & size, _pBg);

    if (elevation > 0.005) {
      final sw = (18 * elevation).clamp(0.0, 18.0);
      final r  = Rect.fromLTWH(gw, 0, sw, size.height);
      if ((elevation - _cachedElevation).abs() > 0.01 || _cachedElevRect != r) {
        _cachedElevation = elevation;
        _cachedElevRect  = r;
        _pElev.shader = LinearGradient(
          colors: [Colors.black.withOpacity(0.24 * elevation), Colors.transparent],
        ).createShader(r);
      }
      canvas.drawRect(r, _pElev);
    }

    // Compute fl/ll here so they always reflect the CURRENT vis.length.
    // Calculating them outside (in the builder) risks stale clamp values
    // when a fold changes vis.length between the builder and paint calls.
    final vLen = vis.length;
    int fl, ll;
    if (wrapOffsets.length >= vLen + 1) {
      // Word-wrap: binary search in wrapOffsets
      fl = 0;
      while (fl < vLen - 1 && wrapOffsets[fl + 1] <= scrollY) fl++;
      ll = fl;
      while (ll < vLen - 1 && wrapOffsets[ll] < scrollY + size.height) ll++;
    } else {
      fl = (scrollY / lhS).floor().clamp(0, math.max(0, vLen - 1)).toInt();
      ll = ((scrollY + size.height) / lhS).ceil().clamp(0, math.max(0, vLen - 1)).toInt();
    }

    for (int vi = fl; vi <= ll; vi++) {
      if (vi >= vLen) break;
      double rowY, rowH;
      if (wrapOffsets.length > vi + 1) {
        // word-wrap uses stored offsets + ghost shift
        rowY = _rowY(vi, lhS);
        rowH = wrapOffsets[vi + 1] - wrapOffsets[vi];
      } else {
        rowY = _rowY(vi, lhS);
        rowH = lhS;
      }
      _row(canvas, cs, vis[vi], rowY, rowH);
    }

    _pDiv.color = cs.lineDivider; canvas.drawLine(Offset(gw, 0), Offset(gw, size.height), _pDiv);
  }

  void _row(Canvas canvas, EditorColorScheme cs, int line, double y, double lhS) {
    final hasBP = controller.hasBreakpoint(line);
    final isCur = line == controller.cursor.line;
    final fs    = zoom; // mesmo tamanho do código — alinhamento garantido
    // Right-align position (same whether or not there is a breakpoint)
    final nr    = controller.props.showFoldArrows ? gw - 18 : gw - 2;
    if (controller.props.showLineNumbers) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${line + 1}',
          style: TextStyle(
            color: hasBP ? Colors.white : (isCur ? cs.lineNumberCurrent : cs.lineNumber),
            fontSize: fs,
            fontFamily: theme.fontFamily,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(4.0, nr));

      // Mesma fórmula de _paintLine: y + (rowHeight - tp.height) / 2
      // Usa lhS (altura real da linha passada como parâmetro) — não lhU.
      final numX = math.max(0.0, nr - tp.width);
      final numY = y + (lhS - tp.height) / 2;

      if (hasBP) {
        // Circle centred on the number, drawn BEFORE the number so number is on top
        const bpR = 9.0;
        final bpCy = y + lhS / 2;
        final bpCx = numX + tp.width / 2;   // horizontally centred on number
        canvas.drawCircle(Offset(bpCx, bpCy), bpR, _pBp1);
        canvas.drawCircle(Offset(bpCx, bpCy), bpR, _pBp2);
      }

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, y, gw - 1, lhS));
      tp.paint(canvas, Offset(numX, numY));
      canvas.restore();
    } else if (hasBP) {
      // No line numbers — draw circle at standard gutter position
      const bpR = 9.0;
      final bpCy = y + lhS / 2;
      canvas.drawCircle(Offset(gw / 2, bpCy), bpR, _pBp1);
      canvas.drawCircle(Offset(gw / 2, bpCy), bpR, _pBp2);
    }

    if (controller.props.showFoldArrows) {
      CodeBlock? blk;
      for (final b in controller.styles.codeBlocks) {
        if (b.startLine == line && b.isFoldable) {
          if (blk == null || b.lineCount > blk.lineCount) blk = b;
        }
      }
      if (blk != null) {
        final folded = controller.isFolded(line);
        final ax = gw - 10.0;
        final ay = y + lhU / 2;
        _pArr.color = cs.lineNumber; final p = _pArr;
        final path = Path();
        if (folded) { path..moveTo(ax - 3, ay - 4)..lineTo(ax + 3, ay)..lineTo(ax - 3, ay + 4); }
        else        { path..moveTo(ax - 4, ay - 2)..lineTo(ax, ay + 3)..lineTo(ax + 4, ay - 2); }
        canvas.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter o) =>
      o.scrollY != scrollY || o.elevation != elevation ||
      o.controller != controller ||
      o.zoom != zoom || o.lineHeightZoomed != lineHeightZoomed ||
      o.ghostInsertVi != ghostInsertVi || o.ghostExtraRows != ghostExtraRows ||
      o.wrapOffsets != wrapOffsets || !_visEq(o.vis, vis);

  // Fast structural equality for vis list — avoids a full deep-equal every frame.
  // Returns true when lists are identical (same fold state, same lines visible).
  static bool _visEq(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }
}