// lib/src/language/xml_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class XmlLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'XML';
  @override
  String get tsName => 'xml';

  @override
  List<TokenRule> get rules => [
    TokenRule(r'<!--[\s\S]*?-->', TokenType.comment),
    TokenRule(r'<\?[\s\S]*?\?>', TokenType.preprocessor),
    TokenRule(r'</?[a-zA-Z:_][a-zA-Z0-9:._-]*', TokenType.htmlTag),
    TokenRule(r'\b[a-zA-Z:_][a-zA-Z0-9:._-]*(?=\s*=)', TokenType.attrName),
    TokenRule(r'"[^"]*"', TokenType.attrValue),
    TokenRule(r"'[^']*'", TokenType.attrValue),
    TokenRule(r'[<>/="!]', TokenType.operator_),
    TokenRule(r'&[a-zA-Z]+;', TokenType.literal),
  ];
}
