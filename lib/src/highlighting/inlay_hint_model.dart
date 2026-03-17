// lib/src/highlighting/inlay_hint_model.dart
import 'package:flutter/painting.dart';
import '../core/char_position.dart';

enum InlayHintKind { text, color }

/// An inline hint rendered inside the text area.
class InlayHint {
  final CharPosition position;
  final InlayHintKind kind;
  final String? label;
  final Color? color;

  const InlayHint.text({
    required this.position,
    required String this.label,
  })  : kind = InlayHintKind.text,
        color = null;

  const InlayHint.color({
    required this.position,
    required Color this.color,
  })  : kind = InlayHintKind.color,
        label = null;
}
