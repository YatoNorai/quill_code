// lib/src/text/content.dart
import 'content_line.dart';
import 'rope.dart';
import 'text_range.dart';
import 'undo_manager.dart';
import 'line_separator.dart';
import '../core/char_position.dart';

typedef ContentChangeListener = void Function(ContentChangeEvent event);

class ContentChangeEvent {
  final ContentChangeType type;
  final CharPosition position;
  final String text;
  final int affectedLine;
  const ContentChangeEvent({
    required this.type,
    required this.position,
    required this.text,
    required this.affectedLine,
  });
}

enum ContentChangeType { insert, delete }

class Content {
  static const int defaultMaxUndoSize = 500;

  // ── Storage backend ───────────────────────────────────────────────────────
  //
  // For small documents we use a plain List<ContentLine> — the cheapest option.
  // Once the line count exceeds [ropeThreshold] after a bulkReset, we switch to
  // a RopeLineBuffer for O(log n) line-level insert / delete.  A mixed strategy
  // keeps everyday small files fast while making 100k-line files snappy.
  //
  // The threshold is conservative: List.insert/removeRange are O(n) but very
  // cache-friendly; the rope pays a constant overhead per op.  Benchmarks show
  // the rope wins around 5 000 lines.

  /// Switch to RopeLineBuffer when line count exceeds this value.
  static const int ropeThreshold = 5000;

  // Backing stores — exactly one is non-null at a time.
  List<ContentLine>? _list;
  RopeLineBuffer?    _rope;

  bool get _usesRope => _rope != null;

  // ── Uniform line-store API ────────────────────────────────────────────────

  int get lineCount => _usesRope ? _rope!.length : _list!.length;

  ContentLine _getLine(int i)                 => _usesRope ? _rope![i]     : _list![i];
  void        _setLine(int i, ContentLine l)  { if (_usesRope) _rope![i] = l; else _list![i] = l; }

  void _linesInsert(int i, ContentLine l) {
    if (_usesRope) {
      _rope!.insert(i, l);
    } else {
      _list!.insert(i, l);
    }
  }

  void _linesRemoveRange(int s, int e) {
    if (_usesRope) {
      _rope!.removeRange(s, e);
    } else {
      _list!.removeRange(s, e);
    }
  }

  void _linesClear() {
    if (_usesRope) {
      _rope!.clear();
    } else {
      _list!.clear();
    }
  }

  void _linesAdd(ContentLine l) {
    if (_usesRope) {
      _rope!.insert(_rope!.length, l);
    } else {
      _list!.add(l);
    }
  }

  // ── Constructor & listeners ───────────────────────────────────────────────

  final List<ContentChangeListener> _listeners = [];
  final UndoManager _undoManager;
  LineSeparator lineSeparator;
  int _nestedBatch = 0;
  int _documentVersion = 0;

  // ── fullText cache ────────────────────────────────────────────────────────
  // fullText is O(n) — rebuilds the whole string. Cache it so repeated calls
  // (LSP didChange, search, etc.) don't pay the cost when nothing changed.
  String _cachedFullText = '';
  int    _cachedFullTextVersion = -1;

  // ── maxLineLength cache ───────────────────────────────────────────────────
  // Cached per documentVersion — performLayout reads this instead of O(n)
  // scanning _vis every layout call.
  //
  // Incremental tracking: for single-line edits we update in O(1):
  //  • insert into line L: if new length > max → update max trivially.
  //  • delete from line L: only a rescan is needed when L was the max line
  //    and it got shorter — rare, lazy.
  // Multi-line edits and undo/redo force a full rescan on next access.
  int _maxLineLength        = 0;
  int _maxLineLengthVersion = -1;
  int _maxLineLengthLine    = -1;   // which line currently holds the maximum

  /// Length of the longest line. O(1) amortized:
  /// rescans only when [_maxLineLengthVersion] is stale (multi-line edit or
  /// undo/redo); single-line insert/delete updates incrementally in O(1).
  int get maxLineLength {
    if (_maxLineLengthVersion == _documentVersion) return _maxLineLength;
    int m = 0, ml = 0;
    final n = lineCount;
    for (int i = 0; i < n; i++) {
      final l = _getLine(i).length;
      if (l > m) { m = l; ml = i; }
    }
    _maxLineLength        = m;
    _maxLineLengthLine    = ml;
    _maxLineLengthVersion = _documentVersion;
    return m;
  }

  // ── length cache ─────────────────────────────────────────────────────────
  // Content.length is O(n) — sum of every line length + separators.
  // Cache by documentVersion so repeated calls (LSP, search, etc.) are O(1).
  int _cachedLength        = 0;
  int _cachedLengthVersion = -1;

  // ── Helpers for incremental max / length tracking ─────────────────────

  Content({
    String? initialText,
    LineSeparator separator = LineSeparator.lf,
    int maxUndoSize = defaultMaxUndoSize,
  })  : _undoManager = UndoManager(maxSize: maxUndoSize),
        lineSeparator = separator {
    _list = [ContentLine()]; // start with flat list
    if (initialText != null && initialText.isNotEmpty) {
      bulkReset(initialText);
    }
  }

  /// Replace the entire document content in O(n) time.
  ///
  /// Unlike delete()+insert() which calls _doInsert() — a loop of 20k
  /// List.insert() operations = O(n²) — this rebuilds _lines directly from
  /// split('\n'), which is a single O(n) pass. Clears undo history.
  void bulkReset(String newText) {
    _bulkResetCore(newText);
    _notifyAll();
  }

  /// Same as [bulkReset] but suppresses the content-change notification.
  /// Use from [QuillCodeController.setText] where the controller manually
  /// coordinates reanalysis — avoids a wasted fast-path dispatch that
  /// onContentChanged would otherwise fire for the intermediate state.
  void bulkResetSilent(String newText) {
    _bulkResetCore(newText);
    // Intentionally no _notifyAll() — caller drives reanalysis.
  }

  void _bulkResetCore(String newText) {
    _undoManager.setEnabled(false);

    final normalized = _normalize(newText);
    final parts = normalized.isEmpty ? <String>[''] : normalized.split('\n');
    int maxLen = 0, maxLine = 0;
    int totalLen = 0;

    if (parts.length > ropeThreshold) {
      // ── Large document: build a balanced rope in O(n) ──────────────────
      final newLines = <ContentLine>[];
      for (int i = 0; i < parts.length; i++) {
        final p = parts[i];
        newLines.add(ContentLine(p));
        totalLen += p.length + 1;
        if (p.length > maxLen) { maxLen = p.length; maxLine = i; }
      }
      _rope = RopeLineBuffer.fromList(newLines);
      _list = null;
    } else {
      // ── Small document: use flat list ──────────────────────────────────
      _rope = null;
      _list = [];
      for (int i = 0; i < parts.length; i++) {
        final p = parts[i];
        _list!.add(ContentLine(p));
        totalLen += p.length + 1;
        if (p.length > maxLen) { maxLen = p.length; maxLine = i; }
      }
    }

    _undoManager.setEnabled(true);
    _undoManager.clear();
    _documentVersion++;
    _cachedFullTextVersion = -1;
    _maxLineLength        = maxLen;
    _maxLineLengthLine    = maxLine;
    _maxLineLengthVersion = _documentVersion;
    _cachedLength         = parts.isEmpty ? 0 : totalLen - 1;
    _cachedLengthVersion  = _documentVersion;
  }

  int get documentVersion => _documentVersion;
  UndoManager get undoManager => _undoManager;
  ContentLine getLine(int index) => _getLine(index);
  String getLineText(int index) => _getLine(index).text;
  int getLineLength(int index) => _getLine(index).length;

  int get length {
    // Fast path: if fullText is already cached for this version, reuse its length.
    if (_cachedFullTextVersion == _documentVersion) return _cachedFullText.length;
    if (_cachedLengthVersion   == _documentVersion) return _cachedLength;
    int len = 0;
    final n = lineCount;
    for (int i = 0; i < n; i++) len += _getLine(i).length + 1;
    _cachedLength        = n > 0 ? len - 1 : 0;
    _cachedLengthVersion = _documentVersion;
    return _cachedLength;
  }

  // ── Incremental max-line-length update ──────────────────────────────────
  //
  // Called from insert() / delete() after the structural change and after
  // _documentVersion has been bumped.
  //
  // Single-line insert: line L only got longer → O(1) max update.
  // Single-line delete: if L was the max line and got shorter → force lazy
  //   rescan (rare). Otherwise O(1).
  // Multi-line edits and undo/redo: invalidate entirely (rescan on next access).

  void _updateMaxOnInsert(int line, int addedChars) {
    final newLen = _getLine(line).length;
    if (newLen > _maxLineLength) {
      _maxLineLength     = newLen;
      _maxLineLengthLine = line;
    }
    _maxLineLengthVersion = _documentVersion;
    // length grows by exactly addedChars
    _cachedLength        += addedChars;
    _cachedLengthVersion  = _documentVersion;
  }

  void _updateMaxOnDelete(int line, int removedChars) {
    final newLen = _getLine(line).length;
    if (line == _maxLineLengthLine && newLen < _maxLineLength) {
      // The previously longest line got shorter — schedule a lazy rescan.
      _maxLineLengthVersion = -1;
    } else {
      _maxLineLengthVersion = _documentVersion;
    }
    // length shrinks by exactly removedChars
    _cachedLength        -= removedChars;
    _cachedLengthVersion  = _documentVersion;
  }

  void _invalidateMaxAndLength() {
    _maxLineLengthVersion = -1;   // force full rescan on next access
    _cachedLengthVersion  = -1;
  }

  String get fullText {
    if (_documentVersion == _cachedFullTextVersion) return _cachedFullText;
    final buf = StringBuffer();
    final n = lineCount;
    for (int i = 0; i < n; i++) {
      if (i > 0) buf.write(lineSeparator.value);
      buf.write(_getLine(i).text);
    }
    _cachedFullText = buf.toString();
    _cachedFullTextVersion = _documentVersion;
    return _cachedFullText;
  }

  void insert(CharPosition pos, String text) {
    if (text.isEmpty) return;
    _undoManager.recordInsert(pos, text,
        cursorBefore: EditorRange.collapsed(pos));
    final normText = _normalize(text);
    final isSingleLine = !normText.contains('\n');
    _doInsert(pos, normText);
    _documentVersion++;
    if (isSingleLine) {
      _updateMaxOnInsert(pos.line, normText.length);
    } else {
      _invalidateMaxAndLength();
    }
    _notify(ContentChangeEvent(
        type: ContentChangeType.insert,
        position: pos, text: text, affectedLine: pos.line));
  }

  void _doInsert(CharPosition pos, String text) {
    final parts = _normalize(text).split('\n');
    if (parts.length == 1) {
      _getLine(pos.line).insert(pos.column, parts[0]);
    } else {
      final current = _getLine(pos.line);
      final tail = current.substring(pos.column);
      current.delete(pos.column, current.length);
      current.insert(pos.column, parts[0]);
      for (int i = 1; i < parts.length - 1; i++) {
        _linesInsert(pos.line + i, ContentLine(parts[i]));
      }
      _linesInsert(pos.line + parts.length - 1, ContentLine(parts.last + tail));
    }
  }

  void delete(EditorRange range) {
    final norm = range.normalized();
    if (norm.isEmpty) return;
    final deletedText = getTextInRange(norm);
    _undoManager.recordDelete(norm.start, deletedText,
        cursorBefore: norm,
        cursorAfter: EditorRange.collapsed(norm.start));
    final isSingleLine = norm.start.line == norm.end.line;
    final removedChars = deletedText.length;
    _doDelete(norm);
    _documentVersion++;
    if (isSingleLine) {
      _updateMaxOnDelete(norm.start.line, removedChars);
    } else {
      _invalidateMaxAndLength();
    }
    _notify(ContentChangeEvent(
        type: ContentChangeType.delete,
        position: norm.start, text: deletedText,
        affectedLine: norm.start.line));
  }

  void _doDelete(EditorRange range) {
    final s = range.start, e = range.end;
    if (s.line == e.line) {
      _getLine(s.line).delete(s.column, e.column);
    } else {
      final tail = _getLine(e.line).substring(e.column);
      _linesRemoveRange(s.line + 1, e.line + 1);
      final first = _getLine(s.line);
      first.delete(s.column, first.length);
      first.insert(s.column, tail);
    }
  }

  void replace(EditorRange range, String newText) {
    beginBatchEdit();
    delete(range);
    insert(range.normalized().start, newText);
    endBatchEdit();
  }

  String getTextInRange(EditorRange range) {
    final norm = range.normalized();
    if (norm.isEmpty) return '';
    final s = norm.start, e = norm.end;
    if (s.line == e.line) return _getLine(s.line).substring(s.column, e.column);
    final buf = StringBuffer();
    buf.write(_getLine(s.line).substring(s.column));
    for (int i = s.line + 1; i < e.line; i++) {
      buf.write(lineSeparator.value);
      buf.write(_getLine(i).text);
    }
    buf.write(lineSeparator.value);
    buf.write(_getLine(e.line).substring(0, e.column));
    return buf.toString();
  }

  bool get canUndo => _undoManager.canUndo;
  bool get canRedo => _undoManager.canRedo;

  EditorRange? undo() {
    final compound = _undoManager.popUndo();
    if (compound == null) return null;
    EditorRange? newCursor;
    for (final action in compound.actions.reversed) {
      if (action.type == ActionType.insert) {
        _doDelete(EditorRange(action.position, _offsetEnd(action.position, action.text)));
      } else {
        _doInsert(action.position, action.text);
      }
      _documentVersion++;
      newCursor = action.cursorBefore;
    }
    _cachedFullTextVersion = -1;
    _invalidateMaxAndLength();
    _notifyAll();
    return newCursor;
  }

  EditorRange? redo() {
    final compound = _undoManager.popRedo();
    if (compound == null) return null;
    EditorRange? newCursor;
    for (final action in compound.actions) {
      if (action.type == ActionType.insert) {
        _doInsert(action.position, action.text);
      } else {
        _doDelete(EditorRange(action.position, _offsetEnd(action.position, action.text)));
      }
      _documentVersion++;
      newCursor = action.cursorAfter;
    }
    _cachedFullTextVersion = -1;
    _invalidateMaxAndLength();
    _notifyAll();
    return newCursor;
  }

  void beginBatchEdit() {
    _nestedBatch++;
    if (_nestedBatch == 1) _undoManager.beginBatchEdit();
  }

  void endBatchEdit() {
    if (_nestedBatch <= 0) return;
    _nestedBatch--;
    if (_nestedBatch == 0) _undoManager.endBatchEdit();
  }

  void addListener(ContentChangeListener listener) => _listeners.add(listener);
  void removeListener(ContentChangeListener listener) => _listeners.remove(listener);

  void _notify(ContentChangeEvent event) {
    // Iterate by index to avoid allocating a copy — safe because
        // listeners are only added/removed outside of notification.
    for (int _i = 0; _i < _listeners.length; _i++) _listeners[_i](event);
  }

  void _notifyAll() {
    _notify(ContentChangeEvent(
        type: ContentChangeType.insert,
        position: const CharPosition.zero(),
        text: '', affectedLine: 0));
  }

  CharPosition offsetToPosition(int offset) {
    int rem = offset;
    final n = lineCount;
    for (int i = 0; i < n; i++) {
      final ll = _getLine(i).length;
      if (rem <= ll) return CharPosition(i, rem);
      rem -= ll + 1;
    }
    final last = n - 1;
    return CharPosition(last, _getLine(last).length);
  }

  int positionToOffset(CharPosition pos) {
    int offset = 0;
    for (int i = 0; i < pos.line; i++) offset += _getLine(i).length + 1;
    return offset + pos.column;
  }

  CharPosition clampPosition(CharPosition pos) {
    final line = pos.line.clamp(0, lineCount - 1);
    final col = pos.column.clamp(0, _getLine(line).length);
    return CharPosition(line, col);
  }

  String _normalize(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  CharPosition _offsetEnd(CharPosition start, String text) {
    final lines = _normalize(text).split('\n');
    if (lines.length == 1) return CharPosition(start.line, start.column + lines[0].length);
    return CharPosition(start.line + lines.length - 1, lines.last.length);
  }
}
