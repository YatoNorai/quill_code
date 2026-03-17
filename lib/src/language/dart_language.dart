// lib/src/language/dart_language.dart
import '../highlighting/span.dart';
import '_regex_language.dart';
import '../tree_sitter/ts_language.dart';


class DartLanguage extends RegexLanguage with TsLanguageMixin {
  @override
  String get name => 'Dart';
  @override
  String get tsName => 'dart';

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

  @override
  List<String> get completionKeywords => [..._kw, ..._types];

  /// Pre-built word map for the isolate tokenizer:
  /// all keywords + lowercase built-in types → their TokenType index.
  /// Uppercase types (String, List, Widget …) are handled by the
  /// isolate's UpperCase → type_ fast path, so we skip them here.
  @override
  Map<String, int> get isolateWordMap {
    final m = <String, int>{};
    for (final kw in _kw)    m[kw] = TokenType.keyword.index;
    for (final t  in _types) m[t]  = TokenType.type_.index; // no overlap with _kw
    return m;
  }

  @override
  List<TokenRule> get rules => [
    TokenRule(r'"""[\s\S]*?"""', TokenType.string),
    TokenRule(r"'''[\s\S]*?'''", TokenType.string),
    TokenRule(r'///.*', TokenType.comment),
    TokenRule(r'//.*', TokenType.comment),
    TokenRule(r'/\*[\s\S]*?\*/', TokenType.comment),
    TokenRule(r'"(?:[^"\\]|\\.)*"', TokenType.string),
    TokenRule(r"'(?:[^'\\]|\\.)*'", TokenType.string),
    TokenRule(r'@[a-zA-Z_]\w*', TokenType.annotation),
    TokenRule(r'\b0x[0-9a-fA-F]+\b', TokenType.number),
    TokenRule(r'\b\d+\.?\d*(?:e[+-]?\d+)?\b', TokenType.number),
    TokenRule(r'\b(?:int|double|String|bool|List|Map|Set|Object|Iterable|Future|Stream|Duration|DateTime|num|Never|Null|Symbol|Type|BigInt|Completer|Pattern|RegExp|Widget|State)\b', TokenType.type_),
    TokenRule(r'\b(?:abstract|as|assert|async|await|base|break|case|catch|class|const|continue|covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|Function|get|hide|if|implements|import|in|interface|is|late|library|mixin|new|null|of|on|operator|part|required|rethrow|return|sealed|set|show|static|super|switch|sync|this|throw|true|try|typedef|var|void|when|while|with|yield)\b', TokenType.keyword),
    TokenRule(r'\b[a-zA-Z_]\w*\s*(?=\()', TokenType.function_),
    TokenRule(r'\b[A-Z][a-zA-Z0-9_]*\b', TokenType.type_),
    TokenRule(r'\b[a-zA-Z_]\w*\b', TokenType.identifier),
    TokenRule(r'[+\-*/%&|^~<>!=?:]+', TokenType.operator_),
    TokenRule(r'[(){}\[\];,.]', TokenType.punctuation),
  ];

  @override
  int getIndentAdvance(content, line, column) {
    if (line < 0) return 0;
    final t = content.getLineText(line).trimRight();
    if (t.endsWith('{') || t.endsWith('(') || t.endsWith('[')) return 4;
    return 0;
  }
}
