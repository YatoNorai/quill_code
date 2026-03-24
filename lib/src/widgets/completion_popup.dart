// lib/src/widgets/completion_popup.dart
//
// Enhanced completion popup (inspired by Sora + Monaco):
//
//  • Loading indicator (spinner) while LSP request is in-flight — user sees
//    local items immediately, then spinner shows more is coming.
//  • Lazy-resolve on item hover: when the selected item changes, the popup
//    calls controller.resolveCompletionItem() to fetch full documentation
//    from the LSP server (Monaco's resolveCompletionItem pattern).
//  • Documentation panel alongside the list when docs are available.
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../completion/completion_item.dart';
import '../theme/editor_theme.dart';

class CompletionPopup extends StatefulWidget {
  final QuillCodeController controller;
  final EditorTheme theme;
  final int selectedIndex;

  const CompletionPopup({
    super.key,
    required this.controller,
    required this.theme,
    this.selectedIndex = 0,
  });

  @override
  State<CompletionPopup> createState() => _CompletionPopupState();
}

class _CompletionPopupState extends State<CompletionPopup> {
  int _lastResolvedIndex = -1;

  @override
  void didUpdateWidget(CompletionPopup old) {
    super.didUpdateWidget(old);
    // When selection changes, trigger lazy resolve for the new item.
    if (widget.selectedIndex != old.selectedIndex) {
      _maybeResolve(widget.selectedIndex);
    }
  }

  void _maybeResolve(int index) {
    final items = widget.controller.completionItems;
    if (index < 0 || index >= items.length) return;
    if (_lastResolvedIndex == index) return;
    final item = items[index];
    if (item.isResolved) return;
    _lastResolvedIndex = index;
    // Fetch docs — controller updates the list and notifies listeners.
    widget.controller.resolveCompletionItem(index);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    final ctrl = widget.controller;
    final items = ctrl.completionItems;

    if (items.isEmpty) return const SizedBox.shrink();

    final selectedItem = (widget.selectedIndex >= 0 && widget.selectedIndex < items.length)
        ? items[widget.selectedIndex]
        : null;
    final hasDoc = selectedItem != null &&
        selectedItem.documentation != null &&
        selectedItem.documentation!.isNotEmpty;

    // Use LayoutBuilder so we respect whatever width the parent gives us.
    // On narrow screens (< 260px) the doc panel is hidden to prevent overflow.
    return LayoutBuilder(builder: (context, constraints) {
      const docW    = 200.0;
      const gap     = 4.0;
      const minListW = 160.0;
      final availW  = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
      final showDocsHere = hasDoc && availW >= minListW + gap + docW;
      final listMaxW = showDocsHere
          ? (availW - docW - gap).clamp(minListW, 260.0)
          : availW.clamp(minListW, 260.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main completion list ─────────────────────────────────────────────
        Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(6),
          color: cs.completionBackground,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.completionBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: BoxConstraints(maxHeight: 160, maxWidth: listMaxW),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (items.isNotEmpty)
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final selected = i == widget.selectedIndex;
                          return InkWell(
                            onTap: () => ctrl.selectCompletionItem(item),
                            child: Container(
                              color: selected ? cs.completionItemSelected : null,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              child: Row(
                                children: [
                                  _KindBadge(kind: item.kind, color: cs.completionTextMatched),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _HighlightLabel(
                                          text: item.label,
                                          prefix: ctrl.completionPrefix,
                                          normalColor: cs.completionTextPrimary,
                                          matchColor: cs.completionTextMatched,
                                          fontSize: widget.theme.fontSize,
                                          fontFamily: widget.theme.fontFamily,
                                        ),
                                        if (item.detail != null)
                                          Text(item.detail!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: cs.completionTextSecondary,
                                                fontSize: widget.theme.fontSize * 0.78,
                                                fontFamily: widget.theme.fontFamily,
                                              )),
                                      ],
                                    ),
                                  ),
                                  if (item.isSnippet)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: cs.snippetActiveBackground,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text('snip',
                                          style: TextStyle(
                                              color: cs.cursor,
                                              fontSize: widget.theme.fontSize * 0.68)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // ── Documentation panel (lazy-resolved, shown beside list) ───────────
        if (showDocsHere) ...[
          const SizedBox(width: gap),
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            color: cs.completionBackground,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.completionBorder),
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: BoxConstraints(maxHeight: 160, maxWidth: docW),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectedItem!.detail != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(selectedItem.detail!,
                              style: TextStyle(
                                color: cs.completionTextMatched,
                                fontSize: widget.theme.fontSize * 0.82,
                                fontFamily: widget.theme.fontFamily,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                      Text(selectedItem.documentation!,
                          style: TextStyle(
                            color: cs.completionTextPrimary,
                            fontSize: widget.theme.fontSize * 0.8,
                            fontFamily: widget.theme.fontFamily,
                            height: 1.5,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    }); // LayoutBuilder
  }
}

class _KindBadge extends StatelessWidget {
  final CompletionItemKind kind;
  final Color color;
  const _KindBadge({required this.kind, required this.color});

  static const _icons = <CompletionItemKind, IconData>{
    CompletionItemKind.keyword:       Icons.key_rounded,
    CompletionItemKind.function_:     Icons.functions,
    CompletionItemKind.method:        Icons.functions,
    CompletionItemKind.class_:        Icons.category_rounded,
    CompletionItemKind.variable:      Icons.data_object,
    CompletionItemKind.field:         Icons.data_object,
    CompletionItemKind.snippet:       Icons.snippet_folder,
    CompletionItemKind.constant:      Icons.push_pin,
    CompletionItemKind.enum_:         Icons.format_list_bulleted,
    CompletionItemKind.interface_:    Icons.hexagon_outlined,
    CompletionItemKind.module:        Icons.folder_outlined,
    CompletionItemKind.typeParameter: Icons.text_fields,
  };

  @override
  Widget build(BuildContext context) => Icon(
    _icons[kind] ?? Icons.code,
    size: 14,
    color: color,
  );
}

class _HighlightLabel extends StatelessWidget {
  final String text, prefix;
  final Color normalColor, matchColor;
  final double fontSize;
  final String fontFamily;
  const _HighlightLabel({
    required this.text, required this.prefix,
    required this.normalColor, required this.matchColor,
    required this.fontSize, required this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, fontFamily: fontFamily);
    if (prefix.isEmpty || !text.toLowerCase().startsWith(prefix.toLowerCase())) {
      return Text(text, style: base.copyWith(color: normalColor));
    }
    return RichText(
      text: TextSpan(children: [
        TextSpan(text: text.substring(0, prefix.length),
            style: base.copyWith(color: matchColor, fontWeight: FontWeight.bold)),
        TextSpan(text: text.substring(prefix.length),
            style: base.copyWith(color: normalColor)),
      ]),
    );
  }
}