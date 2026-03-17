// lib/src/actions/symbol_info_panel.dart
import 'package:flutter/material.dart';
import 'code_action.dart';
import '../theme/editor_theme.dart';

class SymbolInfoPanel extends StatefulWidget {
  final SymbolInfo symbol;
  final EditorTheme theme;
  final Offset anchorLocal;
  final double lineHeight;
  final double viewportWidth;
  final double viewportHeight;
  final VoidCallback? onGoToDefinition;
  final VoidCallback? onDismiss;

  static const double _overlayW = 200.0;
  static const double _overlayH = 150.0;

  const SymbolInfoPanel({
    super.key,
    required this.symbol,
    required this.theme,
    required this.anchorLocal,
    required this.lineHeight,
    required this.viewportWidth,
    required this.viewportHeight,
    this.onGoToDefinition,
    this.onDismiss,
  });

  @override
  State<SymbolInfoPanel> createState() => _SymbolInfoPanelState();
}

class _SymbolInfoPanelState extends State<SymbolInfoPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double>  _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs  = widget.theme.colorScheme;
    final sym = widget.symbol;
    const W   = SymbolInfoPanel._overlayW;
    const H   = SymbolInfoPanel._overlayH;
    const pad = 4.0;

    // Smart positioning (4-way: never overlaps cursor)
    final kbH      = MediaQuery.of(context).viewInsets.bottom;
    final usableH  = widget.viewportHeight - kbH;
    final cursorBottom = widget.anchorLocal.dy + widget.lineHeight;
    final spaceBelow = usableH - cursorBottom - pad;
    final spaceAbove = widget.anchorLocal.dy - pad;
    double top;
    if (spaceBelow >= H) {
      top = cursorBottom + pad;
    } else if (spaceAbove >= H) {
      top = widget.anchorLocal.dy - H - pad;
    } else if (spaceBelow >= spaceAbove) {
      top = cursorBottom + pad;
    } else {
      top = widget.anchorLocal.dy - H - pad;
      if (top < pad) top = pad;
    }
    final maxTop = (usableH - H - pad);
    if (top > maxTop && maxTop >= pad) top = maxTop;
    final double left = widget.anchorLocal.dx.clamp(pad, (widget.viewportWidth - W - pad).clamp(pad, double.maxFinite));

    final badgeColor = _badgeColor(sym.kind, cs);

    return Positioned(
      left: left, top: top, width: W, height: H,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: cs.hoverBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.hoverBorder, width: 0.8),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(sym.kindIcon,
                        style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(sym.kindLabel,
                      style: TextStyle(color: cs.lineNumber, fontSize: 11), overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Icon(Icons.close, color: cs.lineNumber, size: 13),
                    ),
                  ]),
                ),
                // Name
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 3),
                  child: Text(sym.name,
                    style: TextStyle(color: cs.type_, fontSize: widget.theme.fontSize * 0.95,
                      fontWeight: FontWeight.w700, fontFamily: widget.theme.fontFamily),
                    overflow: TextOverflow.ellipsis),
                ),
                // Signature
                if (sym.signature != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Text(sym.signature!,
                      style: TextStyle(color: cs.lineNumber, fontSize: widget.theme.fontSize * 0.78,
                        fontFamily: widget.theme.fontFamily),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                const Divider(height: 1, thickness: 0.5),
                // Footer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(children: [
                    if (sym.definedAtLine >= 0)
                      _FooterBtn(label: 'Ln ${sym.definedAtLine + 1}', icon: Icons.location_on_outlined, cs: cs, onTap: widget.onGoToDefinition),
                    const Spacer(),
                    if (widget.onGoToDefinition != null)
                      _FooterBtn(label: 'Ir para', icon: Icons.arrow_forward, cs: cs, onTap: widget.onGoToDefinition, highlighted: true),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _badgeColor(SymbolKind k, dynamic cs) {
    switch (k) {
      case SymbolKind.class_:     return cs.type_;
      case SymbolKind.function_:  return cs.function_;
      case SymbolKind.method:     return cs.function_;
      case SymbolKind.enum_:      return cs.keyword;
      case SymbolKind.mixin_:     return cs.annotation;
      case SymbolKind.extension_: return cs.constant;
      default:                    return cs.textNormal;
    }
  }
}

class _FooterBtn extends StatelessWidget {
  final String label; final IconData icon;
  final dynamic cs; final VoidCallback? onTap; final bool highlighted;
  const _FooterBtn({required this.label, required this.icon, required this.cs, this.onTap, this.highlighted = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: highlighted ? BoxDecoration(color: cs.type_.withOpacity(0.15), borderRadius: BorderRadius.circular(4)) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: highlighted ? cs.type_ : cs.lineNumber),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: highlighted ? cs.type_ : cs.lineNumber, fontSize: 11,
          fontWeight: highlighted ? FontWeight.w600 : FontWeight.normal)),
      ]),
    ),
  );
}
