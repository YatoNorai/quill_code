
// lib/src/widgets/minimap_widget.dart
//
// Minimap VSCode-style
//
// ARQUITETURA:
//  • LayoutBuilder fornece o tamanho real desde o primeiro frame.
//  • Toda a lógica (cálculo de scrollRatio, rebuild de picture, repaint)
//    vive DENTRO do AnimatedBuilder — nunca há estado stale.
//  • _picture é reconstruída dentro do mesmo builder que a exibe,
//    portanto nunca pode ser null quando o painter a usa.
//  • O AnimatedBuilder escuta tanto _repaintN (scroll/content) quanto
//    _hlAnim (tap highlight) — um único ponto de rebuild.
//  • Paints são campos do State (não do Painter) para sobreviver entre
//    rebuilds sem realocar.

import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../theme/editor_theme.dart';
import '../theme/color_scheme.dart';
import '../highlighting/span.dart';

const double _kLineH  = 2.0;  // altura de cada linha no minimap (px)
const int    _kBuffer = 50;   // linhas extra acima/abaixo da janela visível

class MinimapWidget extends StatefulWidget {
  final QuillCodeController controller;
  final EditorTheme         theme;
  final ScrollController    vCtrl;
  final double              viewportH;
  final double              lineHeight;

  const MinimapWidget({
    super.key,
    required this.controller,
    required this.theme,
    required this.vCtrl,
    required this.viewportH,
    required this.lineHeight,
  });

  @override
  State<MinimapWidget> createState() => _MinimapState();
}

class _MinimapState extends State<MinimapWidget>
    with SingleTickerProviderStateMixin {

  // ── Picture cache ─────────────────────────────────────────────────────────
  ui.Picture? _picture;
  double _pictureWidth   = 0;
  double _pictureHeight  = 0;
  int    _cacheVersion   = -1;
  // Line range covered by the current picture.  The picture only needs
  // rebuilding when the visible range leaves this window — NOT on every
  // scroll tick.  Storing both endpoints lets us skip the rebuild on fast
  // flinging when the buffered over-scan still covers the viewport.
  int    _cacheFirstLine = -1;
  int    _cacheLastLine  = -1;

  // ── Token color cache (rebuilt only when theme changes) ──────────────────
  EditorColorScheme? _cachedCs;
  Color _cTextNormal = const Color(0xFF888888);
  final Map<TokenType, Color> _tokenColors = {};

  // ── Cached Paint objects (reused every frame, owned by State) ─────────────
  final _pBg   = Paint();
  final _pVp1  = Paint();
  final _pVp2  = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
  final _pHl1  = Paint();
  final _pHl2  = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0;
  final _pAcc  = Paint()..strokeWidth = 1.0;
  final _pLine = Paint()..strokeWidth = _kLineH * 0.7;

  // ── Tap highlight state ───────────────────────────────────────────────────
  late AnimationController _hlAnim;
  double _hlTop = 0, _hlHeight = 0;
  bool   _hlActive = false;

  // ── Notifier that drives the AnimatedBuilder ──────────────────────────────
  final _repaintN = ValueNotifier<int>(0);

  // ── Scroll helpers ────────────────────────────────────────────────────────
  double get _scrollRatio {
    if (!widget.vCtrl.hasClients) return 0.0;
    try {
      final p = widget.vCtrl.position;
      return p.maxScrollExtent > 0
          ? (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0) : 0.0;
    } catch (_) { return 0.0; }
  }

  double _vpRatio(int lineCount) {
    final totalH = lineCount * _kLineH;
    return totalH > 0 ? (widget.viewportH / totalH).clamp(0.0, 1.0) : 1.0;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _hlAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    widget.controller.addListener(_onContentChanged);
    widget.vCtrl.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(MinimapWidget old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onContentChanged);
      widget.controller.addListener(_onContentChanged);
      _invalidate();
    }
    if (old.vCtrl != widget.vCtrl) {
      old.vCtrl.removeListener(_onScrollChanged);
      widget.vCtrl.addListener(_onScrollChanged);
      _invalidate();
    }
    if (old.theme != widget.theme) _invalidate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onContentChanged);
    widget.vCtrl.removeListener(_onScrollChanged);
    _hlAnim.dispose();
    _picture?.dispose();
    _repaintN.dispose();
    super.dispose();
  }

  /// Content changed → always rebuild the picture (new tokens / new lines).
  void _onContentChanged() {
    if (!mounted) return;
    _picture?.dispose();
    _picture        = null;
    _cacheFirstLine = -1;
    _cacheLastLine  = -1;
    _repaintN.value++;
  }

  /// Scroll changed → only request a repaint; the picture is reused as long as
  /// the visible line range stays inside the already-buffered region.
  /// _ensurePicture will decide whether a rebuild is necessary.
  void _onScrollChanged() {
    if (!mounted) return;
    _repaintN.value++;
  }

  void _invalidate() => _onContentChanged();

  // ── Token color helpers ───────────────────────────────────────────────────
  void _rebuildTokenColors(EditorColorScheme cs) {
    if (identical(_cachedCs, cs)) return;
    _cachedCs    = cs;
    _cTextNormal = cs.textNormal.withOpacity(0.5);
    _tokenColors.clear();
    _tokenColors[TokenType.keyword]     = cs.keyword.withOpacity(0.65);
    _tokenColors[TokenType.comment]     = cs.comment.withOpacity(0.65);
    _tokenColors[TokenType.string]      = cs.string.withOpacity(0.65);
    _tokenColors[TokenType.number]      = cs.number.withOpacity(0.65);
    _tokenColors[TokenType.function_]   = cs.function_.withOpacity(0.65);
    _tokenColors[TokenType.type_]       = cs.type_.withOpacity(0.65);
    _tokenColors[TokenType.annotation]  = cs.annotation.withOpacity(0.65);
  }

  Color _miniTokenColor(TokenType t) => _tokenColors[t] ?? _cTextNormal;

  // ── Picture builder ───────────────────────────────────────────────────────
  // Chamado DENTRO do AnimatedBuilder com dados sempre frescos.
  // Retorna a picture existente se o cache ainda é válido.
  ui.Picture _ensurePicture(Size size, double scrollRatio) {
    final ver       = widget.controller.content.documentVersion;
    final lineCount = widget.controller.content.lineCount;

    // Compute which lines are currently visible (+ 1-line tolerance).
    final totalMiniH = lineCount * _kLineH;
    final miniOff    = totalMiniH > size.height
        ? scrollRatio * (totalMiniH - size.height) : 0.0;
    final visFirst = math.max(0, (miniOff / _kLineH).floor() - 1);
    final visLast  = math.min(lineCount - 1,
        ((miniOff + size.height) / _kLineH).ceil() + 1);

    // Reuse the cached picture if it still covers the visible range.
    if (_picture != null
        && _cacheVersion   == ver
        && _cacheFirstLine <= visFirst
        && _cacheLastLine  >= visLast
        && (_pictureWidth  - size.width ).abs() <= 0.5
        && (_pictureHeight - size.height).abs() <= 0.5) {
      return _picture!;
    }

    // Build with 2× over-scan so the picture lasts longer before needing
    // a rebuild (important for large files where each build touches the rope).
    final buildFirst = math.max(0,            visFirst - _kBuffer * 2);
    final buildLast  = math.min(lineCount - 1, visLast + _kBuffer * 2);

    _picture?.dispose();
    _picture        = _buildPicture(size, buildFirst, buildLast);
    _cacheVersion   = ver;
    _cacheFirstLine = buildFirst;
    _cacheLastLine  = buildLast;
    _pictureWidth   = size.width;
    _pictureHeight  = size.height;
    return _picture!;
  }

  ui.Picture _buildPicture(Size size, int firstLine, int lastLine) {
    final ctrl = widget.controller;
    final cs   = widget.theme.colorScheme;
    _rebuildTokenColors(cs);

    final w   = size.width;
    final rec = ui.PictureRecorder();
    final c   = Canvas(rec);

    for (int line = firstLine; line <= lastLine; line++) {
      final text = ctrl.content.getLineText(line);
      if (text.isEmpty) continue;
      final y     = line * _kLineH + _kLineH / 2;
      final spans = ctrl.styles.spansForLine(line);

      if (spans.isEmpty) {
        _pLine.color = _cTextNormal;
        final x2 = math.min(text.length.toDouble(), w - 2);
        c.drawLine(Offset(2, y), Offset(2 + x2, y), _pLine);
      } else {
        final tLen = text.length;
        for (int si = 0; si < spans.length; si++) {
          final sp = spans[si];
          // Guard: spans are async — text may have changed before highlights
          // catch up. A stale span can reference a column beyond text.length,
          // making clamp(0, text.length - sp.column) throw ArgumentError.
          if (sp.column >= tLen) break;
          final nextC      = si + 1 < spans.length ? spans[si + 1].column : tLen;
          final effectiveEnd = nextC.clamp(sp.column, tLen);
          final segLen       = effectiveEnd - sp.column;
          if (segLen <= 0) continue;
          final x1 = 2.0 + sp.column;
          final x2 = math.min(x1 + segLen.toDouble(), w - 1);
          if (x2 <= x1) continue;
          _pLine.color = _miniTokenColor(sp.type);
          c.drawLine(Offset(x1, y), Offset(x2, y), _pLine);
        }
      }
    }
    return rec.endRecording();
  }

  // ── Tap / drag ─────────────────────────────────────────────────────────────
  void _onTapOrDrag(Offset local, Size size) {
    if (!widget.vCtrl.hasClients) return;
    final lineCount = widget.controller.content.lineCount;
    if (lineCount == 0) return;

    final totalMiniH = lineCount * _kLineH;
    final miniOff    = totalMiniH > size.height
        ? _scrollRatio * (totalMiniH - size.height) : 0.0;

    final tappedLine =
        ((local.dy + miniOff) / _kLineH).clamp(0.0, lineCount - 1.0);

    final targetScrollY =
        (tappedLine * widget.lineHeight - widget.viewportH / 2)
            .clamp(0.0, widget.vCtrl.position.maxScrollExtent);

    widget.vCtrl.animateTo(
      targetScrollY,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );

    final vr   = _vpRatio(lineCount).clamp(0.0, 1.0);
    final indH = (vr * size.height).clamp(12.0, size.height);
    final newSr = widget.vCtrl.position.maxScrollExtent > 0
        ? targetScrollY / widget.vCtrl.position.maxScrollExtent : 0.0;
    final indT =
        (newSr * (size.height - indH)).clamp(0.0, size.height - indH);

    _hlAnim..stop()..value = 1.0;
    setState(() { _hlActive = true; _hlTop = indT; _hlHeight = indH; });
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _hlAnim.reverse()
          .then((_) { if (mounted) setState(() => _hlActive = false); });
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:   (d) => _onTapOrDrag(d.localPosition, size),
        onPanUpdate: (d) => _onTapOrDrag(d.localPosition, size),
        child: AnimatedBuilder(
          // Quando _repaintN ou _hlAnim disparam, este builder re-executa:
          // recalcula sr, chama _ensurePicture com dados frescos, e passa
          // a picture válida para o painter. Nunca há picture=null no painter.
          animation: Listenable.merge([_repaintN, _hlAnim]),
          builder: (_, __) {
            final sr        = _scrollRatio;
            final lineCount = widget.controller.content.lineCount;
            final vr        = _vpRatio(lineCount);

            final pic = lineCount > 0
                ? _ensurePicture(size, sr)
                : null;

            return CustomPaint(
              size: size,
              painter: _MinimapPainter(
                picture:       pic,
                pictureWidth:  _pictureWidth  > 0 ? _pictureWidth  : size.width,
                pictureHeight: _pictureHeight > 0 ? _pictureHeight : size.height,
                lineCount:     lineCount,
                theme:         widget.theme,
                lineH:         _kLineH,
                viewportH:     widget.viewportH,
                scrollRatio:   sr,
                vpRatio:       vr.clamp(0.0, 1.0),
                hlActive:      _hlActive,
                hlTop:         _hlTop,
                hlHeight:      _hlHeight,
                hlOpacity:     _hlAnim.value,
                pBg:  _pBg,
                pVp1: _pVp1,
                pVp2: _pVp2,
                pHl1: _pHl1,
                pHl2: _pHl2,
                pAcc: _pAcc,
              ),
            );
          },
        ),
      );
    });
  }
}

// ── Painter ────────────────────────────────────────────────────────────────────
// Stateless — recebe tudo do State. Não aloca Paint, não tem cache próprio.

class _MinimapPainter extends CustomPainter {
  final ui.Picture? picture;
  final double pictureWidth, pictureHeight;
  final double lineH, viewportH, scrollRatio, vpRatio;
  final double hlTop, hlHeight, hlOpacity;
  final int    lineCount;
  final EditorTheme theme;
  final bool   hlActive;
  final Paint  pBg, pVp1, pVp2, pHl1, pHl2, pAcc;

  const _MinimapPainter({
    required this.picture,
    required this.pictureWidth,
    required this.pictureHeight,
    required this.lineCount,
    required this.theme,
    required this.lineH,
    required this.viewportH,
    required this.scrollRatio,
    required this.vpRatio,
    required this.hlActive,
    required this.hlTop,
    required this.hlHeight,
    required this.hlOpacity,
    required this.pBg,
    required this.pVp1,
    required this.pVp2,
    required this.pHl1,
    required this.pHl2,
    required this.pAcc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cs = theme.colorScheme;

    pBg.color = cs.lineNumberBackground;
    canvas.drawRect(Offset.zero & size, pBg);

    if (lineCount == 0 || picture == null) return;

    final totalMiniH = lineCount * lineH;
    final miniOff    = totalMiniH > size.height
        ? scrollRatio * (totalMiniH - size.height) : 0.0;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, -miniOff);
    if (pictureWidth > 0 && (pictureWidth - size.width).abs() > 0.5) {
      canvas.scale(size.width / pictureWidth, 1.0);
    }
    canvas.drawPicture(picture!);
    canvas.restore();

    // Indicador de viewport
    final indH   = (vpRatio * size.height).clamp(12.0, size.height);
    final indTop = (scrollRatio * (size.height - indH))
        .clamp(0.0, size.height - indH);
    pVp1.color = cs.lineNumberCurrent.withOpacity(0.12);
    canvas.drawRect(Rect.fromLTWH(0, indTop, size.width, indH), pVp1);
    pVp2.color = cs.lineNumberCurrent.withOpacity(0.40);
    canvas.drawRect(Rect.fromLTWH(0, indTop, size.width, indH), pVp2);

    // Tap highlight
    if (hlActive && hlOpacity > 0.01) {
      pHl1.color = cs.lineNumberCurrent.withOpacity(0.48 * hlOpacity);
      canvas.drawRect(Rect.fromLTWH(0, hlTop, size.width, hlHeight), pHl1);
      pHl2.color = cs.lineNumberCurrent.withOpacity(0.95 * hlOpacity);
      canvas.drawRect(
          Rect.fromLTWH(0.5, hlTop + 0.5, size.width - 1, hlHeight - 1), pHl2);
      pAcc.color = Colors.white.withOpacity(0.30 * hlOpacity);
      canvas.drawLine(
          Offset(2, hlTop + 2),
          Offset(size.width - 2, hlTop + 2), pAcc);
      canvas.drawLine(
          Offset(2, hlTop + hlHeight - 2),
          Offset(size.width - 2, hlTop + hlHeight - 2), pAcc);
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter o) =>
      o.picture     != picture     ||
      o.scrollRatio != scrollRatio ||
      o.vpRatio     != vpRatio     ||
      o.hlActive    != hlActive    ||
      o.hlTop       != hlTop       ||
      o.hlHeight    != hlHeight    ||
      o.hlOpacity   != hlOpacity;
}
