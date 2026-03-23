// lib/src/language/javascript_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class JavaScriptLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'JavaScript';
  @override
  String get tsName => 'javascript';

  static const _kw = [
    'async','await','break','case','catch','class','const','continue',
    'debugger','default','delete','do','else','export','extends','false',
    'finally','for','from','function','if','import','in','instanceof',
    'let','new','null','of','return','static','super','switch','this',
    'throw','true','try','typeof','undefined','var','void','while','with','yield',
  ];

  @override
  List<String> get completionKeywords => _kw;

  @override
  List<TokenRule> get rules => [
    TokenRule(r'//.*', TokenType.comment),
    TokenRule(r'/\*[\s\S]*?\*/', TokenType.comment),
    TokenRule(r'`(?:[^`\\]|\\.)*`', TokenType.string),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
    TokenRule(r'\b\d+\.?\d*\b', TokenType.number),
    TokenRule(r'\b(?:async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|false|finally|for|from|function|if|import|in|instanceof|let|new|null|of|return|static|super|switch|this|throw|true|try|typeof|undefined|var|void|while|with|yield)\b', TokenType.keyword),
    TokenRule(r'\b[a-zA-Z_\$]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
    TokenRule(r'\b[a-zA-Z_\$]\w*\b', TokenType.identifier),
    TokenRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
    TokenRule(r'[(){}\[\];,.]', TokenType.punctuation),
  ];
}
