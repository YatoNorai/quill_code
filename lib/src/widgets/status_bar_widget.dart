// lib/src/widgets/status_bar_widget.dart
//
// A thin bottom bar that mirrors VSCode's status bar.
// Shows: cursor position, selection length, line count, language, line endings.
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../theme/editor_theme.dart';
import '../text/line_separator.dart';

class StatusBarWidget extends StatelessWidget {
  final QuillCodeController controller;
  final EditorTheme theme;

  const StatusBarWidget({
    super.key,
    required this.controller,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Listen to both cursor and content changes so the bar stays in sync.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cs     = theme.colorScheme;
        final cursor = controller.cursor;
        final pos    = cursor.position;
        final hasSel = cursor.hasSelection;

        final int selLen = hasSel
            ? controller.content
                .getTextInRange(cursor.selection)
                .length
            : 0;

        final String langName = controller.language.name;
        final int    lines    = controller.content.lineCount;
        final String eol      = _eolLabel(controller.content.lineSeparator);

        // Background: slightly lighter / darker than the line-number gutter —
        // looks natural without introducing a new color token.
        final Color bg = Color.lerp(
          cs.lineNumberBackground,
          cs.background,
          0.35,
        )!;

        final TextStyle labelStyle = TextStyle(
          fontSize:      11,
          fontFamily:    theme.fontFamily,
          color:         cs.lineNumber.withValues(alpha: 0.85),
          height:        1.0,
          letterSpacing: 0.2,
        );

        return Container(
          height: 22,
          color:  bg,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // ── Left group: cursor position (+ selection count) ──────
              _StatusItem(
                label: hasSel
                    ? 'Ln ${pos.line + 1}, Col ${pos.column + 1}'
                      '  ($selLen selected)'
                    : 'Ln ${pos.line + 1}, Col ${pos.column + 1}',
                style: labelStyle,
              ),

              const Spacer(),

              // ── Right group ──────────────────────────────────────────
              _StatusItem(label: '$lines lines', style: labelStyle),
              _StatusDivider(color: cs.blockLine),
              _StatusItem(label: langName,       style: labelStyle),
              _StatusDivider(color: cs.blockLine),
              _StatusItem(label: eol,            style: labelStyle),
            ],
          ),
        );
      },
    );
  }

  static String _eolLabel(LineSeparator sep) => switch (sep) {
    LineSeparator.lf   => 'LF',
    LineSeparator.crlf => 'CRLF',
    LineSeparator.cr   => 'CR',
  };
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _StatusItem extends StatelessWidget {
  final String    label;
  final TextStyle style;

  const _StatusItem({required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(label, style: style, maxLines: 1),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  final Color color;
  const _StatusDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 12,
      child: ColoredBox(color: color.withValues(alpha: 0.5)),
    );
  }
}
