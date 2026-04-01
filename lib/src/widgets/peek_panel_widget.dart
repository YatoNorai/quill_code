// lib/src/widgets/peek_panel_widget.dart
// ─────────────────────────────────────────────────────────────────────────────
// Inline Peek Definition panel — shows source code at the definition location
// without navigating away. Dismissible via Escape or tap outside.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';
import 'package:flutter/material.dart';
import '../lsp/lsp_bridge.dart';
import '../theme/editor_theme.dart';
import '../theme/color_scheme.dart';

class PeekPanelWidget extends StatefulWidget {
  final EditorTheme theme;
  final LspLocation location;
  final double viewportWidth;
  final double viewportHeight;
  final Offset anchorLocal; // local offset of cursor bottom edge
  final VoidCallback onDismiss;
  final void Function(LspLocation loc)? onNavigate;

  const PeekPanelWidget({
    super.key,
    required this.theme,
    required this.location,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.anchorLocal,
    required this.onDismiss,
    this.onNavigate,
  });

  @override
  State<PeekPanelWidget> createState() => _PeekPanelState();
}

class _PeekPanelState extends State<PeekPanelWidget>
    with SingleTickerProviderStateMixin {
  String _snippet = '';
  bool   _loading = true;
  int    _highlightLine = 0; // line index within snippet to highlight

  late AnimationController _anim;
  late Animation<double>   _fade;

  static const double _panelW = 520.0;
  static const double _panelH = 210.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
    _loadSnippet();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadSnippet() async {
    final uri  = widget.location.uri;
    final path = uri.startsWith('file://') ? uri.substring(7) : uri;
    String snippet;
    int highlight = 0;
    try {
      final file = File(path);
      if (await file.exists()) {
        final lines   = await file.readAsLines();
        final defLine = widget.location.range.start.line;
        final from    = (defLine - 10).clamp(0, lines.length - 1);
        final to      = (defLine + 15).clamp(0, lines.length);
        snippet       = lines.sublist(from, to).join('\n');
        highlight     = defLine - from;
      } else {
        snippet   = '// File not found: $path';
        highlight = 0;
      }
    } catch (e) {
      snippet   = '// Could not load: $e';
      highlight = 0;
    }
    if (mounted) {
      setState(() {
        _snippet       = snippet;
        _highlightLine = highlight;
        _loading       = false;
      });
    }
  }

  String _uriLabel(String uri) {
    final clean = uri.replaceFirst('file://', '');
    final parts = clean.replaceAll('\\', '/').split('/');
    return parts.length > 2
        ? '.../${parts.sublist(parts.length - 2).join('/')}'
        : clean;
  }

  @override
  Widget build(BuildContext context) {
    final cs  = widget.theme.colorScheme;
    const pad = 4.0;

    // Smart vertical positioning — prefer below cursor, fallback above.
    final spaceBelow = widget.viewportHeight - widget.anchorLocal.dy - pad;
    final spaceAbove = widget.anchorLocal.dy - pad;
    double top;
    if (spaceBelow >= _panelH) {
      top = widget.anchorLocal.dy + pad;
    } else if (spaceAbove >= _panelH) {
      top = widget.anchorLocal.dy - _panelH - pad;
    } else if (spaceBelow >= spaceAbove) {
      top = widget.anchorLocal.dy + pad;
    } else {
      top = (widget.anchorLocal.dy - _panelH - pad).clamp(pad, double.maxFinite);
    }
    top = top.clamp(pad, (widget.viewportHeight - _panelH - pad).clamp(pad, double.maxFinite));

    // Horizontal: keep within viewport.
    final maxLeft = (widget.viewportWidth - _panelW - pad).clamp(pad, double.maxFinite);
    final left    = widget.anchorLocal.dx.clamp(pad, maxLeft);

    return Positioned(
      left: left, top: top,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(6),
          color: cs.completionBackground,
          child: Container(
            width: _panelW,
            height: _panelH,
            decoration: BoxDecoration(
              border: Border.all(color: cs.lineDivider, width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: cs.lineNumberBackground,
                      border: Border(
                        bottom: BorderSide(color: cs.lineDivider, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 13, color: cs.lineNumber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _uriLabel(widget.location.uri),
                            style: TextStyle(
                              fontSize: widget.theme.fontSize * 0.75,
                              color: cs.lineNumber,
                              fontFamily: widget.theme.fontFamily,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // "Go to definition" button
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => widget.onNavigate?.call(widget.location),
                          child: Text(
                            'Go to definition',
                            style: TextStyle(
                              fontSize: widget.theme.fontSize * 0.72,
                              color: cs.lineNumber,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Close button
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: Icon(Icons.close, size: 14, color: cs.lineNumber),
                        ),
                      ],
                    ),
                  ),
                  // ── Code snippet ─────────────────────────────────────────
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : SingleChildScrollView(
                            child: _buildSnippet(cs),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSnippet(EditorColorScheme cs) {
    final lines = _snippet.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines.length, (i) {
        final isHighlight = i == _highlightLine;
        return Container(
          width: double.infinity,
          color: isHighlight ? cs.currentLineBackground : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          child: Text(
            lines[i],
            style: TextStyle(
              fontSize: widget.theme.fontSize * 0.88,
              fontFamily: widget.theme.fontFamily,
              color: cs.textNormal,
              height: 1.5,
            ),
          ),
        );
      }),
    );
  }
}
