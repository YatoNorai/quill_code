// lib/src/completion/completion_publisher.dart
import 'completion_item.dart';

/// Used by language plugins to push completion items.
class CompletionPublisher {
  final List<CompletionItem> _items = [];
  bool _cancelled = false;

  void addItem(CompletionItem item) {
    if (_cancelled) throw CompletionCancelledException();
    _items.add(item);
  }

  void addItems(List<CompletionItem> items) {
    for (final item in items) addItem(item);
  }

  List<CompletionItem> get items => List.unmodifiable(_items);
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class CompletionCancelledException implements Exception {
  const CompletionCancelledException();
  @override
  String toString() => 'CompletionCancelledException';
}
