// lib/src/completion/snippet_controller.dart
import 'snippet.dart';
import '../core/char_position.dart';
import '../text/content.dart';
import '../text/text_range.dart';

class SnippetController {
  final Content _content;
  CodeSnippet? _activeSnippet;
  List<SnippetTabStop>? _tabStops;
  int _currentTabStop = 0;
  final Map<int, EditorRange> _tabStopRanges = {};

  SnippetController(this._content);

  bool get hasActiveSnippet => _activeSnippet != null;

  EditorRange? insertSnippet(String snippetText, CharPosition position,
      {String indentation = '', Map<String, String> variables = const {}}) {
    final snippet = CodeSnippet.parse(snippetText);
    var expanded = _expandVars(snippet.toPlainText(), variables);
    if (indentation.isNotEmpty) {
      expanded = expanded.split('\n').join('\n$indentation');
    }
    _content.beginBatchEdit();
    _content.insert(position, expanded);
    _content.endBatchEdit();

    _activeSnippet = snippet;
    _tabStops = snippet.tabStops;
    _currentTabStop = 0;
    _computeRanges(position, expanded, snippet);

    if (_tabStops!.isEmpty) {
      _clear();
      return EditorRange.collapsed(_offsetEnd(position, expanded));
    }
    return _rangeForCurrent();
  }

  EditorRange? nextTabStop() {
    if (_tabStops == null) return null;
    _currentTabStop++;
    if (_currentTabStop >= _tabStops!.length) {
      final r = _tabStopRanges[0];
      _clear();
      return r != null ? EditorRange.collapsed(r.start) : null;
    }
    return _rangeForCurrent();
  }

  EditorRange? previousTabStop() {
    if (_tabStops == null) return null;
    if (_currentTabStop > 0) _currentTabStop--;
    return _rangeForCurrent();
  }

  void cancelSnippet() => _clear();

  EditorRange? _rangeForCurrent() {
    if (_tabStops == null || _currentTabStop >= _tabStops!.length) return null;
    return _tabStopRanges[_tabStops![_currentTabStop].index];
  }

  void _computeRanges(CharPosition insertAt, String text, CodeSnippet snippet) {
    _tabStopRanges.clear();
    // Build char-index → editor-position map for the full expanded text.
    int line = insertAt.line, col = insertAt.column;
    final positions = <int, CharPosition>{0: insertAt};
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '\n') { line++; col = 0; } else { col++; }
      positions[i + 1] = CharPosition(line, col);
    }
    // Walk tab stops using their correct offsets within the plain text.
    // Previously this used a running accumulator of placeholder lengths only,
    // which ignored all static text parts and placed every tab stop at offset 0.
    // e.g. "SizedBox($1)" → tab stop 1 at offset 8 (after "SizedBox("), not 0.
    for (final (:offset, :tabStop) in snippet.tabStopOffsets) {
      final start = positions[offset] ?? insertAt;
      final end   = positions[offset + tabStop.placeholder.length] ?? start;
      _tabStopRanges[tabStop.index] = EditorRange(start, end);
    }
  }

  String _expandVars(String text, Map<String, String> vars) {
    var r = text;
    vars.forEach((k, v) {
      r = r.replaceAll('\$$k', v).replaceAll('\${$k}', v);
    });
    return r;
  }

  CharPosition _offsetEnd(CharPosition start, String text) {
    final lines = text.split('\n');
    if (lines.length == 1) return CharPosition(start.line, start.column + text.length);
    return CharPosition(start.line + lines.length - 1, lines.last.length);
  }

  void _clear() {
    _activeSnippet = null;
    _tabStops = null;
    _currentTabStop = 0;
    _tabStopRanges.clear();
  }
}
