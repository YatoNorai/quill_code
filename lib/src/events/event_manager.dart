// lib/src/events/event_manager.dart
import 'dart:async';
import 'editor_event.dart';

typedef EventCallback<T extends EditorEvent> = void Function(T event);

class EventManager {
  final StreamController<EditorEvent> _controller =
      StreamController.broadcast();

  Stream<EditorEvent> get stream => _controller.stream;

  StreamSubscription<T> subscribe<T extends EditorEvent>(EventCallback<T> cb) {
    return _controller.stream
        .where((e) => e is T)
        .cast<T>()
        .listen(cb);
  }

  void dispatch(EditorEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void dispose() => _controller.close();
}
