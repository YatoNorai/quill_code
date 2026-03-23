// lib/src/language/rust_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class RustLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'Rust';
  @override
  String get tsName => 'rust';

  static const _kw = [
    'as','async','await','break','const','continue','crate','dyn','else',
    'enum','extern','false','fn','for','if','impl','in','let','loop','match',
    'mod','move','mut','pub','ref','return','self','Self','static','struct',
    'super','trait','true','type','union','unsafe','use','where','while',
  ];

  @override
  List<String> get completionKeywords => _kw;

  @override
  List<TokenRule> get rules => [
    TokenRule(r'///.*', TokenType.comment),
    TokenRule(r'//.*', TokenType.comment),
    TokenRule(r'/\*[\s\S]*?\*/', TokenType.comment),
    TokenRule(r'r#?"[^"]*"#?', TokenType.string),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"b'[^']*'", TokenType.string),
    TokenRule(r'#!\[[\s\S]*?\]', TokenType.annotation),
    TokenRule(r'#\[[\s\S]*?\]', TokenType.annotation),
    TokenRule(r'\b(?:u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|f32|f64|bool|char|str|String)\b', TokenType.type_),
    TokenRule(r'\b0x[0-9a-fA-F_]+\b', TokenType.number),
    TokenRule(r'\b\d[\d_]*\.?[\d_]*\b', TokenType.number),
    TokenRule(r'\b(?:as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|union|unsafe|use|where|while)\b', TokenType.keyword),
    TokenRule(r'\b[A-Z][A-Z0-9_]+\b', TokenType.constant),
    TokenRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
    TokenRule(r'\b[a-z_]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
    TokenRule(r'[+\-*/%&|^~<>!=?:;]+', TokenType.operator_),
    TokenRule(r'[(){}\[\],.]', TokenType.punctuation),
  ];
}
