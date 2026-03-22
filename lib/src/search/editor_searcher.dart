// lib/src/search/editor_searcher.dart
import 'dart:async';
import 'dart:typed_data';
import 'search_options.dart';
import '../text/content.dart';
import '../text/text_range.dart';
import '../core/char_position.dart';
import '../native/quill_native.dart';

class EditorSearcher {
  final Content _content;
  String? _currentPattern;
  SearchOptions _searchOptions = const SearchOptions();
  ReplaceOptions _replaceOptions = ReplaceOptions.defaults;
  List<EditorRange> _results = [];
  int _currentResultIndex = -1;
  bool _cyclicJumping = true;
  Timer? _debounce;

  final StreamController<List<EditorRange>> _resultsController =
      StreamController.broadcast();

  Stream<List<EditorRange>> get resultsStream => _resultsController.stream;
  List<EditorRange> get results => List.unmodifiable(_results);
  bool get hasQuery => _currentPattern != null && _currentPattern!.isNotEmpty;
  bool get cyclicJumping => _cyclicJumping;
  set cyclicJumping(bool v) => _cyclicJumping = v;
  int get currentResultIndex => _currentResultIndex;
  int get resultCount => _results.length;

  EditorSearcher(this._content);

  void search(String pattern, SearchOptions options) {
    if (pattern.isEmpty) return;
    _currentPattern = pattern;
    _searchOptions = options;
    _schedule();
  }

  void stopSearch() {
    _currentPattern = null;
    _results = [];
    _currentResultIndex = -1;
    if (!_resultsController.isClosed) _resultsController.add([]);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _execute);
  }

  Future<void> _execute() async {
    if (_currentPattern == null) return;
    final pattern = _currentPattern!;
    final opts    = _searchOptions;
    final text    = _content.fullText;

    List<EditorRange>? results;

    // Try Rust literal search (no regex, no heap on hot path)
    final isLiteral = opts.type != SearchType.regularExpression;
    if (isLiteral && QuillNative.isAvailable) {
      final lineStarts = QuillNative.buildLineStarts(text);
      results = QuillNative.searchLiteral(
        text, pattern,
        caseSensitive: opts.caseSensitive,
        wholeWord:     opts.type == SearchType.wholeWord,
        lineStarts:    lineStarts,
      );
    }

    // Fallback to Dart regex for regex mode or if native unavailable
    results ??= await Future.microtask(() => _findAll(text, pattern, opts));

    _results = results!;
    _currentResultIndex = _results.isEmpty ? -1 : 0;
    if (!_resultsController.isClosed) _resultsController.add(_results);
  }

  List<EditorRange> _findAll(String text, String pattern, SearchOptions opts) {
    final results = <EditorRange>[];
    try {
      RegExp regex;
      if (opts.type == SearchType.regularExpression) {
        regex = RegExp(pattern, caseSensitive: opts.caseSensitive);
      } else {
        var esc = RegExp.escape(pattern);
        if (opts.type == SearchType.wholeWord) esc = r'\b' + esc + r'\b';
        regex = RegExp(esc, caseSensitive: opts.caseSensitive);
      }
      final matches = regex.allMatches(text);
      if (matches.isEmpty) return results;

      // Build a line-start offset table once so each match lookup is O(log n)
      // instead of O(n) — critical for large files with many matches.
      final lineStarts = <int>[0];
      for (int i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) lineStarts.add(i + 1);
      }

      CharPosition _offsetToPos(int offset) {
        // Binary search for the line whose start is <= offset.
        int lo = 0, hi = lineStarts.length - 1;
        while (lo < hi) {
          final mid = (lo + hi + 1) ~/ 2;
          if (lineStarts[mid] <= offset) lo = mid; else hi = mid - 1;
        }
        return CharPosition(lo, offset - lineStarts[lo]);
      }

      for (final m in matches) {
        results.add(EditorRange(_offsetToPos(m.start), _offsetToPos(m.end)));
      }
    } catch (_) {}
    return results;
  }

  EditorRange? gotoNext(CharPosition currentPos) {
    if (_results.isEmpty) return null;
    for (int i = 0; i < _results.length; i++) {
      if (_results[i].start > currentPos) {
        _currentResultIndex = i;
        return _results[i];
      }
    }
    if (_cyclicJumping) { _currentResultIndex = 0; return _results[0]; }
    return null;
  }

  EditorRange? gotoPrevious(CharPosition currentPos) {
    if (_results.isEmpty) return null;
    for (int i = _results.length - 1; i >= 0; i--) {
      if (_results[i].end < currentPos) {
        _currentResultIndex = i;
        return _results[i];
      }
    }
    if (_cyclicJumping) {
      _currentResultIndex = _results.length - 1;
      return _results.last;
    }
    return null;
  }

  void replaceCurrent(String replacement) {
    if (_currentResultIndex < 0 || _currentResultIndex >= _results.length) return;
    final range = _results[_currentResultIndex];
    final orig = _content.getTextInRange(range);
    _content.replace(range, _applyReplace(orig, replacement));
    _execute();
  }

  void replaceAll(String replacement) {
    if (_results.isEmpty) return;
    _content.beginBatchEdit();
    for (final range in _results.reversed) {
      _content.replace(range, _applyReplace(_content.getTextInRange(range), replacement));
    }
    _content.endBatchEdit();
    stopSearch();
  }

  String _applyReplace(String orig, String replacement) {
    if (_replaceOptions.preserveCase) {
      if (orig == orig.toUpperCase()) return replacement.toUpperCase();
      if (orig.isNotEmpty && orig[0] == orig[0].toUpperCase()) {
        return replacement[0].toUpperCase() + replacement.substring(1);
      }
    }
    return replacement;
  }

  void onContentChanged() {
    if (hasQuery) _schedule();
  }

  void dispose() {
    _debounce?.cancel();
    _resultsController.close();
  }
}
