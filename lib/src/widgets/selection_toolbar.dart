// lib/src/widgets/selection_toolbar.dart
// Floating selection toolbar — like Sora/VSCode mobile
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/editor_controller.dart';
import '../theme/editor_theme.dart';
// ignore: avoid_relative_lib_imports — needed inside package
import 'dart:math' as math;
import '../core/char_position.dart';
import '../text/text_range.dart';

typedef _CB = VoidCallback;

class SelectionToolbar extends StatelessWidget {
  final QuillCodeController controller;
  final EditorTheme theme;
  final Offset position; // local anchor (above selection start)
  final Size vpSize;
  final VoidCallback onDismiss;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;

  const SelectionToolbar({
    super.key,
    required this.controller,
    required this.theme,
    required this.position,
    required this.vpSize,
    required this.onDismiss,
    this.onCut,
    this.onCopy,
    this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final cs   = theme.colorScheme;
    final hasSel = controller.cursor.hasSelection;

    final items = <_ToolItem>[
      if (hasSel) _ToolItem('Cut',     Icons.content_cut,     () { onCut?.call(); onDismiss(); }),
      if (hasSel) _ToolItem('Copy',    Icons.content_copy,    () { onCopy?.call(); onDismiss(); }),
      _ToolItem('Paste',   Icons.content_paste,   () { onPaste?.call(); onDismiss(); }),
      if (hasSel) _ToolItem('Select Line',  Icons.select_all,      () { controller.selectLine();  }),
      _ToolItem('Select All', Icons.checklist_rtl, () { controller.selectAll(); onDismiss(); }),
      if (hasSel) _ToolItem('Indent',   Icons.format_indent_increase, () { _indent(); }),
      if (hasSel) _ToolItem('Unindent', Icons.format_indent_decrease, () { _unindent(); }),
      if (hasSel) _ToolItem('Comment',  Icons.code,            () { _toggleComment(); onDismiss(); }),
      if (hasSel) _ToolItem('UPPER',    Icons.arrow_upward,    () { _toUpper(); onDismiss(); }),
      if (hasSel) _ToolItem('lower',    Icons.arrow_downward,  () { _toLower(); onDismiss(); }),
      _ToolItem('Undo',    Icons.undo,             () { controller.undo(); onDismiss(); }),
      _ToolItem('Redo',    Icons.redo,             () { controller.redo(); onDismiss(); }),
    ];

    // Clamp horizontal position so toolbar stays on screen
    const toolW = 52.0; // per item
    final totalW = math.min(items.length * toolW, vpSize.width - 8.0);
    final leftX  = (position.dx - totalW / 2).clamp(4.0, vpSize.width - totalW - 4.0);
    // Show above cursor, flip below if too close to top
    final topY = position.dy - 52 < 8 ? position.dy + 8 : position.dy - 52;

    return Positioned(
      left: leftX,
      top:  topY,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: cs.completionBackground,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: items.map((it) => _buildBtn(it, cs)).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBtn(_ToolItem it, dynamic cs) {
    return Tooltip(
      message: it.label,
      child: InkWell(
        onTap: it.action,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(it.icon, size: 18, color: cs.lineNumberCurrent),
        ),
      ),
    );
  }

  void _indent() {
    final sel = controller.cursor.selection;
    for (int line = sel.start.line; line <= sel.end.line; line++) {
      final indent = controller.props.useSpacesForTabs
          ? ' ' * controller.props.tabSize : '\t';
      controller.content.insert(
        CharPosition(line, 0),
        indent,
      );
    }
  }

  void _unindent() {
    final sel = controller.cursor.selection;
    for (int line = sel.start.line; line <= sel.end.line; line++) {
      final text = controller.content.getLineText(line);
      if (text.startsWith('    ')) {
        controller.content.delete(EditorRange(
          CharPosition(line, 0), CharPosition(line, 4)));
      } else if (text.startsWith('\t')) {
        controller.content.delete(EditorRange(
          CharPosition(line, 0), CharPosition(line, 1)));
      }
    }
  }

  void _toggleComment() {
    final sel = controller.cursor.selection;
    final lang = controller.language.lineCommentPrefix;
    if (lang.isEmpty) return;
    for (int line = sel.start.line; line <= sel.end.line; line++) {
      final text = controller.content.getLineText(line);
      if (text.trimLeft().startsWith(lang)) {
        final idx = text.indexOf(lang);
        controller.content.delete(EditorRange(
          CharPosition(line, idx), CharPosition(line, idx + lang.length)));
      } else {
        controller.content.insert(CharPosition(line, 0), lang);
      }
    }
  }

  void _toUpper() {
    final sel  = controller.cursor.selection;
    final text = controller.content.getTextInRange(sel);
    controller.content.delete(sel);
    controller.content.insert(sel.start, text.toUpperCase());
    controller.cursor.setSelection(sel.start,
        CharPosition(sel.start.line, sel.start.column + text.length));
  }

  void _toLower() {
    final sel  = controller.cursor.selection;
    final text = controller.content.getTextInRange(sel);
    controller.content.delete(sel);
    controller.content.insert(sel.start, text.toLowerCase());
    controller.cursor.setSelection(sel.start,
        CharPosition(sel.start.line, sel.start.column + text.length));
  }
}

class _ToolItem {
  final String label;
  final IconData icon;
  final VoidCallback action;
  const _ToolItem(this.label, this.icon, this.action);
}

