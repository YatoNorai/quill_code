// lib/src/lsp/lsp_bridge.dart
// ─────────────────────────────────────────────────────────────────────────────
// LSP (Language Server Protocol) bridge.
// Provides an interface for connecting real LSP servers to QuillCodeEditor.
// Developers implement LspClient to forward requests to their LSP server
// (e.g. via dart_lsp_client, flutter_lsp, or a custom WebSocket/stdio bridge).
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import '../completion/completion_item.dart';
import '../core/char_position.dart';
import '../diagnostics/diagnostic_region.dart';
import '../text/text_range.dart';

// ── Data types ───────────────────────────────────────────────────────────────

enum LspCompletionKind {
  text, method, function_, constructor, field, variable, class_, interface,
  module, property, unit, value, enum_, keyword, snippet, color, file,
  reference, folder, enumMember, constant, struct, event, operator_, typeParameter,
}

class LspCompletionResult {
  final String label;
  final String? insertText;
  final String? filterText;
  final String? sortText;
  final String? detail;
  final String? documentation;
  final LspCompletionKind kind;
  final bool isSnippet;

  const LspCompletionResult({
    required this.label,
    this.insertText,
    this.filterText,
    this.sortText,
    this.detail,
    this.documentation,
    this.kind = LspCompletionKind.text,
    this.isSnippet = false,
  });

  CompletionItem toCompletionItem() => CompletionItem(
    label: label,
    kind: isSnippet ? CompletionItemKind.snippet : CompletionItemKind.text,
    detail: detail ?? '',
    insertText: insertText ?? label,
    isSnippet: isSnippet,
  );
}

/// Wraps an LSP CompletionList response, preserving the isIncomplete flag.
/// When [isIncomplete] is true the server can produce more items — re-request
/// with triggerKind=3 (TriggerForIncompleteCompletions) as the user types.
class LspCompletionList {
  final List<LspCompletionResult> items;
  final bool isIncomplete;
  const LspCompletionList({required this.items, this.isIncomplete = false});
  static const empty = LspCompletionList(items: []);
}

class LspDiagnostic {
  final EditorRange range;
  final String message;
  final DiagnosticSeverity severity;
  final String? source;
  final String? code;

  const LspDiagnostic({
    required this.range,
    required this.message,
    required this.severity,
    this.source,
    this.code,
  });
}

class LspHover {
  final String contents; // Markdown or plain text
  final EditorRange? range;
  const LspHover({required this.contents, this.range});
}

class LspLocation {
  final String uri;
  final EditorRange range;
  const LspLocation({required this.uri, required this.range});
}

class LspTextEdit {
  final EditorRange range;
  final String newText;
  const LspTextEdit({required this.range, required this.newText});
}

/// Signature help result: one signature with its parameters.
class LspSignatureHelp {
  /// Full signature label, e.g. `void foo(int x, String y)`.
  final String label;

  /// Optional documentation for this signature.
  final String? documentation;

  /// List of parameter labels (each is a substring of [label]).
  final List<String> parameters;

  /// Index of the currently-active parameter (0-based).
  final int activeParameter;

  const LspSignatureHelp({
    required this.label,
    this.documentation,
    required this.parameters,
    this.activeParameter = 0,
  });
}

/// A symbol in the document outline.
class LspDocumentSymbol {
  final String name;
  final String? detail;
  final int kind;        // SymbolKind from LSP spec (1=File … 26=TypeParameter)
  final EditorRange range;
  final EditorRange selectionRange;
  final List<LspDocumentSymbol> children;

  const LspDocumentSymbol({
    required this.name,
    this.detail,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.children = const [],
  });
}

/// A code lens item — an actionable annotation shown above a function/class.
class LspCodeLens {
  final EditorRange range;           // The line this lens belongs to
  final String? title;               // Display text (e.g. "3 references")
  final String? command;             // LSP command identifier
  final List<dynamic>? commandArgs;
  final Map<String, dynamic>? data;  // For resolve request

  const LspCodeLens({
    required this.range,
    this.title,
    this.command,
    this.commandArgs,
    this.data,
  });
}

/// An inlay hint (inline annotation, e.g. parameter name or inferred type).
class LspInlayHint {
  final CharPosition position;
  final String label;
  final bool isParameter; // true = param name, false = type annotation

  const LspInlayHint({
    required this.position,
    required this.label,
    required this.isParameter,
  });
}

// ── Client interface ─────────────────────────────────────────────────────────

/// Implement this interface to connect a real LSP server.
/// All methods are async and return null/empty on error.
abstract class LspClient {
  /// True once the LSP initialize handshake completed successfully.
  /// All methods that touch the server check this flag and return early if false.
  bool get isReady;
  /// Called when the editor opens a file.
  Future<void> didOpen({
    required String uri,
    required String languageId,
    required String text,
    required int version,
  });

  /// Called on every text change.
  Future<void> didChange({
    required String uri,
    required String text,
    required int version,
  });

  /// Called when the file is closed.
  Future<void> didClose({required String uri});

  /// Completion at cursor position.
  ///
  /// [triggerCharacter] — set when user typed a trigger char (`.`, `(`, etc.)
  ///   → sends triggerKind=2 (TriggerCharacter).
  /// [retriggerIncomplete] — set when the previous response had isIncomplete=true
  ///   → sends triggerKind=3 (TriggerForIncompleteCompletions).
  /// Otherwise sends triggerKind=1 (Invoked).
  Future<LspCompletionList> completion({
    required String uri,
    required CharPosition position,
    String? triggerCharacter,
    bool retriggerIncomplete = false,
  });

  /// Trigger characters reported by the server in its initialize response.
  /// Populated after the handshake; empty list before that.
  List<String> get triggerCharacters;

  /// Hover information at position.
  Future<LspHover?> hover({
    required String uri,
    required CharPosition position,
  });

  /// Signature help — shown when user types `(` or `,`.
  ///
  /// [triggerCharacter] is `(`, `,`, or null for manual invocation.
  Future<LspSignatureHelp?> signatureHelp({
    required String uri,
    required CharPosition position,
    String? triggerCharacter,
  });

  /// Go-to-definition.
  Future<List<LspLocation>> definition({
    required String uri,
    required CharPosition position,
  });

  /// Find all references.
  Future<List<LspLocation>> references({
    required String uri,
    required CharPosition position,
  });

  /// Get diagnostics (published by the server, polled here).
  Future<List<LspDiagnostic>> diagnostics({required String uri});

  /// Subscribe to server-pushed diagnostics for [uri].
  /// Called immediately every time the server sends a publishDiagnostics
  /// notification — no polling delay. Cancel the returned subscription when done.
  StreamSubscription<List<LspDiagnostic>> listenDiagnostics(
      String uri, void Function(List<LspDiagnostic> diags) onDiag);

  /// Subscribe to ALL server-pushed diagnostics regardless of URI.
  /// Dart analysis server, gopls, etc. push diagnostics for every file they
  /// analyse — not just the currently open one.  Use this to build a
  /// project-wide problems list without having to open every file.
  /// Cancel the returned subscription when done.
  StreamSubscription<void> listenAllDiagnostics(
      void Function(String uri, List<LspDiagnostic> diags) onDiag);

  /// Format entire document.
  Future<List<LspTextEdit>> formatting({required String uri});

  /// Format a range.
  Future<List<LspTextEdit>> rangeFormatting({
    required String uri,
    required EditorRange range,
  });

  /// Rename symbol.
  Future<Map<String, List<LspTextEdit>>?> rename({
    required String uri,
    required CharPosition position,
    required String newName,
  });

  /// Code actions at position.
  Future<List<LspCodeAction>> codeActions({
    required String uri,
    required EditorRange range,
  });

  /// Document outline symbols.
  Future<List<LspDocumentSymbol>> documentSymbols({required String uri});

  /// All occurrences of symbol under cursor (for highlight).
  Future<List<EditorRange>> documentHighlight({
    required String uri,
    required CharPosition position,
  });

  /// Inlay hints for the visible range.
  Future<List<LspInlayHint>> inlayHints({
    required String uri,
    required EditorRange range,
  });

  /// Lazy-resolve a single completion item to fill in documentation/detail.
  /// Returns null if the server doesn't support it or the request fails.
  /// This is the `completionItem/resolve` LSP request (Monaco pattern).
  Future<LspCompletionResult?> resolveCompletion(LspCompletionResult item);

  /// Code lens items for the document — small actionable annotations shown
  /// above functions/classes (e.g. "3 references | Run | Debug").
  Future<List<LspCodeLens>> codeLens({required String uri});

  /// Resolve a single code lens item to fill in its command/title.
  /// Returns null if the server doesn't support it or the request fails.
  Future<LspCodeLens?> resolveCodeLens(LspCodeLens item);

  /// Shutdown the server.
  Future<void> shutdown();
}

class LspCodeAction {
  final String title;
  final String kind; // e.g. 'quickfix', 'refactor'
  final List<LspTextEdit> edits;
  const LspCodeAction({required this.title, required this.kind, this.edits = const []});
}

// ── LSP-backed QuillLanguage adapter ────────────────────────────────────────

/// A no-op LSP client for testing / offline use.
class NullLspClient implements LspClient {
  const NullLspClient();
  @override bool get isReady => false;
  @override Future<void>   didOpen({required uri, required languageId, required text, required version}) async {}
  @override Future<void>   didChange({required uri, required text, required version}) async {}
  @override Future<void>   didClose({required uri}) async {}
  @override List<String> get triggerCharacters => const [];
  @override Future<LspCompletionList> completion({required uri, required position, triggerCharacter, retriggerIncomplete = false}) async => LspCompletionList.empty;
  @override Future<LspHover?> hover({required uri, required position}) async => null;
  @override Future<LspSignatureHelp?> signatureHelp({required uri, required position, triggerCharacter}) async => null;
  @override Future<List<LspLocation>> definition({required uri, required position}) async => [];
  @override Future<List<LspLocation>> references({required uri, required position}) async => [];
  @override Future<List<LspDiagnostic>> diagnostics({required uri}) async => [];
  @override StreamSubscription<List<LspDiagnostic>> listenDiagnostics(String uri, void Function(List<LspDiagnostic>) onDiag) =>
      const Stream<List<LspDiagnostic>>.empty().listen(onDiag);
  @override StreamSubscription<void> listenAllDiagnostics(void Function(String uri, List<LspDiagnostic>) onDiag) =>
      const Stream<void>.empty().listen((_) {});
  @override Future<List<LspTextEdit>> formatting({required uri}) async => [];
  @override Future<List<LspTextEdit>> rangeFormatting({required uri, required range}) async => [];
  @override Future<Map<String, List<LspTextEdit>>?> rename({required uri, required position, required newName}) async => null;
  @override Future<List<LspCodeAction>> codeActions({required uri, required range}) async => [];
  @override Future<List<LspDocumentSymbol>> documentSymbols({required uri}) async => [];
  @override Future<List<EditorRange>> documentHighlight({required uri, required position}) async => [];
  @override Future<List<LspInlayHint>> inlayHints({required uri, required range}) async => [];
  @override Future<LspCompletionResult?> resolveCompletion(LspCompletionResult item) async => null;
  @override Future<List<LspCodeLens>> codeLens({required uri}) async => [];
  @override Future<LspCodeLens?> resolveCodeLens(LspCodeLens item) async => null;
  @override Future<void> shutdown() async {}
}

