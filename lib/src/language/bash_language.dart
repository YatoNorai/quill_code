// lib/src/language/bash_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class BashLanguage extends RegexLanguage with TsLanguageMixin {
  @override

  @override
  String get lineCommentPrefix => '#';
  String get name => 'Bash';
  @override
  String get tsName => 'bash';

  static const _kw = [
    'if','then','else','elif','fi','case','esac','for','while','until',
    'do','done','in','function','select','time','return','break','continue',
    'exit','local','export','declare','typeset','readonly','unset','set',
    'shift','source','eval','exec',
  ];

  @override
  List<String> get completionKeywords => _kw;

  @override
  List<TokenRule> get rules => [
    TokenRule(r'#.*', TokenType.comment),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'[^']*'", TokenType.string),
    TokenRule(r'\$\{[^}]*\}', TokenType.identifier),
    TokenRule(r'\$\w+', TokenType.identifier),
    TokenRule(r'\b(?:if|then|else|elif|fi|case|esac|for|while|until|do|done|in|function|select|time|return|break|continue|exit|local|export|declare|typeset|readonly|unset|set|shift|source|eval|exec)\b', TokenType.keyword),
    TokenRule(r'\b\d+\b', TokenType.number),
    TokenRule(r'[a-zA-Z_]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'[a-zA-Z_]\w*', TokenType.identifier),
    TokenRule(r'[|&;<>(){}]', TokenType.operator_),
  ];
}
