// lib/src/tree_sitter/ts_queries.dart
//
// Tree-sitter S-expression highlight queries for each language.
// Each query maps capture names to token types via TsTokenMapper.
//
// Capture name conventions (compatible with nvim-treesitter):
//   keyword          → keyword
//   keyword.function → keyword
//   string           → string
//   comment          → comment
//   number           → number
//   operator         → operator_
//   function         → function_
//   function.call    → function_
//   type             → type_
//   type.builtin     → type_
//   variable         → identifier
//   attribute        → annotation
//   constant         → literal
//   namespace        → namespace
//   punctuation      → punctuation
//   tag              → htmlTag
//   attribute.name   → attrName
//   attribute.value  → attrValue
//   error            → error_

class TsQueries {
  TsQueries._();

  /// Returns the highlight query source for [langName], or null if none.
  static String? forLanguage(String langName) =>
      _queries[langName];

  // ──────────────────────────────────────────────────────────────────────────
  static const _queries = <String, String>{

// ── Dart ─────────────────────────────────────────────────────────────────────
// All patterns verified against the bundled tree-sitter-dart grammar.
// Note: this grammar has NO call_expression node — calls are postfix_expression.
// method_signature has no fields; it wraps function_signature/getter/setter.
'dart': r'''
(comment) @comment
(documentation_comment) @comment
(string_literal) @string
(template_substitution) @variable
(decimal_integer_literal) @number
(hex_integer_literal) @number
(decimal_floating_point_literal) @number
(true) @boolean
(false) @boolean
(null_literal) @constant.builtin
(symbol_literal) @string.special
(void_type) @type.builtin
(type_identifier) @type
(annotation name: (identifier) @attribute)
["import" "export" "library" "part" "as" "show" "hide" "deferred"
 "class" "extends" "implements" "with" "mixin" "enum" "typedef"
 "abstract" "interface" "base" "final" "sealed" "extension" "type"
 "var" "late" "required" "covariant" "const" "static"
 "external" "factory" "operator" "get" "set" "inline"
 "if" "else" "switch" "case" "default" "when"
 "for" "while" "do" "in" "break" "continue"
 "return" "yield" "throw" "rethrow"
 "try" "catch" "finally" "on" "assert"
 "new" "is" "as" "async" "await" "sync" "Function"] @keyword
(const_builtin) @keyword
(final_builtin) @keyword
(break_builtin) @keyword
(assert_builtin) @keyword
(rethrow_builtin) @keyword
(case_builtin) @keyword
(this) @keyword
(super) @keyword
(function_signature name: (identifier) @function)
(getter_signature name: (identifier) @function)
(setter_signature name: (identifier) @function)
(constructor_signature name: (identifier) @constructor)
(method_signature (function_signature name: (identifier) @function.method))
(method_signature (getter_signature name: (identifier) @function.method))
(method_signature (setter_signature name: (identifier) @function.method))
(class_definition name: (identifier) @type)
(mixin_declaration (identifier) @type)
(enum_declaration name: (identifier) @type)
(enum_constant name: (identifier) @constant)
(extension_declaration name: (identifier) @type)
(type_parameter (type_identifier) @type)
(formal_parameter name: (identifier) @variable.parameter)
(named_argument (label (identifier) @variable.parameter))
(library_name) @namespace
(identifier) @variable
["+=" "-=" "*=" "/=" "%=" "~/=" "&=" "|=" "^=" "<<=" ">>=" ">>>="
 "==" "!=" "<" "<=" ">" ">=" "&&" "||" "!" "??" "?." "?.." "??=" "=>"] @operator
["+" "-" "*" "/" "%" "~/" "=" "." ".." "..." "|" "&" "^" "~"] @operator
["(" ")" "[" "]" "{" "}"] @punctuation.bracket
[";" "," ":"] @punctuation.delimiter
(ERROR) @error
''',

// ── JavaScript / TypeScript ───────────────────────────────────────────────
'javascript': r'''
["import" "export" "from" "as" "default"] @keyword
["var" "let" "const" "function" "class" "extends"
 "new" "delete" "typeof" "instanceof" "void" "in" "of"] @keyword
["if" "else" "switch" "case" "default" "for" "while" "do"
 "break" "continue" "return" "throw" "try" "catch" "finally"] @keyword
["async" "await" "yield" "static" "get" "set" "super" "this"] @keyword
(comment) @comment
(string (string_fragment) @string)
(string) @string
(template_string) @string
(template_substitution) @variable
(number) @number
(regex) @string
[true false] @constant
(null) @constant
(undefined) @constant
(function_declaration name: (identifier) @function)
(function name: (identifier) @function)
(arrow_function) @function
(call_expression function: (identifier) @function.call)
(call_expression function: (member_expression property: (property_identifier) @function.call))
(method_definition name: (property_identifier) @function)
(class_declaration name: (identifier) @type)
(new_expression constructor: (identifier) @type)
(import_specifier name: (identifier) @namespace)
(namespace_import (identifier) @namespace)
(identifier) @variable
["+" "-" "*" "/" "%" "**" "==" "===" "!=" "!==" "<" "<=" ">" ">="
 "&&" "||" "??" "!" "=" "+=" "-=" "*=" "/=" "?" ":" "..." "=>"] @operator
["(" ")" "[" "]" "{" "}"] @punctuation
[";" "," "."] @punctuation
(ERROR) @error
''',

'typescript': r'''
["import" "export" "from" "as" "default" "type" "declare" "namespace"
 "module" "enum" "interface" "abstract" "implements"] @keyword
["var" "let" "const" "function" "class" "extends" "new" "delete"
 "typeof" "instanceof" "void" "in" "of" "keyof" "readonly"] @keyword
["if" "else" "switch" "case" "default" "for" "while" "do"
 "break" "continue" "return" "throw" "try" "catch" "finally"] @keyword
["async" "await" "yield" "static" "get" "set" "super" "this" "override"] @keyword
(comment) @comment
(string) @string (template_string) @string
(number) @number (regex) @string
[true false] @constant (null) @constant
(type_identifier) @type
(generic_type name: (type_identifier) @type)
(predefined_type) @type
(function_declaration name: (identifier) @function)
(method_definition name: (property_identifier) @function)
(call_expression function: (identifier) @function.call)
(class_declaration name: (identifier) @type)
(interface_declaration name: (type_identifier) @type)
(enum_declaration name: (identifier) @type)
(decorator) @attribute
(identifier) @variable
["+" "-" "*" "/" "%" "**" "==" "===" "!=" "!==" "<" "<=" ">" ">="
 "&&" "||" "??" "!" "=" "+=" "-=" "?" ":" "..." "=>" "|" "&"] @operator
["(" ")" "[" "]" "{" "}"] @punctuation [";" "," "."] @punctuation
(ERROR) @error
''',

// ── Python ────────────────────────────────────────────────────────────────
'python': r'''
(comment) @comment
(string) @string (concatenated_string) @string
(interpolation) @variable
(integer) @number (float) @number (complex_number) @number
[true false] @constant (none) @constant (ellipsis) @constant
["import" "from" "as" "in" "is" "not" "and" "or"] @keyword
["def" "class" "return" "yield" "del" "pass" "break" "continue"
 "raise" "try" "except" "finally" "with" "lambda" "global" "nonlocal"
 "assert" "print"] @keyword
["if" "elif" "else" "for" "while" "async" "await" "match" "case"] @keyword
(decorator) @attribute
(function_definition name: (identifier) @function)
(class_definition name: (identifier) @type)
(call function: (identifier) @function.call)
(call function: (attribute attribute: (identifier) @function.call))
(type (identifier) @type)
(import_from_statement module_name: (dotted_name) @namespace)
(aliased_import alias: (identifier) @namespace)
(attribute object: (identifier) @variable attribute: (identifier) @variable.member)
(parameter (identifier) @variable.parameter)
(typed_parameter name: (identifier) @variable.parameter)
(identifier) @variable
["+" "-" "*" "/" "//" "%" "**" "@" "==" "!=" "<" "<=" ">" ">="
 "=" "+=" "-=" "*=" "/=" "//=" "%=" "**=" "|" "&" "^" "~" "<<" ">>"
 "->" ":="] @operator
["(" ")" "[" "]" "{" "}"] @punctuation ["," "." ":" ";"] @punctuation
(ERROR) @error
''',

// ── Kotlin ────────────────────────────────────────────────────────────────
'kotlin': r'''
["import" "package"] @keyword
["class" "object" "interface" "enum" "data" "sealed" "abstract" "open"
 "inner" "companion" "fun" "val" "var" "typealias" "by" "is" "as"
 "in" "out" "where" "actual" "expect" "external"] @keyword
["if" "else" "when" "for" "while" "do" "return" "throw"
 "try" "catch" "finally" "break" "continue"] @keyword
["override" "private" "protected" "public" "internal" "static"
 "inline" "noinline" "crossinline" "reified" "suspend" "operator"
 "infix" "tailrec" "vararg" "lateinit" "const"] @keyword
(annotation) @attribute
(multiline_comment) @comment (line_comment) @comment
(string_literal) @string (character_literal) @string
(integer_literal) @number (real_literal) @number (hex_literal) @number
[true false] @constant (null) @constant
(function_declaration (simple_identifier) @function)
(anonymous_function) @function
(class_declaration (type_identifier) @type)
(object_declaration (simple_identifier) @type)
(call_expression (simple_identifier) @function.call)
(type_reference (user_type (simple_identifier) @type))
(simple_identifier) @variable
["+" "-" "*" "/" "%" "==" "!=" "<" "<=" ">" ">=" "&&" "||" "!"
 "=" "+=" "-=" "*=" "/=" "++" "--" "?." "?:" ".."] @operator
["(" ")" "[" "]" "{" "}"] @punctuation [";" "," "." ":"] @punctuation
(ERROR) @error
''',

// ── Rust ──────────────────────────────────────────────────────────────────
'rust': r'''
["use" "mod" "pub" "crate" "super" "self" "extern" "as"] @keyword
["fn" "struct" "enum" "trait" "impl" "type" "const" "static"
 "let" "mut" "ref" "move" "dyn" "where" "async" "await" "unsafe"] @keyword
["if" "else" "match" "for" "while" "loop" "return" "break" "continue"] @keyword
(attribute_item) @attribute (inner_attribute_item) @attribute
(line_comment) @comment (block_comment) @comment
(string_literal) @string (raw_string_literal) @string
(char_literal) @string
(integer_literal) @number (float_literal) @number
[true false] @constant
(function_item name: (identifier) @function)
(call_expression function: (identifier) @function.call)
(call_expression function: (field_expression field: (field_identifier) @function.call))
(macro_invocation macro: (identifier) @function)
(type_identifier) @type
(primitive_type) @type
(self) @keyword
(identifier) @variable
["+" "-" "*" "/" "%" "==" "!=" "<" "<=" ">" ">=" "&&" "||" "!"
 "=" "+=" "-=" "|" "&" "^" "~" "<<" ">>" "->" "=>" "::" ".." "..="] @operator
["(" ")" "[" "]" "{" "}"] @punctuation [";" "," "." ":"] @punctuation
(ERROR) @error
''',

// ── C++ ───────────────────────────────────────────────────────────────────
'cpp': r'''
(preproc_include) @preprocessor
(preproc_def) @preprocessor
(preproc_if) @preprocessor
(preproc_ifdef) @preprocessor
["include" "define" "ifdef" "ifndef" "endif" "pragma"] @preprocessor
["auto" "bool" "char" "double" "float" "int" "long" "short"
 "signed" "unsigned" "void" "wchar_t" "size_t"] @type
["class" "struct" "union" "enum" "namespace" "template"
 "typename" "typedef" "using" "public" "private" "protected"
 "virtual" "override" "final" "explicit" "friend" "inline"
 "static" "extern" "const" "constexpr" "volatile" "mutable"
 "operator" "new" "delete" "sizeof" "alignof" "decltype"] @keyword
["if" "else" "switch" "case" "default" "for" "while" "do"
 "return" "break" "continue" "goto" "throw" "try" "catch"] @keyword
(comment) @comment
(string_literal) @string (char_literal) @string (raw_string_literal) @string
(number_literal) @number
[true false] @constant (null) @constant (nullptr) @constant
(function_declarator declarator: (identifier) @function)
(call_expression function: (identifier) @function.call)
(type_identifier) @type
(namespace_identifier) @namespace
(identifier) @variable
["+" "-" "*" "/" "%" "==" "!=" "<" "<=" ">" ">=" "&&" "||" "!"
 "=" "+=" "-=" "*=" "/=" "|" "&" "^" "~" "<<" ">>" "->" "::" "..."] @operator
["(" ")" "[" "]" "{" "}"] @punctuation [";" "," "." ":"] @punctuation
(ERROR) @error
''',

// ── C ─────────────────────────────────────────────────────────────────────
'c': r'''
(preproc_include) @preprocessor
(preproc_def) @preprocessor
["auto" "char" "double" "float" "int" "long" "short"
 "signed" "unsigned" "void" "size_t"] @type
["struct" "union" "enum" "typedef" "static" "extern"
 "const" "volatile" "inline" "register"] @keyword
["if" "else" "switch" "case" "default" "for" "while" "do"
 "return" "break" "continue" "goto"] @keyword
(comment) @comment
(string_literal) @string (char_literal) @string
(number_literal) @number
[true false] @constant (null) @constant
(function_declarator declarator: (identifier) @function)
(call_expression function: (identifier) @function.call)
(type_identifier) @type
(identifier) @variable
["+" "-" "*" "/" "%" "==" "!=" "<" "<=" ">" ">=" "&&" "||" "!"
 "=" "+=" "-=" "*=" "/=" "|" "&" "^" "~" "<<" ">>" "->"] @operator
["(" ")" "[" "]" "{" "}"] @punctuation [";" "," "." ":"] @punctuation
(ERROR) @error
''',

// ── HTML ──────────────────────────────────────────────────────────────────
'html': r'''
(tag_name) @tag
(attribute (attribute_name) @attribute.name)
(attribute (quoted_attribute_value) @attribute.value)
(attribute (attribute_value) @attribute.value)
(comment) @comment
(doctype) @keyword
(script_element) @none
(style_element)  @none
(raw_text)       @string
(ERROR) @error
''',

// ── CSS ───────────────────────────────────────────────────────────────────
'css': r'''
(class_selector (class_name) @attribute.name)
(id_selector (id_name) @attribute.name)
(tag_name) @tag
(property_name) @attribute.name
(plain_value) @attribute.value
(integer_value) @number (float_value) @number
(color_value) @constant
(string_value) @string
(comment) @comment
["@" "@import" "@media" "@keyframes" "@font-face" "@charset"] @keyword
["!" "important"] @keyword
[":" "::" "." "," ";"] @punctuation
["(" ")" "[" "]" "{" "}"] @punctuation
(ERROR) @error
''',

// ── JSON ──────────────────────────────────────────────────────────────────
'json': r'''
(pair key: (string) @attribute.name)
(string) @string
(number) @number
[true false] @constant
(null) @constant
["[" "]" "{" "}"] @punctuation
["," ":"] @punctuation
(ERROR) @error
''',

// ── YAML ──────────────────────────────────────────────────────────────────
'yaml': r'''
(block_mapping_pair key: (flow_node) @attribute.name)
(block_mapping_pair key: (block_node) @attribute.name)
(string_scalar) @string
(double_quote_scalar) @string (single_quote_scalar) @string
(integer_scalar) @number (float_scalar) @number
(boolean_scalar) @constant
(null_scalar) @constant
(tag) @keyword
(anchor) @attribute
(alias) @attribute
(comment) @comment
(ERROR) @error
''',

// ── Bash ──────────────────────────────────────────────────────────────────
'bash': r'''
["if" "then" "elif" "else" "fi" "for" "in" "do" "done"
 "while" "until" "case" "esac" "function" "return"
 "break" "continue" "local" "declare" "export" "readonly"] @keyword
(comment) @comment
(string) @string (raw_string) @string
(ansi_c_string) @string
(number) @number
(command_name) @function
(function_definition name: (word) @function)
(variable_name) @variable
["$" "$("] @operator
[";" "&" "|" "||" "&&" ">" ">>" "<" "<<" "2>"] @operator
(ERROR) @error
''',

// ── XML ───────────────────────────────────────────────────────────────────
'xml': r'''
(tag_name) @tag
(attribute (attribute_name) @attribute.name)
(attribute_value) @attribute.value
(comment) @comment
(cdata_section) @string
(processing_instruction) @preprocessor
(prolog) @keyword
(ERROR) @error
''',

  }; // end _queries
}
