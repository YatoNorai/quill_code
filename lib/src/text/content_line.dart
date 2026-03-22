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
    if (text.isEmpty) return;
    // Use StringBuffer to avoid creating 3 intermediate String objects
    // (substring before, text, substring after) and then joining them.
    // For typical code lines (< 200 chars) this is still very fast
    // and avoids 2 extra string allocations per keystroke.
    final buf = StringBuffer();
    buf.write(_text.substring(0, column));
    buf.write(text);
    buf.write(_text.substring(column));
    _text = buf.toString();
    _cachedWidth = null;
  }

  void delete(int startColumn, int endColumn) {
    if (startColumn >= endColumn) return;
    final buf = StringBuffer();
    if (startColumn > 0) buf.write(_text.substring(0, startColumn));
    if (endColumn < _text.length) buf.write(_text.substring(endColumn));
    _text = buf.toString();
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
