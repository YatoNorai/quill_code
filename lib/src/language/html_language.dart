// lib/src/language/html_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class HtmlLanguage extends MonarchLanguage {
  @override String get name => 'HTML';
  @override String get lineCommentPrefix => '<!--';

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'<!--', TokenType.comment, next: const MonarchState('htmlComment')),
      MonarchRule(r'<!DOCTYPE[^>]*>', TokenType.preprocessor),
      MonarchRule(r'<[/]?[a-zA-Z][a-zA-Z0-9-]*', TokenType.htmlTag,
          next: const MonarchState('tag')),
      MonarchRule(r'&[a-zA-Z]+;|&#\d+;', TokenType.literal),
      MonarchRule(r'[^<&]+', TokenType.normal),
    ],
    'tag': [
      MonarchRule(r'>', TokenType.punctuation, pop: true),
      MonarchRule(r'/', TokenType.punctuation),
      MonarchRule(r'[a-zA-Z_:][\w:.-]*\s*(?==)', TokenType.attrName),
      MonarchRule(r'"[^"]*"', TokenType.attrValue),
      MonarchRule(r"'[^']*'", TokenType.attrValue),
      MonarchRule(r'[a-zA-Z_][\w-]*', TokenType.identifier),
      MonarchRule(r'=', TokenType.operator_),
      MonarchRule(r'\s+', TokenType.normal),
    ],
    'htmlComment': [
      MonarchRule(r'-->', TokenType.comment, pop: true),
      MonarchRule(r'[^-]+|-(?!->)', TokenType.comment),
    ],
  });
}
