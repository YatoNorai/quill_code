// lib/src/text/undo_manager.dart
import '../core/char_position.dart';
import '../text/text_range.dart';

enum ActionType { insert, delete }

class ContentAction {
  final ActionType type;
  final CharPosition position;
  final String text;
  final int timestamp;
  final EditorRange? cursorBefore;
  final EditorRange? cursorAfter;

  ContentAction({
    required this.type, required this.position,
    required this.text, required this.timestamp,
    this.cursorBefore, this.cursorAfter,
  });
}

class CompoundAction {
  final List<ContentAction> actions = [];
  bool get isEmpty => actions.isEmpty;
}

class UndoManager {
  static const int defaultMaxStackSize = 500;
  static const int mergeTimeWindowMs = 800;

  final List<CompoundAction> _stack = [];
  int _pointer = 0;
  int _maxSize;
  bool _enabled = true;
  bool _inBatch = false;
  CompoundAction? _pendingBatch;
  CompoundAction? _currentMerge;
  // Stopwatch is cheaper than DateTime.now() — no syscall
  final _sw = Stopwatch()..start();

  UndoManager({int maxSize = defaultMaxStackSize}) : _maxSize = maxSize;

  bool get canUndo => _pointer > 0;
  bool get canRedo => _pointer < _stack.length;
  bool get isEnabled => _enabled;

  void setEnabled(bool v) => _enabled = v;

  void beginBatchEdit() {
    _inBatch = true;
    _pendingBatch ??= CompoundAction();
  }

  void endBatchEdit() {
    _inBatch = false;
    if (_pendingBatch != null && !_pendingBatch!.isEmpty) _push(_pendingBatch!);
    _pendingBatch = null;
  }

  void recordInsert(CharPosition pos, String text,
      {EditorRange? cursorBefore, EditorRange? cursorAfter}) {
    if (!_enabled) return;
    _record(ActionType.insert, pos, text,
        cursorBefore: cursorBefore, cursorAfter: cursorAfter);
  }

  void recordDelete(CharPosition pos, String text,
      {EditorRange? cursorBefore, EditorRange? cursorAfter}) {
    if (!_enabled) return;
    _record(ActionType.delete, pos, text,
        cursorBefore: cursorBefore, cursorAfter: cursorAfter);
  }

  void _record(ActionType type, CharPosition pos, String text,
      {EditorRange? cursorBefore, EditorRange? cursorAfter}) {
    final now = _sw.elapsedMilliseconds;
    final action = ContentAction(
        type: type, position: pos, text: text, timestamp: now,
        cursorBefore: cursorBefore, cursorAfter: cursorAfter);

    if (_inBatch && _pendingBatch != null) {
      _pendingBatch!.actions.add(action);
      return;
    }

    if (_currentMerge != null &&
        (now - _currentMerge!.actions.last.timestamp) < mergeTimeWindowMs &&
        _currentMerge!.actions.last.type == type) {
      _currentMerge!.actions.add(action);
      return;
    }

    if (_currentMerge != null && !_currentMerge!.isEmpty) _push(_currentMerge!);
    _currentMerge = CompoundAction()..actions.add(action);
  }

  void flush() {
    if (_currentMerge != null && !_currentMerge!.isEmpty) {
      _push(_currentMerge!);
      _currentMerge = null;
    }
  }

  void _push(CompoundAction action) {
    if (_pointer < _stack.length) _stack.removeRange(_pointer, _stack.length);
    _stack.add(action);
    _pointer++;
    _trim();
  }

  void _trim() {
    while (_stack.length > _maxSize) {
      _stack.removeAt(0);
      _pointer = (_pointer - 1).clamp(0, _stack.length);
    }
  }

  CompoundAction? popUndo() {
    flush();
    if (!canUndo) return null;
    _pointer--;
    return _stack[_pointer];
  }

  CompoundAction? popRedo() {
    flush();
    if (!canRedo) return null;
    final a = _stack[_pointer];
    _pointer++;
    return a;
  }

  void clear() {
    _stack.clear();
    _pointer = 0;
    _currentMerge = null;
    _pendingBatch = null;
  }
}
