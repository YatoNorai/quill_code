// lib/src/language/plain_text_language.dart
import '../highlighting/span.dart';
import '../highlighting/analyze_manager.dart';
import '../highlighting/incremental_analyze_manager.dart';
import '../completion/completion_publisher.dart';
import '../core/char_position.dart';
import '../text/content.dart';
import 'language.dart';

class PlainTextLanguage extends QuillLanguage {
  @override
  String get name => 'Plain Text';

  @override
  AnalyzeManager createAnalyzeManager() =>
      IncrementalAnalyzeManager(language: this);

  @override
  List<List<CodeSpan>> tokenize(List<String> lines) =>
      lines.map((_) => <CodeSpan>[]).toList();

  @override
  Future<void> getCompletions(Content content, CharPosition position,
      CompletionPublisher publisher) async {}

  @override
  int getIndentAdvance(Content content, int line, int column) => 0;
}
