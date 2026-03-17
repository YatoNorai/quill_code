// lib/src/lsp/lsp_signature_panel.dart
import 'package:flutter/material.dart';
import '../theme/editor_theme.dart';
import 'lsp_bridge.dart';

class LspSignaturePanel extends StatelessWidget {
  final LspSignatureHelp sigHelp;
  final EditorTheme theme;
  final Offset anchorLocal;
  final double lineHeight;
  final double viewportWidth;
  final double viewportHeight;
  final VoidCallback? onDismiss;

  static const double _overlayW = 200.0;
  static const double _overlayH = 150.0;

  const LspSignaturePanel({
    super.key,
    required this.sigHelp,
    required this.theme,
    required this.anchorLocal,
    required this.lineHeight,
    required this.viewportWidth,
    required this.viewportHeight,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs   = theme.colorScheme;
    final fs   = theme.fontSize;
    final font = theme.fontFamily;

    final label     = sigHelp.label;
    final params    = sigHelp.parameters;
    final activeIdx = sigHelp.activeParameter.clamp(0, params.isEmpty ? 0 : params.length - 1);

    final List<TextSpan> labelSpans;
    if (params.isEmpty || activeIdx >= params.length) {
      labelSpans = [TextSpan(text: label, style: TextStyle(color: cs.textNormal, fontSize: fs * 0.82, fontFamily: font))];
    } else {
      final activeParam = params[activeIdx];
      final startIdx = label.indexOf(activeParam);
      if (startIdx < 0) {
        labelSpans = [TextSpan(text: label, style: TextStyle(color: cs.textNormal, fontSize: fs * 0.82, fontFamily: font))];
      } else {
        final endIdx = startIdx + activeParam.length;
        labelSpans = [
          if (startIdx > 0)
            TextSpan(text: label.substring(0, startIdx),
              style: TextStyle(color: cs.textNormal, fontSize: fs * 0.82, fontFamily: font)),
          TextSpan(text: activeParam,
            style: TextStyle(color: cs.keyword, fontSize: fs * 0.82, fontFamily: font, fontWeight: FontWeight.bold)),
          if (endIdx < label.length)
            TextSpan(text: label.substring(endIdx),
              style: TextStyle(color: cs.textNormal, fontSize: fs * 0.82, fontFamily: font)),
        ];
      }
    }

    const pad = 4.0;
    // Smart positioning (4-way: never overlaps cursor)
    final kbH      = MediaQuery.of(context).viewInsets.bottom;
    final usableH  = viewportHeight - kbH;
    final cursorBottom = anchorLocal.dy + lineHeight;
    final spaceBelow = usableH - cursorBottom - pad;
    final spaceAbove = anchorLocal.dy - pad;
    double top;
    if (spaceBelow >= _overlayH) {
      top = cursorBottom + pad;
    } else if (spaceAbove >= _overlayH) {
      top = anchorLocal.dy - _overlayH - pad;
    } else if (spaceBelow >= spaceAbove) {
      top = cursorBottom + pad;
    } else {
      top = anchorLocal.dy - _overlayH - pad;
      if (top < pad) top = pad;
    }
    final maxTop = (usableH - _overlayH - pad);
    if (top > maxTop && maxTop >= pad) top = maxTop;
    final double left = anchorLocal.dx
        .clamp(pad, (viewportWidth - _overlayW - pad).clamp(pad, double.maxFinite));

    return Positioned(
      left: left, top: top, width: _overlayW, height: _overlayH,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        color: cs.completionBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                  color: cs.lineNumber.withOpacity(0.2))),
              ),
              child: Row(children: [
                Icon(Icons.functions, size: 13, color: cs.keyword),
                const SizedBox(width: 5),
                Expanded(child: RichText(
                  text: TextSpan(children: labelSpans),
                  overflow: TextOverflow.ellipsis,
                )),
                if (onDismiss != null)
                  GestureDetector(
                    onTap: onDismiss,
                    child: Icon(Icons.close, size: 13, color: cs.lineNumber),
                  ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (params.isNotEmpty)
                      Text(
                        '${activeIdx + 1} / ${params.length}  ·  ${params.isNotEmpty && activeIdx < params.length ? params[activeIdx] : ""}',
                        style: TextStyle(fontSize: fs * 0.75, color: cs.lineNumber, fontFamily: font),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (sigHelp.documentation != null && sigHelp.documentation!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sigHelp.documentation!,
                        style: TextStyle(
                          fontSize: fs * 0.78,
                          color: cs.textNormal.withOpacity(0.7),
                          fontFamily: font,
                          height: 1.4,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 4,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
