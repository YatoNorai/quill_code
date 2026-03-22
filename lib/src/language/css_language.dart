// lib/src/language/css_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class CssLanguage extends MonarchLanguage {
  @override String get name => 'CSS';
  @override String get lineCommentPrefix => '/* */';

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'"[^"]*"', TokenType.string),
      MonarchRule(r"'[^']*'", TokenType.string),
      MonarchRule(r'#[0-9a-fA-F]{3,8}\b', TokenType.literal),
      MonarchRule(r'\b\d+\.?\d*(?:px|em|rem|vh|vw|%|s|ms|deg|rad)?\b', TokenType.number),
      MonarchRule(r'@[a-zA-Z-]+', TokenType.annotation),
      MonarchRule(r':[a-zA-Z-]+', TokenType.keyword),
      MonarchRule(r'\.[a-zA-Z_-][a-zA-Z0-9_-]*', TokenType.function_),
      MonarchRule(r'\b[a-zA-Z-]+(?=\s*:)', TokenType.attrName),
      MonarchRule(r'[a-zA-Z-]+', TokenType.identifier),
      MonarchRule(r'[{};:,()]', TokenType.punctuation),
    ],
    'blockComment': [
      MonarchRule(r'[*]/', TokenType.comment, pop: true),
      MonarchRule(r'[^*]+|[*](?!/)', TokenType.comment),
    ],
  });
}
