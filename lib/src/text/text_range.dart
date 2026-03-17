// lib/src/text/text_range.dart
import '../core/char_position.dart';

/// A range in the document from [start] to [end] (both inclusive on start, exclusive on end).
class EditorRange {
  final CharPosition start;
  final CharPosition end;

  const EditorRange(this.start, this.end);

  const EditorRange.collapsed(CharPosition position)
      : start = position,
        end = position;

  bool get isEmpty => start == end;
  bool get isNotEmpty => !isEmpty;

  bool contains(CharPosition pos) => start <= pos && pos <= end;

  EditorRange normalized() =>
      start <= end ? this : EditorRange(end, start);

  @override
  bool operator ==(Object other) =>
      other is EditorRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'EditorRange($start → $end)';
}
