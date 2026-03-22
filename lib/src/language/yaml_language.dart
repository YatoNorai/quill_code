// lib/src/language/yaml_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class YamlLanguage extends MonarchLanguage {
  @override String get name => 'YAML';
  @override String get lineCommentPrefix => '#';

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'#.*', TokenType.comment),
      MonarchRule(r'---', TokenType.keyword),
      MonarchRule(r'\.\.\.', TokenType.keyword),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'\b(?:true|false|null|yes|no|on|off)\b', TokenType.keyword),
      MonarchRule(r'\b-?\d+\.?\d*\b', TokenType.number),
      MonarchRule(r'^[\s]*[a-zA-Z_][\w\-]*(?=\s*:)', TokenType.attrName),
      MonarchRule(r'[!&*][a-zA-Z_]\w*', TokenType.annotation),
      MonarchRule(r'[{}\[\],:|>-]', TokenType.punctuation),
      MonarchRule(r'[a-zA-Z_]\w*', TokenType.identifier),
    ],
  });
}
