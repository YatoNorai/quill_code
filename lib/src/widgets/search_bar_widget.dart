// lib/src/widgets/search_bar_widget.dart
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../search/search_options.dart';
import '../theme/editor_theme.dart';
import '../theme/color_scheme.dart';
import '../text/text_range.dart';

class QuillSearchBar extends StatefulWidget {
  final QuillCodeController controller;
  final EditorTheme theme;
  final VoidCallback onClose;

  const QuillSearchBar({
    super.key,
    required this.controller,
    required this.theme,
    required this.onClose,
  });

  @override
  State<QuillSearchBar> createState() => _QuillSearchBarState();
}

class _QuillSearchBarState extends State<QuillSearchBar> {
  final TextEditingController _searchCtrl  = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _caseSensitive = false;
  bool _wholeWord     = false;
  bool _regex         = false;
  bool _showReplace   = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field when the bar opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _replaceCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _search() {
    final pattern = _searchCtrl.text;
    if (pattern.isEmpty) {
      widget.controller.searcher.stopSearch();
      setState(() {});
      return;
    }
    final type = _regex
        ? SearchType.regularExpression
        : _wholeWord
            ? SearchType.wholeWord
            : SearchType.plainText;
    widget.controller.searcher.search(pattern, SearchOptions(caseSensitive: _caseSensitive, type: type));
    // Scroll to first result after debounce settles.
    Future.delayed(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      _scrollToCurrentResult();
      setState(() {});
    });
  }

  /// Navigate to [result] range: set cursor + scroll the editor viewport.
  void _gotoResult(EditorRange? r) {
    if (r == null) return;
    widget.controller.setCursor(r.start);
    // Bump decorVersion so _paintSearch re-fires with the new currentResultIndex.
    widget.controller.decorVersion.value++;
  }

  void _goNext() {
    final r = widget.controller.searcher.gotoNext(widget.controller.cursor.position);
    _gotoResult(r);
    _scrollToCurrentResult();
    setState(() {});
  }

  void _goPrev() {
    final r = widget.controller.searcher.gotoPrevious(widget.controller.cursor.position);
    _gotoResult(r);
    _scrollToCurrentResult();
    setState(() {});
  }

  /// Tells the editor to scroll so the current search result is visible.
  /// The controller's setCursor already calls _ensureCursorVisible internally,
  /// so this is a belt-and-suspenders no-op for now; kept as extension point.
  void _scrollToCurrentResult() {
    final idx = widget.controller.searcher.currentResultIndex;
    final results = widget.controller.searcher.results;
    if (idx < 0 || idx >= results.length) return;
    // setCursor already triggers _ensureCursorVisible in the editor.
    // No extra work needed.
  }

  InputDecoration _inputDec(String hint, EditorColorScheme cs, double fs) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: cs.lineNumber, fontSize: fs),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: cs.blockLine)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: cs.blockLine)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: cs.cursor)),
        filled: true,
        fillColor: cs.background,
      );

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    final fs = widget.theme.fontSize;
    final ff = widget.theme.fontFamily;
    final ts = TextStyle(color: cs.textNormal, fontSize: fs, fontFamily: ff);

    return Container(
      color: cs.lineNumberBackground,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Find row ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: (_) => _search(),
                  // Enter = go next, Shift+Enter = go prev
                  onSubmitted: (_) => _goNext(),
                  style: ts,
                  decoration: _inputDec('Find…', cs, fs),
                ),
              ),
              const SizedBox(width: 6),
              // Result count badge
              StreamBuilder<List>(
                stream: widget.controller.searcher.resultsStream,
                builder: (_, __) {
                  final total = widget.controller.searcher.resultCount;
                  final cur   = widget.controller.searcher.currentResultIndex;
                  final label = total == 0
                      ? 'No results'
                      : '${cur >= 0 ? cur + 1 : 1} of $total';
                  return Text(label,
                      style: TextStyle(
                          color: total == 0 ? cs.problemError : cs.lineNumber,
                          fontSize: fs * 0.82));
                },
              ),
              const SizedBox(width: 4),
              // Toggle: case-sensitive
              _TB(label: 'Aa', tooltip: 'Match Case',       active: _caseSensitive, cs: cs, fs: fs,
                  onTap: () => setState(() { _caseSensitive = !_caseSensitive; _search(); })),
              // Toggle: whole word
              _TB(label: 'W', tooltip: 'Whole Word',        active: _wholeWord,     cs: cs, fs: fs,
                  onTap: () => setState(() { _wholeWord = !_wholeWord; _search(); })),
              // Toggle: regex
              _TB(label: '.*', tooltip: 'Use RegExp',       active: _regex,         cs: cs, fs: fs,
                  onTap: () => setState(() { _regex = !_regex; _search(); })),
              // Toggle: show replace
              _TB(label: '↔', tooltip: 'Toggle Replace',   active: _showReplace,   cs: cs, fs: fs,
                  onTap: () => setState(() => _showReplace = !_showReplace)),
              // Navigate prev/next
              _IBtn(icon: Icons.keyboard_arrow_up,   tooltip: 'Previous Match', cs: cs, onTap: _goPrev),
              _IBtn(icon: Icons.keyboard_arrow_down, tooltip: 'Next Match',     cs: cs, onTap: _goNext),
              _IBtn(icon: Icons.close,               tooltip: 'Close Search',   cs: cs, onTap: () {
                widget.controller.searcher.stopSearch();
                widget.onClose();
              }),
            ],
          ),
          // ── Replace row ───────────────────────────────────────────────
          if (_showReplace) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceCtrl,
                    style: ts,
                    decoration: _inputDec('Replace…', cs, fs),
                  ),
                ),
                const SizedBox(width: 6),
                _Btn(label: 'Replace', cs: cs, fs: fs,
                    onTap: () { widget.controller.searcher.replaceCurrent(_replaceCtrl.text); setState(() {}); }),
                const SizedBox(width: 4),
                _Btn(label: 'Replace All', cs: cs, fs: fs,
                    onTap: () { widget.controller.searcher.replaceAll(_replaceCtrl.text); setState(() {}); }),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _TB extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final EditorColorScheme cs;
  final double fs;
  final VoidCallback onTap;
  const _TB({required this.label, required this.tooltip, required this.active,
              required this.cs, required this.fs, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? cs.cursor.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? cs.cursor : cs.blockLine),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? cs.cursor : cs.lineNumber,
                fontSize: fs * 0.82,
                fontWeight: FontWeight.bold)),
      ),
    ),
  );
}

class _IBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final EditorColorScheme cs;
  final VoidCallback onTap;
  const _IBtn({required this.icon, required this.tooltip, required this.cs, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: cs.textNormal, size: 18)),
    ),
  );
}

class _Btn extends StatelessWidget {
  final String label;
  final EditorColorScheme cs;
  final double fs;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.cs, required this.fs, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: cs.cursor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: cs.cursor.withOpacity(0.4))),
      child: Text(label,
          style: TextStyle(
              color: cs.cursor, fontSize: fs * 0.85, fontWeight: FontWeight.w600)),
    ),
  );
}
