// lib/src/language/javascript_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class JavaScriptLanguage extends MonarchLanguage {
  @override String get name => 'JavaScript';
  @override String get lineCommentPrefix => '//';

  static const _kw = [
    'async','await','break','case','catch','class','const','continue',
    'debugger','default','delete','do','else','export','extends','false',
    'finally','for','from','function','get','if','import','in','instanceof',
    'let','new','null','of','return','set','static','super','switch','this',
    'throw','true','try','typeof','undefined','var','void','while','with','yield',
  ];
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'//.*', TokenType.comment),
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'`', TokenType.string, next: const MonarchState('templateString')),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'\b0x[0-9a-fA-F]+n?\b', TokenType.number),
      MonarchRule(r'\b\d+\.?\d*(?:[eE][+-]?\d+)?n?\b', TokenType.number),
      MonarchRule(r'\b(?:async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|false|finally|for|from|function|get|if|import|in|instanceof|let|new|null|of|return|set|static|super|switch|this|throw|true|try|typeof|undefined|var|void|while|with|yield)\b', TokenType.keyword),
      MonarchRule(r'\b[a-zA-Z_$]\w*(?=\s*\()', TokenType.function_),
      MonarchRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
      MonarchRule(r'\b[a-zA-Z_$]\w*\b', TokenType.identifier),
      MonarchRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
      MonarchRule(r'[(){}\[\];,.]', TokenType.punctuation),
    ],
    'blockComment': [
      MonarchRule(r'[*]/', TokenType.comment, pop: true),
      MonarchRule(r'[^*]+|[*](?!/)', TokenType.comment),
    ],
    'templateString': [
      MonarchRule(r'`', TokenType.string, pop: true),
      MonarchRule(r'[^`\\]+|\\[\s\S]', TokenType.string),
    ],
  });
}
