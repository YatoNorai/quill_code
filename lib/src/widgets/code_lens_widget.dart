// lib/src/widgets/code_lens_widget.dart
// ─────────────────────────────────────────────────────────────────────────────
// Renders LSP code lens items as small inline text shown ABOVE the
// corresponding source lines.  Floats over the editor canvas via Positioned
// inside the editor's Stack.
//
//   3 references  |  Run  |  Debug        ← code lens line (non-editable)
//   void main() {
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../lsp/lsp_bridge.dart';
import '../theme/editor_theme.dart';

class CodeLensWidget extends StatelessWidget {
  final QuillCodeController controller;
  final EditorTheme theme;
  final double gutterWidth;
  final double scrollY;
  final double lineHeight;
  final double viewportHeight;

  /// Called when the user taps/clicks a code lens item.
  final void Function(LspCodeLens lens)? onTap;

  const CodeLensWidget({
    super.key,
    required this.controller,
    required this.theme,
    required this.gutterWidth,
    required this.scrollY,
    required this.lineHeight,
    required this.viewportHeight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lenses = controller.codeLensItems;
    if (lenses.isEmpty) return const SizedBox.shrink();

    final labelColor = theme.colorScheme.lineNumber;
    final hoverColor = labelColor.withOpacity(0.15);

    final children = <Widget>[];
    for (final lens in lenses) {
      // Position is relative to the top of the scrollable content.
      // The lens floats 18px above the start of its line.
      final lineY = lens.range.start.line * lineHeight - scrollY;

      // Skip lenses that are out of the visible viewport.
      if (lineY < -lineHeight || lineY > viewportHeight + lineHeight) continue;

      final title = lens.title ?? '';
      if (title.isEmpty) continue;

      children.add(
        Positioned(
          left: gutterWidth + 4,
          top: lineY - 18,
          child: _CodeLensItem(
            title: title,
            labelColor: labelColor,
            hoverColor: hoverColor,
            fontFamily: theme.fontFamily,
            onTap: onTap != null ? () => onTap!(lens) : null,
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Stack(children: children);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual code lens item — supports hover highlight on desktop,
// tap on both desktop and mobile.
// ─────────────────────────────────────────────────────────────────────────────
class _CodeLensItem extends StatefulWidget {
  final String title;
  final Color labelColor;
  final Color hoverColor;
  final String fontFamily;
  final VoidCallback? onTap;

  const _CodeLensItem({
    required this.title,
    required this.labelColor,
    required this.hoverColor,
    required this.fontFamily,
    this.onTap,
  });

  @override
  State<_CodeLensItem> createState() => _CodeLensItemState();
}

class _CodeLensItemState extends State<_CodeLensItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.title,
            style: TextStyle(
              fontSize: 11,
              color: widget.labelColor,
              fontFamily: widget.fontFamily,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
