// lib/src/language/json_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class JsonLanguage extends MonarchLanguage {
  @override String get name => 'JSON';
  @override String get lineCommentPrefix => '//';

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'"(?:[^"\\]|\\.)*"\s*(?=:)', TokenType.attrName),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r'\b-?\d+\.?\d*(?:[eE][+-]?\d+)?\b', TokenType.number),
      MonarchRule(r'\b(?:true|false|null)\b', TokenType.keyword),
      MonarchRule(r'[{}\[\]]', TokenType.punctuation),
      MonarchRule(r'[,:]', TokenType.punctuation),
    ],
  });
}
