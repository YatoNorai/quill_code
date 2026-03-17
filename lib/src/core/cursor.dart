// lib/src/core/cursor.dart
import 'char_position.dart';
import '../text/text_range.dart';
import '../text/content.dart';

class EditorCursor {
  CharPosition _anchor;
  CharPosition _position;
  final Content _content;

  EditorCursor(this._content)
      : _anchor = const CharPosition.zero(),
        _position = const CharPosition.zero();

  CharPosition get position => _position;
  CharPosition get anchor => _anchor;
  bool get hasSelection => _anchor != _position;
  int get line => _position.line;
  int get column => _position.column;

  EditorRange get selection {
    if (_anchor <= _position) return EditorRange(_anchor, _position);
    return EditorRange(_position, _anchor);
  }

  void moveTo(CharPosition pos, {bool select = false}) {
    _position = _content.clampPosition(pos);
    if (!select) _anchor = _position;
  }

  void clearSelection() => _anchor = _position;

  void setSelection(CharPosition start, CharPosition end) {
    _anchor = _content.clampPosition(start);
    _position = _content.clampPosition(end);
  }

  void setRange(EditorRange range) => setSelection(range.start, range.end);

  void moveLeft({bool select = false, bool byWord = false}) {
    if (!select && hasSelection) { moveTo(selection.start); return; }
    var pos = _position;
    if (byWord) {
      pos = _wordLeft(pos);
    } else if (pos.column > 0) {
      pos = CharPosition(pos.line, pos.column - 1);
    } else if (pos.line > 0) {
      final pl = pos.line - 1;
      pos = CharPosition(pl, _content.getLineLength(pl));
    }
    moveTo(pos, select: select);
  }

  void moveRight({bool select = false, bool byWord = false}) {
    if (!select && hasSelection) { moveTo(selection.end); return; }
    var pos = _position;
    if (byWord) {
      pos = _wordRight(pos);
    } else {
      final ll = _content.getLineLength(pos.line);
      if (pos.column < ll) {
        pos = CharPosition(pos.line, pos.column + 1);
      } else if (pos.line < _content.lineCount - 1) {
        pos = CharPosition(pos.line + 1, 0);
      }
    }
    moveTo(pos, select: select);
  }

  void moveUp({bool select = false}) {
    var pos = _position;
    if (pos.line > 0) {
      final nl = pos.line - 1;
      final nc = pos.column.clamp(0, _content.getLineLength(nl));
      pos = CharPosition(nl, nc);
    }
    moveTo(pos, select: select);
  }

  void moveDown({bool select = false}) {
    var pos = _position;
    if (pos.line < _content.lineCount - 1) {
      final nl = pos.line + 1;
      final nc = pos.column.clamp(0, _content.getLineLength(nl));
      pos = CharPosition(nl, nc);
    }
    moveTo(pos, select: select);
  }

  void moveToLineStart({bool select = false, bool enhanced = true}) {
    final line = _position.line;
    int col = 0;
    if (enhanced) {
      final text = _content.getLineText(line);
      int fns = 0;
      while (fns < text.length && (text[fns] == ' ' || text[fns] == '\t')) fns++;
      col = _position.column == fns ? 0 : fns;
    }
    moveTo(CharPosition(line, col), select: select);
  }

  void moveToLineEnd({bool select = false}) {
    moveTo(CharPosition(_position.line, _content.getLineLength(_position.line)),
        select: select);
  }

  void moveToDocumentStart({bool select = false}) =>
      moveTo(const CharPosition.zero(), select: select);

  void moveToDocumentEnd({bool select = false}) {
    final ll = _content.lineCount - 1;
    moveTo(CharPosition(ll, _content.getLineLength(ll)), select: select);
  }

  void selectWord() {
    final pos = _position;
    final text = _content.getLineText(pos.line);
    if (text.isEmpty) return;
    int start = pos.column, end = pos.column;
    while (start > 0 && _wc(text.codeUnitAt(start - 1))) start--;
    while (end < text.length && _wc(text.codeUnitAt(end))) end++;
    setSelection(CharPosition(pos.line, start), CharPosition(pos.line, end));
  }

  void selectLine() {
    final l = _position.line;
    setSelection(CharPosition(l, 0),
        CharPosition(l, _content.getLineLength(l)));
  }

  void selectAll() {
    final ll = _content.lineCount - 1;
    setSelection(
        const CharPosition.zero(),
        CharPosition(ll, _content.getLineLength(ll)));
  }

  CharPosition _wordLeft(CharPosition pos) {
    int col = pos.column;
    final text = _content.getLineText(pos.line);
    if (col == 0 && pos.line > 0) {
      return CharPosition(pos.line - 1, _content.getLineLength(pos.line - 1));
    }
    col--;
    while (col > 0 && text[col - 1] != ' ' && text[col - 1] != '\t') col--;
    return CharPosition(pos.line, col);
  }

  CharPosition _wordRight(CharPosition pos) {
    final text = _content.getLineText(pos.line);
    int col = pos.column;
    if (col >= text.length) {
      return pos.line < _content.lineCount - 1
          ? CharPosition(pos.line + 1, 0)
          : pos;
    }
    col++;
    while (col < text.length && text[col] != ' ' && text[col] != '\t') col++;
    return CharPosition(pos.line, col);
  }

  static bool _wc(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) || c == 95;
}
