// lib/src/completion/snippet.dart

class SnippetTabStop {
  final int index;
  final String placeholder;
  final List<String> choices;

  const SnippetTabStop({
    required this.index,
    this.placeholder = '',
    this.choices = const [],
  });
}

class CodeSnippet {
  final String raw;
  final List<_SnippetPart> _parts;

  CodeSnippet._(this.raw, this._parts);

  factory CodeSnippet.parse(String snippet) => _SnippetParser.parse(snippet);

  String toPlainText() {
    final buf = StringBuffer();
    for (final part in _parts) {
      if (part is _TextPart) buf.write(part.text);
      else if (part is _TabStopPart) buf.write(part.tabStop.placeholder);
      else if (part is _VariablePart) buf.write(part.value ?? '');
    }
    return buf.toString();
  }

  List<SnippetTabStop> get tabStops {
    final stops = <SnippetTabStop>[];
    for (final p in _parts) {
      if (p is _TabStopPart) stops.add(p.tabStop);
    }
    stops.sort((a, b) => a.index.compareTo(b.index));
    return stops;
  }
}

abstract class _SnippetPart {}
class _TextPart extends _SnippetPart { final String text; _TextPart(this.text); }
class _TabStopPart extends _SnippetPart { final SnippetTabStop tabStop; _TabStopPart(this.tabStop); }
class _VariablePart extends _SnippetPart { final String name; final String? value; _VariablePart(this.name, this.value); }

class _SnippetParser {
  static const _dollar = 0x24; // $
  static const _backslash = 0x5C; // \
  static const _openBrace = 0x7B; // {
  static const _closeBrace = 0x7D; // }

  static CodeSnippet parse(String input) {
    final parts = <_SnippetPart>[];
    int i = 0;

    while (i < input.length) {
      final c = input.codeUnitAt(i);

      if (c == _dollar) {
        i++;
        if (i >= input.length) break;

        if (input.codeUnitAt(i) == _openBrace) {
          i++;
          final end = input.indexOf('}', i);
          if (end == -1) break;
          final content = input.substring(i, end);
          i = end + 1;

          final colon = content.indexOf(':');
          final pipe = content.indexOf('|');

          if (pipe != -1) {
            final idx = int.tryParse(content.substring(0, pipe)) ?? 0;
            final choiceStr = content.substring(pipe + 1);
            final choices = (choiceStr.endsWith('|')
                ? choiceStr.substring(0, choiceStr.length - 1)
                : choiceStr).split(',');
            parts.add(_TabStopPart(SnippetTabStop(
                index: idx,
                placeholder: choices.isNotEmpty ? choices.first : '',
                choices: choices)));
          } else if (colon != -1) {
            final idx = int.tryParse(content.substring(0, colon));
            final ph = content.substring(colon + 1);
            if (idx != null && idx > 0) {
              parts.add(_TabStopPart(SnippetTabStop(index: idx, placeholder: ph)));
            } else {
              parts.add(_VariablePart(content.substring(0, colon), ph));
            }
          } else {
            final idx = int.tryParse(content);
            if (idx != null) {
              parts.add(_TabStopPart(SnippetTabStop(index: idx)));
            } else {
              parts.add(_VariablePart(content, null));
            }
          }
        } else if (_isDigit(input.codeUnitAt(i))) {
          int j = i;
          while (j < input.length && _isDigit(input.codeUnitAt(j))) j++;
          parts.add(_TabStopPart(SnippetTabStop(index: int.parse(input.substring(i, j)))));
          i = j;
        } else {
          int j = i;
          while (j < input.length && _isVarChar(input.codeUnitAt(j))) j++;
          if (j > i) {
            parts.add(_VariablePart(input.substring(i, j), null));
            i = j;
          }
        }
      } else if (c == _backslash && i + 1 < input.length) {
        parts.add(_TextPart(String.fromCharCode(input.codeUnitAt(i + 1))));
        i += 2;
      } else {
        int start = i;
        while (i < input.length &&
            input.codeUnitAt(i) != _dollar &&
            input.codeUnitAt(i) != _backslash) i++;
        if (i > start) parts.add(_TextPart(input.substring(start, i)));
      }
    }
    return CodeSnippet._(input, parts);
  }

  static bool _isDigit(int c) => c >= 48 && c <= 57;
  static bool _isVarChar(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95;
}
