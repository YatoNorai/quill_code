// lib/src/text/bracket_matcher.dart
// Finds matching bracket pairs for the cursor position.
// Handles: {} () [] <>
// Returns null if no bracket is adjacent to the cursor,
// or if the bracket is unmatched.
import 'content.dart';
import '../native/quill_native.dart';
import 'text_range.dart';
import '../core/char_position.dart';

class BracketPair {
  final CharPosition open;
  final CharPosition close;
  const BracketPair({required this.open, required this.close});
}

class BracketMatcher {
  static const Map<String, String> _open  = {'{': '}', '(': ')', '[': ']', '<': '>'};
  static const Map<String, String> _close = {'}': '{', ')': '(', ']': '[', '>': '<'};
  // Only highlight <> for known generic contexts (not comparison operators)
  static const _angleAllowBefore = {'List', 'Map', 'Set', 'Future', 'Stream',
    'Iterable', 'Function', 'ValueNotifier', 'ValueChanged', 'Widget',
    'BuildContext', 'State', 'StatefulWidget', 'extends', 'implements'};

  /// Find the matching bracket pair adjacent to [cursor].
  /// Checks: cursor is at (left of) an opener, or right of a closer.
  static BracketPair? findPair(Content content, CharPosition cursor) {
    // Try Rust path first — O(n) per line (one-pass string state), vs
    // the Dart path which was O(col * lineLen) due to _inString rescanning.
    final native = QuillNative.bracketMatch(content, cursor.line, cursor.column);
    if (native != null) {
      return BracketPair(
        open:  CharPosition(native[0], native[1]),
        close: CharPosition(native[2], native[3]),
      );
    }

    final line = content.getLineText(cursor.line);
    final col  = cursor.column;

    // Check char at cursor and char before cursor
    for (final checkCol in [col, col - 1]) {
      if (checkCol < 0 || checkCol >= line.length) continue;
      final ch = line[checkCol];

      if (_open.containsKey(ch)) {
        // Skip < > unless context suggests generics
        if (ch == '<' && !_isGenericContext(line, checkCol)) continue;
        final close = _findForward(content, cursor.line, checkCol, ch, _open[ch]!);
        if (close != null) {
          return BracketPair(
            open:  CharPosition(cursor.line, checkCol),
            close: close,
          );
        }
      } else if (_close.containsKey(ch)) {
        if (ch == '>' && !_isGenericContext(line, checkCol)) continue;
        final open = _findBackward(content, cursor.line, checkCol, ch, _close[ch]!);
        if (open != null) {
          return BracketPair(
            open:  open,
            close: CharPosition(cursor.line, checkCol),
          );
        }
      }
    }
    return null;
  }

  // ── Search forward for matching closer ──────────────────────────────────

  static CharPosition? _findForward(Content content, int startLine,
      int startCol, String opener, String closer) {
    int depth = 0;
    const maxLines = 300;
    for (int li = startLine; li < content.lineCount && li < startLine + maxLines; li++) {
      final text = content.getLineText(li);
      final start = li == startLine ? startCol : 0;
      for (int ci = start; ci < text.length; ci++) {
        final c = text[ci];
        if (_inString(text, ci)) continue;
        if (c == opener)  depth++;
        if (c == closer) {
          depth--;
          if (depth == 0) return CharPosition(li, ci);
        }
      }
    }
    return null;
  }

  // ── Search backward for matching opener ─────────────────────────────────

  static CharPosition? _findBackward(Content content, int startLine,
      int startCol, String closer, String opener) {
    int depth = 0;
    const maxLines = 300;
    for (int li = startLine; li >= 0 && li > startLine - maxLines; li--) {
      final text = content.getLineText(li);
      final start = li == startLine ? startCol : text.length - 1;
      for (int ci = start; ci >= 0; ci--) {
        final c = text[ci];
        if (_inString(text, ci)) continue;
        if (c == closer)  depth++;
        if (c == opener) {
          depth--;
          if (depth == 0) return CharPosition(li, ci);
        }
      }
    }
    return null;
  }

  // ── Heuristics ────────────────────────────────────────────────────────────

  static bool _isGenericContext(String line, int col) {
    // Look for word before <
    int start = col - 1;
    while (start >= 0 && _isWordChar(line[start])) start--;
    if (start < col - 1) {
      final word = line.substring(start + 1, col);
      if (_angleAllowBefore.contains(word)) return true;
      // Also allow PascalCase words (type names)
      if (word.isNotEmpty && word[0] == word[0].toUpperCase() &&
          word[0] != word[0].toLowerCase()) return true;
    }
    return false;
  }

  static bool _isWordChar(String c) =>
      c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90 ||
      c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122 ||
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57 ||
      c == '_';

  // Naive string detection (just checks odd/even quote counts before position)
  static bool _inString(String line, int col) {
    int sq = 0, dq = 0;
    for (int i = 0; i < col; i++) {
      if (line[i] == "'" && (i == 0 || line[i-1] != '\\')) sq++;
      if (line[i] == '"' && (i == 0 || line[i-1] != '\\')) dq++;
    }
    return sq % 2 == 1 || dq % 2 == 1;
  }
}
