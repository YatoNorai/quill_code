// lib/src/widgets/diagnostics_panel.dart
//
// A standalone panel that lists all diagnostics produced by the editor
// (tree-sitter syntax errors, LSP errors/warnings, or manual calls to
// controller.setDiagnostics).
//
// Usage:
//   DiagnosticsPanel(
//     controller: _controller,
//     theme: _theme,           // optional — falls back to dark theme
//     onNavigate: (diag) { ... }, // optional extra callback on item tap
//   )
//
// The panel rebuilds automatically whenever the controller pushes new
// diagnostics (it listens to the controller via ListenableBuilder).
// No tree-sitter files are touched by this widget.

import 'package:flutter/material.dart';
import '../core/char_position.dart';
import '../core/editor_controller.dart';
import '../diagnostics/diagnostic_region.dart';
import '../theme/editor_theme.dart';
import '../theme/theme_dark.dart';

class DiagnosticsPanel extends StatelessWidget {
  final QuillCodeController controller;

  /// Editor theme used for colours. Falls back to the dark theme if null.
  final EditorTheme? theme;

  /// Called after the panel navigates the cursor to a diagnostic.
  /// Use this to close a bottom-sheet, scroll a parent, etc.
  final void Function(DiagnosticRegion)? onNavigate;

  const DiagnosticsPanel({
    super.key,
    required this.controller,
    this.theme,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final t  = theme ?? QuillThemeDark.build();
    final cs = t.colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final all      = controller.diagnostics.all;
        final errors   = all.where((d) => d.severity == DiagnosticSeverity.error).length;
        final warnings = all.where((d) => d.severity == DiagnosticSeverity.warning).length;
        final infos    = all.where((d) => d.severity == DiagnosticSeverity.info ||
                                          d.severity == DiagnosticSeverity.hint).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header bar ─────────────────────────────────────────────────
            _Header(
              errors: errors, warnings: warnings, infos: infos,
              cs: cs, fontSize: t.fontSize,
            ),
            const Divider(height: 1, thickness: 1),
            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: all.isEmpty
                  ? _EmptyState(cs: cs, fontSize: t.fontSize)
                  : ListView.builder(
                      itemCount: all.length,
                      itemExtent: 52,
                      itemBuilder: (ctx, i) => _DiagItem(
                        diag: all[i],
                        cs: cs,
                        fontSize: t.fontSize,
                        onTap: () {
                          controller.setCursor(CharPosition(
                            all[i].range.start.line,
                            all[i].range.start.column,
                          ));
                          onNavigate?.call(all[i]);
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int errors, warnings, infos;
  final dynamic cs;   // EditorColorScheme
  final double fontSize;

  const _Header({
    required this.errors,
    required this.warnings,
    required this.infos,
    required this.cs,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: cs.lineNumberBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'Problems',
            style: TextStyle(
              color: cs.textNormal,
              fontSize: fontSize * 0.88,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          if (errors > 0)   _Badge(count: errors,   color: cs.problemError,   icon: Icons.error_outline,           fontSize: fontSize),
          if (warnings > 0) _Badge(count: warnings, color: cs.problemWarning, icon: Icons.warning_amber_outlined,  fontSize: fontSize),
          if (infos > 0)    _Badge(count: infos,    color: cs.problemTypo,    icon: Icons.info_outline,             fontSize: fontSize),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;
  final double fontSize;

  const _Badge({
    required this.count,
    required this.color,
    required this.icon,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: fontSize * 1.1),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(color: color, fontSize: fontSize * 0.85),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final dynamic cs;
  final double fontSize;
  const _EmptyState({required this.cs, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: cs.problemTypo, size: 28),
          const SizedBox(height: 6),
          Text(
            'No problems detected',
            style: TextStyle(
              color: cs.lineNumber,
              fontSize: fontSize * 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single diagnostic row ─────────────────────────────────────────────────────

class _DiagItem extends StatelessWidget {
  final DiagnosticRegion diag;
  final dynamic cs;
  final double fontSize;
  final VoidCallback onTap;

  const _DiagItem({
    required this.diag,
    required this.cs,
    required this.fontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (diag.severity) {
      DiagnosticSeverity.error   => Icons.error_outline,
      DiagnosticSeverity.warning => Icons.warning_amber_outlined,
      DiagnosticSeverity.info    => Icons.info_outline,
      DiagnosticSeverity.hint    => Icons.lightbulb_outline,
    };
    final color = switch (diag.severity) {
      DiagnosticSeverity.error   => cs.problemError,
      DiagnosticSeverity.warning => cs.problemWarning,
      _                          => cs.problemTypo,
    };

    final line = diag.range.start.line + 1;   // 1-based for display
    final col  = diag.range.start.column + 1;
    final src  = diag.source;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: fontSize * 1.15),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    diag.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.textNormal,
                      fontSize: fontSize * 0.9,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        'Ln $line, Col $col',
                        style: TextStyle(
                          color: cs.lineNumber,
                          fontSize: fontSize * 0.78,
                        ),
                      ),
                      if (src != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.lineNumberBackground,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            src,
                            style: TextStyle(
                              color: cs.lineNumber,
                              fontSize: fontSize * 0.74,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
