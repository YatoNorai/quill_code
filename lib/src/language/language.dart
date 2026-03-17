// lib/src/language/language.dart
import '../highlighting/span.dart';
import '../highlighting/analyze_manager.dart';
import '../completion/completion_item.dart';
import '../completion/completion_publisher.dart';
import '../core/char_position.dart';
import '../core/symbol_pair.dart';
import '../text/content.dart';

abstract class QuillLanguage {
  List<List<CodeSpan>> tokenize(List<String> lines);

  Future<void> getCompletions(
    Content content,
    CharPosition position,
    CompletionPublisher publisher,
  );

  int getIndentAdvance(Content content, int line, int column);

  bool get useTab => false;
  SymbolPairMatch get symbolPairs => SymbolPairMatch.defaults;
  AnalyzeManager createAnalyzeManager();
  Map<String, String> get bracketPairs => {'(': ')', '[': ']', '{': '}'};

  /// Line comment prefix, e.g. '//', '#', '--'
  String get lineCommentPrefix => '//';

  void init() {}
  void destroy() {}

  String get name;
}
