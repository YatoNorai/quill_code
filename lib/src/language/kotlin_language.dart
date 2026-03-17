// lib/src/language/kotlin_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class KotlinLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'Kotlin';
  @override
  String get tsName => 'kotlin';

  static const _kw = [
    'as','break','class','continue','do','else','false','for','fun','if',
    'in','interface','is','null','object','package','return','super','this',
    'throw','true','try','typealias','val','var','when','while',
    'abstract','actual','annotation','by','catch','companion','constructor',
    'crossinline','data','enum','expect','external','field','final','finally',
    'get','import','infix','init','inline','inner','internal','lateinit',
    'noinline','open','operator','out','override','private','protected',
    'public','reified','sealed','set','suspend','tailrec','vararg',
  ];

  @override
  List<String> get completionKeywords => _kw;

  @override
  List<TokenRule> get rules => [
    TokenRule(r'//.*', TokenType.comment),
    TokenRule(r'/\*[\s\S]*?\*/', TokenType.comment),
    TokenRule(r'"""[\s\S]*?"""', TokenType.string),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
    TokenRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
    TokenRule(r'\b\d+\.?\d*[fLuU]*\b', TokenType.number),
    TokenRule(r'\b(?:as|break|class|continue|do|else|false|for|fun|if|in|interface|is|null|object|package|return|super|this|throw|true|try|typealias|val|var|when|while|abstract|actual|annotation|by|catch|companion|constructor|crossinline|data|enum|expect|external|field|final|finally|get|import|infix|init|inline|inner|internal|lateinit|noinline|open|operator|out|override|private|protected|public|reified|sealed|set|suspend|tailrec|vararg)\b', TokenType.keyword),
    TokenRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
    TokenRule(r'\b[a-zA-Z_]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
    TokenRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
    TokenRule(r'[(){}\[\];,.]', TokenType.punctuation),
  ];
}
