// lib/src/actions/standard_actions.dart
//
// Standard editor actions — identical to VSCode's built-in command palette items.
// These are the actions shown in the lightbulb / right-click / Ctrl+Shift+P menu.
//
// Each action is a QuillEditorAction with a title, icon, keyboard shortcut hint,
// and a callback.  The QuillActionMenu widget displays them as a VSCode-style list.

import 'package:flutter/material.dart';
import '../core/editor_controller.dart';

class QuillEditorAction {
  final String      title;
  final String?     description;
  final IconData?   icon;
  final String?     shortcut;   // display only, e.g. "Ctrl+Shift+F"
  final bool        dividerBefore;
  final Future<void> Function(QuillCodeController ctrl) execute;

  const QuillEditorAction({
    required this.title,
    this.description,
    this.icon,
    this.shortcut,
    this.dividerBefore = false,
    required this.execute,
  });
}

// ── Standard actions available in every editor ───────────────────────────────

class StandardEditorActions {
  static List<QuillEditorAction> build() => [
    // ── Edit ──────────────────────────────────────────────────────────────────
    QuillEditorAction(
      title: 'Undo',
      icon: Icons.undo,
      shortcut: 'Ctrl+Z',
      execute: (ctrl) async => ctrl.undo(),
    ),
    QuillEditorAction(
      title: 'Redo',
      icon: Icons.redo,
      shortcut: 'Ctrl+Y',
      execute: (ctrl) async => ctrl.redo(),
    ),
    QuillEditorAction(
      title: 'Select All',
      icon: Icons.select_all,
      shortcut: 'Ctrl+A',
      execute: (ctrl) async => ctrl.selectAll(),
    ),
    QuillEditorAction(
      title: 'Select Line',
      icon: Icons.wrap_text,
      execute: (ctrl) async => ctrl.selectLine(),
    ),
    QuillEditorAction(
      title: 'Select Word',
      icon: Icons.text_fields,
      execute: (ctrl) async => ctrl.selectWord(),
    ),
    QuillEditorAction(
      title: 'Delete Line',
      icon: Icons.delete_sweep,
      shortcut: 'Ctrl+Shift+K',
      dividerBefore: true,
      execute: (ctrl) async {
        ctrl.selectLine();
        if (ctrl.cursor.hasSelection) ctrl.deleteSelection();
        // Also delete the newline
        ctrl.deleteCharBefore();
      },
    ),
    QuillEditorAction(
      title: 'Duplicate Line',
      icon: Icons.content_copy,
      shortcut: 'Ctrl+D',
      execute: (ctrl) async {
        final line    = ctrl.cursor.line;
        final text    = ctrl.content.getLineText(line);
        ctrl.insertText('\n$text');
      },
    ),
    QuillEditorAction(
      title: 'Move Line Up',
      icon: Icons.arrow_upward,
      shortcut: 'Alt+Up',
      execute: (ctrl) async {
        final line = ctrl.cursor.line;
        if (line == 0) return;
        final current  = ctrl.content.getLineText(line);
        final above    = ctrl.content.getLineText(line - 1);
        // Replace both lines
        ctrl.selectLine();
        ctrl.insertText(above);
        ctrl.setCursor(ctrl.cursor.position.copyWith(line: line - 1));
        ctrl.selectLine();
        ctrl.insertText(current);
        ctrl.setCursor(ctrl.cursor.position.copyWith(line: line - 1));
      },
    ),
    QuillEditorAction(
      title: 'Move Line Down',
      icon: Icons.arrow_downward,
      shortcut: 'Alt+Down',
      execute: (ctrl) async {
        final line  = ctrl.cursor.line;
        final total = ctrl.content.lineCount;
        if (line >= total - 1) return;
        final current = ctrl.content.getLineText(line);
        final below   = ctrl.content.getLineText(line + 1);
        ctrl.selectLine();
        ctrl.insertText(below);
        ctrl.setCursor(ctrl.cursor.position.copyWith(line: line + 1));
        ctrl.selectLine();
        ctrl.insertText(current);
        ctrl.setCursor(ctrl.cursor.position.copyWith(line: line + 1));
      },
    ),

    // ── Code ──────────────────────────────────────────────────────────────────
    QuillEditorAction(
      title: 'Toggle Comment',
      icon: Icons.code,
      shortcut: 'Ctrl+/',
      dividerBefore: true,
      execute: (ctrl) async {
        final line    = ctrl.cursor.line;
        final text    = ctrl.content.getLineText(line);
        final trimmed = text.trimLeft();
        if (trimmed.startsWith('//')) {
          // Remove comment
          final idx = text.indexOf('//');
          final newText = text.substring(0, idx) + text.substring(idx + 2).trimLeft();
          ctrl.selectLine();
          ctrl.insertText(newText);
        } else {
          // Add comment
          final indent = text.length - trimmed.length;
          ctrl.selectLine();
          ctrl.insertText('${text.substring(0, indent)}// $trimmed');
        }
      },
    ),
    QuillEditorAction(
      title: 'Indent',
      icon: Icons.format_indent_increase,
      shortcut: 'Tab',
      execute: (ctrl) async => ctrl.insertTab(),
    ),
    QuillEditorAction(
      title: 'Outdent',
      icon: Icons.format_indent_decrease,
      shortcut: 'Shift+Tab',
      execute: (ctrl) async {
        final line = ctrl.cursor.line;
        final text = ctrl.content.getLineText(line);
        if (text.startsWith('  ')) {
          ctrl.selectLine();
          ctrl.insertText(text.substring(2));
        } else if (text.startsWith('\t')) {
          ctrl.selectLine();
          ctrl.insertText(text.substring(1));
        }
      },
    ),
    QuillEditorAction(
      title: 'Add Cursor Above',
      description: 'Insert newline before current line',
      icon: Icons.expand_less,
      shortcut: 'Ctrl+Shift+Enter',
      execute: (ctrl) async {
        final line = ctrl.cursor.line;
        final indent = _getIndent(ctrl, line);
        ctrl.setCursor(ctrl.cursor.position.copyWith(column: 0));
        ctrl.insertText('$indent\n');
        ctrl.setCursor(ctrl.cursor.position.copyWith(line: line, column: indent.length));
      },
    ),
    QuillEditorAction(
      title: 'Insert Line Below',
      icon: Icons.expand_more,
      shortcut: 'Ctrl+Enter',
      execute: (ctrl) async {
        final line   = ctrl.cursor.line;
        final lineLen = ctrl.content.getLineLength(line);
        final indent  = _getIndent(ctrl, line);
        ctrl.setCursor(ctrl.cursor.position.copyWith(column: lineLen));
        ctrl.insertText('\n$indent');
      },
    ),

    // ── View ──────────────────────────────────────────────────────────────────
    QuillEditorAction(
      title: 'Fold Block',
      icon: Icons.unfold_less,
      shortcut: 'Ctrl+Shift+[',
      dividerBefore: true,
      execute: (ctrl) async {
        final line   = ctrl.cursor.line;
        final blocks = ctrl.styles.codeBlocks;
        for (final b in blocks) {
          if (b.startLine == line && b.isFoldable) {
            ctrl.toggleFold(line);
            return;
          }
        }
      },
    ),
    QuillEditorAction(
      title: 'Unfold Block',
      icon: Icons.unfold_more,
      shortcut: 'Ctrl+Shift+]',
      execute: (ctrl) async {
        final line = ctrl.cursor.line;
        if (ctrl.isFolded(line)) ctrl.toggleFold(line);
      },
    ),
    QuillEditorAction(
      title: 'Fold All',
      icon: Icons.compress,
      execute: (ctrl) async {
        for (final b in ctrl.styles.codeBlocks) {
          if (b.isFoldable && !ctrl.isFolded(b.startLine)) {
            ctrl.toggleFold(b.startLine);
          }
        }
      },
    ),
    QuillEditorAction(
      title: 'Unfold All',
      icon: Icons.expand,
      execute: (ctrl) async {
        for (final startLine in List.of(ctrl.foldedBlocks)) {
          ctrl.toggleFold(startLine);
        }
      },
    ),

    // ── Transform ─────────────────────────────────────────────────────────────
    QuillEditorAction(
      title: 'Transform to Uppercase',
      icon: Icons.text_fields,
      dividerBefore: true,
      execute: (ctrl) async {
        if (!ctrl.cursor.hasSelection) ctrl.selectWord();
        final text = ctrl.copyText();
        if (text != null) ctrl.pasteText(text.toUpperCase());
      },
    ),
    QuillEditorAction(
      title: 'Transform to Lowercase',
      icon: Icons.text_fields,
      execute: (ctrl) async {
        if (!ctrl.cursor.hasSelection) ctrl.selectWord();
        final text = ctrl.copyText();
        if (text != null) ctrl.pasteText(text.toLowerCase());
      },
    ),
    QuillEditorAction(
      title: 'Trim Trailing Whitespace',
      icon: Icons.cleaning_services,
      execute: (ctrl) async {
        final lines = ctrl.text.split('\n');
        final trimmed = lines.map((l) => l.trimRight()).join('\n');
        if (trimmed != ctrl.text) ctrl.setText(trimmed);
      },
    ),
  ];

  static String _getIndent(QuillCodeController ctrl, int line) {
    final text = ctrl.content.getLineText(line);
    int i = 0;
    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) i++;
    return text.substring(0, i);
  }
}
