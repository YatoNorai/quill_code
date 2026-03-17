// lib/src/language/css_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class CssLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'CSS';
  @override
  String get lineCommentPrefix => '/* */';
  @override
  String get tsName => 'css';

  @override
  List<TokenRule> get rules => [
    TokenRule(r'/\*[\s\S]*?\*/', TokenType.comment),
    TokenRule(r'"[^"]*"', TokenType.string),
    TokenRule(r"'[^']*'", TokenType.string),
    TokenRule(r'#[0-9a-fA-F]{3,8}', TokenType.literal),
    TokenRule(r'\b\d+\.?\d*(?:px|em|rem|vh|vw|%|s|ms|deg|rad)?\b', TokenType.number),
    TokenRule(r'@[a-zA-Z-]+', TokenType.annotation),
    TokenRule(r':[a-zA-Z-]+', TokenType.keyword),
    TokenRule(r'\.[a-zA-Z_-][a-zA-Z0-9_-]*', TokenType.function_),
    TokenRule(r'#[a-zA-Z_-][a-zA-Z0-9_-]*', TokenType.type_),
    TokenRule(r'\b[a-zA-Z-]+(?=\s*:)', TokenType.attrName),
    TokenRule(r'[a-zA-Z-]+', TokenType.identifier),
    TokenRule(r'[{};:,()]', TokenType.punctuation),
  ];
}
