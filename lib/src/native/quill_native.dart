// lib/src/native/quill_native.dart
//
// Dart FFI bindings for the Rust performance helpers in libquill_ts.so.
//
// ALL functions gracefully degrade to null/false when the native library is
// unavailable (simulator, desktop test, or old APK without the .so).
//
// Usage:
//   final ok = QuillNative.isAvailable;
//   if (ok) {
//     final blocks = QuillNative.extractBlocks(content);
//     final matches = QuillNative.searchLiteral(text, pattern, caseSensitive, wholeWord);
//   }

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../text/content.dart';
import '../text/text_range.dart';
import '../core/char_position.dart';
import '../highlighting/code_block.dart';

// ── Native function typedefs ──────────────────────────────────────────────────

typedef _ExtractBlocksNative = Int32 Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Int32, Pointer<Int32>, Int32);
typedef _ExtractBlocksDart = int Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, int, Pointer<Int32>, int);

typedef _SearchNative = Int32 Function(
    Pointer<Uint8>, Int32, Pointer<Uint8>, Int32, Int32, Pointer<Int32>, Int32);
typedef _SearchDart = int Function(
    Pointer<Uint8>, int, Pointer<Uint8>, int, int, Pointer<Int32>, int);

typedef _BuildLineStartsNative = Int32 Function(
    Pointer<Uint8>, Int32, Pointer<Int32>, Int32);
typedef _BuildLineStartsDart = int Function(
    Pointer<Uint8>, int, Pointer<Int32>, int);

typedef _MaxLineLengthNative = Int32 Function(Pointer<Int32>, Int32);
typedef _MaxLineLengthDart   = int Function(Pointer<Int32>, int);

typedef _BracketMatchNative = Int32 Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Int32, Int32, Int32, Pointer<Int32>);
typedef _BracketMatchDart = int Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, int, int, int, Pointer<Int32>);

typedef _FulltextJoinNative = Int32 Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Int32, Pointer<Uint8>, Int32);
typedef _FulltextJoinDart = int Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, int, Pointer<Uint8>, int);

typedef _TokenizeLineNative = Int32 Function(
    Pointer<Uint8>, Int32, Pointer<Uint8>, Int32, Pointer<Uint32>, Int32);
typedef _TokenizeLineDart = int Function(
    Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint32>, int);

typedef _SymbolScanNative = Int32 Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Int32, Pointer<Int32>, Int32);
typedef _SymbolScanDart = int Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, int, Pointer<Int32>, int);

typedef _HasStructCharNative = Int32 Function(Pointer<Uint8>, Int32);
typedef _HasStructCharDart   = int Function(Pointer<Uint8>, int);

typedef _StripFoldNative = Int32 Function(Pointer<Uint8>, Int32, Pointer<Uint8>, Int32);
typedef _StripFoldDart   = int Function(Pointer<Uint8>, int, Pointer<Uint8>, int);

typedef _ValidateBlocksNative = Int32 Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Int32, Pointer<Int32>, Int32);
typedef _ValidateBlocksDart = int Function(
    Pointer<Pointer<Uint8>>, Pointer<Int32>, int, Pointer<Int32>, int);

typedef _IndentAdvanceNative = Int32 Function(Pointer<Uint8>, Int32);
typedef _IndentAdvanceDart   = int Function(Pointer<Uint8>, int);

typedef _PosToOffsetNative = Int32 Function(Pointer<Int32>, Int32, Int32, Int32);
typedef _PosToOffsetDart   = int Function(Pointer<Int32>, int, int, int);

typedef _OffsetToPosNative = Int32 Function(
    Pointer<Int32>, Int32, Int32, Pointer<Int32>, Pointer<Int32>);
typedef _OffsetToPosDart = int Function(
    Pointer<Int32>, int, int, Pointer<Int32>, Pointer<Int32>);

// ── QuillNative singleton ─────────────────────────────────────────────────────

class QuillNative {
  QuillNative._();

  static QuillNative? _instance;
  static QuillNative get _i => _instance ??= QuillNative._().._init();

  bool _available = false;
  static bool get isAvailable => _i._available;

  /// Call once at app startup (e.g. in main() before runApp) to warm up
  /// the native library. Without this, the first call pays the DynamicLibrary
  /// load cost. Safe to call multiple times.
  static void warmup() => _i;

  /// Raw FFI function pointer for quill_tokenize_line.
  /// Used by IncrementalAnalyzeManager for zero-overhead per-line tokenization.
  static _TokenizeLineDart? get tokenizeLineRaw => _i._tokenizeLine; // triggers _init() via lazy getter

  _ExtractBlocksDart?   _extractBlocks;
  _SearchDart?          _search;
  _BuildLineStartsDart? _buildLineStarts;
  _MaxLineLengthDart?   _maxLineLength;
  _BracketMatchDart?    _bracketMatch;
  _FulltextJoinDart?    _fulltextJoin;
  _TokenizeLineDart?    _tokenizeLine;
  _SymbolScanDart?      _symbolScan;
  _HasStructCharDart?   _hasStructChar;
  _StripFoldDart?       _stripFold;
  _ValidateBlocksDart?  _validateBlocks;
  _IndentAdvanceDart?   _indentAdvance;
  _PosToOffsetDart?     _posToOffset;
  _OffsetToPosDart?     _offsetToPos;

  void _init() {
    try {
      final DynamicLibrary lib = Platform.isAndroid
          ? DynamicLibrary.open('libquill_perf.so')
          : DynamicLibrary.process();

      _extractBlocks = lib.lookupFunction<_ExtractBlocksNative, _ExtractBlocksDart>(
          'quill_extract_blocks');
      _search = lib.lookupFunction<_SearchNative, _SearchDart>(
          'quill_search');
      _buildLineStarts = lib.lookupFunction<_BuildLineStartsNative, _BuildLineStartsDart>(
          'quill_build_line_starts');
      _maxLineLength = lib.lookupFunction<_MaxLineLengthNative, _MaxLineLengthDart>(
          'quill_max_line_length');
      _bracketMatch = lib.lookupFunction<_BracketMatchNative, _BracketMatchDart>(
          'quill_bracket_match');
      _fulltextJoin = lib.lookupFunction<_FulltextJoinNative, _FulltextJoinDart>(
          'quill_fulltext_join');
      _tokenizeLine = lib.lookupFunction<_TokenizeLineNative, _TokenizeLineDart>(
          'quill_tokenize_line');
      _symbolScan = lib.lookupFunction<_SymbolScanNative, _SymbolScanDart>(
          'quill_symbol_scan');

      _hasStructChar = lib.lookupFunction<_HasStructCharNative, _HasStructCharDart>(
          'quill_has_structural_char');
      _stripFold = lib.lookupFunction<_StripFoldNative, _StripFoldDart>(
          'quill_strip_fold_opener');
      _validateBlocks = lib.lookupFunction<_ValidateBlocksNative, _ValidateBlocksDart>(
          'quill_validate_blocks');
      _indentAdvance = lib.lookupFunction<_IndentAdvanceNative, _IndentAdvanceDart>(
          'quill_indent_advance');
      _posToOffset = lib.lookupFunction<_PosToOffsetNative, _PosToOffsetDart>(
          'quill_pos_to_offset');
      _offsetToPos = lib.lookupFunction<_OffsetToPosNative, _OffsetToPosDart>(
          'quill_offset_to_pos');

      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  // ── extractBlocks ───────────────────────────────────────────────────────────
  // Rust port of _extractCodeBlocksUI: O(n) scan, no heap alloc on hot path.
  // Returns null if unavailable.
  static List<CodeBlock>? extractBlocks(Content content) {
    final inst = _i;
    if (!inst._available || inst._extractBlocks == null) return null;

    final n = content.lineCount;
    if (n == 0) return const [];

    // Allocate line pointer + length arrays once using ffi arena
    final arena = Arena();
    try {
      final ptrs    = arena<Pointer<Uint8>>(n);
      final lengths = arena<Int32>(n);

      // Copy each line into a native buffer and record its pointer + length.
      // We use a single contiguous buffer for all line bytes to minimise allocs.
      // Max total bytes: n * ~80 chars typical = well within a few KB.
      //
      // NOTE: we pin the strings via Utf8 native allocs in the arena.
      // Each alloc is freed when the arena is released at function exit.
      for (int i = 0; i < n; i++) {
        final txt = content.getLineText(i);
        final encoded = txt.toNativeUtf8(allocator: arena);
        ptrs[i] = encoded.cast<Uint8>();
        lengths[i] = txt.length; // byte count ≈ char count for ASCII-heavy code
      }

      // Output buffer: up to 1024 blocks × 3 ints = 3072 ints
      const maxBlocks = 1024;
      final outBuf = arena<Int32>(maxBlocks * 3);

      final count = inst._extractBlocks!(
          ptrs.cast(), lengths, n, outBuf, maxBlocks * 3);

      if (count < 0) return null;

      final blocks = <CodeBlock>[];
      for (int i = 0; i < count; i++) {
        blocks.add(CodeBlock(
          startLine: outBuf[i * 3],
          endLine:   outBuf[i * 3 + 1],
          indent:    outBuf[i * 3 + 2],
        ));
      }
      return blocks;
    } finally {
      arena.releaseAll();
    }
  }

  // ── searchLiteral ───────────────────────────────────────────────────────────
  // Rust literal/whole-word search: faster than Dart RegExp for large files.
  // Returns null if unavailable or pattern is too long (use Dart regex then).
  static List<EditorRange>? searchLiteral(
    String text,
    String pattern, {
    bool caseSensitive = true,
    bool wholeWord     = false,
    required List<int> lineStarts,
  }) {
    final inst = _i;
    if (!inst._available || inst._search == null) return null;
    if (pattern.isEmpty) return const [];

    final arena = Arena();
    try {
      // Convert to native UTF-8
      final textN    = text.toNativeUtf8(allocator: arena);
      final patternN = pattern.toNativeUtf8(allocator: arena);

      // Flags: bit 0 = case sensitive, bit 1 = whole word
      final flags = (caseSensitive ? 1 : 0) | (wholeWord ? 2 : 0);

      // Output buffer: up to 8192 matches × 2 ints
      const maxMatches = 8192;
      final outBuf = arena<Int32>(maxMatches * 2);

      final count = inst._search!(
          textN.cast<Uint8>(), text.length,
          patternN.cast<Uint8>(), pattern.length,
          flags,
          outBuf, maxMatches * 2);

      if (count < 0) return null;

      // Convert byte offsets → (line, col) using pre-built lineStarts
      final results = <EditorRange>[];
      final actualCount = count < maxMatches ? count : maxMatches;

      for (int i = 0; i < actualCount; i++) {
        final startOff = outBuf[i * 2];
        final endOff   = outBuf[i * 2 + 1];

        final startPos = _offsetToPosFromStarts(startOff, lineStarts);
        final endPos   = _offsetToPosFromStarts(endOff,   lineStarts);
        results.add(EditorRange(startPos, endPos));
      }
      return results;
    } finally {
      arena.releaseAll();
    }
  }

  /// Build line-start offset table from document text.
  /// Call once per search query. Returns a plain Dart Int32List.
  static Int32List buildLineStarts(String text) {
    final inst = _i;
    if (!inst._available || inst._buildLineStarts == null) {
      // Dart fallback
      final starts = <int>[0];
      for (int i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) starts.add(i + 1);
      }
      return Int32List.fromList(starts);
    }

    final arena = Arena();
    try {
      final textN  = text.toNativeUtf8(allocator: arena);
      final lineCount = text.length; // upper bound (at most one per char)
      final outBuf = arena<Int32>(lineCount + 2);

      final count = inst._buildLineStarts!(
          textN.cast<Uint8>(), text.length, outBuf, lineCount + 2);

      if (count < 0) {
        // fallback
        final starts = <int>[0];
        for (int i = 0; i < text.length; i++) {
          if (text.codeUnitAt(i) == 10) starts.add(i + 1);
        }
        return Int32List.fromList(starts);
      }

      final result = Int32List(count);
      for (int i = 0; i < count; i++) result[i] = outBuf[i];
      return result;
    } finally {
      arena.releaseAll();
    }
  }

  // ── bracketMatch ──────────────────────────────────────────────────────────
  /// Finds the matching bracket for cursor at (cursorLine, cursorCol).
  /// Returns [openLine, openCol, closeLine, closeCol] or null if no bracket/match.
  static List<int>? bracketMatch(Content content, int cursorLine, int cursorCol) {
    final inst = _i;
    if (!inst._available || inst._bracketMatch == null) return null;
    final n = content.lineCount;
    if (n == 0) return null;
    final arena = Arena();
    try {
      final ptrs = arena<Pointer<Uint8>>(n);
      final lens = arena<Int32>(n);
      for (int i = 0; i < n; i++) {
        final txt = content.getLineText(i);
        final enc = txt.toNativeUtf8(allocator: arena);
        ptrs[i] = enc.cast<Uint8>();
        lens[i] = txt.length;
      }
      final out = arena<Int32>(4);
      final r = inst._bracketMatch!(ptrs.cast(), lens, n, cursorLine, cursorCol, out);
      if (r != 1) return null;
      return [out[0], out[1], out[2], out[3]];
    } finally { arena.releaseAll(); }
  }

  // ── fulltextJoin ───────────────────────────────────────────────────────────
  /// Joins all document lines into a single String using Rust memcpy.
  /// Faster than Dart StringBuffer for large files.
  /// Returns null if unavailable; caller falls back to Content.fullText.
  static String? fulltextJoin(Content content) {
    final inst = _i;
    if (!inst._available || inst._fulltextJoin == null) return null;
    final n = content.lineCount;
    if (n == 0) return '';
    // Estimate total bytes: sum of line lengths + n-1 newlines
    // We overestimate slightly to avoid realloc.
    int totalBytes = n - 1; // newlines
    for (int i = 0; i < n; i++) totalBytes += content.getLineLength(i);
    final arena = Arena();
    try {
      final ptrs = arena<Pointer<Uint8>>(n);
      final lens = arena<Int32>(n);
      for (int i = 0; i < n; i++) {
        final txt = content.getLineText(i);
        final enc = txt.toNativeUtf8(allocator: arena);
        ptrs[i] = enc.cast<Uint8>();
        lens[i] = txt.length;
      }
      final buf = arena<Uint8>(totalBytes + 4);
      final written = inst._fulltextJoin!(ptrs.cast(), lens, n, buf, totalBytes + 4);
      if (written < 0) return null;
      // Convert raw UTF-8 bytes to Dart String
      final bytes = Uint8List.view(buf.cast<Uint8>().asTypedList(written).buffer, 0, written);
      return String.fromCharCodes(bytes);
    } finally { arena.releaseAll(); }
  }

  // ── symbolScan ─────────────────────────────────────────────────────────────
  /// Scans document for class/func/var declarations.
  /// Returns list of [line, col_start, col_end, kind] quads.
  /// kind: 0=class 1=mixin 2=extension 3=enum 4=function 5=variable
  static List<List<int>>? symbolScan(Content content) {
    final inst = _i;
    if (!inst._available || inst._symbolScan == null) return null;
    final n = content.lineCount;
    if (n == 0) return const [];
    final arena = Arena();
    try {
      final ptrs = arena<Pointer<Uint8>>(n);
      final lens = arena<Int32>(n);
      for (int i = 0; i < n; i++) {
        final txt = content.getLineText(i);
        final enc = txt.toNativeUtf8(allocator: arena);
        ptrs[i] = enc.cast<Uint8>();
        lens[i] = txt.length;
      }
      const maxSym = 2048;
      final out = arena<Int32>(maxSym * 4);
      final count = inst._symbolScan!(ptrs.cast(), lens, n, out, maxSym * 4);
      if (count < 0) return null;
      final result = <List<int>>[];
      for (int i = 0; i < count; i++) {
        result.add([out[i*4], out[i*4+1], out[i*4+2], out[i*4+3]]);
      }
      return result;
    } finally { arena.releaseAll(); }
  }

  // ── hasStructuralChar ─────────────────────────────────────────────────────
  static bool hasStructuralChar(String text) {
    final inst = _i;
    if (!inst._available || inst._hasStructChar == null) {
      // Dart fallback
      for (int i = 0; i < text.length; i++) {
        final c = text.codeUnitAt(i);
        if (c == 123 || c == 125 || c == 40 || c == 41) return true;
      }
      final tr = text.trimRight();
      return tr.isNotEmpty && tr.codeUnitAt(tr.length - 1) == 58;
    }
    final arena = Arena();
    try {
      final p = text.toNativeUtf8(allocator: arena);
      return inst._hasStructChar!(p.cast<Uint8>(), text.length) == 1;
    } finally { arena.releaseAll(); }
  }

  // ── stripFoldOpener ────────────────────────────────────────────────────────
  static String? stripFoldOpener(String text) {
    final inst = _i;
    if (!inst._available || inst._stripFold == null) return null;
    final arena = Arena();
    try {
      final src = text.toNativeUtf8(allocator: arena);
      final buf = arena<Uint8>(text.length + 4);
      final n = inst._stripFold!(src.cast<Uint8>(), text.length, buf, text.length + 4);
      if (n < 0) return null;
      return String.fromCharCodes(buf.asTypedList(n));
    } finally { arena.releaseAll(); }
  }

  // ── validateBlocks ─────────────────────────────────────────────────────────
  /// Validates a list of CodeBlocks in-place via Rust.
  /// Returns null if native unavailable (caller uses Dart path).
  static List<CodeBlock>? validateBlocks(Content content, List<CodeBlock> blocks) {
    final inst = _i;
    if (!inst._available || inst._validateBlocks == null || blocks.isEmpty) return null;
    final n = content.lineCount;
    final arena = Arena();
    try {
      final ptrs = arena<Pointer<Uint8>>(n);
      final lens = arena<Int32>(n);
      for (int i = 0; i < n; i++) {
        final txt = content.getLineText(i);
        ptrs[i] = txt.toNativeUtf8(allocator: arena).cast<Uint8>();
        lens[i] = txt.length;
      }
      final bc = blocks.length;
      final buf = arena<Int32>(bc * 3);
      for (int i = 0; i < bc; i++) {
        buf[i * 3]     = blocks[i].startLine;
        buf[i * 3 + 1] = blocks[i].endLine;
        buf[i * 3 + 2] = blocks[i].indent;
      }
      final kept = inst._validateBlocks!(ptrs.cast(), lens, n, buf, bc);
      if (kept < 0) return null;
      return List.generate(kept, (i) => CodeBlock(
        startLine: buf[i * 3],
        endLine:   buf[i * 3 + 1],
        indent:    buf[i * 3 + 2],
      ));
    } finally { arena.releaseAll(); }
  }

  // ── indentAdvance ──────────────────────────────────────────────────────────
  static int indentAdvance(String lineText) {
    final inst = _i;
    if (!inst._available || inst._indentAdvance == null) return 0;
    final arena = Arena();
    try {
      final p = lineText.toNativeUtf8(allocator: arena);
      return inst._indentAdvance!(p.cast<Uint8>(), lineText.length);
    } finally { arena.releaseAll(); }
  }

  // ── posToOffset / offsetToPos ──────────────────────────────────────────────
  /// Convert (line, col) → byte offset. Needs pre-built line-lengths array.
  static int posToOffset(Int32List lineLengths, int line, int col) {
    final inst = _i;
    if (!inst._available || inst._posToOffset == null) return -1;
    final arena = Arena();
    try {
      final buf = arena<Int32>(lineLengths.length);
      for (int i = 0; i < lineLengths.length; i++) buf[i] = lineLengths[i];
      return inst._posToOffset!(buf, lineLengths.length, line, col);
    } finally { arena.releaseAll(); }
  }

  /// Convert byte offset → (line, col) CharPosition.
  static CharPosition? offsetToPos(Int32List lineLengths, int offset) {
    final inst = _i;
    if (!inst._available || inst._offsetToPos == null) return null;
    final arena = Arena();
    try {
      final buf  = arena<Int32>(lineLengths.length);
      for (int i = 0; i < lineLengths.length; i++) buf[i] = lineLengths[i];
      final outL = arena<Int32>(1);
      final outC = arena<Int32>(1);
      final r = inst._offsetToPos!(buf, lineLengths.length, offset, outL, outC);
      if (r != 0) return null;
      return CharPosition(outL[0], outC[0]);
    } finally { arena.releaseAll(); }
  }

  // ── Binary search helper: byte offset → CharPosition ─────────────────────
  static CharPosition _offsetToPosFromStarts(int offset, List<int> lineStarts) {
    int lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) lo = mid; else hi = mid - 1;
    }
    return CharPosition(lo, offset - lineStarts[lo]);
  }
}