// lib/src/highlighting/styles.dart
import 'span.dart';
import 'code_block.dart';
import '../highlighting/inlay_hint_model.dart';
import '../highlighting/line_style.dart';

/// Holds all computed style data for the document.
/// Updated by [AnalyzeManager] asynchronously.
class Styles {
  /// Per-line list of [CodeSpan]s. Index = line number.
  final List<List<CodeSpan>> spans;

  /// Indentation code blocks for drawing side lines.
  final List<CodeBlock> codeBlocks;

  /// Inlay hints.
  final List<InlayHint> inlayHints;

  /// Per-line styles (custom backgrounds, icons, etc.).
  final Map<int, LineStyle> lineStyles;

  const Styles({
    this.spans = const [],
    this.codeBlocks = const [],
    this.inlayHints = const [],
    this.lineStyles = const {},
  });

  static const Styles empty = Styles();

  List<CodeSpan> spansForLine(int line) {
    if (line < 0 || line >= spans.length) return const [];
    return spans[line];
  }
}
