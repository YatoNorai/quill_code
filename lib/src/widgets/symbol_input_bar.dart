// lib/src/widgets/symbol_input_bar.dart
import 'package:flutter/material.dart';
import '../core/editor_controller.dart';
import '../theme/editor_theme.dart';

/// A horizontal bar of common programming symbols, shown below the editor
/// for easy mobile input.
class SymbolInputBar extends StatelessWidget {
  final QuillCodeController controller;
  final EditorTheme theme;

  static const _symbols = [
    'Tab', '{', '}', '(', ')', '[', ']', ';', ':', '"', "'",
    '=', '<', '>', '/', '\\', '|', '&', '!', '?', '_', '+', '-', '*',
  ];

  const SymbolInputBar({
    super.key,
    required this.controller,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Container(
      height: 40,
      color: cs.lineNumberBackground,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: _symbols.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final sym = _symbols[index];
          return _SymbolKey(
            symbol: sym,
            colorScheme: cs,
            fontSize: theme.fontSize,
            fontFamily: theme.fontFamily,
            onTap: () {
              if (sym == 'Tab') {
                controller.insertTab();
              } else {
                controller.insertText(sym);
              }
            },
          );
        },
      ),
    );
  }
}

class _SymbolKey extends StatelessWidget {
  final String symbol;
  final dynamic colorScheme;
  final double fontSize;
  final String fontFamily;
  final VoidCallback onTap;

  const _SymbolKey({
    required this.symbol,
    required this.colorScheme,
    required this.fontSize,
    required this.fontFamily,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colorScheme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.blockLine),
        ),
        alignment: Alignment.center,
        child: Text(
          symbol,
          style: TextStyle(
            color: colorScheme.textNormal,
            fontSize: fontSize * 0.85,
            fontFamily: fontFamily,
          ),
        ),
      ),
    );
  }
}
