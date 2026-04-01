// lib/src/core/multi_cursor.dart
import 'dart:math' as math;
import 'char_position.dart';
import '../text/content.dart';
import '../text/text_range.dart';

/// A single extra cursor (beyond the primary EditorCursor).
class ExtraCursor {
  CharPosition anchor;
  CharPosition position;

  ExtraCursor(this.anchor, this.position);

  bool get hasSelection => anchor != position;

  EditorRange? get selection {
    if (!hasSelection) return null;
    return anchor < position
        ? EditorRange(anchor, position)
        : EditorRange(position, anchor);
  }
}

/// Manages a set of extra cursors for multi-cursor editing.
/// The primary [EditorCursor] is not managed here — this only holds
/// the *additional* cursors. When this list is empty, all editor
/// behaviour is identical to single-cursor mode.
class MultiCursorManager {
  final List<ExtraCursor> _extras = [];

  List<ExtraCursor> get extras => List.unmodifiable(_extras);
  bool get hasExtras => _extras.isNotEmpty;

  /// Add an extra cursor at [pos]. Silently ignores duplicate positions.
  void addAt(CharPosition pos) {
    if (_extras.any((c) => c.position == pos)) return;
    _extras.add(ExtraCursor(pos, pos));
  }

  /// Add a cursor on the line above [currentPos], clamped to line length.
  void addLineAbove(CharPosition currentPos, Content content) {
    if (currentPos.line == 0) return;
    final newLine = currentPos.line - 1;
    final col = currentPos.column.clamp(0, content.getLineLength(newLine));
    addAt(CharPosition(newLine, col));
  }

  /// Add a cursor on the line below [currentPos], clamped to line length.
  void addLineBelow(CharPosition currentPos, Content content) {
    if (currentPos.line >= content.lineCount - 1) return;
    final newLine = currentPos.line + 1;
    final col = currentPos.column.clamp(0, content.getLineLength(newLine));
    addAt(CharPosition(newLine, col));
  }

  /// Remove the extra cursor whose position matches [pos] exactly.
  void removeAt(CharPosition pos) {
    _extras.removeWhere((c) => c.position == pos);
  }

  /// Remove all extra cursors.
  void clear() => _extras.clear();

  /// Move all extra cursors one character to the right.
  void moveAllRight(Content content) {
    for (final c in _extras) {
      final lineLen = content.getLineLength(c.position.line);
      if (c.position.column < lineLen) {
        c.anchor = c.position =
            CharPosition(c.position.line, c.position.column + 1);
      } else if (c.position.line < content.lineCount - 1) {
        c.anchor = c.position = CharPosition(c.position.line + 1, 0);
      }
    }
  }

  /// Move all extra cursors one character to the left.
  void moveAllLeft(Content content) {
    for (final c in _extras) {
      if (c.position.column > 0) {
        c.anchor = c.position =
            CharPosition(c.position.line, c.position.column - 1);
      } else if (c.position.line > 0) {
        final prevLine = c.position.line - 1;
        c.anchor = c.position =
            CharPosition(prevLine, content.getLineLength(prevLine));
      }
    }
  }

  /// Sort cursors top-to-bottom and remove exact-position duplicates.
  void normalize() {
    _extras.sort((a, b) {
      final lc = a.position.line.compareTo(b.position.line);
      return lc != 0 ? lc : a.position.column.compareTo(b.position.column);
    });
    for (int i = _extras.length - 1; i > 0; i--) {
      if (_extras[i].position == _extras[i - 1].position) {
        _extras.removeAt(i);
      }
    }
  }

  /// Returns a list of all extra cursors sorted in **reverse** document order
  /// (bottom-to-top). Used when applying batch edits so earlier insertions
  /// don't shift the positions of later cursors.
  List<ExtraCursor> get extrasReversed {
    final copy = List<ExtraCursor>.from(_extras);
    copy.sort((a, b) {
      final lc = b.position.line.compareTo(a.position.line);
      return lc != 0 ? lc : b.position.column.compareTo(a.position.column);
    });
    return copy;
  }

  /// Update all extra-cursor positions after a batch insert at a position
  /// above a given cursor.  Called after each single-cursor insert so the
  /// remaining cursors stay aligned.
  ///
  /// [insertedAt] — the position where text was inserted.
  /// [addedLines] — number of newlines in the inserted text (0 for single-line).
  /// [lastLineLen] — length of the last line of the inserted text.
  void shiftAfterInsert(
      CharPosition insertedAt, int addedLines, int lastLineLen) {
    for (final c in _extras) {
      if (c.position.line > insertedAt.line ||
          (c.position.line == insertedAt.line &&
              c.position.column >= insertedAt.column)) {
        if (addedLines == 0) {
          // Same line insert — shift column only
          c.anchor = CharPosition(c.anchor.line, c.anchor.column + lastLineLen);
          c.position = CharPosition(
              c.position.line, c.position.column + lastLineLen);
        } else {
          // Multi-line insert — shift to new line
          final newLine = c.position.line + addedLines;
          final newCol = c.position.line == insertedAt.line
              ? lastLineLen + (c.position.column - insertedAt.column)
              : c.position.column;
          c.anchor = CharPosition(c.anchor.line + addedLines,
              c.anchor.line == insertedAt.line
                  ? math.max(0, c.anchor.column - insertedAt.column) +
                      lastLineLen
                  : c.anchor.column);
          c.position = CharPosition(newLine, newCol);
        }
      }
    }
  }

  /// Update all extra-cursor positions after a batch delete.
  /// [deletedRange] — the normalized range that was deleted.
  void shiftAfterDelete(EditorRange deletedRange) {
    final ds = deletedRange.start;
    final de = deletedRange.end;
    final removedLines = de.line - ds.line;

    for (final c in _extras) {
      CharPosition shift(CharPosition p) {
        if (p < ds) return p; // before deletion — unchanged
        if (p >= ds && p <= de) return ds; // inside deletion — collapse to start
        // After deletion
        if (removedLines == 0) {
          return CharPosition(p.line, p.column - (de.column - ds.column));
        } else {
          if (p.line > de.line) {
            return CharPosition(p.line - removedLines, p.column);
          } else {
            // Same line as de but after it
            return CharPosition(
                ds.line, ds.column + (p.column - de.column));
          }
        }
      }

      c.position = shift(c.position);
      c.anchor = shift(c.anchor);
    }
  }
}
