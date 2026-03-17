// lib/src/tree_sitter/ts_token_mapper.dart
//
// Maps tree-sitter capture names (e.g. "keyword", "function.call")
// to QuillCode TokenType values.

import '../highlighting/span.dart';

class TsTokenMapper {
  TsTokenMapper._();

  static TokenType fromCaptureName(String name) =>
      _map[name] ?? _prefixMatch(name);

  static TokenType _prefixMatch(String name) {
    if (name.startsWith('keyword'))    return TokenType.keyword;
    if (name.startsWith('function'))   return TokenType.function_;
    if (name.startsWith('type'))       return TokenType.type_;
    if (name.startsWith('string'))     return TokenType.string;
    if (name.startsWith('number'))     return TokenType.number;
    if (name.startsWith('constant'))   return TokenType.literal;
    if (name.startsWith('comment'))    return TokenType.comment;
    if (name.startsWith('attribute'))  return TokenType.annotation;
    if (name.startsWith('operator'))   return TokenType.operator_;
    if (name.startsWith('punctuation'))return TokenType.punctuation;
    if (name.startsWith('variable'))   return TokenType.identifier;
    if (name.startsWith('namespace'))  return TokenType.namespace;
    if (name.startsWith('tag'))        return TokenType.htmlTag;
    if (name.startsWith('preproc') ||
        name.startsWith('preprocessor')) return TokenType.preprocessor;
    if (name.startsWith('error'))      return TokenType.error_;
    return TokenType.normal;
  }

  static const _map = <String, TokenType>{
    'keyword':           TokenType.keyword,
    'keyword.function':  TokenType.keyword,
    'keyword.operator':  TokenType.keyword,
    'keyword.return':    TokenType.keyword,
    'keyword.import':    TokenType.keyword,
    'keyword.control':   TokenType.keyword,
    'keyword.modifier':  TokenType.keyword,

    'function':          TokenType.function_,
    'function.call':     TokenType.function_,
    'function.builtin':  TokenType.function_,
    'function.method':   TokenType.function_,
    'method':            TokenType.function_,
    'method.call':       TokenType.function_,
    'constructor':       TokenType.function_,

    'type':              TokenType.type_,
    'type.builtin':      TokenType.type_,
    'type.definition':   TokenType.type_,

    'string':            TokenType.string,
    'string.special':    TokenType.string,
    'string.escape':     TokenType.string,
    'string.regexp':     TokenType.string,
    'string.symbol':     TokenType.string,

    'number':            TokenType.number,
    'number.float':      TokenType.number,

    'comment':           TokenType.comment,
    'comment.line':      TokenType.comment,
    'comment.block':     TokenType.comment,
    'comment.doc':       TokenType.comment,

    'constant':          TokenType.literal,
    'constant.builtin':  TokenType.literal,
    'constant.macro':    TokenType.literal,
    'boolean':           TokenType.literal,
    'null':              TokenType.literal,

    'operator':          TokenType.operator_,
    'punctuation':       TokenType.punctuation,
    'punctuation.bracket': TokenType.punctuation,
    'punctuation.delimiter': TokenType.punctuation,

    'variable':          TokenType.identifier,
    'variable.builtin':  TokenType.identifier,
    'variable.parameter': TokenType.identifier,
    'variable.member':   TokenType.identifier,
    'field':             TokenType.identifier,
    'property':          TokenType.identifier,

    'attribute':         TokenType.annotation,
    'attribute.name':    TokenType.attrName,
    'attribute.value':   TokenType.attrValue,
    'decorator':         TokenType.annotation,
    'annotation':        TokenType.annotation,

    'namespace':         TokenType.namespace,
    'module':            TokenType.namespace,
    'package':           TokenType.namespace,

    'tag':               TokenType.htmlTag,
    'tag.builtin':       TokenType.htmlTag,

    'preprocessor':      TokenType.preprocessor,
    'preproc':           TokenType.preprocessor,
    'include':           TokenType.preprocessor,
    'define':            TokenType.preprocessor,

    'label':             TokenType.label,

    'error':             TokenType.error_,
    'ERROR':             TokenType.error_,

    'none':              TokenType.normal,
  };
}
