// lib/src/widgets/breadcrumbs_widget.dart
// ─────────────────────────────────────────────────────────────────────────────
// Breadcrumbs navigation bar — shows the current symbol path under the cursor,
// like VSCode. Example: MyClass > build > someVariable
// Only rendered when LSP is available and the cursor is inside a symbol.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quill_code/quill_code.dart';
import '../core/editor_controller.dart';
import '../lsp/lsp_bridge.dart';
import '../theme/editor_theme.dart';
// Re-export CharPosition so callers can import it from here if needed.
export '../core/char_position.dart' show CharPosition;

class BreadcrumbsWidget extends StatefulWidget {
  final QuillCodeController controller;
  final EditorTheme theme;

  /// Called when the user taps a breadcrumb item to jump to that symbol.
  final void Function(LspDocumentSymbol symbol)? onSymbolTap;

  const BreadcrumbsWidget({
    super.key,
    required this.controller,
    required this.theme,
    this.onSymbolTap,
  });

  @override
  State<BreadcrumbsWidget> createState() => _BreadcrumbsWidgetState();
}

class _BreadcrumbsWidgetState extends State<BreadcrumbsWidget> {
  List<LspDocumentSymbol> _path = [];
  CharPosition? _lastPos;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(BreadcrumbsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      // Reset path — new controller means new file.
      _lastPos = null;
      _path = [];
    }
  }

  void _onControllerChanged() {
    final pos = widget.controller.cursor.position;
    // Only re-query when the cursor moves to a different line — no need to
    // call documentSymbols on every character typed within the same line.
    if (_lastPos != null && pos.line == _lastPos!.line) return;
    _lastPos = pos;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refresh);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    try {
      final path = await widget.controller.getBreadcrumbPath();
      if (mounted) setState(() => _path = path);
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e, stack: st,
        library: 'quill_code', context: ErrorDescription('BreadcrumbsWidget._refresh'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hide the bar entirely when LSP is absent or cursor is outside all symbols.
    if (!widget.controller.hasLsp || _path.isEmpty) {
      return const SizedBox.shrink();
    }

    final cs = widget.theme.colorScheme;

    return Container(
      height: 26,
      color: cs.lineNumberBackground,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _path.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, size: 14, color: cs.lineNumber),
        ),
        itemBuilder: (context, i) {
          final sym = _path[i];
          final isLast = i == _path.length - 1;
          return InkWell(
            onTap: () => widget.onSymbolTap?.call(sym),
            borderRadius: BorderRadius.circular(3),
            child: Center(
              child: Text(
                sym.name,
                style: TextStyle(
                  fontSize: 12,
                  color: isLast ? cs.textNormal : cs.lineNumber,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                  fontFamily: widget.theme.fontFamily,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }
}

