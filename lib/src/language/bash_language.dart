// lib/src/language/bash_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class BashLanguage extends MonarchLanguage {
  @override String get name => 'Bash';
  @override String get lineCommentPrefix => '#';

  static const _kw = [
    'if','then','else','elif','fi','for','while','do','done','case','esac',
    'function','return','in','select','until','break','continue','exit',
    'declare','local','readonly','export','source','alias','unset',
  ];
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'#!.*', TokenType.comment),
      MonarchRule(r'#.*', TokenType.comment),
      MonarchRule(r'"(?:[^"\\$]|\\.)*"', TokenType.string),
      MonarchRule(r"'[^']*'", TokenType.string),
      MonarchRule(r'\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|function|return|in|select|until|break|continue|exit|declare|local|readonly|export|source|alias|unset)\b', TokenType.keyword),
      MonarchRule(r'\$[{(]?[a-zA-Z_]\w*[})]?', TokenType.identifier),
      MonarchRule(r'\b\d+\b', TokenType.number),
      MonarchRule(r'[a-zA-Z_]\w*(?=\s*\()', TokenType.function_),
      MonarchRule(r'[a-zA-Z_]\w*', TokenType.identifier),
      MonarchRule(r'[|&;<>!\-=+*/%]', TokenType.operator_),
      MonarchRule(r'[(){}\[\];,]', TokenType.punctuation),
    ],
  });
}
