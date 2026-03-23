// lib/src/tree_sitter/ts_analyze_manager.dart
//
// AnalyzeManager backed by tree-sitter, running on the MAIN thread.
// No isolate — tree-sitter is fast enough (< 5ms for 1k lines).
// 80ms debounce prevents excessive re-parses while typing.
// Falls back to regex (IncrementalAnalyzeManager) when unavailable.

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';
import '../highlighting/analyze_manager.dart';
import '../highlighting/incremental_analyze_manager.dart';
import '../highlighting/styles.dart';
import '../highlighting/span.dart';
import '../highlighting/code_block.dart';
import '../language/language.dart';
import '../text/content.dart';
import 'ts_ffi.dart';
import 'ts_parser.dart';
import 'ts_language.dart';

class TsAnalyzeManager extends AnalyzeManager {
  final QuillLanguage _language;

  late final AnalyzeManager _fallback;
  bool _useFallback = false;
  TsParser? _tsParser;
  Timer? _debounce;
  int _pendingVersion = -1;
  int _diagSeq = 0;

  static const _kDebounceMs = 80;

  // Tracks whether a next-frame reparse is already queued (structural edits).
  bool _immediateReparsePending = false;

  TsAnalyzeManager({required QuillLanguage language}) : _language = language;

  @override
  void init(Content content) {
    _fallback = IncrementalAnalyzeManager(language: _language);
    _fallback.onStylesUpdated        = (s) { if (_useFallback) pushStyles(s); };
    _fallback.onTokenizationComplete = ()  { if (_useFallback) onTokenizationComplete?.call(); };

    debugPrint('[TS] init: lang=${_language.name} isAvailable=${QuillTsLib.isAvailable}');

    if (!QuillTsLib.isAvailable) {
      debugPrint('[TS] FALLBACK: QuillTsLib not available');
      _useFallback = true;
      _fallback.init(content);
      return;
    }

    final langName = (_language is TsLanguageMixin)
        ? (_language as TsLanguageMixin).tsName
        : _language.name.toLowerCase();

    debugPrint('[TS] creating parser for langName="$langName"');
    _tsParser = TsParser.create(langName);
    if (_tsParser == null) {
      debugPrint('[TS] FALLBACK: TsParser.create("$langName") returned null');
      _useFallback = true;
      _fallback.init(content);
      return;
    }

    debugPrint('[TS] parser created OK for "$langName", calling _parseAndPush');
    _parseAndPush(content);
  }

  ContentChangeEvent? _lastEvent;

  @override
  void onContentChanged(ContentChangeEvent event, Content content) {
    if (_useFallback) { _fallback.onContentChanged(event, content); return; }
    _lastEvent = event;
    _debounce?.cancel();

    // Structural edits — characters that open/close fold blocks, or newlines.
    // Skip the 80ms debounce and schedule a reparse in the next frame (~16ms)
    // so fold arrows appear/disappear immediately, matching the regex path.
    if (_isStructuralEdit(event, content)) {
      _scheduleImmediateReparse(content);
      return;
    }

    _debounce = Timer(Duration(milliseconds: _kDebounceMs),
        () { _parseAndPush(content); _lastEvent = null; });
  }

  /// Returns true when the edit contains characters that affect fold blocks:
  /// {, }, (, ), newline, or a colon at end-of-line (Python/Dart style).
  static bool _isStructuralEdit(ContentChangeEvent event, Content content) {
    if (event.text.contains('\n')) return true;
    for (int i = 0; i < event.text.length; i++) {
      final c = event.text.codeUnitAt(i);
      if (c == 123 || c == 125 || c == 40 || c == 41) return true; // { } ( )
    }
    // Colon at end-of-line on the affected line.
    final line = event.affectedLine;
    if (line >= 0 && line < content.lineCount) {
      final tr = content.getLineText(line).trimRight();
      if (tr.isNotEmpty && tr.codeUnitAt(tr.length - 1) == 58) return true; // :
    }
    return false;
  }

  /// Schedules [_parseAndPush] on the next animation frame so that fold arrows
  /// update in ~16ms without blocking the current keystroke.
  void _scheduleImmediateReparse(Content content) {
    if (_immediateReparsePending) return;
    _immediateReparsePending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _immediateReparsePending = false;
      if (_useFallback) return;
      _parseAndPush(content);
      _lastEvent = null;
    }, rescheduling: false);
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void reanalyze(Content content) {
    if (_useFallback) { _fallback.reanalyze(content); return; }
    _debounce?.cancel();
    _lastEvent = null;
    _parseAndPush(content);
  }

  void _parseAndPush(Content content) {
    final parser = _tsParser;
    if (parser == null) { debugPrint('[TS] _parseAndPush: parser is null!'); return; }

    final version = content.documentVersion;
    _pendingVersion = version;
    final source = content.fullText;

    final evt = _lastEvent;
    if (evt != null && parser.hasTree) {
      _applyIncrementalEdit(parser, source, evt);
    } else {
      final ok = parser.parseString(source);
      debugPrint('[TS] parseString ok=$ok sourceLen=${source.length} hasTree=${parser.hasTree}');
    }
    if (version != _pendingVersion) { debugPrint('[TS] version mismatch, aborting'); return; }

    final spans  = parser.highlight(source);
    final blocks = parser.extractBlocks();
    debugPrint('[TS] highlight: ${spans.length} spans, ${blocks.length} blocks');
    final lineStarts  = _buildLineStarts(source);
    final lineCount   = source.split('\n').length;
    final spansByLine = <int, List<CodeSpan>>{};

    for (final sp in spans) {
      final sLC = _byteToLineCol(sp.startByte, lineStarts);
      final eLC = _byteToLineCol(sp.endByte,   lineStarts);
      if (sLC.$1 == eLC.$1) {
        // Single-line span
        spansByLine.putIfAbsent(sLC.$1, () => [])
            .add(CodeSpan(column: sLC.$2, type: sp.type));
      } else {
        // Multi-line: add one entry per covered line
        for (int ln = sLC.$1; ln <= eLC.$1; ln++) {
          spansByLine.putIfAbsent(ln, () => [])
              .add(CodeSpan(column: ln == sLC.$1 ? sLC.$2 : 0, type: sp.type));
        }
      }
    }

    for (final list in spansByLine.values) {
      if (list.length > 1) list.sort((a, b) => a.column.compareTo(b.column));
    }

    int maxLine = lineCount - 1;
    for (final b in blocks) { if (b.endLine > maxLine) maxLine = b.endLine; }

    pushStyles(Styles(
      spans: List<List<CodeSpan>>.generate(
          maxLine + 1, (i) => spansByLine[i] ?? const [], growable: false),
      codeBlocks: blocks,
    ));
    onTokenizationComplete?.call();
    // Push diagnostics deferred: prevents setDiagnostics→notifyListeners()
    // from clearing the TextPainter cache during the same synchronous call.
    // Use a sequence number so a stale microtask from a superseded parse
    // doesn't clobber diagnostics with wrong byte offsets.
    final diagSeq = ++_diagSeq;
    Future.microtask(() {
      if (diagSeq != _diagSeq) return; // superseded by a newer parse
      _pushDiagnostics(parser, source, lineStarts);
    });
  }

  void _pushDiagnostics(TsParser parser, String source, List<int> lineStarts) {
    final errors = parser.extractErrors();
    if (errors.isEmpty) {
      onDiagnosticsUpdated?.call(const []);
      return;
    }
    final regions = <TsDiagEntry>[];
    for (final (sb, eb) in errors) {
      final s = _byteToLineCol(sb, lineStarts);
      final e = _byteToLineCol(eb <= sb ? sb + 1 : eb, lineStarts);
      regions.add(TsDiagEntry(s.$1, s.$2, e.$1, e.$2));
    }
    onDiagnosticsUpdated?.call(regions);
  }

  /// Called when syntax diagnostics change. Controller wires this to setDiagnostics().
  void Function(List<TsDiagEntry>)? onDiagnosticsUpdated;

  // ── Incremental edit helper ─────────────────────────────────────────────────

  void _applyIncrementalEdit(TsParser parser, String newSource,
      ContentChangeEvent event) {
    final lineStarts = _buildLineStarts(newSource);
    final startByte = _lcToByte(event.position.line, event.position.column, lineStarts);
    final textBytes = _utf8ByteLen(event.text);

    int oldEndByte, newEndByte;
    int oldEndRow, oldEndCol, newEndRow, newEndCol;

    if (event.type == ContentChangeType.insert) {
      oldEndByte = startByte;
      newEndByte = startByte + textBytes;
      oldEndRow  = event.position.line;
      oldEndCol  = event.position.column;
      final ne   = _byteToLineCol(newEndByte, lineStarts);
      newEndRow  = ne.$1;  newEndCol = ne.$2;
    } else {
      oldEndByte = startByte + textBytes;
      newEndByte = startByte;
      final oe   = _byteToLineCol(oldEndByte, lineStarts);
      oldEndRow  = oe.$1;  oldEndCol = oe.$2;
      newEndRow  = event.position.line;
      newEndCol  = event.position.column;
    }

    parser.editAndReparse(
      newSource:  newSource,
      startByte:  startByte,    oldEndByte: oldEndByte,    newEndByte: newEndByte,
      startRow:   event.position.line,     startCol:    event.position.column,
      oldEndRow:  oldEndRow,    oldEndCol:  oldEndCol,
      newEndRow:  newEndRow,    newEndCol:  newEndCol,
    );
  }

  static int _lcToByte(int line, int col, List<int> starts) =>
      (line < starts.length ? starts[line] : 0) + col;

  static int _utf8ByteLen(String s) {
    int b = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c <= 0x7F) b++;
      else if (c <= 0x7FF) b += 2;
      else if (c >= 0xD800 && c <= 0xDBFF) { b += 4; i++; }
      else b += 3;
    }
    return b;
  }

  @override
  void destroy() {
    _debounce?.cancel();
    _immediateReparsePending = false;
    _tsParser?.dispose();
    _tsParser = null;
    _fallback.destroy();
  }

  static List<int> _buildLineStarts(String src) {
    final starts = <int>[0];
    int byte = 0;
    for (int i = 0; i < src.length; i++) {
      final c = src.codeUnitAt(i);
      if (c <= 0x7F)               { byte++; }
      else if (c <= 0x7FF)          { byte += 2; }
      else if (c >= 0xD800 && c <= 0xDBFF) { byte += 4; i++; }
      else                          { byte += 3; }
      if (c == 0x0A) starts.add(byte);
    }
    return starts;
  }

  static (int, int) _byteToLineCol(int byteOffset, List<int> lineStarts) {
    int lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lineStarts[mid] <= byteOffset) lo = mid; else hi = mid - 1;
    }
    return (lo, byteOffset - lineStarts[lo]);
  }
}

/// Lightweight struct for passing diagnostic positions out of TsAnalyzeManager.
class TsDiagEntry {
  final int startLine, startCol, endLine, endCol;
  const TsDiagEntry(this.startLine, this.startCol, this.endLine, this.endCol);
}
