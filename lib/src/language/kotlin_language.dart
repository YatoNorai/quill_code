// lib/src/language/kotlin_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class KotlinLanguage extends MonarchLanguage {
  @override String get name => 'Kotlin';
  @override String get lineCommentPrefix => '//';

  static const _kw = [
    'abstract','actual','annotation','as','break','by','catch','class',
    'companion','const','constructor','continue','crossinline','data','do',
    'dynamic','else','enum','expect','external','false','final','finally',
    'for','fun','get','if','import','in','infix','init','inline','inner',
    'interface','internal','is','it','lateinit','noinline','null','object',
    'open','operator','out','override','package','private','protected',
    'public','reified','return','sealed','set','static','super','suspend',
    'tailrec','this','throw','true','try','typealias','typeof','val','var',
    'vararg','when','where','while',
  ];
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'//.*', TokenType.comment),
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'"""', TokenType.string, next: const MonarchState('tripleDouble')),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
      MonarchRule(r'\b0x[0-9a-fA-F_]+[lL]?\b', TokenType.number),
      MonarchRule(r'\b\d[\d_]*\.?[\d_]*[fFdDlL]?\b', TokenType.number),
      MonarchRule(r'\b(?:abstract|actual|annotation|as|break|by|catch|class|companion|const|constructor|continue|crossinline|data|do|dynamic|else|enum|expect|external|false|final|finally|for|fun|get|if|import|in|infix|init|inline|inner|interface|internal|is|it|lateinit|noinline|null|object|open|operator|out|override|package|private|protected|public|reified|return|sealed|set|static|super|suspend|tailrec|this|throw|true|try|typealias|typeof|val|var|vararg|when|where|while)\b', TokenType.keyword),
      MonarchRule(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenType.function_),
      MonarchRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
      MonarchRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
      MonarchRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
      MonarchRule(r'[(){}\[\];,.]', TokenType.punctuation),
    ],
    'blockComment': [
      MonarchRule(r'[*]/', TokenType.comment, pop: true),
      MonarchRule(r'[^*]+|[*](?!/)', TokenType.comment),
    ],
    'tripleDouble': [
      MonarchRule(r'"""', TokenType.string, pop: true),
      MonarchRule(r'[^"]+|"(?!"")', TokenType.string),
    ],
  });
}
