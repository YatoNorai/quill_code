// lib/src/language/yaml_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class YamlLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'YAML';
  @override
  String get lineCommentPrefix => '#';
  @override
  String get tsName => 'yaml';

  @override
  List<TokenRule> get rules => [
    TokenRule(r'#.*', TokenType.comment),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
    TokenRule(r'\b(?:true|false|null|yes|no|on|off)\b', TokenType.keyword),
    TokenRule(r'\b\d+\.?\d*\b', TokenType.number),
    TokenRule(r'[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*:)', TokenType.attrName),
    TokenRule(r'[&*!|>%@]', TokenType.operator_),
    TokenRule(r'[:{}\[\],]', TokenType.punctuation),
    TokenRule(r'[a-zA-Z_][a-zA-Z0-9_-]*', TokenType.identifier),
  ];
}
