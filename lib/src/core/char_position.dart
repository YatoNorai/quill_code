// lib/src/core/char_position.dart

/// Represents a position in the document as (line, column).
/// Line and column are zero-based.
class CharPosition {
  final int line;
  final int column;

  const CharPosition(this.line, this.column);
  const CharPosition.zero() : line = 0, column = 0;

  CharPosition copyWith({int? line, int? column}) =>
      CharPosition(line ?? this.line, column ?? this.column);

  bool operator <(CharPosition other) =>
      line < other.line || (line == other.line && column < other.column);

  bool operator <=(CharPosition other) => this < other || this == other;

  bool operator >(CharPosition other) => other < this;

  bool operator >=(CharPosition other) => other <= this;

  @override
  bool operator ==(Object other) =>
      other is CharPosition && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => 'CharPosition($line, $column)';
}
