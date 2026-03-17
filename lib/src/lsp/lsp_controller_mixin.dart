// lib/src/lsp/lsp_controller_mixin.dart
// Wires LspClient to the editor controller:
// - didOpen/didChange on text changes
// - Merges LSP completions into the completion list
// - Sets LSP diagnostics
// - Provides hover/definition/codeAction/signatureHelp/documentSymbols APIs
import 'dart:async';
import '../core/char_position.dart';
import '../text/text_range.dart';
import '../diagnostics/diagnostic_region.dart';
import '../diagnostics/quick_fix.dart';
import '../completion/completion_item.dart';
import '../actions/code_action.dart';
import 'lsp_bridge.dart';

/// Mixin that adds LSP support to the controller.
/// Usage: attach via QuillCodeController.attachLsp(client, uri)
class LspBinding {
  final LspClient client;
  final String    uri;
  final String    languageId;
  
  // callbacks set by controller
  late void Function(List<CompletionItem> items) onCompletionItems;
  late void Function(List<DiagnosticRegion> diags) onDiagnostics;
  late void Function() onNotify;

  Timer?  _diagTimer;
  bool    _opened = false;
  int     _version = 0;

  LspBinding({
    required this.client,
    required this.uri,
    required this.languageId,
  });

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> open(String text) async {
    _version++;
    await client.didOpen(uri: uri, languageId: languageId, text: text, version: _version);
    _opened = true;
    _startDiagPoll();
  }

  Future<void> change(String text) async {
    if (!_opened) return;
    _version++;
    await client.didChange(uri: uri, text: text, version: _version);
    // Monaco-style: debounce 500ms after edit, not a fixed 2s periodic poll.
    // This means the first diagnostic response comes fast after typing stops.
    _diagTimer?.cancel();
    _diagTimer = Timer(const Duration(milliseconds: 500), _pollDiagnostics);
  }

  Future<void> close() async {
    _diagTimer?.cancel();
    if (_opened) await client.didClose(uri: uri);
    _opened = false;
  }

  // ── Completions ────────────────────────────────────────────────────────────

  Future<List<CompletionItem>> completionsAt(CharPosition pos) async {
    if (!_opened) return [];
    try {
      final results = await client.completion(uri: uri, position: pos);
      return results.map((r) {
        final kind = _mapKind(r.kind);
        return CompletionItem(
          label:         r.label,
          kind:          kind,
          insertText:    r.insertText ?? r.label,
          detail:        r.detail,
          documentation: r.documentation,
          isSnippet:     r.isSnippet,
          // Mark as unresolved if documentation is missing — lazy resolve later.
          isResolved:    r.documentation != null && r.documentation!.isNotEmpty,
          rawLspData:    r, // store original for resolve request
        );
      }).toList();
    } catch (_) { return []; }
  }

  /// Fetch full documentation for a single item (Monaco lazy-resolve pattern).
  /// Returns a new CompletionItem with isResolved=true, or null on failure.
  Future<CompletionItem?> resolveCompletionItem(CompletionItem item) async {
    if (!_opened || item.rawLspData == null) return null;
    try {
      final raw = item.rawLspData as LspCompletionResult;
      final resolved = await client.resolveCompletion(raw);
      if (resolved == null) return null;
      return item.withResolved(
        documentation: resolved.documentation,
        detail:        resolved.detail,
      );
    } catch (_) { return null; }
  }

  // ── Diagnostics ────────────────────────────────────────────────────────────

  void _startDiagPoll() {
    _diagTimer?.cancel();
    // Slow fallback: every 5s re-check even if no edits happened.
    // The main diagnostic path is the 500ms debounce after each change().
    // 5s is just a safety net for servers that push without responding to pulls.
    _diagTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollDiagnostics());
  }

  Future<void> _pollDiagnostics() async {
    if (!_opened) return;
    try {
      final lspDiags = await client.diagnostics(uri: uri);
      final regions = lspDiags.map((d) => DiagnosticRegion(
        range:    d.range,
        severity: _mapSeverity(d.severity),
        message:  d.message,
        source:   d.source,
        code:     d.code,
      )).toList();
      onDiagnostics(regions);
      onNotify();
    } catch (_) {}
  }

  // ── Hover ──────────────────────────────────────────────────────────────────

  Future<LspHover?> hoverAt(CharPosition pos) async {
    if (!_opened) return null;
    try { return await client.hover(uri: uri, position: pos); }
    catch (_) { return null; }
  }

  // ── Signature help ─────────────────────────────────────────────────────────

  Future<LspSignatureHelp?> signatureHelpAt(CharPosition pos, {String? triggerChar}) async {
    if (!_opened) return null;
    try {
      return await client.signatureHelp(
        uri: uri, position: pos, triggerCharacter: triggerChar);
    } catch (_) { return null; }
  }

  // ── Definition ────────────────────────────────────────────────────────────

  Future<List<LspLocation>> definitionAt(CharPosition pos) async {
    if (!_opened) return [];
    try { return await client.definition(uri: uri, position: pos); }
    catch (_) { return []; }
  }

  // ── References ────────────────────────────────────────────────────────────

  Future<List<LspLocation>> referencesAt(CharPosition pos) async {
    if (!_opened) return [];
    try { return await client.references(uri: uri, position: pos); }
    catch (_) { return []; }
  }

  // ── Code actions ──────────────────────────────────────────────────────────

  Future<List<CodeAction>> codeActionsAt(EditorRange range) async {
    if (!_opened) return [];
    try {
      final lspActions = await client.codeActions(uri: uri, range: range);
      return lspActions.map((a) => CodeAction(
        title:  a.title,
        kind:   a.kind.contains('fix') ? CodeActionKind.quickFix : CodeActionKind.refactor,
        edits:  a.edits.map((e) => CodeActionEdit(range: e.range, newText: e.newText)).toList(),
      )).toList();
    } catch (_) { return []; }
  }

  // ── Document symbols ──────────────────────────────────────────────────────

  Future<List<LspDocumentSymbol>> documentSymbols() async {
    if (!_opened) return [];
    try { return await client.documentSymbols(uri: uri); }
    catch (_) { return []; }
  }

  // ── Document highlight ────────────────────────────────────────────────────

  Future<List<EditorRange>> documentHighlightAt(CharPosition pos) async {
    if (!_opened) return [];
    try { return await client.documentHighlight(uri: uri, position: pos); }
    catch (_) { return []; }
  }

  // ── Inlay hints ───────────────────────────────────────────────────────────

  Future<List<LspInlayHint>> inlayHintsForRange(EditorRange range) async {
    if (!_opened) return [];
    try { return await client.inlayHints(uri: uri, range: range); }
    catch (_) { return []; }
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  Future<List<LspTextEdit>> format() async {
    if (!_opened) return [];
    try { return await client.formatting(uri: uri); }
    catch (_) { return []; }
  }

  // ── Rename ────────────────────────────────────────────────────────────────

  Future<Map<String, List<LspTextEdit>>?> renameAt(
      CharPosition pos, String newName) async {
    if (!_opened) return null;
    try { return await client.rename(uri: uri, position: pos, newName: newName); }
    catch (_) { return null; }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  CompletionItemKind _mapKind(LspCompletionKind k) {
    switch (k) {
      case LspCompletionKind.keyword:       return CompletionItemKind.keyword;
      case LspCompletionKind.function_:     return CompletionItemKind.function_;
      case LspCompletionKind.method:        return CompletionItemKind.method;
      case LspCompletionKind.class_:        return CompletionItemKind.class_;
      case LspCompletionKind.variable:      return CompletionItemKind.variable;
      case LspCompletionKind.field:         return CompletionItemKind.field;
      case LspCompletionKind.constant:      return CompletionItemKind.constant;
      case LspCompletionKind.snippet:       return CompletionItemKind.snippet;
      case LspCompletionKind.constructor:   return CompletionItemKind.constructor;
      case LspCompletionKind.enum_:         return CompletionItemKind.enum_;
      case LspCompletionKind.enumMember:    return CompletionItemKind.property;
      case LspCompletionKind.module:        return CompletionItemKind.module;
      case LspCompletionKind.typeParameter: return CompletionItemKind.typeParameter;
      default:                              return CompletionItemKind.text;
    }
  }

  DiagnosticSeverity _mapSeverity(DiagnosticSeverity s) => s; // same enum
}
