// lib/src/actions/code_action.dart
import '../core/char_position.dart';
import '../text/text_range.dart';

enum CodeActionKind { quickFix, refactor, snippet, info, surroundWith, generate, navigate }

class CodeAction {
  final String title;
  final String? description;
  final CodeActionKind kind;
  final List<CodeActionEdit> edits;
  final void Function()? callback;

  const CodeAction({
    required this.title,
    this.description,
    required this.kind,
    this.edits = const [],
    this.callback,
  });
}

class CodeActionEdit {
  final EditorRange range;
  final String newText;
  const CodeActionEdit({required this.range, required this.newText});
}

enum SymbolKind { class_, function_, variable, method, field, enum_, mixin_, extension_, unknown }

class SymbolInfo {
  final String name;
  final SymbolKind kind;
  final String? signature;
  final String? documentation;
  final EditorRange nameRange;
  final int definedAtLine;

  const SymbolInfo({
    required this.name,
    required this.kind,
    required this.nameRange,
    this.signature,
    this.documentation,
    this.definedAtLine = -1,
  });

  String get kindLabel {
    switch (kind) {
      case SymbolKind.class_:     return 'class';
      case SymbolKind.function_:  return 'function';
      case SymbolKind.variable:   return 'variable';
      case SymbolKind.method:     return 'method';
      case SymbolKind.field:      return 'field';
      case SymbolKind.enum_:      return 'enum';
      case SymbolKind.mixin_:     return 'mixin';
      case SymbolKind.extension_: return 'extension';
      default:                    return 'symbol';
    }
  }

  String get kindIcon {
    switch (kind) {
      case SymbolKind.class_:     return 'C';
      case SymbolKind.function_:  return 'f';
      case SymbolKind.method:     return 'm';
      case SymbolKind.enum_:      return 'E';
      case SymbolKind.mixin_:     return 'M';
      case SymbolKind.extension_: return 'X';
      default:                    return '◆';
    }
  }
}
