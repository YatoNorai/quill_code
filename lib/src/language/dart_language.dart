// lib/src/language/dart_language.dart
import '../highlighting/span.dart';
import 'monarch_language.dart';

class DartLanguage extends MonarchLanguage {
  @override String get name => 'Dart';
  @override String get lineCommentPrefix => '//';

  static const _kw = [
    'abstract','as','assert','async','await','base','break','case','catch',
    'class','const','continue','covariant','default','deferred','do','dynamic',
    'else','enum','export','extends','extension','external','factory','false',
    'final','finally','for','Function','get','hide','if','implements','import',
    'in','interface','is','late','library','mixin','new','null','of','on',
    'operator','part','required','rethrow','return','sealed','set','show',
    'static','super','switch','sync','this','throw','true','try','typedef',
    'var','void','when','while','with','yield',
  ];
  static const _types = [
    'int','double','String','bool','List','Map','Set','Object','Iterable',
    'Future','Stream','Duration','DateTime','num','Never','Null','Symbol',
    'Type','BigInt','Completer','Pattern','RegExp','Widget','State',
  ];

  @override List<String> get completionKeywords => [..._kw, ..._types];

  @override Map<String, int> get isolateWordMap {
    final m = <String, int>{};
    for (final kw in _kw)   m[kw] = TokenType.keyword.index;
    for (final t in _types) m[t]  = TokenType.type_.index;
    return m;
  }

  @override
  MonarchRuleSet get monarchRules => MonarchRuleSet({
    'root': [
      MonarchRule(r'///.*', TokenType.comment),
      MonarchRule(r'//.*', TokenType.comment),
      MonarchRule(r'/[*]', TokenType.comment, next: const MonarchState('blockComment')),
      MonarchRule(r'"""', TokenType.string, next: const MonarchState('tripleDouble')),
      MonarchRule(r"'''", TokenType.string, next: const MonarchState('tripleSingle')),
      MonarchRule(r'r"[^"]*"', TokenType.string),
      MonarchRule(r"r'[^']*'", TokenType.string),
      MonarchRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
      MonarchRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
      MonarchRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
      MonarchRule(r'\b0x[0-9a-fA-F]+\b', TokenType.number),
      MonarchRule(r'\b\d+\.?\d*(?:e[+-]?\d+)?\b', TokenType.number),
      MonarchRule(r'\b(?:int|double|String|bool|List|Map|Set|Object|Iterable|Future|Stream|Duration|DateTime|num|Never|Null|Symbol|Type|BigInt|Completer|Pattern|RegExp|Widget|State)\b', TokenType.type_),
      MonarchRule(r'\b(?:abstract|as|assert|async|await|base|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|Function|get|hide|if|implements|import|in|interface|is|late|library|mixin|new|null|of|on|operator|part|required|rethrow|return|sealed|set|show|static|super|switch|sync|this|throw|true|try|typedef|var|void|when|while|with|yield)\b', TokenType.keyword),
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
    'tripleSingle': [
      MonarchRule(r"'''", TokenType.string, pop: true),
      MonarchRule(r"[^']+|'(?!'')", TokenType.string),
    ],
  });

  @override
  int getIndentAdvance(content, line, column) {
    if (line < 0) return 0;
    final t = content.getLineText(line).trimRight();
    if (t.endsWith('{') || t.endsWith('(') || t.endsWith('[')) return 4;
    return 0;
  }
}
