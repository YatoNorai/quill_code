// lib/src/highlighting/code_block.dart

/// Represents a foldable code block (e.g. { ... } or indented block).
class CodeBlock {
  final int startLine;
  final int endLine;
  final int indent; // indent level (units of tabSize)

  const CodeBlock({
    required this.startLine,
    required this.endLine,
    required this.indent,
  });

  int get lineCount => endLine - startLine + 1;
  bool get isFoldable => lineCount > 1;
}
