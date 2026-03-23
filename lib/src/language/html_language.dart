// lib/src/language/html_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class HtmlLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'HTML';
  @override
  String get tsName => 'html';

  @override
  List<TokenRule> get rules => [
    TokenRule(r'<!--[\s\S]*?-->', TokenType.comment),
    TokenRule(r'<!DOCTYPE[^>]*>', TokenType.keyword),
    TokenRule(r'</?[a-zA-Z][a-zA-Z0-9]*', TokenType.htmlTag),
    TokenRule(r'\b[a-zA-Z-]+(?=\s*=)', TokenType.attrName),
    TokenRule(r'"[^"]*"', TokenType.attrValue),
    TokenRule(r"'[^']*'", TokenType.attrValue),
    TokenRule(r'[<>/"=]', TokenType.operator_),
    TokenRule(r'&[a-zA-Z]+;', TokenType.literal),
  ];
}
