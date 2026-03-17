// lib/src/completion/ghost_text_controller.dart
//
// Ghost text — inline AI / snippet suggestions exactly like VSCode Copilot:
//
//  • Provider is called after typing stops (debounce).
//  • Rendered as faded text after the cursor on the same line, plus ghost lines below.
//  • Tab  = accept full suggestion.
//  • Escape / any cursor move = dismiss.
//  • Multiple candidates cycle with Alt+] / Alt+[.
//
// INTEGRATION
//   controller.setGhostTextProvider(SnippetGhostProvider(languageId: 'dart').call);
//   // OR supply an API-backed provider for real Copilot-style suggestions.

import 'dart:async';

// ─────────────────────────────────────────────────────────────────────────────
// Context passed to every provider call
// ─────────────────────────────────────────────────────────────────────────────

class GhostTextContext {
  final String documentText;
  final int    line;
  final int    column;
  final String linePrefix;   // text on current line left of cursor
  final String lineSuffix;   // text on current line right of cursor
  final String languageId;

  const GhostTextContext({
    required this.documentText,
    required this.line,
    required this.column,
    required this.linePrefix,
    required this.lineSuffix,
    required this.languageId,
  });
}

typedef GhostTextProvider = Future<List<String>> Function(GhostTextContext ctx);

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

class GhostTextController {
  GhostTextProvider? _provider;

  /// True when a provider is set.
  bool get hasProvider => _provider != null;

  List<String>       _lines       = const [];  // current ghost text lines
  List<List<String>> _candidates  = const [];  // all suggestion candidates
  int                _idx         = 0;          // which candidate is active
  int                _atLine      = -1;
  int                _atColumn    = -1;

  Timer? _debounce;
  bool   _destroyed = false;
  // Monotonically-increasing sequence number. Incremented on every debounced
  // _fetch() call so stale async responses are silently discarded.
  int    _reqSeq    = 0;

  final List<void Function()> _listeners = [];
  void addListener(void Function() l)    => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _notify() { for (final l in List.of(_listeners)) l(); }

  // ── Public state ──────────────────────────────────────────────────────────

  bool         get isVisible      => _lines.isNotEmpty;
  /// Number of EXTRA virtual rows the ghost text occupies below the cursor line.
  /// e.g. if ghostLines = ['in() {', '  body', '}'] → extraRows = 2 (lines 1 and 2 are virtual).
  int          get extraRows       => _lines.isEmpty ? 0 : (_lines.length - 1).clamp(0, 9999);
  List<String> get ghostLines     => _lines;
  int          get atLine         => _atLine;
  int          get atColumn       => _atColumn;
  int          get candidateCount => _candidates.length;
  int          get currentIndex   => _idx;

  // ── Configuration ─────────────────────────────────────────────────────────

  void setProvider(GhostTextProvider? p) {
    _provider = p;
    if (p == null) dismiss();
  }

  // ── Called by the editor on every keystroke ───────────────────────────────

  void onEdit({
    required String documentText,
    required int    line,
    required int    column,
    required String linePrefix,
    required String lineSuffix,
    required String languageId,
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    // Immediately clear — ghost text disappears while typing (like VSCode).
    if (isVisible) { _lines = const []; _notify(); }
    if (_provider == null || _destroyed) return;
    _debounce?.cancel();
    final seq = ++_reqSeq;
    _debounce = Timer(debounce, () => _fetch(GhostTextContext(
      documentText: documentText,
      line:         line,
      column:       column,
      linePrefix:   linePrefix,
      lineSuffix:   lineSuffix,
      languageId:   languageId,
    ), seq));
  }

  Future<void> _fetch(GhostTextContext ctx, int seq) async {
    if (_provider == null || _destroyed) return;
    List<String> results;
    try { results = await _provider!(ctx); }
    catch (_) { results = const []; }
    // Discard stale response — a newer edit/request fired while we were waiting.
    if (_destroyed || seq != _reqSeq) return;

    final candidates = results
        .where((s) => s.isNotEmpty)
        .map((s) => _stripPrefix(s, ctx.linePrefix))
        .where((s) => s.isNotEmpty)
        .map((s) => s.split('\n'))
        .toList();
    if (candidates.isEmpty) return;

    _candidates = candidates;
    _idx        = 0;
    _atLine     = ctx.line;
    _atColumn   = ctx.column;
    _lines      = candidates[0];
    _notify();
  }

  /// Strip the already-typed linePrefix from the AI completion.
  ///
  /// AI models sometimes echo back the full line ("void main() {") when the
  /// user already typed part of it ("void ma"). We remove the overlap so only
  /// the missing part is shown as ghost text.
  ///
  /// Strategy: find the longest suffix of [prefix] that is a prefix of [text],
  /// then strip it. Falls back to full [text] if there's no overlap.
  static String _stripPrefix(String text, String prefix) {
    if (prefix.isEmpty) return text;
    // Try progressively shorter suffixes of prefix
    for (int len = prefix.length; len > 0; len--) {
      final suffix = prefix.substring(prefix.length - len);
      if (text.startsWith(suffix)) {
        return text.substring(suffix.length);
      }
    }
    return text;
  }

  // ── Accept (Tab key) — returns text to insert ─────────────────────────────

  String? accept() {
    if (!isVisible) return null;
    final text = _lines.join('\n');
    // notify: true so _EBox clears _ghostInsertVi/_ghostExtraRows immediately
    // and the virtual ghost rows disappear from the layout on the same frame.
    dismiss(notify: true);
    return text;
  }

  // ── Accept one word (Alt+Right) ───────────────────────────────────────────

  String? acceptWord() {
    if (!isVisible || _lines.isEmpty) return null;
    final first = _lines[0];
    int i = 0;
    // Skip leading whitespace
    while (i < first.length && _isWs(first.codeUnitAt(i))) i++;
    // Consume word chars
    while (i < first.length && _isWordChar(first.codeUnitAt(i))) i++;
    if (i == 0) i = 1;

    final partial   = first.substring(0, i);
    final remainder = first.substring(i);
    final newLines  = remainder.isEmpty ? _lines.sublist(1)
                                        : [remainder, ..._lines.sublist(1)];
    if (newLines.isEmpty) {
      dismiss();
    } else {
      _lines = newLines;
      if (_idx < _candidates.length) _candidates[_idx] = _lines;
      _notify();
    }
    return partial;
  }

  static bool _isWs(int c)       => c == 32 || c == 9;
  static bool _isWordChar(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) || c == 95;

  // ── Cycle candidates (Alt+] / Alt+[) ─────────────────────────────────────

  void nextCandidate() {
    if (_candidates.length <= 1) return;
    _idx   = (_idx + 1) % _candidates.length;
    _lines = _candidates[_idx];
    _notify();
  }

  void previousCandidate() {
    if (_candidates.length <= 1) return;
    _idx   = (_idx - 1 + _candidates.length) % _candidates.length;
    _lines = _candidates[_idx];
    _notify();
  }

  // ── Dismiss (Escape / cursor move / edit) ─────────────────────────────────

  void dismiss({bool notify = true}) {
    _debounce?.cancel();
    final wasVisible = isVisible;
    _lines      = const [];
    _candidates = const [];
    _idx        = 0;
    _atLine     = -1;
    _atColumn   = -1;
    if (notify && wasVisible) _notify();
  }

  void destroy() {
    _destroyed = true;
    _debounce?.cancel();
    _reqSeq++;   // invalidate any in-flight request
    _listeners.clear();
  }
}

// ── Extra line count exposed for layout ──────────────────────────────────────
// The renderer needs to know how many EXTRA (virtual) rows to insert after
// atLine so the real content below gets pushed down.
