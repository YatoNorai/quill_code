// lib/src/language/python_language.dart
import '../native/quill_native.dart';
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class PythonLanguage extends RegexLanguage with TsLanguageMixin {
  @override

  @override
  String get lineCommentPrefix => '#';
  String get name => 'Python';
  @override
  String get tsName => 'python';

  static const _kw = [
    'and','as','assert','async','await','break','class','continue','def',
    'del','elif','else','except','False','finally','for','from','global',
    'if','import','in','is','lambda','None','nonlocal','not','or','pass',
    'raise','return','True','try','while','with','yield',
  ];

  @override
  List<String> get completionKeywords => _kw;

  @override
  List<TokenRule> get rules => [
    TokenRule(r'#.*', TokenType.comment),
    TokenRule(r'"""[\s\S]*?"""', TokenType.string),
    TokenRule(r"'''[\s\S]*?'''", TokenType.string),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
    TokenRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
    TokenRule(r'\b0x[0-9a-fA-F]+\b', TokenType.number),
    TokenRule(r'\b\d+\.?\d*\b', TokenType.number),
    TokenRule(r'\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b', TokenType.keyword),
    TokenRule(r'\b[a-zA-Z_]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
    TokenRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
    TokenRule(r'[+\-*/%&|^~<>!=]+', TokenType.operator_),
    TokenRule(r'[(){}\[\]:,.]', TokenType.punctuation),
  ];

  @override
  int getIndentAdvance(content, line, column) {
    if (line < 0) return 0;
    final t = content.getLineText(line);
    return QuillNative.indentAdvance(t);
  }
}
