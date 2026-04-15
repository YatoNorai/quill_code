// lib/src/widgets/status_bar_widget.dart
//
// A thin bottom bar that mirrors VSCode's status bar.
// Shows: cursor position, selection length, line count, language, line endings.
// Diagnostic counts (errors / warnings / infos) appear left of the divider and
// are tappable when [onDiagnosticTap] is provided — e.g. to open the Problems
// panel in the host IDE.
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../diagnostics/diagnostic_region.dart';
import '../theme/editor_theme.dart';
import '../text/line_separator.dart';

class StatusBarWidget extends StatelessWidget {
  final QuillCodeController controller;
  final EditorTheme theme;

  /// Called when the user taps any diagnostic count chip.
  /// Wire this up to open the Problems panel in the host IDE.
  final VoidCallback? onDiagnosticTap;

  /// Project-wide diagnostic counts supplied by the host IDE.
  /// When non-null these are shown instead of the current-file counts so the
  /// indicator never disappears when switching to a file that has no errors.
  final int? projectErrors;
  final int? projectWarnings;
  final int? projectInfos;

  const StatusBarWidget({
    super.key,
    required this.controller,
    required this.theme,
    this.onDiagnosticTap,
    this.projectErrors,
    this.projectWarnings,
    this.projectInfos,
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

        // Diagnostic counts — prefer project-wide totals when provided by the
        // host IDE so the indicator persists across file switches.
        final int errors, warnings, infos;
        if (projectErrors != null || projectWarnings != null || projectInfos != null) {
          errors   = projectErrors   ?? 0;
          warnings = projectWarnings ?? 0;
          infos    = projectInfos    ?? 0;
        } else {
          final diags = controller.diagnostics.all;
          errors   = diags.where((d) => d.severity == DiagnosticSeverity.error).length;
          warnings = diags.where((d) => d.severity == DiagnosticSeverity.warning).length;
          infos    = diags.where((d) => d.severity == DiagnosticSeverity.info).length;
        }

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

              // ── Diagnostic counts (only shown when there are issues) ──
              if (errors > 0 || warnings > 0 || infos > 0) ...[
                _StatusDivider(color: cs.blockLine),
                _DiagChip(
                  errors: errors,
                  warnings: warnings,
                  infos: infos,
                  style: labelStyle,
                  onTap: onDiagnosticTap,
                ),
              ],

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

/// Tappable diagnostic count row — e.g. "2 ✕  1 ▲" — displayed inline in the
/// status bar. Tapping opens the Problems panel (host app provides [onTap]).
class _DiagChip extends StatelessWidget {
  final int errors;
  final int warnings;
  final int infos;
  final TextStyle style;
  final VoidCallback? onTap;

  const _DiagChip({
    required this.errors,
    required this.warnings,
    required this.infos,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final errorColor   = const Color(0xFFE57373);
    final warningColor = const Color(0xFFFFB74D);
    final infoColor    = const Color(0xFF64B5F6);

    final parts = <Widget>[];

    void add(int count, IconData icon, Color color) {
      if (count == 0) return;
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 6));
      parts.add(Icon(icon, size: 12, color: color));
      parts.add(const SizedBox(width: 2));
      parts.add(Text('$count', style: style.copyWith(color: color)));
    }

    add(errors,   Icons.highlight_off,          errorColor);
    add(warnings, Icons.warning_amber_rounded,  warningColor);
    add(infos,    Icons.info_outline,            infoColor);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );

    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}
