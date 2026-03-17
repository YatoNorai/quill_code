// lib/src/completion/vscode_snippets.dart
// ─────────────────────────────────────────────────────────────────────────────
// VSCode-compatible snippet library.
// Each snippet has a prefix, description, and body (VSCode snippet syntax).
// Supports: $1..$N tab stops, ${1:placeholder}, ${1|a,b,c|} choices, $0 final.
// ─────────────────────────────────────────────────────────────────────────────

class VsSnippet {
  final String prefix;
  final String description;
  final String body; // VSCode snippet body with \n for newlines

  const VsSnippet({
    required this.prefix,
    required this.description,
    required this.body,
  });
}

class VsCodeSnippets {
  // ── Dart ────────────────────────────────────────────────────────────────
  static const List<VsSnippet> dart = [
    VsSnippet(prefix: 'main',       description: 'main() function',         body: 'void main() {\n  \$0\n}'),
    VsSnippet(prefix: 'class',      description: 'Class definition',         body: 'class \${1:ClassName} {\n  \$0\n}'),
    VsSnippet(prefix: 'stl',        description: 'StatelessWidget',          body: 'class \${1:MyWidget} extends StatelessWidget {\n  const \${1:MyWidget}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return \${2:Container()};\n  }\n}'),
    VsSnippet(prefix: 'stf',        description: 'StatefulWidget',           body: 'class \${1:MyWidget} extends StatefulWidget {\n  const \${1:MyWidget}({super.key});\n\n  @override\n  State<\${1:MyWidget}> createState() => _\${1:MyWidget}State();\n}\n\nclass _\${1:MyWidget}State extends State<\${1:MyWidget}> {\n  @override\n  Widget build(BuildContext context) {\n    return \${2:Container()};\n  }\n}'),
    VsSnippet(prefix: 'if',         description: 'if statement',             body: 'if (\$1) {\n  \$0\n}'),
    VsSnippet(prefix: 'ife',        description: 'if/else statement',        body: 'if (\$1) {\n  \$2\n} else {\n  \$0\n}'),
    VsSnippet(prefix: 'for',        description: 'for loop',                 body: 'for (int \${1:i} = 0; \${1:i} < \${2:count}; \${1:i}++) {\n  \$0\n}'),
    VsSnippet(prefix: 'fore',       description: 'for-in loop',              body: 'for (final \${1:item} in \${2:items}) {\n  \$0\n}'),
    VsSnippet(prefix: 'while',      description: 'while loop',               body: 'while (\$1) {\n  \$0\n}'),
    VsSnippet(prefix: 'switch',     description: 'switch statement',         body: 'switch (\${1:value}) {\n  case \${2:pattern}:\n    \$0\n    break;\n  default:\n    break;\n}'),
    VsSnippet(prefix: 'try',        description: 'try/catch',                body: 'try {\n  \$1\n} catch (\${2:e}) {\n  \$0\n}'),
    VsSnippet(prefix: 'fn',         description: 'Function',                 body: '\${1:void} \${2:name}(\${3:}) {\n  \$0\n}'),
    VsSnippet(prefix: 'get',        description: 'Getter',                   body: '\${1:Type} get \${2:name} => \$0;'),
    VsSnippet(prefix: 'set',        description: 'Setter',                   body: 'set \${1:name}(\${2:Type} value) {\n  \$0\n}'),
    VsSnippet(prefix: 'print',      description: 'print()',                  body: 'print(\$1);'),
    VsSnippet(prefix: 'log',        description: 'debugPrint()',             body: 'debugPrint(\'\$1\');'),
    VsSnippet(prefix: 'async',      description: 'async function',           body: 'Future<\${1:void}> \${2:name}() async {\n  \$0\n}'),
    VsSnippet(prefix: 'await',      description: 'await expression',         body: 'await \$1;'),
    VsSnippet(prefix: 'stream',     description: 'Stream builder snippet',   body: 'Stream<\${1:T}> \${2:name}() async* {\n  \$0\n}'),
    VsSnippet(prefix: 'enum',       description: 'enum definition',          body: 'enum \${1:Name} {\n  \${2:value1},\n  \$0\n}'),
    VsSnippet(prefix: 'mixin',      description: 'mixin definition',         body: 'mixin \${1:Name} {\n  \$0\n}'),
    VsSnippet(prefix: 'ext',        description: 'extension',                body: 'extension \${1:Name} on \${2:Type} {\n  \$0\n}'),
    VsSnippet(prefix: 'override',   description: '@override method',         body: '@override\n\${1:void} \${2:name}() {\n  \$0\n}'),
    VsSnippet(prefix: 'test',       description: 'test() block',             body: 'test(\'\${1:description}\', () {\n  \$0\n});'),
    VsSnippet(prefix: 'group',      description: 'group() block',            body: 'group(\'\${1:description}\', () {\n  \$0\n});'),
    VsSnippet(prefix: 'expect',     description: 'expect()',                 body: 'expect(\$1, \${2:equals(\$3)});'),
  ];

  // ── JavaScript / TypeScript ──────────────────────────────────────────────
  static const List<VsSnippet> javascript = [
    VsSnippet(prefix: 'cl',         description: 'console.log()',            body: 'console.log(\$1);'),
    VsSnippet(prefix: 'ce',         description: 'console.error()',          body: 'console.error(\$1);'),
    VsSnippet(prefix: 'fn',         description: 'function declaration',     body: 'function \${1:name}(\${2:params}) {\n  \$0\n}'),
    VsSnippet(prefix: 'afn',        description: 'Arrow function',           body: 'const \${1:name} = (\${2:params}) => {\n  \$0\n};'),
    VsSnippet(prefix: 'iife',       description: 'IIFE',                     body: '((\${1:params}) => {\n  \$0\n})(\${2:args});'),
    VsSnippet(prefix: 'class',      description: 'ES6 class',                body: 'class \${1:ClassName} {\n  constructor(\${2:params}) {\n    \$0\n  }\n}'),
    VsSnippet(prefix: 'imp',        description: 'import statement',         body: 'import \${1:{ \${2:name} }} from \'\${3:module}\';'),
    VsSnippet(prefix: 'exp',        description: 'export statement',         body: 'export \${1:default} \${2:name};'),
    VsSnippet(prefix: 'if',         description: 'if statement',             body: 'if (\$1) {\n  \$0\n}'),
    VsSnippet(prefix: 'ife',        description: 'if/else',                  body: 'if (\$1) {\n  \$2\n} else {\n  \$0\n}'),
    VsSnippet(prefix: 'for',        description: 'for loop',                 body: 'for (let \${1:i} = 0; \${1:i} < \${2:arr}.length; \${1:i}++) {\n  \$0\n}'),
    VsSnippet(prefix: 'fore',       description: 'for...of loop',            body: 'for (const \${1:item} of \${2:items}) {\n  \$0\n}'),
    VsSnippet(prefix: 'forin',      description: 'for...in loop',            body: 'for (const \${1:key} in \${2:obj}) {\n  \$0\n}'),
    VsSnippet(prefix: 'while',      description: 'while loop',               body: 'while (\$1) {\n  \$0\n}'),
    VsSnippet(prefix: 'try',        description: 'try/catch/finally',        body: 'try {\n  \$1\n} catch (\${2:error}) {\n  \$3\n} finally {\n  \$0\n}'),
    VsSnippet(prefix: 'promise',    description: 'new Promise()',            body: 'new Promise((\${1:resolve}, \${2:reject}) => {\n  \$0\n});'),
    VsSnippet(prefix: 'async',      description: 'async function',           body: 'async function \${1:name}(\${2:params}) {\n  \$0\n}'),
    VsSnippet(prefix: 'await',      description: 'await',                    body: 'const \${1:result} = await \${2:promise};'),
    VsSnippet(prefix: 'switch',     description: 'switch statement',         body: 'switch (\${1:key}) {\n  case \${2:value}:\n    \$0\n    break;\n  default:\n    break;\n}'),
    VsSnippet(prefix: 'tern',       description: 'Ternary operator',         body: '\${1:condition} ? \${2:then} : \${3:else}'),
    VsSnippet(prefix: 'destobj',    description: 'Destructure object',       body: 'const { \${1:key} } = \${2:obj};'),
    VsSnippet(prefix: 'destarr',    description: 'Destructure array',        body: 'const [\${1:first}, \${2:rest}] = \${3:arr};'),
    VsSnippet(prefix: 'spread',     description: 'Spread operator',          body: '...\${1:iterable}'),
    VsSnippet(prefix: 'typeof',     description: 'typeof check',             body: 'typeof \${1:value} === \'\${2:string}\''),
    VsSnippet(prefix: 'fetch',      description: 'fetch API',                body: 'const response = await fetch(\'\${1:url}\');\nconst data = await response.json();\n\$0'),
  ];

  // ── Python ───────────────────────────────────────────────────────────────
  static const List<VsSnippet> python = [
    VsSnippet(prefix: 'main',       description: 'main guard',               body: 'if __name__ == \'__main__\':\n    \$0'),
    VsSnippet(prefix: 'def',        description: 'function def',             body: 'def \${1:name}(\${2:params}):\n    \$0'),
    VsSnippet(prefix: 'class',      description: 'class definition',         body: 'class \${1:ClassName}:\n    def __init__(self\${2:, params}):\n        \$0'),
    VsSnippet(prefix: 'if',         description: 'if statement',             body: 'if \${1:condition}:\n    \$0'),
    VsSnippet(prefix: 'ife',        description: 'if/else',                  body: 'if \${1:condition}:\n    \$2\nelse:\n    \$0'),
    VsSnippet(prefix: 'elif',       description: 'elif chain',               body: 'elif \${1:condition}:\n    \$0'),
    VsSnippet(prefix: 'for',        description: 'for loop',                 body: 'for \${1:item} in \${2:items}:\n    \$0'),
    VsSnippet(prefix: 'forr',       description: 'for range loop',           body: 'for \${1:i} in range(\${2:n}):\n    \$0'),
    VsSnippet(prefix: 'while',      description: 'while loop',               body: 'while \${1:condition}:\n    \$0'),
    VsSnippet(prefix: 'try',        description: 'try/except',               body: 'try:\n    \$1\nexcept \${2:Exception} as \${3:e}:\n    \$0'),
    VsSnippet(prefix: 'with',       description: 'with statement',           body: 'with \${1:open(\'\${2:file}\')} as \${3:f}:\n    \$0'),
    VsSnippet(prefix: 'lc',         description: 'list comprehension',       body: '[\${1:expr} for \${2:item} in \${3:items}]'),
    VsSnippet(prefix: 'dc',         description: 'dict comprehension',       body: '{\${1:key}: \${2:value} for \${3:item} in \${4:items}}'),
    VsSnippet(prefix: 'lambda',     description: 'lambda function',          body: 'lambda \${1:params}: \${2:expr}'),
    VsSnippet(prefix: 'print',      description: 'print()',                  body: 'print(\$1)'),
    VsSnippet(prefix: 'import',     description: 'import',                   body: 'import \${1:module}'),
    VsSnippet(prefix: 'from',       description: 'from import',              body: 'from \${1:module} import \${2:name}'),
    VsSnippet(prefix: 'dataclass',  description: '@dataclass',               body: 'from dataclasses import dataclass\n\n@dataclass\nclass \${1:ClassName}:\n    \${2:field}: \${3:type}\n    \$0'),
    VsSnippet(prefix: 'async',      description: 'async def',                body: 'async def \${1:name}(\${2:params}):\n    \$0'),
    VsSnippet(prefix: 'await',      description: 'await',                    body: 'await \$1'),
  ];

  // ── HTML ─────────────────────────────────────────────────────────────────
  static const List<VsSnippet> html = [
    VsSnippet(prefix: 'html5',      description: 'HTML5 boilerplate',        body: '<!DOCTYPE html>\n<html lang="\${1:en}">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title>\${2:Document}</title>\n</head>\n<body>\n  \$0\n</body>\n</html>'),
    VsSnippet(prefix: 'div',        description: '<div>',                    body: '<div\${1: class="\${2:}"}>\\n  \$0\n</div>'),
    VsSnippet(prefix: 'span',       description: '<span>',                   body: '<span\${1: class="\${2:}"}>\\n  \$0\n</span>'),
    VsSnippet(prefix: 'p',          description: '<p>',                      body: '<p>\$0</p>'),
    VsSnippet(prefix: 'a',          description: '<a>',                      body: '<a href="\${1:#}">\${2:link text}</a>'),
    VsSnippet(prefix: 'img',        description: '<img>',                    body: '<img src="\${1:path}" alt="\${2:description}">'),
    VsSnippet(prefix: 'input',      description: '<input>',                  body: '<input type="\${1|text,email,password,number,checkbox,radio,file|}" name="\${2:name}" id="\${2:name}">'),
    VsSnippet(prefix: 'button',     description: '<button>',                 body: '<button type="\${1|button,submit,reset|}">\${2:label}</button>'),
    VsSnippet(prefix: 'form',       description: '<form>',                   body: '<form action="\${1:#}" method="\${2|get,post|}">\n  \$0\n</form>'),
    VsSnippet(prefix: 'ul',         description: '<ul>',                     body: '<ul>\n  <li>\$1</li>\n  \$0\n</ul>'),
    VsSnippet(prefix: 'ol',         description: '<ol>',                     body: '<ol>\n  <li>\$1</li>\n  \$0\n</ol>'),
    VsSnippet(prefix: 'table',      description: '<table>',                  body: '<table>\n  <thead>\n    <tr>\n      <th>\$1</th>\n    </tr>\n  </thead>\n  <tbody>\n    <tr>\n      <td>\$2</td>\n    </tr>\n  </tbody>\n</table>'),
    VsSnippet(prefix: 'link',       description: '<link>',                   body: '<link rel="stylesheet" href="\${1:style.css}">'),
    VsSnippet(prefix: 'script',     description: '<script>',                 body: '<script src="\${1:script.js}"></script>'),
    VsSnippet(prefix: 'meta',       description: '<meta>',                   body: '<meta name="\${1:name}" content="\${2:content}">'),
  ];

  // ── CSS ──────────────────────────────────────────────────────────────────
  static const List<VsSnippet> css = [
    VsSnippet(prefix: 'flex',       description: 'Flexbox container',        body: 'display: flex;\njustify-content: \${1|flex-start,center,flex-end,space-between,space-around|};\nalign-items: \${2|stretch,center,flex-start,flex-end|};'),
    VsSnippet(prefix: 'grid',       description: 'Grid container',           body: 'display: grid;\ngrid-template-columns: \${1:repeat(3, 1fr)};\ngrid-gap: \${2:1rem};'),
    VsSnippet(prefix: 'var',        description: 'CSS variable',             body: '--\${1:name}: \${2:value};'),
    VsSnippet(prefix: 'media',      description: '@media query',             body: '@media (\${1|max-width,min-width|}: \${2:768px}) {\n  \$0\n}'),
    VsSnippet(prefix: 'anim',       description: '@keyframes',               body: '@keyframes \${1:name} {\n  from { \$2 }\n  to { \$0 }\n}'),
    VsSnippet(prefix: 'trans',      description: 'transition',               body: 'transition: \${1:all} \${2:0.3s} \${3|ease,linear,ease-in,ease-out,ease-in-out|};'),
    VsSnippet(prefix: 'shadow',     description: 'box-shadow',               body: 'box-shadow: \${1:0} \${2:2px} \${3:8px} \${4:rgba(0, 0, 0, 0.2)};'),
  ];

  // ── JSON ─────────────────────────────────────────────────────────────────
  static const List<VsSnippet> json = [
    VsSnippet(prefix: 'obj',        description: 'JSON object',              body: '{\n  "\${1:key}": \${2:value}\n}'),
    VsSnippet(prefix: 'arr',        description: 'JSON array',               body: '[\n  \$0\n]'),
  ];

  /// Get snippets for a language name (case-insensitive).
  static List<VsSnippet> forLanguage(String languageName) {
    final lower = languageName.toLowerCase();
    List<VsSnippet> builtin;
    if (lower.contains('dart'))       builtin = dart;
    else if (lower.contains('javascript') || lower.contains('typescript') ||
             lower == 'js' || lower == 'ts') builtin = javascript;
    else if (lower.contains('python'))     builtin = python;
    else if (lower.contains('html'))       builtin = html;
    else if (lower.contains('css'))        builtin = css;
    else if (lower.contains('json'))       builtin = json;
    else                                   builtin = const [];
    final custom = SnippetRegistry.forLanguage(lower);
    return custom.isEmpty ? builtin : [...builtin, ...custom];
  }
}

// ── Runtime snippet registry (loaded from JSON or user code) ─────────────────

class SnippetRegistry {
  static final Map<String, List<VsSnippet>> _custom = {};

  /// Register snippets for a language ID from a VSCode-format JSON map.
  /// JSON format: { "Name": { "prefix": "...", "body": "...", "description": "..." } }
  static void loadFromJson(String languageId, Map<String, dynamic> json) {
    final snippets = <VsSnippet>[];
    for (final entry in json.entries) {
      final v = entry.value as Map<String, dynamic>;
      final prefix = v['prefix'];
      final body   = v['body'];
      final desc   = v['description'] as String? ?? entry.key;
      if (prefix == null || body == null) continue;
      // body can be string or list of strings
      final bodyStr = body is List
          ? (body as List).join('\n')
          : body.toString();
      final prefixStr = prefix is List
          ? (prefix as List).first.toString()
          : prefix.toString();
      snippets.add(VsSnippet(
        prefix:      prefixStr,
        description: desc,
        body:        bodyStr,
      ));
    }
    _custom[languageId.toLowerCase()] = [
      ...(_custom[languageId.toLowerCase()] ?? []),
      ...snippets,
    ];
  }

  /// Register snippets programmatically.
  static void register(String languageId, List<VsSnippet> snippets) {
    final key = languageId.toLowerCase();
    _custom[key] = [...(_custom[key] ?? []), ...snippets];
  }

  /// Get all registered snippets for a language.
  static List<VsSnippet> forLanguage(String languageId) =>
      _custom[languageId.toLowerCase()] ?? [];

  /// Clear all custom snippets (for testing).
  static void clear() => _custom.clear();
}
