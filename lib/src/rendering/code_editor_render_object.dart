// lib/src/rendering/code_editor_render_object.dart
import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/painting.dart';
import '../core/editor_controller.dart';
import '../core/char_position.dart';
import '../core/editor_props.dart';
import '../highlighting/span.dart';
import '../highlighting/text_style_token.dart';
import '../highlighting/code_block.dart';
import '../highlighting/line_style.dart';
import '../diagnostics/diagnostic_region.dart';
import '../theme/editor_theme.dart';
import '../theme/indent_program.dart';
import '../theme/color_scheme.dart';

/// Custom RenderBox for the code editor.
/// Receives two independent ViewportOffsets from TwoDimensionalScrollable.
class CodeEditorRenderObject extends RenderBox {
  QuillCodeController _controller;
  EditorTheme _theme;
  double _gutterWidth;
  ViewportOffset _verticalOffset;
  ViewportOffset _horizontalOffset;

  final Paint _bgPaint = Paint();
  final Paint _gutterPaint = Paint();
  final Paint _hlPaint = Paint();
  final Paint _selPaint = Paint();
  final Paint _cursorPaint = Paint()..strokeWidth = 2.0..style = PaintingStyle.stroke;
  final Paint _blockLinePaint = Paint()..strokeWidth = 1.0;
  final Paint _squigglePaint = Paint()..strokeWidth = 1.5..style = PaintingStyle.stroke;
  final Paint _searchPaint = Paint();
  final Paint _inlayBgPaint = Paint();

  double _cursorAlpha = 1.0;
  int _lastDocVersion = -1;

  CodeEditorRenderObject({
    required QuillCodeController controller,
    required EditorTheme theme,
    required double gutterWidth,
    required ViewportOffset verticalOffset,
    required ViewportOffset horizontalOffset,
  })  : _controller = controller,
        _theme = theme,
        _gutterWidth = gutterWidth,
        _verticalOffset = verticalOffset,
        _horizontalOffset = horizontalOffset {
    _verticalOffset.addListener(markNeedsPaint);
    _horizontalOffset.addListener(markNeedsPaint);
    _controller.addListener(_onChange);
  }

  set controller(QuillCodeController v) {
    if (_controller == v) return;
    _controller.removeListener(_onChange);
    _controller = v;
    _controller.addListener(_onChange);
    markNeedsLayout();
  }

  set theme(EditorTheme v) {
    if (_theme == v) return;
    _theme = v;
    markNeedsLayout();
  }

  set gutterWidth(double v) {
    if (_gutterWidth == v) return;
    _gutterWidth = v;
    markNeedsLayout();
  }

  set verticalOffset(ViewportOffset v) {
    if (_verticalOffset == v) return;
    _verticalOffset.removeListener(markNeedsPaint);
    _verticalOffset = v;
    _verticalOffset.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set horizontalOffset(ViewportOffset v) {
    if (_horizontalOffset == v) return;
    _horizontalOffset.removeListener(markNeedsPaint);
    _horizontalOffset = v;
    _horizontalOffset.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  void _onChange() {
    final v = _controller.content.documentVersion;
    if (v != _lastDocVersion) _lastDocVersion = v;
    markNeedsLayout();
  }

  void setCursorAlpha(double alpha) {
    if (_cursorAlpha == alpha) return;
    _cursorAlpha = alpha;
    markNeedsPaint();
  }

  double get _lh => _theme.lineHeightPx;
  double get _cw => _theme.fontSize * 0.601; // monospace char width approx

  @override
  void performLayout() {
    final lineCount = _controller.content.lineCount;
    final totalH = _lh * lineCount;
    final maxLineLen = _controller.content.maxLineLength.toDouble();
    final totalW = maxLineLen * _cw + _gutterWidth + 80.0;

    _verticalOffset.applyViewportDimension(constraints.maxHeight);
    _verticalOffset.applyContentDimensions(
        0, math.max(0, totalH - constraints.maxHeight));

    final vpW = math.max(0.0, constraints.maxWidth - _gutterWidth);
    _horizontalOffset.applyViewportDimension(vpW);
    _horizontalOffset.applyContentDimensions(
        0, math.max(0, totalW - constraints.maxWidth));

    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final cs = _theme.colorScheme;
    final scrollY = _verticalOffset.pixels;
    final scrollX = _horizontalOffset.pixels;
    final viewH = size.height;
    final viewW = size.width;
    final lineCount = _controller.content.lineCount;

    final firstLine = (scrollY / _lh).floor().clamp(0, lineCount - 1);
    final lastLine = ((scrollY + viewH) / _lh).ceil().clamp(0, lineCount - 1);

    // 1. Background
    _bgPaint.color = cs.background;
    canvas.drawRect(offset & size, _bgPaint);

    // 2. Gutter background
    _gutterPaint.color = cs.lineNumberBackground;
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, _gutterWidth, viewH), _gutterPaint);

    // 3. Current line highlight
    if (_controller.props.highlightCurrentLine) {
      final cl = _controller.cursor.line;
      if (cl >= firstLine && cl <= lastLine) {
        _hlPaint.color = cs.currentLineBackground;
        final y = offset.dy + cl * _lh - scrollY;
        canvas.drawRect(Rect.fromLTWH(offset.dx, y, viewW, _lh), _hlPaint);
      }
    }

    // 4. Selection
    _paintSelection(canvas, offset, cs, firstLine, lastLine, scrollY, scrollX);

    // 5. Search matches
    _paintSearchMatches(canvas, offset, cs, firstLine, lastLine, scrollY, scrollX);

    // 6. Block indent lines
    if (_controller.props.showBlockLines) {
      _paintBlockLines(canvas, offset, cs, firstLine, lastLine, scrollY, scrollX);
    }

    // 7. Text + line numbers
    for (int line = firstLine; line <= lastLine; line++) {
      _paintLine(canvas, offset, cs, line, scrollY, scrollX);
    }

    // 8. Diagnostics
    if (_controller.props.showDiagnosticIndicators) {
      _paintDiagnostics(canvas, offset, cs, firstLine, lastLine, scrollY, scrollX);
    }

    // 9. Inlay hints
    if (_controller.props.showInlayHints) {
      _paintInlayHints(canvas, offset, cs, firstLine, lastLine, scrollY, scrollX);
    }

    // 10. Cursor
    _paintCursor(canvas, offset, cs, scrollY, scrollX);

    // 11. Sticky scroll
    if (_controller.props.stickyScroll && _controller.stickyLines.isNotEmpty) {
      _paintStickyScroll(canvas, offset, cs, scrollX);
    }

    // 12. Gutter divider
    _blockLinePaint.color = cs.lineDivider;
    canvas.drawLine(
        Offset(offset.dx + _gutterWidth, offset.dy),
        Offset(offset.dx + _gutterWidth, offset.dy + viewH),
        _blockLinePaint);
  }

  void _paintSelection(Canvas canvas, Offset offset, EditorColorScheme cs,
      int fl, int ll, double sy, double sx) {
    if (!_controller.cursor.hasSelection) return;
    final sel = _controller.cursor.selection;
    _selPaint.color = cs.selectionColor;
    for (int line = math.max(fl, sel.start.line);
        line <= math.min(ll, sel.end.line);
        line++) {
      final lineLen = _controller.content.getLineLength(line);
      double x1 = offset.dx + _gutterWidth - sx;
      double x2 = offset.dx + _gutterWidth + lineLen * _cw - sx;
      if (line == sel.start.line) x1 = offset.dx + _gutterWidth + sel.start.column * _cw - sx;
      if (line == sel.end.line) x2 = offset.dx + _gutterWidth + sel.end.column * _cw - sx;
      final y = offset.dy + line * _lh - sy;
      if (x2 > x1) canvas.drawRect(Rect.fromLTWH(x1, y, x2 - x1, _lh), _selPaint);
    }
  }

  void _paintSearchMatches(Canvas canvas, Offset offset, EditorColorScheme cs,
      int fl, int ll, double sy, double sx) {
    final results = _controller.searcher.results;
    if (results.isEmpty) return;
    _searchPaint.color = cs.searchMatchBackground;
    for (final r in results) {
      if (r.start.line < fl || r.end.line > ll) continue;
      final y = offset.dy + r.start.line * _lh - sy;
      final x1 = offset.dx + _gutterWidth + r.start.column * _cw - sx;
      final x2 = offset.dx + _gutterWidth + r.end.column * _cw - sx;
      canvas.drawRect(Rect.fromLTWH(x1, y, math.max(4, x2 - x1), _lh), _searchPaint);
    }
  }

  // ── Block / indent guide lines — Program VM ────────────────────────────────

  void _paintBlockLines(Canvas canvas, Offset offset, EditorColorScheme cs,
      int fl, int ll, double sy, double sx) {
    final bt = _theme.blockLines;
    final cursorLine = _controller.cursor.line;

    CodeBlock? activeBlock;
    for (final b in _controller.styles.codeBlocks) {
      if (b.startLine <= cursorLine && b.endLine >= cursorLine) {
        if (activeBlock == null || b.indent > activeBlock.indent) activeBlock = b;
      }
    }

    for (final block in _controller.styles.codeBlocks) {
      if (block.endLine < fl || block.startLine > ll) continue;

      final x = offset.dx + _gutterWidth +
          block.indent * _controller.props.tabSize * _cw - sx;
      if (x <= offset.dx + _gutterWidth) continue;

      final isActive = identical(block, activeBlock);
      final prog     = isActive ? bt.resolvedActiveProgram : bt.resolvedProgram;
      if (prog.ops.isEmpty && !prog.hasEndCap) continue;

      // Colour
      Color lineColor;
      if (bt.colorMode == BlockLineColorMode.rainbow) {
        lineColor = bt.rainbowColors[block.indent % bt.rainbowColors.length];
      } else {
        lineColor = isActive ? bt.activeColor : bt.color;
      }
      if (!isActive) {
        lineColor = lineColor.withOpacity(
            (lineColor.opacity * bt.inactiveOpacity).clamp(0.0, 1.0));
      }

      final strokeWidth = isActive ? bt.resolvedActiveWidth : bt.width;
      final paint = Paint()
        ..color       = lineColor
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round;

      final y1 = offset.dy + block.startLine * _lh - sy;
      final y2 = offset.dy + (block.endLine + 1) * _lh - sy;

      _executeProgram(canvas, x, y1, y2, prog, paint);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Program VM executor
  // ══════════════════════════════════════════════════════════════════════════

  void _executeProgram(Canvas canvas, double x, double y1, double y2,
      IndentLineProgram prog, Paint paint) {
    // Reserve vertical space for the end-cap if needed.
    final capReserve = prog.hasEndCap ? _lh : 0.0;
    final drawEnd    = (y2 - capReserve).clamp(y1, y2);
    final available  = drawEnd - y1;

    if (prog.ops.isEmpty && prog.hasEndCap) {
      _executeEndCap(canvas, x, y2, prog.endCap, paint);
      return;
    }
    if (prog.ops.isEmpty) return;

    // Check if any op fills remaining space (single-pass).
    final hasFill = prog.ops.any((o) => switch (o) {
      OpLine(:final fill) when fill    => true,
      OpWave(:final fill) when fill    => true,
      OpZigzag(:final fill) when fill  => true,
      _ => false,
    });

    double y = y1;
    bool done = false;
    int guard = 0;

    while (!done && y < drawEnd - 0.5 && guard++ < 2000) {
      for (final op in prog.ops) {
        if (done || y >= drawEnd - 0.5) break;
        _executeOp(canvas, x, y, drawEnd, op, paint, (newY, isDone) {
          y = newY;
          if (isDone) done = true;
        });
      }
      if (hasFill) done = true;
    }

    if (prog.hasEndCap) {
      _executeEndCap(canvas, x, y2, prog.endCap, paint);
    }
  }

  void _executeOp(Canvas canvas, double x, double y, double yMax,
      IndentLineOp op, Paint paint,
      void Function(double newY, bool done) advance) {
    switch (op) {
      // ── line ─────────────────────────────────────────────────────────────
      case OpLine(:final fill, :final length):
        final len = fill ? yMax - y : math.min(length, yMax - y);
        if (len > 0) canvas.drawLine(Offset(x, y), Offset(x, y + len), paint);
        advance(y + len, fill);

      // ── gap ──────────────────────────────────────────────────────────────
      case OpGap(:final length):
        advance(y + math.min(length, yMax - y), false);

      // ── dot ──────────────────────────────────────────────────────────────
      case OpDot(:final radius, :final square, :final gap):
        final cy = y + radius;
        if (cy + radius <= yMax) {
          final dotPaint = Paint()
            ..color = paint.color
            ..style = PaintingStyle.fill;
          if (square) {
            canvas.drawRect(
              Rect.fromCenter(center: Offset(x, cy), width: radius*2, height: radius*2),
              dotPaint);
          } else {
            canvas.drawCircle(Offset(x, cy), radius, dotPaint);
          }
        }
        advance(y + radius * 2 + gap, false);

      // ── wave ─────────────────────────────────────────────────────────────
      case OpWave(:final fill, :final height, :final period, :final amplitude, :final phase):
        final h = fill ? yMax - y : math.min(height, yMax - y);
        if (h > 0) _drawWave(canvas, x, y, y + h, period, amplitude, phase, paint);
        advance(y + h, fill);

      // ── zigzag ───────────────────────────────────────────────────────────
      case OpZigzag(:final fill, :final height, :final period, :final amplitude):
        final h = fill ? yMax - y : math.min(height, yMax - y);
        if (h > 0) _drawZigzag(canvas, x, y, y + h, period, amplitude, paint);
        advance(y + h, fill);

      // ── arrow marker ─────────────────────────────────────────────────────
      case OpArrow(:final size, :final gap):
        _drawArrowMarker(canvas, x, y + size, size, paint);
        advance(y + size * 2 + gap, false);

      // ── cross marker ─────────────────────────────────────────────────────
      case OpCross(:final size, :final gap):
        _drawCrossMarker(canvas, x, y + size, size, paint);
        advance(y + size * 2 + gap, false);
    }
  }

  // ── Wave ───────────────────────────────────────────────────────────────────

  void _drawWave(Canvas canvas, double x, double y1, double y2,
      double period, double amplitude, double phase, Paint paint) {
    final path = Path();
    path.moveTo(x, y1);
    const steps = 32;
    for (int i = 1; i <= steps; i++) {
      final t   = i / steps;
      final yp  = y1 + (y2 - y1) * t;
      final xp  = x + math.sin(phase + t * 2 * math.pi * (y2 - y1) / period) * amplitude;
      path.lineTo(xp, yp);
    }
    canvas.drawPath(path, paint);
  }

  // ── Zigzag ─────────────────────────────────────────────────────────────────

  void _drawZigzag(Canvas canvas, double x, double y1, double y2,
      double period, double amplitude, Paint paint) {
    final path = Path();
    path.moveTo(x, y1);
    double y = y1;
    bool right = true;
    final half = period / 2;
    while (y < y2) {
      final yn  = math.min(y + half, y2);
      final xn  = x + (right ? amplitude : -amplitude);
      path.lineTo(xn, yn);
      y = yn; right = !right;
    }
    canvas.drawPath(path, paint);
  }

  // ── Arrow marker ───────────────────────────────────────────────────────────

  void _drawArrowMarker(Canvas canvas, double x, double cy, double size, Paint paint) {
    final path = Path()
      ..moveTo(x - size, cy - size)
      ..lineTo(x, cy)
      ..lineTo(x + size, cy - size);
    canvas.drawPath(path, paint);
  }

  // ── Cross marker ───────────────────────────────────────────────────────────

  void _drawCrossMarker(Canvas canvas, double x, double cy, double size, Paint paint) {
    canvas.drawLine(Offset(x - size, cy - size), Offset(x + size, cy + size), paint);
    canvas.drawLine(Offset(x + size, cy - size), Offset(x - size, cy + size), paint);
  }

  // ── End caps ───────────────────────────────────────────────────────────────

  void _executeEndCap(Canvas canvas, double x, double y2,
      IndentLineCap cap, Paint paint) {
    switch (cap.type) {
      case IndentCapType.none:
        return;

      // Curve to middle of `}` row + optional tick proportional to available space.
      case IndentCapType.curve:
        final r    = cap.radius.clamp(2.0, _lh * 0.4);
        final yMid = y2 + _lh * 0.5;
        final arcEndX = x + r;
        final spaceForTick = (y2 + _lh * 0.5 - 2.0) - arcEndX;
        final path = Path()
          ..moveTo(x, y2 - r)
          ..cubicTo(x, yMid, x + r * 0.5, yMid, arcEndX, yMid);
        if (spaceForTick > 0.5)
          path.lineTo(arcEndX + math.min(spaceForTick, cap.tick.toDouble()), yMid);
        canvas.drawPath(path, paint);

      // L-shape: horizontal tick(s) without rounding
      case IndentCapType.lShape:
        final drawTop = cap.where == 'top'    || cap.where == 'both';
        final drawBot = cap.where == 'bottom' || cap.where == 'both';
        if (drawTop) canvas.drawLine(Offset(x, y2 - _lh), Offset(x + cap.tick, y2 - _lh), paint);
        if (drawBot) canvas.drawLine(Offset(x, y2), Offset(x + cap.tick, y2), paint);

      // → arrowhead at bottom pointing right
      case IndentCapType.arrow:
        final yMid = y2 - _lh * 0.5;
        final s    = cap.size;
        final path = Path()
          ..moveTo(x, yMid - s)
          ..lineTo(x + s * 1.5, yMid)
          ..lineTo(x, yMid + s);
        canvas.drawPath(path, paint);

      case IndentCapType.openCurve:
        return; // openCurve is a startCap only — no-op as endCap
    }
  }

  void _paintLine(Canvas canvas, Offset offset, EditorColorScheme cs,
      int line, double sy, double sx) {
    final y = offset.dy + line * _lh - sy;
    final isCurrentLine = line == _controller.cursor.line;

    // ── Diff / LineStyle background ──────────────────────────────────────
    final ls = _controller.styles.lineStyles[line];
    if (ls != null) {
      final bg = ls.backgroundColor ?? ls.lineBackground;
      if (bg != null) {
        canvas.drawRect(
          Rect.fromLTWH(offset.dx + _gutterWidth, y, size.width - _gutterWidth, _lh),
          Paint()..color = bg,
        );
      }
      if (ls.gutterMarkerColor != null) {
        canvas.drawRect(
          Rect.fromLTWH(offset.dx + _gutterWidth - ls.gutterMarkerWidth, y,
              ls.gutterMarkerWidth, _lh),
          Paint()..color = ls.gutterMarkerColor!,
        );
      }
    }

    // Line number
    if (_controller.props.showLineNumbers) {
      final numStr = '${line + 1}';
      final numColor = isCurrentLine ? cs.lineNumberCurrent : cs.lineNumber;
      _drawText(canvas, numStr,
          Offset(offset.dx + _gutterWidth - 8, y + _lh / 2),
          color: numColor,
          fontSize: _theme.fontSize * 0.82,
          fontFamily: _theme.fontFamily,
          alignRight: true);
    }

    // Line text
    final lineText = _controller.content.getLineText(line);
    if (lineText.isEmpty) return;

    final textX = offset.dx + _gutterWidth - sx;
    final spans = _controller.styles.spansForLine(line);

    if (spans.isEmpty) {
      _drawText(canvas, lineText,
          Offset(textX, y + _lh / 2),
          color: cs.textNormal,
          fontSize: _theme.fontSize,
          fontFamily: _theme.fontFamily);
    } else {
      final textSpans = <TextSpan>[];
      final baseStyle = TextStyle(
        fontSize: _theme.fontSize,
        fontFamily: _theme.fontFamily,
        letterSpacing: _theme.letterSpacing,
      );
      // Prepend any text before the first span (uncaptured leading text).
      if (spans.first.column > 0) {
        final pre = lineText.substring(0, spans.first.column.clamp(0, lineText.length));
        if (pre.isNotEmpty) {
          textSpans.add(TextSpan(
              text: pre,
              style: baseStyle.copyWith(color: cs.textNormal)));
        }
      }
      for (int i = 0; i < spans.length; i++) {
        final span = spans[i];
        final nextCol = i + 1 < spans.length ? spans[i + 1].column : lineText.length;
        if (span.column >= lineText.length) break;
        final end = nextCol.clamp(span.column, lineText.length);
        if (end <= span.column) continue;
        final seg = lineText.substring(span.column, end);
        final colorKey = tokenToColorKey[span.type] ?? 'textNormal';
        final color = cs.colorForToken(colorKey);
        textSpans.add(TextSpan(
            text: seg,
            style: baseStyle.copyWith(
              color: color,
              fontWeight: span.style.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: span.style.italic ? FontStyle.italic : FontStyle.normal,
            )));
      }
      if (textSpans.isNotEmpty) {
        final tp = TextPainter(
            text: TextSpan(children: textSpans),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(textX, y + (_lh - tp.height) / 2));
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset center,
      {required Color color,
      required double fontSize,
      required String fontFamily,
      bool alignRight = false}) {
    final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: color, fontSize: fontSize, fontFamily: fontFamily, height: 1.0)),
        textDirection: TextDirection.ltr)
      ..layout();
    final dx = alignRight ? center.dx - tp.width : center.dx;
    tp.paint(canvas, Offset(dx, center.dy - tp.height / 2));
  }

  void _paintDiagnostics(Canvas canvas, Offset offset, EditorColorScheme cs,
      int fl, int ll, double sy, double sx) {
    for (final diag in _controller.diagnostics.all) {
      final line = diag.range.start.line;
      if (line < fl || line > ll) continue;
      final color = switch (diag.severity) {
        DiagnosticSeverity.error => cs.problemError,
        DiagnosticSeverity.warning => cs.problemWarning,
        _ => cs.problemTypo,
      };
      final y = offset.dy + line * _lh - sy + _lh * 0.84;
      final x1 = offset.dx + _gutterWidth + diag.range.start.column * _cw - sx;
      final x2 = offset.dx + _gutterWidth + diag.range.end.column * _cw - sx;
      if (_controller.props.diagnosticIndicatorStyle == DiagnosticIndicatorStyle.squiggle) {
        _drawSquiggle(canvas, x1, x2, y, color);
      } else {
        _squigglePaint.color = color;
        canvas.drawLine(Offset(x1, y), Offset(x2, y), _squigglePaint);
      }
    }
  }

  void _drawSquiggle(Canvas c, double x1, double x2, double y, Color color) {
    final path = Path();
    const wl = 6.0, amp = 2.0;
    bool up = true;
    double x = x1;
    path.moveTo(x, y);
    while (x < x2) {
      final nx = math.min(x + wl / 2, x2);
      path.quadraticBezierTo((x + nx) / 2, y + (up ? -amp : amp), nx, y);
      up = !up;
      x = nx;
    }
    c.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  void _paintInlayHints(Canvas canvas, Offset offset, EditorColorScheme cs,
      int fl, int ll, double sy, double sx) {
    for (final hint in _controller.styles.inlayHints) {
      final line = hint.position.line;
      if (line < fl || line > ll) continue;
      final x = offset.dx + _gutterWidth + hint.position.column * _cw - sx;
      final y = offset.dy + line * _lh - sy;
      if (hint.label != null) {
        final tp = TextPainter(
            text: TextSpan(
                text: hint.label,
                style: TextStyle(
                    color: cs.inlayHintForeground,
                    fontSize: _theme.fontSize * 0.8,
                    fontFamily: _theme.fontFamily)),
            textDirection: TextDirection.ltr)
          ..layout();
        _inlayBgPaint.color = cs.inlayHintBackground;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x - 2, y + 2, tp.width + 4, _lh - 4),
                const Radius.circular(3)),
            _inlayBgPaint);
        tp.paint(canvas, Offset(x, y + (_lh - tp.height) / 2));
      } else if (hint.color != null) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y + _lh * 0.2, _lh * 0.6, _lh * 0.6),
                const Radius.circular(2)),
            Paint()..color = hint.color!);
      }
    }
  }

  void _paintCursor(Canvas canvas, Offset offset, EditorColorScheme cs,
      double sy, double sx) {
    _cursorPaint.color = cs.cursor.withOpacity(_cursorAlpha.clamp(0.0, 1.0));
    final pos = _controller.cursor.position;
    final x = offset.dx + _gutterWidth + pos.column * _cw - sx;
    final y = offset.dy + pos.line * _lh - sy;
    canvas.drawLine(Offset(x, y + 2), Offset(x, y + _lh - 2), _cursorPaint);
  }

  void _paintStickyScroll(Canvas canvas, Offset offset, EditorColorScheme cs, double sx) {
    final lines = _controller.stickyLines;
    _bgPaint.color = cs.background.withOpacity(0.96);
    canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, size.width, lines.length * _lh), _bgPaint);
    for (int i = 0; i < lines.length; i++) {
      _paintLine(canvas, Offset(offset.dx, offset.dy + i * _lh - lines[i] * _lh),
          cs, lines[i], 0, sx);
    }
    _blockLinePaint.color = cs.stickyScrollDivider;
    canvas.drawLine(
        Offset(offset.dx, offset.dy + lines.length * _lh),
        Offset(offset.dx + size.width, offset.dy + lines.length * _lh),
        _blockLinePaint);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  CharPosition localPositionToChar(Offset local) {
    final sy = _verticalOffset.pixels;
    final sx = _horizontalOffset.pixels;
    final lineCount = _controller.content.lineCount;
    final line = ((local.dy + sy) / _lh).floor().clamp(0, lineCount - 1);
    final col = ((local.dx - _gutterWidth + sx) / _cw)
        .round()
        .clamp(0, _controller.content.getLineLength(line));
    return CharPosition(line, col);
  }

  Offset charToLocalPosition(CharPosition pos) {
    final sy = _verticalOffset.pixels;
    final sx = _horizontalOffset.pixels;
    return Offset(
        _gutterWidth + pos.column * _cw - sx,
        pos.line * _lh + _lh / 2 - sy);
  }

  @override
  void dispose() {
    _verticalOffset.removeListener(markNeedsPaint);
    _horizontalOffset.removeListener(markNeedsPaint);
    _controller.removeListener(_onChange);
    super.dispose();
  }
}