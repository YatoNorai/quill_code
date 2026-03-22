// lib/src/language/python_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class PythonLanguage extends MonarchLanguage {
  @override String get name => 'Python';
  @override String get lineCommentPrefix => '#';

  static const _kw = [
    'and','as','assert','async','await','break','class','continue','def',
    'del','elif','else','except','False','finally','for','from','global',
    'if','import','in','is','lambda','None','nonlocal','not','or','pass',
    'raise','return','True','try','while','with','yield',
  ];
  @override List<String> get completionKeywords => _kw;

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'#.*', TokenType.comment),
      MonarchRule(r'"""', TokenType.string, next: const MonarchState('tripleDouble')),
      MonarchRule(r"'''", TokenType.string, next: const MonarchState('tripleSingle')),
      MonarchRule(r'r"[^"]*"', TokenType.string),
      MonarchRule(r"r'[^']*'", TokenType.string),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
      MonarchRule(r'\b0x[0-9a-fA-F]+\b', TokenType.number),
      MonarchRule(r'\b0b[01]+\b', TokenType.number),
      MonarchRule(r'\b0o[0-7]+\b', TokenType.number),
      MonarchRule(r'\b\d+\.?\d*(?:[eE][+-]?\d+)?[jJ]?\b', TokenType.number),
      MonarchRule(r'\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b', TokenType.keyword),
      MonarchRule(r'\b[a-zA-Z_]\w*(?=\s*\()', TokenType.function_),
      MonarchRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
      MonarchRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
      MonarchRule(r'[+\-*/%&|^~<>!=:]+', TokenType.operator_),
      MonarchRule(r'[(){}\[\]:,.]', TokenType.punctuation),
    ],
    'tripleDouble': [
      MonarchRule(r'"""', TokenType.string, pop: true),
      MonarchRule(r'[^"]+|"(?!"")', TokenType.string),
    ],
    'tripleSingle': [
      MonarchRule(r"'''", TokenType.string, pop: true),
      MonarchRule(r"[^']+|'(?!'')", TokenType.string),
    ],
  });

  @override
  int getIndentAdvance(content, line, column) {
    if (line < 0) return 0;
    final t = content.getLineText(line).trimRight();
    if (t.endsWith(':')) return 4;
    return 0;
  }
}
