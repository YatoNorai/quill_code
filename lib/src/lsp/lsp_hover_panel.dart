// lib/src/lsp/lsp_hover_panel.dart
import 'package:flutter/material.dart';
import '../theme/editor_theme.dart';

class LspHoverPanel extends StatefulWidget {
  final String contents;
  final EditorTheme theme;
  final Offset anchorLocal;
  final double lineHeight;
  final double viewportWidth;
  final double viewportHeight;
  final VoidCallback? onDismiss;

  const LspHoverPanel({
    super.key,
    required this.contents,
    required this.theme,
    required this.anchorLocal,
    required this.lineHeight,
    required this.viewportWidth,
    required this.viewportHeight,
    this.onDismiss,
  });

  @override
  State<LspHoverPanel> createState() => _LspHoverPanelState();
}

class _LspHoverPanelState extends State<LspHoverPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double>   _fade;

  static const double _overlayW = 200.0;
  static const double _overlayH = 150.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    const pad = 4.0;

    // Smart positioning (4-way: never overlaps cursor)
    final kbH      = MediaQuery.of(context).viewInsets.bottom;
    final usableH  = widget.viewportHeight - kbH;
    final cursorBottom = widget.anchorLocal.dy + widget.lineHeight;
    final spaceBelow = usableH - cursorBottom - pad;
    final spaceAbove = widget.anchorLocal.dy - pad;
    double top;
    if (spaceBelow >= _overlayH) {
      top = cursorBottom + pad;
    } else if (spaceAbove >= _overlayH) {
      top = widget.anchorLocal.dy - _overlayH - pad;
    } else if (spaceBelow >= spaceAbove) {
      top = cursorBottom + pad;
    } else {
      top = widget.anchorLocal.dy - _overlayH - pad;
      if (top < pad) top = pad;
    }
    final maxTop = (usableH - _overlayH - pad);
    if (top > maxTop && maxTop >= pad) top = maxTop;
    final double left = widget.anchorLocal.dx
        .clamp(pad, (widget.viewportWidth - _overlayW - pad).clamp(pad, double.maxFinite));

    return Positioned(
      left: left, top: top, width: _overlayW, height: _overlayH,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: cs.completionBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border(
                    bottom: BorderSide(color: cs.lineNumber.withOpacity(0.2)),
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 13, color: cs.lineNumber),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text('Documentation',
                      style: TextStyle(
                        fontSize: widget.theme.fontSize * 0.75,
                        color: cs.lineNumber,
                        fontFamily: widget.theme.fontFamily,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, size: 13, color: cs.lineNumber),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    widget.contents,
                    style: TextStyle(
                      fontSize: widget.theme.fontSize * 0.82,
                      color: cs.textNormal,
                      fontFamily: widget.theme.fontFamily,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
