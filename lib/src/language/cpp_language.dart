// lib/src/language/cpp_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class CppLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'C++';
  @override
  String get tsName => 'cpp';

  static const _kw = [
    'alignas','alignof','and','asm','auto','bool','break','case','catch',
    'char','class','const','consteval','constexpr','constinit','const_cast',
    'continue','decltype','default','delete','do','double','dynamic_cast',
    'else','enum','explicit','export','extern','false','float','for','friend',
    'goto','if','inline','int','long','mutable','namespace','new','noexcept',
    'not','nullptr','operator','or','private','protected','public','register',
    'reinterpret_cast','requires','return','short','signed','sizeof','static',
    'static_assert','static_cast','struct','switch','template','this',
    'thread_local','throw','true','try','typedef','typeid','typename','union',
    'unsigned','using','virtual','void','volatile','wchar_t','while',
  ];

  @override
  List<String> get completionKeywords => _kw;

  @override
  List<TokenRule> get rules => [
    TokenRule(r'//.*', TokenType.comment),
    TokenRule(r'/\*[\s\S]*?\*/', TokenType.comment),
    TokenRule(r'#\s*\w+', TokenType.preprocessor),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
    TokenRule(r'\b0x[0-9a-fA-F]+[uUlL]*\b', TokenType.number),
    TokenRule(r'\b\d+\.?\d*[fFlL]?\b', TokenType.number),
    TokenRule(r'\b(?:alignas|alignof|and|asm|auto|bool|break|case|catch|char|class|const|consteval|constexpr|constinit|const_cast|continue|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|nullptr|operator|or|private|protected|public|register|reinterpret_cast|requires|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|thread_local|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while)\b', TokenType.keyword),
    TokenRule(r'\b[A-Z][A-Z0-9_]+\b', TokenType.constant),
    TokenRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
    TokenRule(r'\b[a-zA-Z_]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
    TokenRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
    TokenRule(r'[(){}\[\];,.]', TokenType.punctuation),
  ];
}
