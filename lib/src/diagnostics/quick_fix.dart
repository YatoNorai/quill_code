// lib/src/diagnostics/quick_fix.dart
import '../text/text_range.dart';

class QuickFix {
  final String title;
  final Map<EditorRange, String> edits;
  const QuickFix({required this.title, required this.edits});
}
