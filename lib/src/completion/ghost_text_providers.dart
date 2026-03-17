// lib/src/completion/ghost_text_providers.dart
//
// Built-in GhostTextProviders (no server needed, instant, offline):
//
//  SnippetGhostProvider  — matches typed prefix against VsCode + Flutter snippets.
//    e.g. typing "stf" shows the full StatefulWidget expansion as ghost text.
//    Typing "for" shows the for-loop body.  Tab accepts.

import 'ghost_text_controller.dart';
import 'vscode_snippets.dart';
import 'flutter_snippets.dart';

class SnippetGhostProvider {
  final String languageId;
  SnippetGhostProvider({required this.languageId});

  Future<List<String>> call(GhostTextContext ctx) async {
    final word = _wordAtCursor(ctx.linePrefix);
    if (word.length < 2) return const [];

    final snippets = _snippetsForLanguage(languageId);
    final matches  = <String>[];

    for (final s in snippets) {
      if (!s.prefix.startsWith(word)) continue;
      final expanded = _expandBody(s.body, ctx);
      if (expanded.isEmpty) continue;
      // Ghost text = the part after the already-typed word.
      final ghost = expanded.startsWith(word) ? expanded.substring(word.length) : expanded;
      if (ghost.isNotEmpty) matches.add(ghost);
      if (matches.length >= 5) break;
    }
    return matches;
  }

  List<VsSnippet> _snippetsForLanguage(String lang) {
    switch (lang) {
      case 'dart':       return [...VsCodeSnippets.dart, ...FlutterSnippets.dart];
      case 'javascript':
      case 'typescript': return VsCodeSnippets.javascript;
      case 'python':     return VsCodeSnippets.python;
      case 'html':       return VsCodeSnippets.html;
      case 'css':        return VsCodeSnippets.css;
      case 'json':       return VsCodeSnippets.json;
      default:           return const [];
    }
  }

  String _wordAtCursor(String linePrefix) {
    int i = linePrefix.length - 1;
    while (i >= 0 && _isIdent(linePrefix.codeUnitAt(i))) i--;
    return linePrefix.substring(i + 1);
  }

  bool _isIdent(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) || c == 95;

  /// Expand VSCode snippet body — strip tab-stop syntax, keep text.
  String _expandBody(String body, GhostTextContext ctx) {
    return body
        .replaceAllMapped(RegExp(r'\$\{(\d+):([^}]*)\}'), (m) => m.group(2) ?? '')
        .replaceAllMapped(RegExp(r'\$\{(\d+)\|([^}]+)\}'), (m) {
          final choices = (m.group(2) ?? '').split(',');
          return choices.isNotEmpty ? choices.first : '';
        })
        .replaceAll(RegExp(r'\$\{TM_[^}]+\}'), '')
        .replaceAll(RegExp(r'\$\d+'), '')
        .replaceAll(r'$0', '');
  }
}
