// lib/src/actions/lightbulb_widget.dart
// Lightbulb icon + floating quick-action popup (like VSCode/Android Studio).
// The popup appears ABOVE or BELOW the current line, never as a bottom sheet.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'code_action.dart';
import 'code_action_provider.dart';
import '../core/editor_controller.dart';
import '../text/text_range.dart';
import '../theme/editor_theme.dart';

class LightbulbWidget extends StatefulWidget {
  final QuillCodeController controller;
  final EditorTheme theme;
  final Offset cursorLocal;
  final double gutterWidth;
  final double lineHeight;
  final double viewportWidth;
  final double viewportHeight;
  final Future<void> Function(CodeAction action)? onAction;

  const LightbulbWidget({
    super.key,
    required this.controller,
    required this.theme,
    required this.cursorLocal,
    required this.gutterWidth,
    required this.lineHeight,
    required this.viewportWidth,
    required this.viewportHeight,
    this.onAction,
  });

  @override
  State<LightbulbWidget> createState() => _LightbulbState();
}

class _LightbulbState extends State<LightbulbWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;
  bool _menuOpen = false;
  List<CodeAction> _actions = [];
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    _anim.forward();
    _loadActions();
  }

  @override
  void didUpdateWidget(LightbulbWidget old) {
    super.didUpdateWidget(old);
    if (old.cursorLocal != widget.cursorLocal) _loadActions();
  }

  @override
  void dispose() {
    // Remove overlay directly without calling setState — widget is being torn down.
    _overlay?.remove();
    _overlay = null;
    _anim.dispose();
    super.dispose();
  }

  void _loadActions() {
    final ctrl = widget.controller;
    final pos   = ctrl.cursor.position;
    // Local (static) actions — synchronous, always available
    final local = CodeActionProvider.actionsAt(
      content:        ctrl.content,
      position:       pos,
      languageName:   ctrl.language.name,
      hasSelection:   ctrl.cursor.hasSelection,
      selectionRange: ctrl.cursor.hasSelection ? ctrl.cursor.selection : null,
    );
    if (mounted) setState(() => _actions = local);
    // LSP actions — async, merged in when they arrive
    if (ctrl.lsp != null) {
      final range = ctrl.cursor.hasSelection
          ? ctrl.cursor.selection
          : EditorRange(pos, pos);
      ctrl.lspActionsAt(range).then((lspActions) {
        if (!mounted) return;
        // De-duplicate by title; LSP actions go first
        final seen = <String>{};
        final merged = <CodeAction>[];
        for (final a in [...lspActions, ...local]) {
          if (seen.add(a.title)) merged.add(a);
        }
        setState(() => _actions = merged);
      });
    }
  }

  void _onTap() {
    if (_actions.isEmpty) return;
    if (_menuOpen) { _removeOverlay(); return; }
    _showFloatingMenu();
  }

  void _showFloatingMenu() {
    _removeOverlay();
    final RenderBox? rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;

    // The lightbulb icon renders at (gutterWidth+4, cursorLocal.dy - lineHeight)
    // in local viewport coords. Its global position:
    //   lightbulbTopGlobal.dy = cursorTopGlobal.dy - lineHeight
    // So cursor TOP global = lightbulbTopGlobal.dy + lineHeight
    final lbGlobal = rb.localToGlobal(Offset.zero);
    // Anchor = global position of the cursor LINE's top edge
    final anchorGlobal = Offset(lbGlobal.dx, lbGlobal.dy + widget.lineHeight);

    _menuOpen = true;
    _overlay = OverlayEntry(builder: (ctx) {
      return _FloatingActionMenu(
        actions:        _actions,
        theme:          widget.theme,
        // anchorGlobal = cursor-line top; menu goes above or below the cursor line
        anchorGlobal:   anchorGlobal,
        lineHeight:     widget.lineHeight,
        onAction:       (a) async {
          _removeOverlay();
          await widget.onAction?.call(a);
        },
        onDismiss:      _removeOverlay,
      );
    });
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    if (_overlay == null) return;
    _overlay!.remove();
    _overlay = null;
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_actions.isEmpty) return const SizedBox.shrink();
    final cs   = widget.theme.colorScheme;
    final top  = widget.cursorLocal.dy - widget.lineHeight;

    return Positioned(
      left: widget.gutterWidth + 4,
      top:  top.clamp(0.0, math.max(0, widget.viewportHeight - 28)),
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap:    _onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color:  _menuOpen
                  ? cs.completionItemSelected
                  : cs.completionBackground.withOpacity(0.95),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _menuOpen
                    ? cs.type_.withOpacity(0.6)
                    : cs.hoverBorder.withOpacity(0.4),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2),
                    blurRadius: 4, offset: const Offset(0, 2))
              ],
            ),
            child: const Center(
              child: Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFFFFD700)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Floating popup menu ───────────────────────────────────────────────────────

class _FloatingActionMenu extends StatefulWidget {
  final List<CodeAction> actions;
  final EditorTheme theme;
  /// Global position of the cursor line's TOP edge.
  /// Menu appears below (cursorTop + lineHeight) or above (cursorTop) the cursor.
  final Offset anchorGlobal;
  final double lineHeight;
  final Future<void> Function(CodeAction) onAction;
  final VoidCallback onDismiss;

  const _FloatingActionMenu({
    required this.actions,
    required this.theme,
    required this.anchorGlobal,
    required this.lineHeight,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  State<_FloatingActionMenu> createState() => _FloatingActionMenuState();
}

class _FloatingActionMenuState extends State<_FloatingActionMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const double _itemH   = 40.0;
  static const double _headerH = 28.0;
  static const double _popupW  = 280.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _slide = Tween<Offset>(
        begin: const Offset(0, -0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  Map<String, List<CodeAction>> get _groups {
    final m = <String, List<CodeAction>>{};
    for (final a in widget.actions) {
      (m[_groupOf(a.kind)] ??= []).add(a);
    }
    return m;
  }

  String _groupOf(CodeActionKind k) {
    switch (k) {
      case CodeActionKind.quickFix:    return 'Correções';
      case CodeActionKind.refactor:    return 'Refatoração';
      case CodeActionKind.snippet:     return 'Snippets';
      case CodeActionKind.surroundWith:return 'Envolver com';
      case CodeActionKind.navigate:    return 'Navegação';
      default:                         return 'Ações';
    }
  }

  double _menuHeight() {
    final groups = _groups;
    double h = 0;
    for (final e in groups.entries) {
      if (groups.length > 1) h += _headerH;
      h += e.value.length * _itemH;
    }
    return h.clamp(48.0, 160.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs  = widget.theme.colorScheme;
    final mh  = _menuHeight();
    final mq  = MediaQuery.of(context);
    final sw  = mq.size.width;
    // Subtract virtual keyboard so the popup is never covered.
    final kbH     = mq.viewInsets.bottom;
    final usableH = mq.size.height - kbH;
    const pad     = 8.0;

    // ── Vertical: never overlap the cursor line ───────────────────────────
    // anchorGlobal = cursor top (global Y).
    // cursor bottom = anchorGlobal.dy + lineHeight.
    final cursorTop    = widget.anchorGlobal.dy;
    final cursorBottom = cursorTop + widget.lineHeight;
    final spaceBelow   = usableH - cursorBottom - pad;
    final spaceAbove   = cursorTop - pad;

    // ALWAYS prefer above the cursor line; only fall back to below when
    // there is more room there. Never floor-clamp to 0 — that pushes the
    // popup back onto the cursor line.
    double top;
    if (spaceAbove >= mh) {
      top = cursorTop - mh - pad;                    // fits above (preferred)
    } else if (spaceBelow >= mh) {
      top = cursorBottom + pad;                      // fits below (fallback)
    } else if (spaceAbove >= spaceBelow) {
      top = cursorTop - mh - pad;                    // more room above — may clip off screen top
    } else {
      top = cursorBottom + pad;                      // more room below — may clip off screen bottom
    }

    // ── Horizontal: clamp so popup never overflows right ─────────────────
    final left = widget.anchorGlobal.dx
        .clamp(pad, math.max(pad, sw - _popupW - pad)).toDouble();

    return Stack(children: [
      // Dismiss tap area
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) => widget.onDismiss(),
        ),
      ),
      // Menu
      Positioned(
        left: left, top: top, width: _popupW, height: mh,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: Container(
                height: mh,
                decoration: BoxDecoration(
                  color:  cs.completionBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.completionBorder, width: 0.7),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3),
                        blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: _buildItems(cs),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  List<Widget> _buildItems(dynamic cs) {
    final groups = _groups;
    final items  = <Widget>[];
    bool first = true;
    for (final entry in groups.entries) {
      if (!first) items.add(Divider(height: 1, thickness: 0.5,
          color: cs.completionBorder.withOpacity(0.4)));
      first = false;
      if (groups.length > 1) {
        items.add(SizedBox(
          height: _headerH,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(entry.key.toUpperCase(),
              style: TextStyle(
                color: cs.lineNumber, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          ),
        ));
      }
      for (final action in entry.value) {
        items.add(_ActionRow(
          action:  action,
          theme:   widget.theme,
          height:  _itemH,
          onTap:   () => widget.onAction(action),
        ));
      }
    }
    return items;
  }
}

class _ActionRow extends StatefulWidget {
  final CodeAction action;
  final EditorTheme theme;
  final double height;
  final VoidCallback onTap;
  const _ActionRow({required this.action, required this.theme,
    required this.height, required this.onTap});
  @override State<_ActionRow> createState() => _ActionRowState();
}
class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final cs   = widget.theme.colorScheme;
    final icon = _icon(widget.action.kind);
    final col  = _color(widget.action.kind, cs);
    return GestureDetector(
      onTapDown:   (_) { setState(() => _hovered = true); },
      onTapUp:     (_) { setState(() => _hovered = false); widget.onTap(); },
      onTapCancel: ()  { setState(() => _hovered = false); },
      child: Container(
        height: widget.height,
        color: _hovered ? cs.completionItemSelected : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Icon(icon, color: col, size: 14),
          const SizedBox(width: 10),
          Expanded(child: Text(
            widget.action.title,
            style: TextStyle(
              color: cs.textNormal,
              fontSize: widget.theme.fontSize * 0.88,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          )),
          if (widget.action.description != null)
            Text(widget.action.description!,
              style: TextStyle(color: cs.lineNumber, fontSize: 10),
              maxLines: 1),
        ]),
      ),
    );
  }

  IconData _icon(CodeActionKind k) {
    switch (k) {
      case CodeActionKind.quickFix:    return Icons.auto_fix_high;
      case CodeActionKind.refactor:    return Icons.refresh;
      case CodeActionKind.snippet:     return Icons.code;
      case CodeActionKind.surroundWith:return Icons.wrap_text;
      case CodeActionKind.generate:    return Icons.auto_awesome;
      case CodeActionKind.navigate:    return Icons.arrow_forward;
      default:                         return Icons.lightbulb_outline;
    }
  }

  Color _color(CodeActionKind k, dynamic cs) {
    switch (k) {
      case CodeActionKind.quickFix:    return cs.problemWarning;
      case CodeActionKind.refactor:    return cs.function_;
      case CodeActionKind.snippet:     return cs.keyword;
      case CodeActionKind.navigate:    return cs.type_;
      default:                         return cs.textNormal;
    }
  }
}
