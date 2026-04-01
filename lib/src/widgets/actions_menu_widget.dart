// lib/src/widgets/actions_menu_widget.dart
//
// QuillActionsMenu — VSCode-style command palette overlay.
// Shows StandardEditorActions + any LSP code actions at the cursor.
// Triggered by Ctrl+Shift+P or the lightbulb icon.
//
// Usage:
//   QuillActionsMenu.show(context, controller, theme);

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/editor_controller.dart';
import '../theme/editor_theme.dart';
import '../theme/color_scheme.dart';
import '../actions/standard_actions.dart';

class QuillActionsMenu extends StatefulWidget {
  final QuillCodeController controller;
  final EditorTheme         theme;
  final VoidCallback?       onClose;
  /// Called when the user selects "Go to Line" from the menu.
  /// The host widget should show the go-to-line overlay in response.
  final VoidCallback?       onGotoLine;
  /// Called when the user selects "Format Document" from the menu.
  final VoidCallback?       onFormatDocument;

  const QuillActionsMenu({
    super.key,
    required this.controller,
    required this.theme,
    this.onClose,
    this.onGotoLine,
    this.onFormatDocument,
  });

  /// Shows the action menu as a modal overlay.
  static Future<void> show(
    BuildContext context,
    QuillCodeController controller,
    EditorTheme theme, {
    VoidCallback? onGotoLine,
    VoidCallback? onFormatDocument,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => QuillActionsMenu(
        controller: controller,
        theme: theme,
        onClose: () => Navigator.of(context, rootNavigator: true).pop(),
        onGotoLine: onGotoLine,
        onFormatDocument: onFormatDocument,
      ),
    );
  }

  @override
  State<QuillActionsMenu> createState() => _QuillActionsMenuState();
}

class _QuillActionsMenuState extends State<QuillActionsMenu> {
  final TextEditingController _filter = TextEditingController();
  final FocusNode             _focus  = FocusNode();
  final ScrollController      _scroll = ScrollController();
  int    _selected = 0;
  List<QuillEditorAction> _actions = const [];
  List<QuillEditorAction> _filtered = const [];

  @override
  void initState() {
    super.initState();
    final base = StandardEditorActions.build();
    // Append widget-level actions (Go to Line, Format Document) that need
    // callbacks into the host widget rather than pure controller calls.
    final extra = <QuillEditorAction>[
      if (widget.onGotoLine != null)
        QuillEditorAction(
          title: 'Go to Line\u2026',
          icon: Icons.vertical_align_center,
          shortcut: 'Ctrl+G',
          dividerBefore: true,
          execute: (_) async {
            widget.onClose?.call();
            widget.onGotoLine!();
          },
        ),
      if (widget.onFormatDocument != null)
        QuillEditorAction(
          title: 'Format Document',
          icon: Icons.auto_fix_high,
          shortcut: 'Shift+Alt+F',
          dividerBefore: widget.onGotoLine == null,
          execute: (_) async {
            widget.onClose?.call();
            widget.onFormatDocument!();
          },
        ),
    ];
    _actions  = [...base, ...extra];
    _filtered = _actions;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _filter.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _applyFilter(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filtered = _actions
          .where((a) =>
              a.title.toLowerCase().contains(lower) ||
              (a.description?.toLowerCase().contains(lower) ?? false))
          .toList();
      _selected = 0;
    });
  }

  void _execute(QuillEditorAction action) {
    widget.onClose?.call();
    action.execute(widget.controller);
  }

  void _handleKey(KeyEvent ev) {
    if (ev is! KeyDownEvent) return;
    final key = ev.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1).clamp(0, _filtered.length - 1));
      _scrollTo(_selected);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1).clamp(0, _filtered.length - 1));
      _scrollTo(_selected);
    } else if (key == LogicalKeyboardKey.enter && _filtered.isNotEmpty) {
      _execute(_filtered[_selected]);
    } else if (key == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
    }
  }

  void _scrollTo(int idx) {
    final offset = idx * 44.0;
    _scroll.animateTo(offset.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    final fs = widget.theme.fontSize;
    final ff = widget.theme.fontFamily;

    return Material(
      color: Colors.transparent,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: _handleKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 60),
            width: 480,
            constraints: const BoxConstraints(maxHeight: 420),
            decoration: BoxDecoration(
              color: cs.completionBackground,
              border: Border.all(color: cs.completionBorder),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Search field ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _filter,
                    focusNode: _focus,
                    onChanged: _applyFilter,
                    style: TextStyle(
                        color: cs.textNormal, fontSize: fs, fontFamily: ff),
                    decoration: InputDecoration(
                      hintText: 'Type a command…',
                      hintStyle: TextStyle(color: cs.lineNumber, fontSize: fs),
                      prefixIcon: Icon(Icons.search, color: cs.lineNumber, size: 16),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: cs.background,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: cs.blockLine)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: cs.blockLine)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: cs.cursor)),
                    ),
                  ),
                ),
                const Divider(height: 1),
                // ── Action list ───────────────────────────────────────────────
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _filtered.length,
                    itemExtent: 44,
                    itemBuilder: (_, i) {
                      final action = _filtered[i];
                      final isSelected = i == _selected;
                      return InkWell(
                        onTap: () => _execute(action),
                        child: Container(
                          height: 44,
                          color: isSelected
                              ? cs.completionItemSelected
                              : Colors.transparent,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(
                                action.icon ?? Icons.play_arrow,
                                color: isSelected
                                    ? cs.completionTextMatched
                                    : cs.lineNumber,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  action.title,
                                  style: TextStyle(
                                    color: isSelected
                                        ? cs.completionTextPrimary
                                        : cs.textNormal,
                                    fontSize: fs,
                                    fontFamily: ff,
                                  ),
                                ),
                              ),
                              if (action.shortcut != null)
                                Text(
                                  action.shortcut!,
                                  style: TextStyle(
                                    color: cs.lineNumber,
                                    fontSize: fs * 0.82,
                                    fontFamily: ff,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
