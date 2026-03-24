// lib/src/highlighting/incremental_analyze_manager.dart
//
// Hybrid tokenisation strategy:
//
//  FULL REANALYSIS (setText / reanalyze)
//  ──────────────────────────────────────
//  • IsolateTokenizer: UI thread free. Spans delivered progressively every
//    400 lines; code blocks from the isolate are the authoritative source.
//  • _kVisible lines tokenised sync for instant first-paint colours.
//  • Old spans preserved — no grey flash while isolate runs.
//
//  INCREMENTAL KEYSTROKE (single-line / structural edits)
//  ───────────────────────────────────────────────────────
//  • Fast path: re-tokenise the edited line synchronously (<0.1 ms).
//  • Block re-scan: lightweight synchronous re-extraction in the NEXT frame
//    whenever a structurally-significant char ({, }, (, )) was edited.
//    This makes fold arrows appear/disappear in 1 frame (~16 ms) instead of
//    waiting for the full isolate debounce (~400 ms + isolate time).
//  • Debounced full isolate re-analysis keeps the authoritative state fresh.
//
//  BUG FIXES (this version)
//  ─────────────────────────
//  • Bug A — All fold icons disappear while typing:
//      _dispatchFull no longer sets _currentBlocks = const [].
//      Existing blocks are kept while the isolate recomputes.
//
//  • Bug B — Fold arrow doesn't reappear after re-typing }:
//      _scheduleBlockRescan() runs _extractCodeBlocksUI() in the next frame
//      on every edit that touches {, }, (, ).  The sync scan is O(n) but
//      ≤ 5 ms for 20 k lines in release, and it only runs once per edit.

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
import 'analyze_manager.dart';
import 'isolate_tokenizer.dart';
import 'styles.dart';
import 'code_block.dart';
import '../text/content.dart';
import '../language/language.dart';
import '../language/_regex_language.dart';
import '../highlighting/span.dart';
import '../native/quill_native.dart';

// Lines tokenised synchronously on init.
const int _kVisible = 120;

// Files larger than this skip the isolate entirely.
// Sending List<String>.generate(180000, ...) to the isolate requires building
// a 180k-element list on the main thread — at ~180k String refs that alone
// freezes the UI for several hundred ms.  For large files the frame-budget
// tokenizer (_onFrame) handles everything on the main thread in 6ms slices.
const int _kMaxIsoLines = 30000;

// ── Lightweight synchronous block extractor (UI thread) ───────────────────────
//
// Duplicates the logic from isolate_tokenizer.dart/_extractBlocks so it can
// run on the UI thread for immediate fold-arrow feedback on { / } edits.
// Must stay in sync with the isolate version — if the algorithm changes,
// update both places.

bool _blank(String s) {
  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c != 32 && c != 9) return false;
  }
  return true;
}

int _ls(String s, int tab) {
  int sp = 0;
  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 32) sp++; else if (c == 9) sp += tab; else break;
  }
  return sp;
}

List<CodeBlock> _extractCodeBlocksUI(Content content) {
  final n      = content.lineCount;
  final stack  = <(int, int)>[];
  final raw    = <(int, int, int)>[];

  // Detect indent unit.
  int tab = 2;
  for (int i = 0; i < n; i++) {
    final l = content.getLineText(i);
    if (_blank(l)) continue;
    final sp = _ls(l, 2);
    if (sp > 0 && sp < tab) tab = sp;
  }
  if (tab < 1) tab = 2;

  for (int i = 0; i < n; i++) {
    final ln = content.getLineText(i);
    if (_blank(ln)) continue;
    bool s1 = false, s2 = false, tpl = false;
    final llen = ln.length;

    for (int j = 0; j < llen; j++) {
      final c = ln.codeUnitAt(j);
      if (c == 47 && j + 1 < llen && ln.codeUnitAt(j + 1) == 47) break; // //
      if (!s1 && !s2 && !tpl) {
        if      (c == 39)  s1  = true;
        else if (c == 34)  s2  = true;
        else if (c == 96)  tpl = true;
        else if (c == 123 || c == 40) stack.add((i, c));
        else if (c == 125 || c == 41) {
          if (stack.isNotEmpty) {
            final (sl, _) = stack.removeLast();
            if (i > sl) raw.add((sl, i, _ls(content.getLineText(sl), tab) ~/ tab));
          }
        }
      } else {
        if (s1  && c == 39 && (j == 0 || ln.codeUnitAt(j-1) != 92)) s1  = false;
        if (s2  && c == 34 && (j == 0 || ln.codeUnitAt(j-1) != 92)) s2  = false;
        if (tpl && c == 96)                                            tpl = false;
      }
    }
    final tr = ln.trimRight();
    if (tr.isNotEmpty && tr.codeUnitAt(tr.length - 1) == 58) stack.add((i, 58));
  }

  final last = n - 1;
  while (stack.isNotEmpty) {
    final (sl, _) = stack.removeLast();
    if (last > sl) raw.add((sl, last, _ls(content.getLineText(sl), tab) ~/ tab));
  }

  // Convert to CodeBlock and sort by startLine.
  final blocks = raw.map((r) => CodeBlock(startLine: r.$1, endLine: r.$2, indent: r.$3)).toList();
  blocks.sort((a, b) {
    final c = a.startLine.compareTo(b.startLine);
    return c != 0 ? c : b.lineCount.compareTo(a.lineCount);
  });
  return blocks;
}

// ── Manager ───────────────────────────────────────────────────────────────────

class IncrementalAnalyzeManager extends AnalyzeManager {
  final QuillLanguage language;

  Content? _content;
  Timer?   _debounceTimer;
  bool     _destroyed    = false;
  int      _lastEditLine = 0;

  // ── Version + span buffer ─────────────────────────────────────────────────
  int _currentVersion = 0;
  List<List<CodeSpan>>? _partialSpans;
  List<CodeBlock> _currentBlocks = const [];

  // ── Block rescan scheduling ───────────────────────────────────────────────
  // Set to true when a char that can open/close a block was edited.
  // _onBlockRescanFrame() runs in the next frame and calls _extractCodeBlocksUI.
  bool _blockRescanPending = false;

  // ── Isolate tokenizer ─────────────────────────────────────────────────────
  IsolateTokenizer? _iso;

  // ── Incremental frame-budget (keystroke convergence only) ─────────────────
  int  _jobTotal       = 0;
  int  _jobVersion     = 0;
  int  _jobNext        = 0;
  int  _jobStart       = 0;
  bool _frameScheduled = false;
  // True when the current job is a full-file scan (init / _dispatchFull for
  // large files).  Full scans MUST tokenize every line — the keystroke
  // convergence check is disabled so an empty line at _jobStart can't cause
  // premature termination.
  bool _jobIsFull      = false;

  // Current viewport range — used to prioritize visible lines first.
  int _visibleFirst = 0;
  int _visibleLast  = 0;

  // ── Progressive block scan (large-file path only) ─────────────────────────
  // Runs in lockstep with _onFrame's Phase 2 sequential scan.
  // Maintains an incremental brace-matching state so fold arrows appear
  // progressively without blocking the main thread.
  int       _blkLine  = 0;   // next line to process in block scan
  int       _blkTab   = 2;   // detected indent unit (spaces per level)
  // Flat lists — avoids List<(int,int)> boxing overhead.
  // _blkStack: [line0, char0, line1, char1, ...] — open brace positions
  // _blkPairs: [start0, end0, start1, end1, ...] — matched brace pairs
  final List<int> _blkStack = [];
  final List<int> _blkPairs = [];

  IncrementalAnalyzeManager({required this.language});

  // ── Rust single-line tokenizer ────────────────────────────────────────────
  // Keyword table bytes — built once lazily, shared across all calls.
  // Format: [len, ...word_bytes, type_idx] per entry.
  Uint8List? _kwBuf;

  Uint8List _buildKwBuf() {
    if (_kwBuf != null) return _kwBuf!;
    final out = <int>[];
    final wm = (language is RegexLanguage)
        ? (language as RegexLanguage).isolateWordMap
        : const <String, int>{};
    for (final e in wm.entries) {
      final bytes = e.key.codeUnits;
      if (bytes.length > 255) continue;
      out.add(bytes.length);
      out.addAll(bytes);
      out.add(e.value);
    }
    _kwBuf = Uint8List.fromList(out);
    return _kwBuf!;
  }

  List<CodeSpan>? _tokenizeLineRust(String line) {
    if (!QuillNative.isAvailable) return null;
    final kw = _buildKwBuf();
    final arena = Arena();
    try {
      final lp  = line.toNativeUtf8(allocator: arena);
      final kwp = arena<Uint8>(kw.length);
      for (int i = 0; i < kw.length; i++) kwp[i] = kw[i];
      const maxSpans = 256;
      final out = arena<Uint32>(maxSpans * 2);
      final fn  = QuillNative.tokenizeLineRaw;
      if (fn == null) return null;
      final n = fn(lp.cast<Uint8>(), line.length,
                   kwp, kw.length, out, maxSpans);
      if (n <= 0) return const [];
      final spans = <CodeSpan>[];
      for (int i = 0; i < n; i++) {
        spans.add(CodeSpan(
          column: out[i * 2],
          type:   TokenType.values[out[i * 2 + 1].clamp(0, TokenType.values.length - 1)],
        ));
      }
      return spans;
    } finally { arena.releaseAll(); }
  }

  // ── Isolate setup ─────────────────────────────────────────────────────────

  IsolateTokenizer _getOrCreateIso() {
    if (_iso != null) return _iso!;
    _iso = IsolateTokenizer(onSpans: _onIsoSpans, onBlocks: _onIsoBlocks);
    if (language is RegexLanguage) {
      final rl = language as RegexLanguage;
      _iso!.setRules(rl.isolateRulePayload, rl.isolateWordMap);
    }
    return _iso!;
  }

  // ── Isolate callbacks ─────────────────────────────────────────────────────

  void _onIsoSpans(int version, List<List<CodeSpan>> spans, bool isFinal, int upTo) {
    if (_destroyed || version != _currentVersion) return;

    if (!isFinal && upTo >= 0 &&
        _partialSpans != null &&
        _partialSpans!.length == spans.length) {
      // Progress merge — overwrite only the freshly tokenised slice so lines
      // beyond upTo keep their previous (possibly slightly stale but not grey)
      // colours.
      final buf = _partialSpans!;
      final end = math.min(upTo, buf.length - 1);
      for (int i = 0; i <= end; i++) buf[i] = spans[i];
      pushStyles(Styles(
        spans:      List<List<CodeSpan>>.unmodifiable(buf),
        codeBlocks: _currentBlocks,
      ));
    } else {
      // Final delivery or size mismatch — accept all spans.
      _partialSpans = spans;
      pushStyles(Styles(
        spans:      List<List<CodeSpan>>.unmodifiable(spans),
        codeBlocks: _currentBlocks,
      ));
    }
    if (isFinal) onTokenizationComplete?.call();
  }

  void _onIsoBlocks(int version, List<CodeBlock> blocks) {
    if (_destroyed || version != _currentVersion) return;
    // Authoritative blocks from the isolate — replace current blocks.
    _currentBlocks = blocks;
    if (_content != null) _validateBlocks(_content!);
    final cur = _partialSpans ?? styles.spans;
    pushStyles(Styles(
      spans:      List<List<CodeSpan>>.unmodifiable(cur),
      codeBlocks: _currentBlocks,
    ));
  }

  // ── Synchronous block re-scan (1 frame after structural char edit) ─────────

  /// Call whenever a char that can open/close a code block was edited:
  /// {, }, (, ), or : at end-of-line.
  /// Schedules a one-shot frame callback that re-extracts ALL code blocks
  /// on the UI thread so fold arrows appear/disappear in ≤ 16 ms.
  void _scheduleBlockRescan() {
    if (_blockRescanPending || _destroyed) return;
    // Large files: skip the full rescan — just validate in the next frame.
    // The progressive block scan in _onFrame handles extraction.
    final content = _content;
    if (content != null && content.lineCount > _kMaxIsoLines) {
      _validateBlocks(content);
      return;
    }
    _blockRescanPending = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onBlockRescanFrame,
        rescheduling: false);
    SchedulerBinding.instance.scheduleFrame();
  }

  void _onBlockRescanFrame(Duration _) {
    _blockRescanPending = false;
    if (_destroyed) return;
    final content = _content;
    if (content == null) return;

    // For large files, skip the full O(n) rescan — the progressive block scan
    // (running in _onFrame) handles it. Just validate existing blocks so stale
    // fold arrows from deleted braces disappear immediately.
    if (content.lineCount > _kMaxIsoLines) {
      _validateBlocks(content);
      final cur = _partialSpans ?? styles.spans;
      pushStyles(Styles(
        spans:      List<List<CodeSpan>>.unmodifiable(cur),
        codeBlocks: _currentBlocks,
      ));
      return;
    }

    // Small/medium file: full rescan via Rust flat-text path (one FFI call,
    // ~0.5 ms for 30k lines) falling back to line-pointer or Dart.
    final blocks = QuillNative.extractBlocksFlat(content.fullText)
        ?? QuillNative.extractBlocks(content)
        ?? _extractCodeBlocksUI(content);
    _currentBlocks = blocks;
    // Bug 1 fix: remove EOF-ghost blocks (unclosed { with no matching }).
    // _extractCodeBlocksUI keeps unmatched openers as blocks ending at EOF;
    // _validateBlocks removes them because their endLine has no expected closer.
    _validateBlocks(content);

    final cur = _partialSpans ?? styles.spans;
    pushStyles(Styles(
      spans:      List<List<CodeSpan>>.unmodifiable(cur),
      codeBlocks: _currentBlocks,
    ));
  }

  // ── Returns true if the text contains a block-structural character ─────────
  static bool _hasStructuralChar(String text) =>
      QuillNative.hasStructuralChar(text);

  // ── Dispatch full job to isolate ──────────────────────────────────────────

  /// Sends a full-document tokenisation + block-extraction job to the isolate.
  ///
  /// FIX (Bug A): does NOT reset _currentBlocks to empty.
  /// Existing blocks remain visible while the isolate computes the new ones.
  /// The isolate delivers authoritative blocks via _onIsoBlocks, which replaces
  /// _currentBlocks when it arrives.
  void _dispatchFull(Content content) {
    if (_destroyed) return;
    final version   = ++_currentVersion;
    final lineCount = content.lineCount;
    // DO NOT touch _currentBlocks here — keep existing fold arrows visible.

    // Resize/preserve _partialSpans — never reset to all-empty.
    if (_partialSpans == null) {
      _partialSpans = List<List<CodeSpan>>.filled(lineCount, const [], growable: false);
    } else if (_partialSpans!.length != lineCount) {
      final old    = _partialSpans!;
      final buf    = List<List<CodeSpan>>.filled(lineCount, const [], growable: false);
      final copyTo = math.min(old.length, lineCount);
      for (int i = 0; i < copyTo; i++) buf[i] = old[i];
      _partialSpans = buf;
    }

    if (lineCount > _kMaxIsoLines) {
      // Large file: skip isolate — use frame-budget. Also start progressive
      // block scan so fold arrows appear without a full O(n) sync extraction.
      _jobIsFull  = true;
      _jobTotal   = lineCount;
      _jobVersion = version;
      _jobNext    = 0;
      _jobStart   = 0;
      _initBlkScan(content);
      _scheduleFrame();
    } else {
      _jobIsFull  = false;
      final lines = List<String>.generate(lineCount, content.getLineText);
      _getOrCreateIso().tokenize(lines, version);
    }
  }

  // ── Incremental frame-budget (keystroke convergence) ─────────────────────

  // ── Block scan helpers (large-file progressive path) ─────────────────────

  /// Resets block-scan state and detects the indent unit from the first
  /// 200 lines.  Called when a large-file full scan begins.
  void _initBlkScan(Content content) {
    _blkLine = 0;
    _blkTab  = 2;
    _blkStack.clear();
    _blkPairs.clear();
    // Detect indent unit from a small sample.
    final sample = content.lineCount.clamp(0, 200);
    for (int i = 0; i < sample; i++) {
      final txt = content.getLineText(i);
      if (txt.isEmpty) continue;
      int sp = 0;
      for (int j = 0; j < txt.length; j++) {
        final c = txt.codeUnitAt(j);
        if (c == 32) sp++;
        else if (c == 9) { sp += 2; break; }
        else break;
      }
      if (sp > 0 && sp < _blkTab) _blkTab = sp;
    }
    if (_blkTab < 1 || _blkTab > 8) _blkTab = 2;
  }

  /// Processes one line of the block scan.  Updates `_blkStack` (open
  /// braces) and `_blkPairs` (matched pairs) but does NOT increment `_blkLine`.
  void _blkProcessLine(String txt, int lineNum) {
    if (txt.isEmpty) return;
    final n = txt.length;
    bool s1 = false, s2 = false, tpl = false;
    for (int j = 0; j < n; j++) {
      final c = txt.codeUnitAt(j);
      if (!s1 && !s2 && !tpl) {
        if (c == 47 && j + 1 < n && txt.codeUnitAt(j + 1) == 47) break; // //
        if (c == 39)  { s1  = true; continue; } // '
        if (c == 34)  { s2  = true; continue; } // "
        if (c == 96)  { tpl = true; continue; } // `
        if (c == 123 || c == 40) {               // { (
          if (_blkStack.length < 1024) { _blkStack.add(lineNum); _blkStack.add(c); }
          continue;
        }
        if (c == 125 || c == 41) {               // } )
          final want = c == 125 ? 123 : 40;
          for (int k = _blkStack.length - 2; k >= 0; k -= 2) {
            if (_blkStack[k + 1] == want) {
              final sl = _blkStack[k];
              if (lineNum > sl) { _blkPairs.add(sl); _blkPairs.add(lineNum); }
              _blkStack.removeRange(k, _blkStack.length);
              break;
            }
          }
        }
      } else {
        final prev = j > 0 ? txt.codeUnitAt(j - 1) : 0;
        if (s1  && c == 39 && prev != 92) { s1  = false; }
        if (s2  && c == 34 && prev != 92) { s2  = false; }
        if (tpl && c == 96)               { tpl = false; }
      }
    }
  }

  /// Called when `_blkLine >= _jobTotal`.  Handles unclosed openers, builds
  /// the sorted CodeBlock list, validates, and pushes updated styles.
  void _blkFinalize(Content content) {
    final last = content.lineCount - 1;
    // Unmatched openers end at last line (Python/Dart open blocks).
    for (int k = 0; k < _blkStack.length; k += 2) {
      final sl = _blkStack[k];
      if (last > sl) { _blkPairs.add(sl); _blkPairs.add(last); }
    }
    _blkStack.clear();

    if (_blkPairs.isEmpty) {
      _currentBlocks = const [];
    } else {
      final raw = <CodeBlock>[];
      for (int i = 0; i < _blkPairs.length; i += 2) {
        final sl = _blkPairs[i];
        final el = _blkPairs[i + 1];
        // Compute indent level from the opener line.
        final txt = content.getLineText(sl);
        int spaces = 0;
        for (int j = 0; j < txt.length; j++) {
          final c = txt.codeUnitAt(j);
          if (c == 32) spaces++;
          else if (c == 9) spaces += _blkTab;
          else break;
        }
        raw.add(CodeBlock(
          startLine: sl,
          endLine:   el,
          indent:    spaces ~/ _blkTab,
        ));
      }
      _blkPairs.clear();
      raw.sort((a, b) {
        final c = a.startLine.compareTo(b.startLine);
        return c != 0 ? c : b.lineCount.compareTo(a.lineCount);
      });
      _currentBlocks = raw;
    }

    _validateBlocks(content);
    final cur = _partialSpans ?? styles.spans;
    pushStyles(Styles(
      spans:      List<List<CodeSpan>>.unmodifiable(cur),
      codeBlocks: _currentBlocks,
    ));
  }

  void _scheduleFrame() {
    if (_frameScheduled || _destroyed) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFrame, rescheduling: false);
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void notifyVisibleRange(int firstLine, int lastLine) {
    _visibleFirst = firstLine;
    _visibleLast  = lastLine;
    // If a full-file job is running there may be untokenized visible lines —
    // schedule a frame so they are tokenized at the next opportunity.
    if (_jobIsFull && _jobTotal > 0 && _jobVersion == _currentVersion) {
      _scheduleFrame();
    }
  }

  void _onFrame(Duration _) {
    _frameScheduled = false;
    if (_destroyed) return;
    final content = _content;
    if (content == null || _jobVersion != _currentVersion) return;

    final buf = _partialSpans;
    if (buf == null || buf.length != _jobTotal) return;

    final sw = Stopwatch()..start();

    if (_jobIsFull) {
      // ── Full-file scan (large file init / full reparse) ─────────────────
      // Phase 1 (3 ms): visible range first — lines on-screen get colours
      // immediately before the sequential scan has reached them.
      final vF = _visibleFirst.clamp(0, _jobTotal - 1);
      final vL = _visibleLast.clamp(0, _jobTotal - 1);
      for (int vi = vF; vi <= vL && sw.elapsedMilliseconds < 3; vi++) {
        if (buf[vi].isNotEmpty) continue;
        final txt = content.getLineText(vi);
        buf[vi] = _tokenizeLineRust(txt) ?? language.tokenize([txt]).firstOrNull ?? const <CodeSpan>[];
      }
      // Phase 2 (next 3 ms): sequential tokenization from _jobNext.
      while (_jobNext < _jobTotal && sw.elapsedMilliseconds < 6) {
        if (buf[_jobNext].isEmpty) {
          final txt = content.getLineText(_jobNext);
          buf[_jobNext] = _tokenizeLineRust(txt) ?? language.tokenize([txt]).firstOrNull ?? const <CodeSpan>[];
        }
        _jobNext++;
      }
      // Phase 3 (next 3 ms): progressive block scan — advances independently
      // so fold arrows appear as matching braces are discovered.
      while (_blkLine < _jobTotal && sw.elapsedMilliseconds < 9) {
        _blkProcessLine(content.getLineText(_blkLine), _blkLine);
        _blkLine++;
      }
      pushStyles(Styles(
        spans:      List<List<CodeSpan>>.unmodifiable(buf),
        codeBlocks: _currentBlocks, // updated by _blkFinalize when scan ends
      ));
      final tokDone = _jobNext >= _jobTotal;
      final blkDone = _blkLine >= _jobTotal;
      if (tokDone && blkDone) {
        _blkFinalize(content);   // pushes final styles with all blocks
        onTokenizationComplete?.call();
      } else {
        _scheduleFrame();
      }
    } else {
      // ── Incremental scan (keystroke convergence) ─────────────────────────
      int  i    = _jobNext;
      bool done = false;

      while (i < _jobTotal) {
        final txt     = content.getLineText(i);
        final oldLast = buf[i].isNotEmpty ? buf[i].last.type.index : -1;
        // Use Rust tokenizer for single-line incremental updates (UI thread safe,
        // ~0.05ms vs ~0.3ms Dart regex). Falls back to Dart if unavailable.
        final spans = _tokenizeLineRust(txt) ?? language.tokenize([txt]).firstOrNull ?? const <CodeSpan>[];
        buf[i] = spans;
        final newLast = spans.isNotEmpty ? spans.last.type.index : -1;
        if (i > _jobStart && newLast == oldLast) { done = true; i++; break; }
        i++;
        if (sw.elapsedMilliseconds >= 6) break;
      }

      _jobNext = i;
      if (done || i >= _jobTotal) {
        pushStyles(Styles(
          spans:      List<List<CodeSpan>>.unmodifiable(buf),
          codeBlocks: _currentBlocks,
        ));
        onTokenizationComplete?.call();
      } else {
        pushStyles(Styles(
          spans:      List<List<CodeSpan>>.unmodifiable(buf),
          codeBlocks: _currentBlocks,
        ));
        _scheduleFrame();
      }
    }
  }

  void _dispatchIncremental(Content content, int editLine) {
    if (_destroyed) return;
    final version   = ++_currentVersion;
    final lineCount = content.lineCount;

    _partialSpans ??= List<List<CodeSpan>>.filled(lineCount, const [], growable: false);
    if (_partialSpans!.length != lineCount) {
      _partialSpans = List<List<CodeSpan>>.filled(lineCount, const [], growable: false);
    }

    final start  = lineCount > 0 ? editLine.clamp(0, lineCount - 1) : 0;
    _jobIsFull   = false;
    _jobTotal    = lineCount;
    _jobVersion  = version;
    _jobNext     = start;
    _jobStart    = start;
    _scheduleFrame();
  }

  // ── init ──────────────────────────────────────────────────────────────────

  @override
  void init(Content content) {
    _content = content;
    final lineCount = content.lineCount;
    final version   = ++_currentVersion;

    final visN     = _kVisible.clamp(0, lineCount);
    final allSpans = List<List<CodeSpan>>.filled(lineCount, const [], growable: false);
    if (visN > 0) {
      final vis = language.tokenize(List<String>.generate(visN, content.getLineText));
      for (int i = 0; i < visN; i++) allSpans[i] = vis[i];
    }
    _partialSpans = allSpans;
    // Synchronous initial block extraction via Rust (zero UI jank).
    // The isolate will deliver authoritative blocks later — this gives
    // fold arrows on the FIRST frame instead of waiting ~400ms.
    _currentBlocks = QuillNative.extractBlocks(content) ?? _extractCodeBlocksUI(content);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_destroyed || _currentVersion != version) return;
      pushStyles(Styles(
        spans:      List<List<CodeSpan>>.unmodifiable(allSpans),
        codeBlocks: _currentBlocks,
      ));
    });

    // Full tokenisation via isolate (small files) or frame-budget (large files).
    // Call tokenize() directly (not _dispatchFull) so we don't double-increment
    // _currentVersion — the frame callback above uses `version`.
    if (lineCount > 0) {
      if (lineCount > _kMaxIsoLines) {
        // Large file: skip isolate — use frame-budget starting just after the
        // already-tokenised visible block so we never freeze the main thread.
        // Block scan always starts from line 0 to ensure correct brace matching.
        _jobIsFull  = true;
        _jobTotal   = lineCount;
        _jobVersion = version;
        _jobNext    = visN;
        _jobStart   = visN;
        _initBlkScan(content); // starts from line 0 regardless of visN
        _scheduleFrame();
      } else {
        _jobIsFull  = false;
        final lines = List<String>.generate(lineCount, content.getLineText);
        _getOrCreateIso().tokenize(lines, version);
      }
    }
  }

  // ── onContentChanged ──────────────────────────────────────────────────────

  @override
  void onContentChanged(ContentChangeEvent event, Content content) {
    _content = content;
    final bool isStructural = event.text.contains('\n');

    if (!isStructural) {
      // ── Fast path: single-line edit ──────────────────────────────────────
      final line      = event.affectedLine;
      final lineCount = content.lineCount;
      if (line >= 0 && line < lineCount) {
        final current = _partialSpans ?? styles.spans;
        final patched = (current.length == lineCount)
            ? List<List<CodeSpan>>.of(current)
            : List<List<CodeSpan>>.filled(lineCount, const [], growable: false);
        final lineText = content.getLineText(line);
        patched[line]  = lineText.isEmpty
            ? const <CodeSpan>[]
            : language.tokenize([lineText]).firstOrNull ?? const <CodeSpan>[];
        _partialSpans  = patched;

        // Block re-scan: if the edited text or the current line contains
        // a block-structural char, re-extract blocks in the next frame.
        // This makes fold arrows appear/disappear in ~16 ms (Bug B fix).
        if (_hasStructuralChar(event.text) ||
            _hasStructuralChar(content.getLineText(line))) {
          // Synchronously validate (removes stale blocks whose } was deleted)
          // BEFORE pushStyles so the fold arrow disappears in THIS frame.
          // Then schedule the full rescan to detect newly-complete blocks.
          _validateBlocks(content);
          _scheduleBlockRescan();
        } else {
          _validateBlocks(content);
        }

        pushStyles(Styles(
          spans:      List<List<CodeSpan>>.unmodifiable(patched),
          codeBlocks: _currentBlocks,
        ));
      }
      _lastEditLine = event.affectedLine;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(
        _debounce(content.lineCount),
        () => _dispatchIncremental(content, _lastEditLine),
      );
      return;
    }

    // ── Structural change (Enter / paste / multi-line delete) ─────────────
    final line      = event.affectedLine;
    final lineCount = content.lineCount;
    final current   = _partialSpans ?? styles.spans;
    final oldCount  = current.length;
    final patched   = List<List<CodeSpan>>.of(current);

    if (lineCount > oldCount) {
      final added = lineCount - oldCount;
      for (int k = 0; k < added; k++) {
        patched.insert((line + 1 + k).clamp(0, patched.length), const <CodeSpan>[]);
      }
    } else if (lineCount < oldCount) {
      final removed = oldCount - lineCount;
      for (int k = 0; k < removed; k++) {
        final at = (line + 1).clamp(0, patched.length - 1);
        if (patched.length > 1) patched.removeAt(at);
      }
    }
    while (patched.length > lineCount) patched.removeLast();
    while (patched.length < lineCount) patched.add(const <CodeSpan>[]);

    if (line >= 0 && line < lineCount) {
      final lineText = content.getLineText(line);
      patched[line]  = lineText.isEmpty
          ? const <CodeSpan>[]
          : language.tokenize([lineText]).firstOrNull ?? const <CodeSpan>[];
    }

    _partialSpans  = patched;
    _currentBlocks = _shiftCodeBlocks(_currentBlocks, line, lineCount, oldCount, event.position.column);
    // Structural edit always warrants a block re-scan (Enter may split a block).
    _scheduleBlockRescan();
    pushStyles(Styles(
      spans:      List<List<CodeSpan>>.unmodifiable(patched),
      codeBlocks: _currentBlocks,
    ));

    _debounceTimer?.cancel();
    _lastEditLine = line;
    _debounceTimer = Timer(
      _debounce(lineCount),
      () => _dispatchFull(content),
    );
  }

  // ── reanalyze ─────────────────────────────────────────────────────────────

  @override
  void reanalyze(Content content) {
    _content = content;
    _debounceTimer?.cancel();
    _dispatchFull(content);
  }

  // ── Block validation ──────────────────────────────────────────────────────

  /// O(blocks) — removes blocks whose opener or closer is no longer present.
  /// Used for non-structural edits that don't affect block chars.
  void _validateBlocks(Content content) {
    if (_currentBlocks.isEmpty) return;
    // Try Rust path first
    final rustResult = QuillNative.validateBlocks(content, _currentBlocks);
    if (rustResult != null) { _currentBlocks = rustResult; return; }
    // Dart fallback
    final total = content.lineCount;
    final kept  = <CodeBlock>[];

    for (final b in _currentBlocks) {
      if (b.startLine < 0 || b.startLine >= total) continue;
      if (b.endLine   < 0 || b.endLine   >= total) continue;
      if (b.endLine <= b.startLine) continue;

      final startText = content.getLineText(b.startLine);
      final endText   = content.getLineText(b.endLine);

      // A block is valid when its opener char EXISTS ANYWHERE on startLine
      // (not just at end — "{" can appear mid-line e.g. "if (x) {").
      // Matches the logic in _extractCodeBlocksUI which pushes { or ( at any column.
      bool hasOpener = false;
      bool inStr1 = false, inStr2 = false;
      for (int ci = 0; ci < startText.length; ci++) {
        final c = startText.codeUnitAt(ci);
        // Skip line comments
        if (!inStr1 && !inStr2 && c == 47 && ci + 1 < startText.length && startText.codeUnitAt(ci+1) == 47) break;
        if (!inStr1 && !inStr2) {
          if      (c == 39) inStr1 = true;
          else if (c == 34) inStr2 = true;
          else if (c == 123 || c == 40) { hasOpener = true; break; }
        } else {
          if (inStr1 && c == 39 && (ci == 0 || startText.codeUnitAt(ci-1) != 92)) inStr1 = false;
          if (inStr2 && c == 34 && (ci == 0 || startText.codeUnitAt(ci-1) != 92)) inStr2 = false;
        }
      }
      // Also allow colon at end-of-line (Python/YAML/Dart labels style)
      if (!hasOpener) {
        final tr = startText.trimRight();
        if (tr.isNotEmpty && tr.codeUnitAt(tr.length - 1) == 58) hasOpener = true;
      }
      if (!hasOpener) continue;

      // For brace/paren blocks: the endLine must have the closer as first non-whitespace char.
      // (colon-blocks have no closer requirement)
      bool needsCloserCheck = false;
      int  expectedCloser   = 0;
      // Determine which opener was found — find last { or ( on startLine (outermost pairing)
      for (int ci = startText.length - 1; ci >= 0; ci--) {
        final c = startText.codeUnitAt(ci);
        if (c == 123) { needsCloserCheck = true; expectedCloser = 125; break; }
        if (c == 40)  { needsCloserCheck = true; expectedCloser = 41;  break; }
      }

      if (needsCloserCheck) {
        // endLine MUST have the closer as its first non-whitespace char.
        // If the user deleted } this check fails and the fold arrow disappears.
        final trimmedEnd = endText.trimLeft();
        if (trimmedEnd.isEmpty) continue;
        if (trimmedEnd.codeUnitAt(0) != expectedCloser) continue;
      }

      kept.add(b);
    }

    if (kept.length != _currentBlocks.length) _currentBlocks = kept;
  }

  // ── Block shift ───────────────────────────────────────────────────────────

  /// Bug 2 fix: [editColumn] aligns the block-shift threshold with
  /// _shiftLineSets' insertPivot logic:
  ///   col = 0  → opener on editLine is pushed to editLine+1, so shift >= editLine
  ///   col > 0  → opener stays on editLine, so only shift > editLine
  static List<CodeBlock> _shiftCodeBlocks(
      List<CodeBlock> blocks, int editLine, int newCount, int oldCount,
      [int editColumn = 1]) {
    if (blocks.isEmpty || newCount == oldCount) return blocks;
    final delta  = newCount - oldCount;
    // For a col-0 insert the opener on editLine itself moves down, so we use
    // threshold = editLine-1 (i.e. >=editLine shifts). For col>0 the opener
    // stays on editLine so threshold = editLine (only >editLine shifts).
    final insertThreshold = (delta > 0 && editColumn == 0) ? editLine - 1 : editLine;
    final result = <CodeBlock>[];
    for (final b in blocks) {
      if (delta < 0) {
        // Delete: remove blocks inside the deleted range, shift the rest down.
        final delStart = editLine + 1;
        final delEnd   = editLine + (-delta);
        if (b.startLine >= delStart && b.startLine <= delEnd) continue;
        final ns = b.startLine > delEnd ? b.startLine + delta : b.startLine;
        final ne = b.endLine   > delEnd ? b.endLine   + delta : b.endLine;
        if (ne < ns) continue;
        result.add(CodeBlock(startLine: ns, endLine: ne, indent: b.indent));
      } else {
        // Insert: shift blocks beyond the threshold.
        final ns = b.startLine > insertThreshold ? b.startLine + delta : b.startLine;
        final ne = b.endLine   > insertThreshold ? b.endLine   + delta : b.endLine;
        result.add(CodeBlock(startLine: ns, endLine: ne, indent: b.indent));
      }
    }
    return result;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void destroy() {
    _destroyed = true;
    _debounceTimer?.cancel();
    _iso?.destroy();
    _iso                = null;
    _jobTotal           = 0;
    _jobIsFull          = false;
    _partialSpans       = null;
    _blockRescanPending = false;
    _blkStack.clear();
    _blkPairs.clear();
  }

  Duration _debounce(int n) {
    if (n <  2000) return const Duration(milliseconds: 80);
    if (n <  5000) return const Duration(milliseconds: 160);
    if (n < 10000) return const Duration(milliseconds: 280);
    return const Duration(milliseconds: 400);
  }
}
