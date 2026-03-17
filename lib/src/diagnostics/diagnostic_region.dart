// lib/src/diagnostics/diagnostic_region.dart
import '../text/text_range.dart';
import 'quick_fix.dart';

enum DiagnosticSeverity { error, warning, info, hint }

class DiagnosticRegion {
  final EditorRange range;
  final DiagnosticSeverity severity;
  final String message;
  final String? source;
  final String? code;
  final List<QuickFix> quickFixes;

  const DiagnosticRegion({
    required this.range,
    required this.severity,
    required this.message,
    this.source,
    this.code,
    this.quickFixes = const [],
  });
}
