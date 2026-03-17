// lib/src/text/content_line.dart

/// A single line in the document.
/// Backed by a plain [String] — edits use substring concatenation which
/// is faster than List<int> insertAll/removeRange for typical code lines
/// (short, mostly ASCII). The VM interns short strings aggressively.
class ContentLine {
  String _text;
  double? _cachedWidth;

  ContentLine([String text = '']) : _text = text;

  int get length => _text.length;
  bool get isEmpty => _text.isEmpty;

  String get text => _text;

  int charCodeAt(int index) => _text.codeUnitAt(index);

  void insert(int column, String text) {
    _text = _text.substring(0, column) + text + _text.substring(column);
    _cachedWidth = null;
  }

  void delete(int startColumn, int endColumn) {
    _text = _text.substring(0, startColumn) + _text.substring(endColumn);
    _cachedWidth = null;
  }

  String substring(int start, [int? end]) => _text.substring(start, end);

  void invalidateWidth() => _cachedWidth = null;
  double? get cachedWidth => _cachedWidth;
  set cachedWidth(double? v) => _cachedWidth = v;

  ContentLine clone() => ContentLine(_text);

  @override
  String toString() => _text;
}
