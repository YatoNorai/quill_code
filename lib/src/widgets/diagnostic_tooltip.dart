// lib/src/widgets/diagnostic_tooltip.dart
import 'package:flutter/material.dart';
import '../diagnostics/diagnostic_region.dart';
import '../theme/editor_theme.dart';

class DiagnosticTooltipWidget extends StatelessWidget {
  final DiagnosticRegion diagnostic;
  final EditorTheme theme;

  const DiagnosticTooltipWidget({
    super.key,
    required this.diagnostic,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final icon = switch (diagnostic.severity) {
      DiagnosticSeverity.error => Icons.error_outline,
      DiagnosticSeverity.warning => Icons.warning_amber_outlined,
      DiagnosticSeverity.info => Icons.info_outline,
      DiagnosticSeverity.hint => Icons.lightbulb_outline,
    };
    final color = switch (diagnostic.severity) {
      DiagnosticSeverity.error => cs.problemError,
      DiagnosticSeverity.warning => cs.problemWarning,
      _ => cs.problemTypo,
    };

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(6),
      color: cs.diagnosticTooltipBackground,
      child: Container(
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(diagnostic.message,
                      style: TextStyle(
                          color: cs.diagnosticTooltipText,
                          fontSize: theme.fontSize * 0.9)),
                  if (diagnostic.source != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(diagnostic.source!,
                          style: TextStyle(
                              color: cs.lineNumber,
                              fontSize: theme.fontSize * 0.78)),
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
