// lib/src/language/xml_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class XmlLanguage extends MonarchLanguage {
  @override String get name => 'XML';
  @override String get lineCommentPrefix => '<!--';

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'<!--', TokenType.comment, next: const MonarchState('comment')),
      MonarchRule(r'<\?[^?]*\?>', TokenType.preprocessor),
      MonarchRule(r'<![^>]+>', TokenType.preprocessor),
      MonarchRule(r'<[/]?[a-zA-Z][\w.-]*', TokenType.htmlTag,
          next: const MonarchState('tag')),
      MonarchRule(r'&[a-zA-Z]+;|&#\d+;', TokenType.literal),
      MonarchRule(r'[^<&]+', TokenType.normal),
    ],
    'tag': [
      MonarchRule(r'/>', TokenType.punctuation, pop: true),
      MonarchRule(r'>', TokenType.punctuation, pop: true),
      MonarchRule(r'[a-zA-Z_:][\w:.-]*\s*(?==)', TokenType.attrName),
      MonarchRule(r'"[^"]*"', TokenType.attrValue),
      MonarchRule(r"'[^']*'", TokenType.attrValue),
      MonarchRule(r'=', TokenType.operator_),
      MonarchRule(r'\s+', TokenType.normal),
    ],
    'comment': [
      MonarchRule(r'-->', TokenType.comment, pop: true),
      MonarchRule(r'[^-]+|-(?!->)', TokenType.comment),
    ],
  });
}
