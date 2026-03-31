// lib/src/language/json_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
class JsonLanguage extends RegexLanguage {
  @override
  String get name => 'JSON';

  @override
  List<TokenRule> get rules => [
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r'\b(?:true|false|null)\b', TokenType.keyword),
    TokenRule(r'-?\d+\.?\d*(?:[eE][+-]?\d+)?', TokenType.number),
    TokenRule(r'[{}\[\]:,]', TokenType.punctuation),
  ];
}
