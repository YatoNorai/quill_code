// lib/src/lsp/quill_lsp_config.dart
// ─────────────────────────────────────────────────────────────────────────────
// User-facing configuration for connecting an LSP server to QuillCodeEditor.
//
// Usage:
//
//   // stdio (pyright, rust-analyzer, clangd, dart language-server…)
//   QuillCodeEditor(
//     controller: ctrl,
//     lspConfig: QuillLspStdioConfig(
//       executable: 'pyright-langserver',
//       args: ['--stdio'],
//       workspacePath: '/my/project',
//       languageId: 'python',
//       capabilities: QuillLspCapabilities(signatureHelp: true),
//     ),
//   )
//
//   // WebSocket (remote / browser-compatible)
//   QuillCodeEditor(
//     controller: ctrl,
//     lspConfig: QuillLspSocketConfig(
//       url: 'ws://localhost:2087',
//       workspacePath: '/my/project',
//       languageId: 'dart',
//     ),
//   )
// ─────────────────────────────────────────────────────────────────────────────

/// Which LSP features the editor should advertise and use.
///
/// Disable individual capabilities to reduce network traffic or to work around
/// server quirks (e.g. a server that crashes on `signatureHelp` requests).
class QuillLspCapabilities {
  /// Auto-completion suggestions (textDocument/completion).
  final bool completion;

  /// Hover documentation panel (textDocument/hover).
  final bool hover;

  /// Signature-help tooltip when typing function arguments
  /// (textDocument/signatureHelp). Shows parameter names + docs.
  final bool signatureHelp;

  /// Inline error/warning squiggles (textDocument/publishDiagnostics).
  final bool diagnostics;

  /// Go-to-definition tap (textDocument/definition).
  final bool definition;

  /// Find all references (textDocument/references).
  final bool references;

  /// Quick-fix / refactor lightbulb (textDocument/codeAction).
  final bool codeAction;

  /// Rename symbol across workspace (textDocument/rename).
  final bool rename;

  /// Whole-file formatting (textDocument/formatting).
  final bool formatting;

  /// Document outline / symbol panel (textDocument/documentSymbol).
  final bool documentSymbols;

  /// Highlight all occurrences of symbol under cursor
  /// (textDocument/documentHighlight).
  final bool documentHighlight;

  /// Inline type / parameter name hints (textDocument/inlayHint).
  final bool inlayHints;

  const QuillLspCapabilities({
    this.completion       = true,
    this.hover            = true,
    this.signatureHelp    = true,
    this.diagnostics      = true,
    this.definition       = true,
    this.references       = true,
    this.codeAction       = true,
    this.rename           = true,
    this.formatting       = true,
    this.documentSymbols  = true,
    this.documentHighlight= true,
    this.inlayHints       = false, // off by default — not all servers support it
  });

  /// Disable every capability (useful for testing).
  static const disabled = QuillLspCapabilities(
    completion: false, hover: false, signatureHelp: false,
    diagnostics: false, definition: false, references: false,
    codeAction: false, rename: false, formatting: false,
    documentSymbols: false, documentHighlight: false, inlayHints: false,
  );
}

// ── Sealed config variants ───────────────────────────────────────────────────

sealed class QuillLspConfig {
  /// The LSP language ID sent during initialization.
  /// Examples: 'dart', 'python', 'rust', 'typescript', 'cpp', 'java'.
  final String languageId;

  /// Absolute path to the workspace root. If analyzing a single file, use
  /// its parent directory.
  final String workspacePath;

  /// Fine-grained feature flags.
  final QuillLspCapabilities capabilities;

  const QuillLspConfig({
    required this.languageId,
    required this.workspacePath,
    this.capabilities = const QuillLspCapabilities(),
  });
}

/// Connect to an LSP server started as a local child process (stdio transport).
///
/// Works with: `dart language-server`, `pyright-langserver --stdio`,
/// `rust-analyzer`, `clangd`, `typescript-language-server --stdio`, etc.
///
/// ```dart
/// QuillLspStdioConfig(
///   executable: '/usr/bin/dart',
///   args: ['language-server', '--client-id=myapp'],
///   workspacePath: '/path/to/project',
///   languageId: 'dart',
/// )
/// ```
class QuillLspStdioConfig extends QuillLspConfig {
  /// Path to the LSP server executable (e.g. 'pyright-langserver').
  final String executable;

  /// Command-line arguments passed to the executable.
  final List<String> args;

  /// Optional environment variables for the server process.
  final Map<String, String>? environment;

  const QuillLspStdioConfig({
    required this.executable,
    required super.languageId,
    required super.workspacePath,
    this.args = const [],
    this.environment,
    super.capabilities,
  });
}

/// Connect to an LSP server over a WebSocket (JSON-RPC 2.0 over ws://).
///
/// Useful for: remote servers, browser environments, or any server that speaks
/// LSP over WebSocket (e.g. `pylsp-ws`, custom bridges).
///
/// ```dart
/// QuillLspSocketConfig(
///   url: 'ws://localhost:2087',
///   workspacePath: '/path/to/project',
///   languageId: 'python',
/// )
/// ```
class QuillLspSocketConfig extends QuillLspConfig {
  /// WebSocket URL of the LSP server (e.g. `ws://localhost:2087`).
  final String url;

  const QuillLspSocketConfig({
    required this.url,
    required super.languageId,
    required super.workspacePath,
    super.capabilities,
  });
}
