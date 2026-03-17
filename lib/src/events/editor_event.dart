// lib/src/events/editor_event.dart
import '../core/char_position.dart';
import '../text/text_range.dart';

abstract class EditorEvent {}

class ContentChangeEvent2 extends EditorEvent {
  final CharPosition position;
  final String insertedText;
  final String deletedText;
  ContentChangeEvent2({
    required this.position,
    this.insertedText = '',
    this.deletedText = '',
  });
}

class SelectionChangeEvent extends EditorEvent {
  final EditorRange selection;
  final SelectionChangeCause cause;
  SelectionChangeEvent({required this.selection, required this.cause});
}

enum SelectionChangeCause { keyboard, mouse, api, drag }

class ScrollEvent extends EditorEvent {
  final double offsetX;
  final double offsetY;
  ScrollEvent({required this.offsetX, required this.offsetY});
}

class ClickEvent extends EditorEvent {
  final CharPosition position;
  ClickEvent({required this.position});
}

class DoubleClickEvent extends EditorEvent {
  final CharPosition position;
  DoubleClickEvent({required this.position});
}

class LongPressEvent extends EditorEvent {
  final CharPosition position;
  LongPressEvent({required this.position});
}

class SearchResultsEvent extends EditorEvent {
  final List<EditorRange> results;
  SearchResultsEvent({required this.results});
}

class DiagnosticsUpdatedEvent extends EditorEvent {}
class StylesUpdatedEvent extends EditorEvent {}
class CompletionRequestEvent extends EditorEvent {
  final CharPosition position;
  CompletionRequestEvent({required this.position});
}
