// lib/src/language/rust_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class RustLanguage extends MonarchLanguage {
  @override String get name => 'Rust';
  @override String get lineCommentPrefix => '//';

  static const _kw = [
    'as','async','await','break','const','continue','crate','dyn','else',
    'enum','extern','false','fn','for','if','impl','in','let','loop','match',
    'mod','move','mut','pub','ref','return','self','Self','static','struct',
    'super','trait','true','type','union','unsafe','use','where','while',
  ];
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'///.*', TokenType.comment),
      MonarchRule(r'//!.*', TokenType.comment),
      MonarchRule(r'//.*', TokenType.comment),
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'r#+"[^"]*"#+', TokenType.string),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"b'[^'\\]|\\.|\\'", TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)'", TokenType.string),
      MonarchRule(r'#!\[[\s\S]*?\]', TokenType.annotation),
      MonarchRule(r'#\[[\s\S]*?\]', TokenType.annotation),
      MonarchRule(r'\b(?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|f32|f64|bool|char|str|String)\b', TokenType.type_),
      MonarchRule(r'\b0x[0-9a-fA-F_]+\b', TokenType.number),
      MonarchRule(r'\b\d[\d_]*\.?[\d_]*(?:[eE][+-]?[\d_]+)?\b', TokenType.number),
      MonarchRule(r"'[a-zA-Z_]\w*\b", TokenType.annotation),
      MonarchRule(r'\b(?:as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|union|unsafe|use|where|while)\b', TokenType.keyword),
      MonarchRule(r'\b[A-Z][A-Z0-9_]+\b', TokenType.constant),
      MonarchRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
      MonarchRule(r'\b[a-z_]\w*!', TokenType.function_),
      MonarchRule(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenType.function_),
      MonarchRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
      MonarchRule(r'[+\-*/%&|^~<>!=?:;]+', TokenType.operator_),
      MonarchRule(r'[(){}\[\],.]', TokenType.punctuation),
    ],
    'blockComment': [
      MonarchRule(r'[*]/', TokenType.comment, pop: true),
      MonarchRule(r'[^*]+|[*](?!/)', TokenType.comment),
    ],
  });
}
