// lib/src/core/editor_controller.dart
// Granular ValueNotifiers — cursor/selection changes do NOT trigger
// a full widget rebuild; only the layers that need it repaint.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'char_position.dart';
import 'cursor.dart';
import 'editor_props.dart';
import 'symbol_pair.dart';
import '../text/content.dart';
import '../text/text_range.dart';
import '../text/line_separator.dart';
import '../language/language.dart';
import '../language/plain_text_language.dart';
import '../highlighting/analyze_manager.dart';
import '../highlighting/styles.dart';
import '../highlighting/line_style.dart';
import '../completion/completion_item.dart';
import '../completion/completion_publisher.dart';
import '../completion/snippet_controller.dart';
import '../diagnostics/diagnostics_container.dart';
import '../diagnostics/diagnostic_region.dart';
import '../search/editor_searcher.dart';
import '../events/editor_event.dart';
import '../events/event_manager.dart';
import '../lsp/lsp_bridge.dart';
import '../lsp/lsp_controller_mixin.dart';
import '../lsp/lsp_stdio_client.dart';
import '../actions/code_action.dart';
import '../completion/ghost_text_controller.dart';
import '../tree_sitter/ts_analyze_manager.dart' show TsAnalyzeManager, TsDiagEntry;
import '../tree_sitter/ts_semantic.dart';
import '../tree_sitter/ts_symbol.dart';

class QuillCodeController extends ChangeNotifier {
  // ── Granular notifiers ─────────────────────────────────────────────────
  /// Fires only when cursor position or selection changes (no text change).
  final ValueNotifier<int> cursorVersion  = ValueNotifier(0);
  /// Fires only when visible text/styles change (edit, undo, language swap).
  final ValueNotifier<int> contentVersion = ValueNotifier(0);
  /// Fires only when completion list changes.
  final ValueNotifier<int> completionVersion = ValueNotifier(0);
  /// Fires when fold state or breakpoints change.
  final ValueNotifier<int> decorVersion   = ValueNotifier(0);
  final ValueNotifier<int> tokenizationVersion = ValueNotifier(0);
  /// Incremented by setText() — widget listens to reset scroll to top.
  final ValueNotifier<int> scrollResetVersion  = ValueNotifier(0);

  late Content          _content;
  late EditorCursor     _cursor;
  late EditorProps      _props;
  late EditorSearcher   _searcher;
  late SnippetController _snippetController;
  late EventManager     _eventManager;

  QuillLanguage        _language;
  late AnalyzeManager  _analyzeManager;
  Styles               _styles = Styles.empty;

  final DiagnosticsContainer _diagnostics = DiagnosticsContainer();
  LspBinding?            _lspBinding;    // optional LSP client
  StreamSubscription<dynamic>? _lspDiagSub; // publishDiagnostics stream sub
  List<CompletionItem>       _completionItems = [];
  bool                       _completionVisible = false;
  bool                       _completionLoading = false; // true while LSP request in-flight
  String                     _completionPrefix  = '';
  int                        _completionRequestId = 0;  // cancellation token

  final Set<int> _foldedBlocks = {};
  final Set<int> _breakpoints  = {};

  // Debounce for completion
  Timer? _completionDebounce;

  // ── Ghost text (inline suggestions — Copilot-style) ──────────────────────
  final GhostTextController _ghostText = GhostTextController();

  QuillCodeController({
    String text = '',
    QuillLanguage? language,
    EditorProps? props,
    LineSeparator separator = LineSeparator.lf,
  }) : _language = language ?? PlainTextLanguage() {
    _props = props ?? EditorProps();
    _content = Content(initialText: text, separator: separator);
    _cursor  = EditorCursor(_content);
    _searcher = EditorSearcher(_content);
    _snippetController = SnippetController(_content);
    _eventManager = EventManager();
    _content.addListener(_onContentChanged);
    _setupLanguage();
  }

  // ── Getters ────────────────────────────────────────────────────────────
  Content           get content          => _content;
  EditorCursor      get cursor           => _cursor;
  EditorProps       get props            => _props;
  QuillLanguage     get language         => _language;
  Styles            get styles           => _styles;

  /// Overwrite the [lineStyles] map used for per-line decorations (e.g. git diff
  /// markers). Merges with existing span / block data and repaints immediately.
  void setLineStyles(Map<int, LineStyle> lineStyles) {
    _styles = Styles(
      spans:      _styles.spans,
      codeBlocks: _styles.codeBlocks,
      inlayHints: _styles.inlayHints,
      lineStyles: Map.unmodifiable(lineStyles),
    );
    notifyListeners();
  }
  DiagnosticsContainer get diagnostics   => _diagnostics;
  EditorSearcher    get searcher         => _searcher;
  GhostTextController get ghostText      => _ghostText;
  SnippetController get snippetController => _snippetController;
  EventManager      get eventManager     => _eventManager;
  List<CompletionItem> get completionItems => _completionItems;
  bool              get isCompletionVisible => _completionVisible;
  bool              get isCompletionLoading => _completionLoading;
  String            get completionPrefix => _completionPrefix;
  Set<int>          get foldedBlocks     => _foldedBlocks;
  Set<int>          get breakpoints      => _breakpoints;
  String            get text             => _content.fullText;

  /// Returns the list of "sticky" ancestor scope lines for the current
  /// scroll position (used by stickyScroll feature in the render object).
  /// Each entry is a line number whose block header should be pinned at top.
  List<int> get stickyLines {
    if (!_props.stickyScroll) return const [];
    final blocks = _styles.codeBlocks;
    final cursorLine = _cursor.line;
    // Find all blocks that contain the cursor line, sorted by indent (outermost first)
    final ancestors = <int>[];
    for (final b in blocks) {
      if (b.startLine < cursorLine && b.endLine >= cursorLine) {
        ancestors.add(b.startLine);
      }
    }
    ancestors.sort();
    // Limit to maxLines
    final max = _props.stickyScrollMaxLines;
    return ancestors.length > max ? ancestors.sublist(ancestors.length - max) : ancestors;
  }


  // ── Folding ────────────────────────────────────────────────────────────
  void toggleFold(int startLine) {
    if (_foldedBlocks.contains(startLine)) _foldedBlocks.remove(startLine);
    else _foldedBlocks.add(startLine);
    _bumpDecor();
    notifyListeners();
  }
  bool isFolded(int startLine) => _foldedBlocks.contains(startLine);

  /// Returns true if [line] is hidden inside a folded block
  /// (i.e. it is NOT a startLine but falls between startLine+1 and endLine).
  bool _lineIsHiddenInFold(int line) {
    if (_foldedBlocks.isEmpty) return false;
    for (final b in _styles.codeBlocks) {
      if (!b.isFoldable) continue;
      if (!_foldedBlocks.contains(b.startLine)) continue;
      if (line > b.startLine && line <= b.endLine) return true;
    }
    return false;
  }

  // ── Breakpoints ────────────────────────────────────────────────────────
  void toggleBreakpoint(int line) {
    if (_breakpoints.contains(line)) _breakpoints.remove(line);
    else _breakpoints.add(line);
    _bumpDecor();
    notifyListeners();
  }
  bool hasBreakpoint(int line) => _breakpoints.contains(line);

  // ── Text editing ───────────────────────────────────────────────────────
  void setText(String text) {
    // ── Reset styles immediately to blank ─────────────────────────────────
    _styles = Styles.empty;

    // ── Clear stale fold/breakpoint state from previous file ──────────────
    _foldedBlocks.clear();
    _breakpoints.clear();

    // ── Replace content in O(n) — silent to avoid double-dispatch ─────────
    // bulkResetSilent skips _notifyAll so _onContentChanged does NOT fire.
    // Avoids the wasted fast-path analysis that onContentChanged would trigger
    // before reanalyze() replaces it with the proper full dispatch.
    _content.bulkResetSilent(text);

    // ── Reset cursor to top ────────────────────────────────────────────────
    _cursor.moveTo(const CharPosition.zero());

    // ── Signal scroll + gutter reset to widget ────────────────────────────
    scrollResetVersion.value++;

    // ── Start background tokenization ─────────────────────────────────────
    _analyzeManager.reanalyze(_content);
    _bumpContent();
    notifyListeners();
  }

  void insertText(String text) {
    if (_props.readOnly) return;
    // ── Bracket skip-over ────────────────────────────────────────────────────
    // When the user types a closing bracket (or quote) that was auto-inserted
    // right after the cursor, skip OVER it instead of inserting a duplicate.
    // Must be checked BEFORE _deleteSelection changes the cursor position.
    final hadNoSelection = !_cursor.hasSelection;
    if (_cursor.hasSelection) _deleteSelection();
    if (hadNoSelection &&
        _props.symbolPairAutoCompletion &&
        text.length == 1 &&
        _language.symbolPairs.isCloseSymbol(text)) {
      final pos  = _cursor.position;
      final line = _content.getLineText(pos.line);
      if (pos.column < line.length && line[pos.column] == text[0]) {
        _cursor.moveTo(CharPosition(pos.line, pos.column + 1));
        _bumpCursor();
        notifyListeners();
        return;
      }
    }
    final pos = _cursor.position;
    _content.insert(pos, text);
    final lines = text.split('\n');
    if (lines.length == 1) {
      _cursor.moveTo(CharPosition(pos.line, pos.column + text.length));
    } else {
      _cursor.moveTo(CharPosition(pos.line + lines.length - 1, lines.last.length));
    }
    _handleSymbolPair(text);
    _triggerGhostText();
    _scheduleCompletion();
    _bumpContent();
    _bumpCursor();
    notifyListeners();
  }

  void _deleteSelection() {
    if (!_cursor.hasSelection) return;
    final sel = _cursor.selection;
    _content.delete(sel);
    _cursor.moveTo(sel.start);
  }

  void deleteSelection() {
    if (!_cursor.hasSelection) return;
    _deleteSelection();
    _bumpContent();
    _bumpCursor();
    notifyListeners();
  }

  void deleteCharBefore() {
    if (_props.readOnly) return;
    if (_cursor.hasSelection) { deleteSelection(); return; }
    final pos = _cursor.position;
    if (pos.column > 0) {
      _content.delete(EditorRange(CharPosition(pos.line, pos.column - 1), pos));
      _cursor.moveTo(CharPosition(pos.line, pos.column - 1));
    } else if (pos.line > 0) {
      // Do NOT merge with the previous line if the current line is hidden
      // inside a fold, or if the previous line is the startLine of a fold
      // (merging would destroy the fold or edit invisible content).
      final prevLine = pos.line - 1;
      if (!_lineIsHiddenInFold(pos.line) && !isFolded(prevLine)) {
        final plLen = _content.getLineLength(prevLine);
        _content.delete(EditorRange(CharPosition(prevLine, plLen), pos));
        _cursor.moveTo(CharPosition(prevLine, plLen));
      }
    }
    _scheduleCompletion();
    _bumpContent();
    _bumpCursor();
    notifyListeners();
  }

  void deleteCharAfter() {
    if (_props.readOnly) return;
    if (_cursor.hasSelection) { deleteSelection(); return; }
    final pos = _cursor.position;
    final ll = _content.getLineLength(pos.line);
    if (pos.column < ll) {
      _content.delete(EditorRange(pos, CharPosition(pos.line, pos.column + 1)));
    } else if (pos.line < _content.lineCount - 1) {
      // Do NOT merge into the next line if it is hidden inside a fold.
      // That would silently destroy the fold or edit invisible content.
      final nextLine = pos.line + 1;
      if (!_lineIsHiddenInFold(nextLine)) {
        _content.delete(EditorRange(pos, CharPosition(nextLine, 0)));
      }
    }
    _bumpContent();
    notifyListeners();
  }

  void insertNewline() {
    if (_props.readOnly) return;
    if (_cursor.hasSelection) _deleteSelection();
    final pos    = _cursor.position;
    final indent = _computeAutoIndent(pos);
    _content.insert(pos, '\n$indent');
    _cursor.moveTo(CharPosition(pos.line + 1, indent.length));
    hideCompletion();
    _bumpContent();
    _bumpCursor();
    notifyListeners();
  }

  void insertTab() {
    if (_props.readOnly) return;
    final t = _props.useSpacesForTabs ? ' ' * _props.tabSize : '\t';
    insertText(t);
  }

  // ── Undo / Redo ────────────────────────────────────────────────────────
  void undo() {
    if (_props.readOnly) return;
    final range = _content.undo();
    if (range != null) _cursor.setRange(range);
    _bumpContent(); _bumpCursor(); notifyListeners();
  }
  void redo() {
    if (_props.readOnly) return;
    final range = _content.redo();
    if (range != null) _cursor.setRange(range);
    _bumpContent(); _bumpCursor(); notifyListeners();
  }

  // ── Clipboard ──────────────────────────────────────────────────────────
  String? copyText() {
    if (!_cursor.hasSelection) return null;
    return _content.getTextInRange(_cursor.selection);
  }
  String? cutText() {
    final t = copyText();
    if (t != null) deleteSelection();
    return t;
  }
  void pasteText(String text) {
    if (_props.readOnly) return;
    if (_cursor.hasSelection) _deleteSelection();
    insertText(text);
  }

  // ── Selection ──────────────────────────────────────────────────────────
  void selectAll()  { _cursor.selectAll();  _bumpCursor(); notifyListeners(); }
  void selectWord() { _cursor.selectWord(); _bumpCursor(); notifyListeners(); }
  void selectLine() { _cursor.selectLine(); _bumpCursor(); notifyListeners(); }

  /// Expand selection to the next enclosing syntax node (tree-sitter powered).
  /// Falls back to selectWord → selectLine → selectAll on non-TS platforms.
  void expandSemanticSelection() {
    final src  = _content.fullText;
    final lang = _language.name.toLowerCase();
    final sel  = _cursor.hasSelection
        ? _cursor.selection
        : EditorRange.collapsed(_cursor.position);

    final result = TsSemantic.expandSelection(
        src, lang,
        sel.start.line, sel.start.column,
        sel.end.line,   sel.end.column);

    if (result != null) {
      _cursor.setSelection(
          CharPosition(result.$1, result.$2),
          CharPosition(result.$3, result.$4));
      _bumpCursor();
      notifyListeners();
    } else {
      // Fallback: word → line → all
      if (!_cursor.hasSelection) {
        selectWord();
      } else {
        final sel2 = _cursor.selection;
        if (sel2.start.line == sel2.end.line) selectLine();
        else selectAll();
      }
    }
  }

  /// Returns named symbols in the current document (functions, classes, etc.).
  List<TsSymbol> getSymbols() {
    return TsSemantic.extractSymbols(_content.fullText, _language.name.toLowerCase());
  }

  /// Pushes tree-sitter syntax errors as diagnostics.
  void updateSyntaxDiagnostics() {
    final diags = TsSemantic.extractDiagnostics(
        _content.fullText, _language.name.toLowerCase());
    if (diags.isNotEmpty) setDiagnostics(diags);
  }

  /// Move cursor without triggering completion — only bumps cursorVersion.
  void setCursor(CharPosition pos, {bool select = false}) {
    _ghostText.dismiss();
    // Clamp to a visible (non-hidden) line.
    final clamped = _clampToVisible(pos);
    _cursor.moveTo(clamped, select: select);
    _bumpCursor();
    // NOTE: We still notifyListeners() here so overlays (handles, tooltip) rebuild.
    // But the heavy RenderBox only repaints via ViewportOffset listeners, not this.
    notifyListeners();
  }

  /// Clamps [pos] so it never lands on a line hidden inside a fold.
  /// If [pos.line] is hidden, moves to the nearest visible line above it
  /// (the startLine of the enclosing fold).
  CharPosition _clampToVisible(CharPosition pos) {
    if (_foldedBlocks.isEmpty) return pos;
    for (final b in _styles.codeBlocks) {
      if (!b.isFoldable) continue;
      if (!_foldedBlocks.contains(b.startLine)) continue;
      if (pos.line > b.startLine && pos.line <= b.endLine) {
        // Snap to the end of startLine (visible fold header).
        final col = _content.getLineLength(b.startLine);
        return CharPosition(b.startLine, col);
      }
    }
    return pos;
  }

  // ── Snippets ───────────────────────────────────────────────────────────
  void insertSnippet(String snippet, {Map<String, String> variables = const {}}) {
    if (_props.readOnly) return;
    if (_cursor.hasSelection) _deleteSelection();
    final pos    = _cursor.position;
    final indent = _getLineIndent(pos.line);
    final range  = _snippetController.insertSnippet(snippet, pos,
        indentation: indent, variables: variables);
    if (range != null) _cursor.setRange(range);
    _bumpContent(); _bumpCursor(); notifyListeners();
  }

  // ── Diagnostics ────────────────────────────────────────────────────────
  // ── LSP ────────────────────────────────────────────────────────────────
  /// Attach an LSP client. Call with the file URI and language ID.
  Future<void> attachLsp(LspClient client, {
    required String uri,
    String? languageId,
  }) async {
    await _lspBinding?.close();
    _lspBinding = LspBinding(
      client:     client,
      uri:        uri,
      languageId: languageId ?? _language.name.toLowerCase(),
    );
    _lspBinding!.onDiagnostics = setDiagnostics;
    _lspBinding!.onCompletionItems = (items) {
      // Merge LSP completions with local completions
      if (items.isNotEmpty) {
        // Avoid creating two intermediate lists before spreading.
        final merged = List<CompletionItem>.of(items);
        int local = 0;
        for (final it in _completionItems) {
          if (local++ >= 5) break;
          merged.add(it);
        }
        _completionItems = merged;
        _completionVisible = _completionItems.isNotEmpty;
        _bumpCompletion();
        notifyListeners();
      }
    };
    _lspBinding!.onNotify = notifyListeners;
    await _lspBinding!.open(text);
    // If the client is a LspStdioClient, subscribe to pushed diagnostics.
    // This handles textDocument/publishDiagnostics server notifications
    // (which arrive asynchronously, not via polling).
    _lspDiagSub?.cancel();
    _lspDiagSub = null;
    final rawClient = client;
    if (rawClient is LspStdioClient) {
      // listenDiagnostics returns a StreamSubscription<List<LspDiagnostic>>.
      // Cast to dynamic since _lspDiagSub is StreamSubscription<dynamic>.
      final sub = rawClient.listenDiagnostics(uri, (lspDiags) {
        setDiagnostics(lspDiags.map((d) => DiagnosticRegion(
          range: d.range, message: d.message, severity: d.severity,
          source: d.source, code: d.code,
        )).toList());
      });
      _lspDiagSub = sub as StreamSubscription<dynamic>;
    }
  }

  Future<void> detachLsp() async {
    _lspDiagSub?.cancel();
    _lspDiagSub = null;
    await _lspBinding?.close();
    _lspBinding = null;
  }

  /// Whether an LSP client is currently attached.
  bool get hasLsp => _lspBinding != null;
  LspBinding? get lsp => _lspBinding;

  /// Get LSP go-to-definition.
  Future<List<LspLocation>> lspDefinitionAt(CharPosition pos) =>
      _lspBinding?.definitionAt(pos) ?? Future.value([]);

  /// Get LSP code actions at range (for lightbulb menu).
  Future<List<CodeAction>> lspActionsAt(EditorRange range) =>
      _lspBinding?.codeActionsAt(range) ?? Future.value([]);

  /// Get LSP hover info (markdown/plain text documentation).
  Future<LspHover?> lspHoverAt(CharPosition pos) =>
      _lspBinding?.hoverAt(pos) ?? Future.value(null);

  /// Get LSP signature help at cursor (shown when user types `(` or `,`).
  Future<LspSignatureHelp?> lspSignatureHelpAt(CharPosition pos, {String? triggerChar}) =>
      _lspBinding?.signatureHelpAt(pos, triggerChar: triggerChar) ?? Future.value(null);

  /// Get LSP find-all-references.
  Future<List<LspLocation>> lspReferencesAt(CharPosition pos) =>
      _lspBinding?.referencesAt(pos) ?? Future.value([]);

  /// Get LSP document symbols (for outline panel).
  Future<List<LspDocumentSymbol>> lspDocumentSymbols() =>
      _lspBinding?.documentSymbols() ?? Future.value([]);

  /// Get LSP document highlight (all occurrences of symbol under cursor).
  Future<List<EditorRange>> lspDocumentHighlightAt(CharPosition pos) =>
      _lspBinding?.documentHighlightAt(pos) ?? Future.value([]);

  /// Get LSP inlay hints for the visible range.
  Future<List<LspInlayHint>> lspInlayHints(EditorRange range) =>
      _lspBinding?.inlayHintsForRange(range) ?? Future.value([]);

  /// Apply LSP format — returns the list of text edits (caller applies them).
  Future<List<LspTextEdit>> lspFormat() =>
      _lspBinding?.format() ?? Future.value([]);

  /// Apply LSP rename — returns map of uri → edits (caller applies them).
  Future<Map<String, List<LspTextEdit>>?> lspRenameAt(CharPosition pos, String newName) =>
      _lspBinding?.renameAt(pos, newName) ?? Future.value(null);

  void setDiagnostics(List<DiagnosticRegion> regions) {
    _diagnostics.setDiagnostics(regions);
    _bumpDecor(); notifyListeners();
  }
  void clearDiagnostics() { _diagnostics.clear(); _bumpDecor(); notifyListeners(); }

  // ── Language ───────────────────────────────────────────────────────────
  void setLanguage(QuillLanguage lang) {
    _analyzeManager.destroy();
    _language = lang;
    _setupLanguage();
    _bumpContent(); notifyListeners();
  }

  void _setupLanguage() {
    _language.init();
    _analyzeManager = _language.createAnalyzeManager();
    _analyzeManager.onStylesUpdated = (s) {
      _styles = s;
      // Prune _foldedBlocks: remove any startLine that no longer has a
      // matching foldable CodeBlock in the new styles. This handles the case
      // where the user deletes '}' (or '{') while a block is folded —
      // _validateBlocks removes it from _currentBlocks/styles.codeBlocks but
      // _foldedBlocks still held the startLine, keeping isFolded() == true
      // and the '•••' indicator visible even after the block was gone.
      if (_foldedBlocks.isNotEmpty) {
        // Simple remove-only policy: drop any fold whose block no longer exists.
        // _shiftLineSets already shifted _foldedBlocks to match the new line
        // numbers, and _shiftCodeBlocks keeps codeBlocks in sync.
        // The "migrate to nearest" heuristic was removed because it fought
        // against the correct shift and caused fold icons to disappear.
        final newValidStarts = <int>{};
        for (final b in s.codeBlocks) { if (b.isFoldable) newValidStarts.add(b.startLine); }
        _foldedBlocks.removeWhere((line) => !newValidStarts.contains(line));
      }
      // Style update: só repaint — sem layout, sem LSP, sem fullText.
      // _EBox escuta decorVersion diretamente via markNeedsPaint.
      _bumpDecor();
      // ── Fix Bug 2/3: clear TextPainter cache on EVERY span update ─────────
      // Previously tokenizationVersion was bumped only at the END of
      // tokenisation. That meant progress-update spans arrived but the
      // _EBox cache served stale TextPainters (built with old empty spans)
      // → visible lines stayed grey until the final update.
      // Bumping here on every pushStyles() ensures the cache is re-filled
      // with the latest spans on every partial progress and final delivery.
      // Cost: ~30 visible lines × 0.1 ms = ~3 ms per update — acceptable.
      tokenizationVersion.value++;
    };
    _analyzeManager.onTokenizationComplete = () {
      // tokenizationVersion already bumped in onStylesUpdated above.
    };
    // Wire tree-sitter syntax diagnostics if the manager supports it
    if (_analyzeManager is TsAnalyzeManager) {
      (_analyzeManager as TsAnalyzeManager).onDiagnosticsUpdated = (entries) {
        if (!_props.showDiagnosticIndicators) return;
        final regions = entries.map((e) => DiagnosticRegion(
          range: EditorRange(
              CharPosition(e.startLine, e.startCol),
              CharPosition(e.endLine,   e.endCol)),
          severity: DiagnosticSeverity.error,
          message:  'Syntax error',
          source:   'tree-sitter',
        )).toList();
        setDiagnostics(regions);
      };
    }
    _analyzeManager.init(_content);
  }

  // ── Completion ─────────────────────────────────────────────────────────
  void _scheduleCompletion() {
    if (!_props.autoCompletion) return;
    _completionDebounce?.cancel();
    _completionDebounce = Timer(const Duration(milliseconds: 60), _doCompletion);
  }

  void _doCompletion() {
    if (!_props.autoCompletion) return;
    final pos = _cursor.position;
    final prefix = _getWordPrefix(pos);
    if (prefix.isEmpty) { hideCompletion(); return; }
    _completionPrefix = prefix;

    // ── Cancellation token ─────────────────────────────────────────────────
    // Each new _doCompletion invocation gets a unique id. When async work
    // finishes, it checks the token — if it changed, a newer request is
    // in-flight and this result is stale (like Sora's runCount mechanism).
    final myId = ++_completionRequestId;

    bool stale() => myId != _completionRequestId;

    // ── Phase 1: Show local items immediately (Sora-style streaming) ───────
    // The publisher collects items synchronously from language plugins, then
    // we show them right away — the list appears in the same frame as typing.
    final publisher = CompletionPublisher();
    _language.getCompletions(_content, pos, publisher).then((_) {
      if (stale()) return;
      final localItems = _filterAndSort(publisher.items, prefix);
      _completionItems   = localItems;
      _completionVisible = localItems.isNotEmpty;
      _completionLoading = _lspBinding != null; // LSP still in-flight
      _bumpCompletion();
      notifyListeners();
    }).catchError((_) {});

    // ── Phase 2: LSP items arrive later, merge in ──────────────────────────
    // Monaco does the same: show the list immediately, then update it when
    // the server responds. The user already sees results from Phase 1.
    if (_lspBinding != null) {
      _completionLoading = true;
      _lspBinding!.completionsAt(pos).then((lspItems) {
        if (stale()) return;
        _completionLoading = false;
        if (publisher.isCancelled) return;
        // Merge: LSP items first (semantically richer), local after.
        // De-duplicate by label so local snippets don't double up.
        final seenLabels = <String>{};
        final merged = <CompletionItem>[];
        for (final item in [...lspItems, ...publisher.items]) {
          if (seenLabels.add(item.label)) merged.add(item);
        }
        _completionItems   = _filterAndSort(merged, prefix);
        _completionVisible = _completionItems.isNotEmpty;
        _bumpCompletion();
        notifyListeners();
      }).catchError((_) {
        if (!stale()) {
          _completionLoading = false;
          _bumpCompletion();
          notifyListeners();
        }
      });
    }
  }

  List<CompletionItem> _filterAndSort(List<CompletionItem> items, String prefix) {
    final lower = prefix.toLowerCase();
    return items
        .where((i) => i.effectiveFilterText.toLowerCase().startsWith(lower))
        .toList()
      ..sort((a, b) => a.effectiveSortText.compareTo(b.effectiveSortText));
  }

  /// Trigger LSP lazy-resolve for a selected item's documentation/detail.
  /// Called by the UI when the user highlights an item in the popup.
  /// Updates the item in place and notifies listeners.
  Future<void> resolveCompletionItem(int index) async {
    if (index < 0 || index >= _completionItems.length) return;
    final item = _completionItems[index];
    if (item.isResolved || _lspBinding == null) return;
    final resolved = await _lspBinding!.resolveCompletionItem(item);
    if (resolved == null) return;
    // Splice the resolved item back in (immutable list → new list)
    final newList = List<CompletionItem>.of(_completionItems);
    newList[index] = resolved;
    _completionItems = newList;
    _bumpCompletion();
    notifyListeners();
  }

  void selectCompletionItem(CompletionItem item) {
    final pos = _cursor.position;
    final start = CharPosition(pos.line, pos.column - _completionPrefix.length);
    _content.delete(EditorRange(start, pos));
    _cursor.moveTo(start);
    if (item.isSnippet) insertSnippet(item.insertText);
    else insertText(item.insertText);
    hideCompletion();
  }

  void hideCompletion() {
    if (!_completionVisible && _completionItems.isEmpty && !_completionLoading) return;
    _completionVisible = false;
    _completionLoading = false;
    _completionItems   = [];
    ++_completionRequestId; // invalidate any in-flight LSP request
    _completionDebounce?.cancel();
    _bumpCompletion();
    notifyListeners();
  }

  // ── Private bumpers ────────────────────────────────────────────────────
  void _bumpCursor()     => cursorVersion.value++;
  void _bumpContent() {
    contentVersion.value++;
    // Notify LSP server of text change (debounced inside LspBinding)
    _lspBinding?.change(this.text);
  }
  void _bumpCompletion() => completionVersion.value++;
  void _bumpDecor()      => decorVersion.value++;

  // ── Helpers ────────────────────────────────────────────────────────────
  String _computeAutoIndent(CharPosition pos) {
    final indent = _getLineIndent(pos.line);
    final extra  = _language.getIndentAdvance(_content, pos.line, pos.column);
    final spaces = _props.useSpacesForTabs
        ? ' ' * extra : '\t' * (extra ~/ _props.tabSize);
    return indent + spaces;
  }
  String _getLineIndent(int line) {
    final text = _content.getLineText(line);
    int i = 0;
    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
    return text.substring(0, i);
  }
  String _getWordPrefix(CharPosition pos) {
    if (pos.column == 0) return '';
    final line = _content.getLineText(pos.line);
    int i = pos.column;
    while (i > 0 && _wc(line.codeUnitAt(i - 1))) i--;
    return line.substring(i, pos.column);
  }
  static bool _wc(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) || c == 95;

  void _handleSymbolPair(String inserted) {
    if (!_props.symbolPairAutoCompletion || inserted.length != 1) return;
    final closing = _language.symbolPairs.getClosingFor(inserted);
    if (closing == null) return;
    final pos = _cursor.position;
    final line = _content.getLineText(pos.line);
    if (pos.column < line.length && line[pos.column] == closing) return;
    _content.insert(pos, closing);
  }

  void _onContentChanged(ContentChangeEvent event) {
    // _shiftLineSets MUST run first — it updates _foldedBlocks and _breakpoints
    // before _analyzeManager.onContentChanged fires, which may synchronously
    // call pushStyles → onStylesUpdated → notifyListeners() and trigger a
    // widget rebuild. Without this order, the rebuild sees stale fold state.
    _shiftLineSets(event);
    _searcher.onContentChanged();
    _analyzeManager.onContentChanged(event, _content);
  }

  /// Keeps [_foldedBlocks] and [_breakpoints] in sync after line insertions
  /// or deletions so that folds and breakpoints follow their original lines.
  void _shiftLineSets(ContentChangeEvent event) {
    final bool isInsert = event.type == ContentChangeType.insert;
    final int  atLine   = event.affectedLine;
    final int  newlines = event.text.split('\n').length - 1;

    if (newlines == 0) {
      // ── Single-line edit: shift diagnostic columns on this line ──────────
      // Positive delta for insert, negative for delete.
      final charDelta = isInsert ? event.text.length : -event.text.length;
      if (charDelta != 0) {
        _diagnostics.shiftColumnsOnLine(atLine, event.position.column, charDelta);
      }
      return;
    }

    if (isInsert) {
      // When the insert starts at column 0 the ENTIRE content of atLine is
      // pushed down to atLine+1 (e.g. pressing Enter at the very start of
      // the line that opens a block with '{').
      // In that case fold/breakpoint entries ON atLine must shift too,
      // so we use pivot = atLine-1  (i.e. shift entries >= atLine).
      // When column > 0 the opener char stays on atLine, so only entries
      // strictly > atLine shift (pivot = atLine, the original behaviour).
      final int insertPivot = (event.position.column == 0) ? atLine - 1 : atLine;
      _shiftSet(_foldedBlocks, insertPivot, newlines);
      _shiftSet(_breakpoints,  insertPivot, newlines);
      _diagnostics.shiftOnInsert(atLine, newlines);
    } else {
      // Lines were deleted — atLine+1 .. atLine+newlines are gone.
      _removeAndShiftSet(_foldedBlocks, atLine, newlines);
      _removeAndShiftSet(_breakpoints,  atLine, newlines);
      _diagnostics.shiftOnDelete(atLine, newlines);
    }
  }

  /// Shift all entries > [pivot] up by [delta] in-place.
  static void _shiftSet(Set<int> s, int pivot, int delta) {
    // Collect entries that need shifting, remove them, then re-add shifted.
    final toShift = s.where((n) => n > pivot).toList();
    for (final n in toShift) { s.remove(n); s.add(n + delta); }
  }

  /// Remove entries in [atLine+1 .. atLine+count], then shift entries
  /// above that range down by [count].
  static void _removeAndShiftSet(Set<int> s, int atLine, int count) {
    // Remove entries inside the deleted range (they no longer exist)
    for (int i = atLine + 1; i <= atLine + count; i++) s.remove(i);
    // Shift remaining entries that were below the deleted range
    final toShift = s.where((n) => n > atLine + count).toList();
    for (final n in toShift) { s.remove(n); s.add(n - count); }
  }

  // ── Ghost text public API ────────────────────────────────────────────────

  /// Attach a ghost text provider. Pass null to disable.
  /// Example:
  ///   controller.setGhostTextProvider(
  ///     SnippetGhostProvider(languageId: 'dart').call);
  void setGhostTextProvider(GhostTextProvider? provider) {
    _ghostText.setProvider(provider);
  }

  bool _suppressGhostTrigger = false;

  /// Accept the current ghost suggestion (Tab / Enter key).
  /// Returns true if a suggestion was accepted.
  bool acceptGhostText() {
    if (!_ghostText.isVisible) return false;
    final atLine = _ghostText.atLine;
    final atCol  = _ghostText.atColumn;
    final text   = _ghostText.accept(); // dismisses + notifies layout
    if (text == null) return false;

    // Reposition cursor to exact ghost anchor if drifted (IME double-fire guard)
    final current = _cursor.position;
    if (current.line != atLine || current.column != atCol) {
      final clampedCol = atCol.clamp(0, _content.getLineLength(atLine));
      _cursor.moveTo(CharPosition(atLine, clampedCol));
    }

    // Suppress _triggerGhostText inside insertText so the accepted suggestion
    // does not immediately re-appear as ghost text behind the inserted code.
    _suppressGhostTrigger = true;
    insertText(text);
    _suppressGhostTrigger = false;
    return true;
  }

  /// Accept the next word of the ghost suggestion (Alt+Right).
  bool acceptGhostWord() {
    final text = _ghostText.acceptWord();
    if (text == null) return false;
    _suppressGhostTrigger = true;
    insertText(text);
    _suppressGhostTrigger = false;
    return true;
  }

  void _triggerGhostText() {
    if (_suppressGhostTrigger) return;
    if (!_ghostText.hasProvider) return;
    final pos       = _cursor.position;
    final lineText  = _content.getLineText(pos.line);
    final prefix    = pos.column < lineText.length
        ? lineText.substring(0, pos.column) : lineText;
    final suffix    = pos.column < lineText.length
        ? lineText.substring(pos.column) : '';
    _ghostText.onEdit(
      documentText: _content.fullText,
      line:         pos.line,
      column:       pos.column,
      linePrefix:   prefix,
      lineSuffix:   suffix,
      languageId:   _language.name.toLowerCase(),
    );
  }

  @override
  void dispose() {
    _lspDiagSub?.cancel();
    _lspBinding?.close();
    _completionDebounce?.cancel();
    _content.removeListener(_onContentChanged);
    _analyzeManager.destroy();
    _language.destroy();
    _ghostText.destroy();
    _searcher.dispose();
    _eventManager.dispose();
    cursorVersion.dispose();
    contentVersion.dispose();
    completionVersion.dispose();
    decorVersion.dispose();
    tokenizationVersion.dispose();
    scrollResetVersion.dispose();
    super.dispose();
  }
}
