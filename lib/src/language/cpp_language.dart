// lib/src/language/cpp_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class CppLanguage extends MonarchLanguage {
  @override String get name => 'C++';
  @override String get lineCommentPrefix => '//';

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
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'//.*', TokenType.comment),
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'#\s*\w+.*', TokenType.preprocessor),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'\b0x[0-9a-fA-F]+[uUlL]*\b', TokenType.number),
      MonarchRule(r'\b\d+\.?\d*[fFlL]?\b', TokenType.number),
      MonarchRule(r'\b(?:alignas|alignof|and|asm|auto|bool|break|case|catch|char|class|const|consteval|constexpr|constinit|const_cast|continue|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|nullptr|operator|or|private|protected|public|register|reinterpret_cast|requires|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|thread_local|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while)\b', TokenType.keyword),
      MonarchRule(r'\b[A-Z][A-Z0-9_]+\b', TokenType.constant),
      MonarchRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
      MonarchRule(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenType.function_),
      MonarchRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
      MonarchRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
      MonarchRule(r'[(){}\[\];,.]', TokenType.punctuation),
    ],
    'blockComment': [
      MonarchRule(r'[*]/', TokenType.comment, pop: true),
      MonarchRule(r'[^*]+|[*](?!/)', TokenType.comment),
    ],
  });
}
