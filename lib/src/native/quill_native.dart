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

// ── QuillNative singleton ─────────────────────────────────────────────────────

class QuillNative {
  QuillNative._();

  static QuillNative? _instance;
  static QuillNative get _i => _instance ??= QuillNative._().._init();

  bool _available = false;
  static bool get isAvailable => _i._available;

  _ExtractBlocksDart?   _extractBlocks;
  _SearchDart?          _search;
  _BuildLineStartsDart? _buildLineStarts;
  _MaxLineLengthDart?   _maxLineLength;

  void _init() {
    try {
      final DynamicLibrary lib = Platform.isAndroid
          ? DynamicLibrary.open('libquill_ts.so')
          : DynamicLibrary.process();

      _extractBlocks = lib.lookupFunction<_ExtractBlocksNative, _ExtractBlocksDart>(
          'quill_extract_blocks');
      _search = lib.lookupFunction<_SearchNative, _SearchDart>(
          'quill_search');
      _buildLineStarts = lib.lookupFunction<_BuildLineStartsNative, _BuildLineStartsDart>(
          'quill_build_line_starts');
      _maxLineLength = lib.lookupFunction<_MaxLineLengthNative, _MaxLineLengthDart>(
          'quill_max_line_length');

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

        final startPos = _offsetToPos(startOff, lineStarts);
        final endPos   = _offsetToPos(endOff,   lineStarts);
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

  // ── Binary search helper: byte offset → CharPosition ─────────────────────
  static CharPosition _offsetToPos(int offset, List<int> lineStarts) {
    int lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) lo = mid; else hi = mid - 1;
    }
    return CharPosition(lo, offset - lineStarts[lo]);
  }
}
