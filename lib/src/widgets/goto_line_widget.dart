// lib/src/widgets/goto_line_widget.dart
//
// Floating go-to-line input overlay.
// Shows "Go to line (1 – N):" as a hint.
// Enter jumps; Escape dismisses.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/editor_theme.dart';

class GotoLineWidget extends StatefulWidget {
  final int lineCount;
  final void Function(int line) onGoto;
  final VoidCallback onDismiss;
  final EditorTheme theme;

  const GotoLineWidget({
    super.key,
    required this.lineCount,
    required this.onGoto,
    required this.onDismiss,
    required this.theme,
  });

  @override
  State<GotoLineWidget> createState() => _GotoLineWidgetState();
}

class _GotoLineWidgetState extends State<GotoLineWidget> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_textCtrl.text.trim());
    if (n == null) { widget.onDismiss(); return; }
    final line = (n - 1).clamp(0, widget.lineCount - 1);
    widget.onGoto(line);
    widget.onDismiss();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    if (ev.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.enter ||
        ev.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    final fs = widget.theme.fontSize;
    final ff = widget.theme.fontFamily;

    return Focus(
      onKeyEvent: _handleKey,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(5),
        color: cs.completionBackground,
        child: Container(
          width: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: cs.cursor.withOpacity(0.6), width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.join_full, size: 14, color: cs.lineNumber),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: cs.textNormal, fontSize: fs, fontFamily: ff, height: 1.3),
                  decoration: InputDecoration(
                    hintText: 'Line (1 \u2013 ${widget.lineCount})',
                    hintStyle: TextStyle(color: cs.lineNumber, fontSize: fs, fontFamily: ff),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
