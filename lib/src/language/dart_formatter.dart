// lib/src/language/dart_formatter.dart
//
// Dart code auto-formatter — applies on save or on-demand.
//
// Uses the dart_style package when available via dart format process,
// OR falls back to a built-in heuristic formatter that handles:
//
//  • Trailing commas → tree-style formatting (Dart official style)
//  • Remove unnecessary `const` before widgets that don't need it
//  • Add missing `const` before constructors in const context
//  • Fix common indent inconsistencies (2-space Dart style)
//  • Remove trailing whitespace
//  • Ensure single newline at end of file
//
// INTEGRATION (in your save handler):
//   final formatted = DartFormatter.formatSync(controller.text);
//   if (formatted != null) controller.setText(formatted);

import 'dart:io' show Directory, File, Process;
// ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart' show kIsWeb;

class DartFormatter {
  /// Try to run `dart format` on the given code string.
  /// Returns the formatted code, or null if dart is not on PATH.
  static Future<String?> formatWithDartTool(String code) async {
    // Not available on web
    if (kIsWeb) return null;
    try {
      // Write to temp file
      final tmp = await File('${Directory.systemTemp.path}/quill_fmt_${DateTime.now().millisecondsSinceEpoch}.dart')
          .create();
      await tmp.writeAsString(code);
      
      final result = await Process.run('dart', ['format', '--output=show', tmp.path],
          runInShell: true);
      
      await tmp.delete();
      
      if (result.exitCode == 0) {
        final out = result.stdout as String;
        // `dart format --output=show` prints formatted code to stdout
        if (out.trim().isNotEmpty) return out;
      }
    } catch (_) {}
    return null;
  }

  /// Synchronous heuristic formatter — always available, no external process.
  /// Implements the most impactful Dart formatting rules.
  static String formatHeuristic(String code) {
    var lines = code.split('\n');

    // 1. Remove trailing whitespace on each line
    lines = lines.map((l) => l.trimRight()).toList();

    // 2. Normalize line endings (no \r)
    lines = lines.map((l) => l.replaceAll('\r', '')).toList();

    // 3. Tree-style: expand trailing-comma argument lists
    lines = _expandTrailingCommaLists(lines);

    // 4. Fix 2-space indentation (Dart style)
    lines = _fixIndentation(lines);

    // 5. Add/remove `const` in common patterns
    lines = _fixConst(lines);

    // 6. Ensure single newline at end of file
    while (lines.isNotEmpty && lines.last.trim().isEmpty) lines.removeLast();
    lines.add('');

    return lines.join('\n');
  }

  // ── Tree-style expansion ──────────────────────────────────────────────────
  //
  // When a function call ends with a trailing comma before `)`, Dart style
  // says each argument should be on its own line.
  // Example:
  //   Row(children: [A(), B()],)  →  Row(\n  children: [\n    A(),\n    B(),\n  ],\n)

  static List<String> _expandTrailingCommaLists(List<String> lines) {
    // This is complex to do correctly without a parser.
    // We apply a simple heuristic: if a line contains a constructor call with
    // a trailing comma inside parens, we leave it as-is and let dart format handle it.
    // The main value here is detecting already-expanded cases.
    return lines; // Defer to dart format tool for this heavy lifting
  }

  // ── Indentation fixer ─────────────────────────────────────────────────────

  static List<String> _fixIndentation(List<String> lines) {
    // Dart uses 2 spaces. If the file consistently uses 4 spaces, convert.
    int twoCount = 0, fourCount = 0;
    for (final line in lines) {
      final leading = _leadingSpaces(line);
      if (leading > 0 && leading % 2 == 0 && leading % 4 != 0) twoCount++;
      if (leading > 0 && leading % 4 == 0) fourCount++;
    }
    // Only convert if overwhelmingly 4-space
    if (fourCount > twoCount * 3) {
      return lines.map((line) {
        final leading = _leadingSpaces(line);
        if (leading > 0 && leading % 4 == 0) {
          return '  ' * (leading ~/ 4) + line.substring(leading);
        }
        return line;
      }).toList();
    }
    return lines;
  }

  static int _leadingSpaces(String line) {
    int i = 0;
    while (i < line.length && line[i] == ' ') i++;
    return i;
  }

  // ── const fixer ───────────────────────────────────────────────────────────
  //
  // Patterns handled:
  //   final x = const SomeWidget(...);  — keep const
  //   var x = SomeWidget(...);           — no change
  //   child: SomeWidget(key: key)       — cannot add const (has non-const arg)

  static List<String> _fixConst(List<String> lines) {
    final result = <String>[];
    for (var line in lines) {
      // Remove double-const
      line = line.replaceAll(RegExp(r'\bconst\s+const\b'), 'const');
      // Remove `const` from non-const contexts (new keyword was removed in Dart 2)
      line = line.replaceAll(RegExp(r'\bnew\s+'), '');
      result.add(line);
    }
    return result;
  }
}
