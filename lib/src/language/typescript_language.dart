// lib/src/language/typescript_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class TypeScriptLanguage extends MonarchLanguage {
  @override String get name => 'TypeScript';
  @override String get lineCommentPrefix => '//';

  static const _kw = [
    'abstract','any','as','asserts','async','await','bigint','boolean','break',
    'case','catch','class','const','constructor','continue','debugger','declare',
    'default','delete','do','else','enum','export','extends','false','finally',
    'for','from','function','get','if','implements','import','in','infer',
    'instanceof','interface','is','keyof','let','module','namespace','never',
    'new','null','number','object','of','override','package','private',
    'protected','public','readonly','return','set','static','string','super',
    'switch','symbol','this','throw','true','try','type','typeof','undefined',
    'unique','unknown','var','void','while','with','yield',
  ];
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'//.*', TokenType.comment),
      MonarchRule(r'/[*][*](?!/)', TokenType.comment, next: const MonarchState('jsdoc')),
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'`', TokenType.string, next: const MonarchState('templateString')),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'\b0x[0-9a-fA-F]+n?\b', TokenType.number),
      MonarchRule(r'\b0[bB][01]+n?\b', TokenType.number),
      MonarchRule(r'\b0[oO][0-7]+n?\b', TokenType.number),
      MonarchRule(r'\b\d+\.?\d*(?:[eE][+-]?\d+)?n?\b', TokenType.number),
      MonarchRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
      MonarchRule(r'\b(?:abstract|any|as|asserts|async|await|bigint|boolean|break|case|catch|class|const|constructor|continue|debugger|declare|default|delete|do|else|enum|export|extends|false|finally|for|from|function|get|if|implements|import|in|infer|instanceof|interface|is|keyof|let|module|namespace|never|new|null|number|object|of|override|package|private|protected|public|readonly|return|set|static|string|super|switch|symbol|this|throw|true|try|type|typeof|undefined|unique|unknown|var|void|while|with|yield)\b', TokenType.keyword),
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
    'jsdoc': [
      MonarchRule(r'[*]/', TokenType.comment, pop: true),
      MonarchRule(r'[^*]+|[*](?!/)', TokenType.comment),
    ],
    'templateString': [
      MonarchRule(r'`', TokenType.string, pop: true),
      MonarchRule(r'[^`\\]+|\\[\s\S]', TokenType.string),
    ],
  });
}
