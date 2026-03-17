// lib/src/highlighting/text_style_token.dart
import 'span.dart';

/// Maps [TokenType] to theme color key names.
const Map<TokenType, String> tokenToColorKey = {
  TokenType.normal: 'textNormal',
  TokenType.keyword: 'keyword',
  TokenType.comment: 'comment',
  TokenType.string: 'string',
  TokenType.number: 'number',
  TokenType.operator_: 'operator',
  TokenType.identifier: 'identifier',
  TokenType.function_: 'function',
  TokenType.type_: 'type',
  TokenType.annotation: 'annotation',
  TokenType.literal: 'literal',
  TokenType.htmlTag: 'htmlTag',
  TokenType.attrName: 'attrName',
  TokenType.attrValue: 'attrValue',
  TokenType.preprocessor: 'preprocessor',
  TokenType.error_: 'errorText',
  TokenType.warning_: 'warningText',
  TokenType.namespace: 'namespace',
  TokenType.constant: 'constant',
  TokenType.label: 'label',
  TokenType.punctuation: 'punctuation',
};
