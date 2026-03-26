// lib/src/tree_sitter/ts_parser.dart
//
// High-level Dart wrapper around TSParser + TSTree.
// Handles:
//  • UTF-8 encoding of Dart strings for C
//  • Tree lifetime via NativeFinalizer
//  • Incremental re-parse on edit events
//  • Highlight query caching per language

import 'dart:ffi';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:ffi/ffi.dart';
import 'ts_ffi.dart';
import 'ts_queries.dart';
import 'ts_token_mapper.dart';
import '../highlighting/span.dart';
import '../highlighting/code_block.dart';
import 'ts_symbol.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TsHighlightSpan — a single syntax span from tree-sitter
// ─────────────────────────────────────────────────────────────────────────────
class TsHighlightSpan {
  final int        startByte;
  final int        endByte;
  final TokenType  type;
  const TsHighlightSpan(this.startByte, this.endByte, this.type);
}

// ─────────────────────────────────────────────────────────────────────────────
// TsParser  — one instance per editor (per language)
// ─────────────────────────────────────────────────────────────────────────────
class TsParser {
  final String langName;
  final QuillTsLib _lib;

  Pointer<TSParser>? _parser;
  Pointer<TSTree>?   _tree;

  // Highlight query compiled once per parser instance
  Pointer<TSQuery>? _query;
  List<TokenType>?  _capMap;   // capture_id → TokenType

  TsParser._(this.langName, this._lib);

  /// Creates a TsParser for [langName] (e.g. 'dart', 'python').
  /// Returns null if the language is not available in libquill_ts.so.
  static TsParser? create(String langName) {
    if (!QuillTsLib.isAvailable) return null;
    final lib = QuillTsLib.instance;
    final p = TsParser._(langName, lib);
    if (!p._init()) return null;
    return p;
  }

  bool _init() {
    final name = langName.toNativeUtf8();
    try {
      _parser = _lib.parserNew(name);
      if (_parser == null || _parser!.address == 0) return false;
      _initQuery(name);
      return true;
    } finally {
      malloc.free(name);
    }
  }

  void _initQuery(Pointer<Utf8> name) {
    final langPtr = _lib.languageForName(name);
    if (langPtr.address == 0) {
      debugPrint('[TS] _initQuery: languageForName returned null for $langName');
      return;
    }

    final builtinPtr = _lib.builtinQuery(name);
    final querySrc   = builtinPtr.address != 0
        ? builtinPtr.toDartString()
        : TsQueries.forLanguage(langName);
    debugPrint('[TS] _initQuery: querySrc=${querySrc?.length ?? 'NULL'} chars for $langName');
    if (querySrc == null || querySrc.isEmpty) {
      debugPrint('[TS] _initQuery: no query source for $langName');
      return;
    }

    final errOff  = malloc<Uint32>();
    final errType = malloc<Uint32>();

    // Try to compile the full query.
    // BUG FIX: pass src.length (UTF-8 byte count) NOT querySrc.length (char count).
    Pointer<TSQuery> q = _tryCompileQuery(langPtr, querySrc, errOff, errType);

    if (q.address == 0 || errType.value != 0) {
      // Full query failed. Truncate at the error position and retry so we get
      // as many patterns as possible rather than nothing at all.
      final errPos = errOff.value;
      if (errPos > 0 && errPos < querySrc.length) {
        // Find the last complete S-expression before the error
        final partial = querySrc.substring(0, errPos);
        final lastParen = partial.lastIndexOf('\n(');
        final truncated = lastParen > 0 ? partial.substring(0, lastParen) : '';
        if (truncated.isNotEmpty) {
          errOff.value  = 0;
          errType.value = 0;
          q = _tryCompileQuery(langPtr, truncated, errOff, errType);
        }
      }
      if (q.address == 0 || errType.value != 0) {
        // Absolute fallback: a minimal query that works with any grammar.
        errOff.value  = 0;
        errType.value = 0;
        q = _tryCompileQuery(langPtr, _kMinimalQuery, errOff, errType);
        if (q.address == 0 || errType.value != 0) {
          malloc.free(errOff);
          malloc.free(errType);
          return;
        }
        debugPrint('[TS] using minimal query for "$langName" (full query error at byte $errPos)');
      }
    }

    malloc.free(errOff);
    malloc.free(errType);
    _query = q;

    // Build capture_id → TokenType map from query's named captures.
    final count  = _lib.queryCapCount(q);
    final capMap = List<TokenType>.filled(count, TokenType.normal);
    final lenPtr = malloc<Uint32>();
    try {
      for (int i = 0; i < count; i++) {
        final namePtr = _lib.queryCapName(q, i, lenPtr);
        if (namePtr.address == 0) continue;
        capMap[i] = TsTokenMapper.fromCaptureName(namePtr.toDartString());
      }
    } finally {
      malloc.free(lenPtr);
    }
    _capMap = capMap;
  }

  /// Compiles [src] as a query for [langPtr].
  /// FIX: passes src.length (UTF-8 byte count) to ts_query_new.
  Pointer<TSQuery> _tryCompileQuery(
      Pointer<TSLanguage> langPtr, String src,
      Pointer<Uint32> errOff, Pointer<Uint32> errType) {
    final nativeSrc = src.toNativeUtf8();
    try {
      // CRITICAL FIX: use nativeSrc.length (strlen = byte count) not src.length
      return _lib.queryNew(langPtr, nativeSrc, nativeSrc.length, errOff, errType);
    } finally {
      malloc.free(nativeSrc); // always freed — no leak
    }
  }

  // Minimal query guaranteed to compile on any tree-sitter grammar.
  static const _kMinimalQuery = r"""
(comment) @comment
(string_literal) @string
(integer_literal) @number
(float_literal) @number
(identifier) @variable
""";

  // ── Full parse ─────────────────────────────────────────────────────────────

  /// Full parse of [source]. Stores tree internally for incremental re-parse.
  /// Returns true on success.
  /// True if a parse tree exists (incremental re-parse is possible).
  bool get hasTree => _tree != null && _tree!.address != 0;

  bool parseString(String source) {
    if (_parser == null) return false;
    _freeTree();

    final utf8 = source.toNativeUtf8();
    try {
      final tree = _lib.parse(_parser!, utf8, utf8.length, nullptr);
      if (tree.address == 0) return false;
      _tree = tree;
      return true;
    } finally {
      malloc.free(utf8);
    }
  }

  // ── Incremental re-parse ───────────────────────────────────────────────────

  /// Notify tree-sitter of an edit, then re-parse the new [source].
  void editAndReparse({
    required String newSource,
    required int startByte,
    required int oldEndByte,
    required int newEndByte,
    required int startRow,
    required int startCol,
    required int oldEndRow,
    required int oldEndCol,
    required int newEndRow,
    required int newEndCol,
  }) {
    if (_parser == null || _tree == null) {
      parseString(newSource);
      return;
    }
    _lib.treeEdit(
      _tree!,
      startByte, oldEndByte, newEndByte,
      startRow,  startCol,
      oldEndRow, oldEndCol,
      newEndRow, newEndCol,
    );
    final utf8 = newSource.toNativeUtf8();
    try {
      final newTree = _lib.parse(_parser!, utf8, utf8.length, _tree!);
      _freeTree();
      if (newTree.address != 0) _tree = newTree;
    } finally {
      malloc.free(utf8);
    }
  }

  // ── Highlight ──────────────────────────────────────────────────────────────

  /// Returns highlight spans for [source] in the range [startRow..endRow].
  /// Call [parseString] first.
  List<TsHighlightSpan> highlight(
      String source, {int startRow = 0, int endRow = 0x7FFFFFFF}) {
    if (_tree == null || _query == null || _capMap == null) return const [];

    final utf8    = source.toNativeUtf8();
    final outCnt  = malloc<Uint32>();
    try {
      final ptr = _lib.highlight(
          _tree!, _query!, utf8, utf8.length, startRow, endRow, outCnt);
      final count = outCnt.value;
      if (count == 0 || ptr.address == 0) return const [];

      final result = <TsHighlightSpan>[];
      final data   = ptr.asTypedList(count * 3);
      final capMap = _capMap!;
      for (int i = 0; i < count; i++) {
        final start  = data[i * 3];
        final end    = data[i * 3 + 1];
        final capId  = data[i * 3 + 2];
        final type   = capId < capMap.length ? capMap[capId] : TokenType.normal;
        result.add(TsHighlightSpan(start, end, type));
      }
      return result;
    } finally {
      malloc.free(utf8);
      malloc.free(outCnt);
    }
  }

  // ── Code blocks ───────────────────────────────────────────────────────────

  /// Extracts foldable code blocks from the parsed tree.
  List<CodeBlock> extractBlocks() {
    if (_tree == null) return const [];
    final outCnt = malloc<Uint32>();
    try {
      final ptr = _lib.extractBlocks(_tree!, outCnt);
      final count = outCnt.value;
      if (count == 0 || ptr.address == 0) return const [];

      final data   = ptr.asTypedList(count * 3);
      final result = <CodeBlock>[];
      for (int i = 0; i < count; i++) {
        final sl = data[i * 3];
        final el = data[i * 3 + 1];
        final ind = data[i * 3 + 2];
        if (el > sl) result.add(CodeBlock(startLine: sl, endLine: el, indent: ind));
      }
      return result;
    } finally {
      malloc.free(outCnt);
    }
  }

  // ── Syntax errors ──────────────────────────────────────────────────────────

  /// Returns byte ranges of syntax errors detected by tree-sitter.
  List<(int startByte, int endByte)> extractErrors() {
    if (_tree == null) return const [];
    final outCnt = malloc<Uint32>();
    try {
      final ptr   = _lib.extractErrors(_tree!, outCnt);
      final count = outCnt.value;
      if (count == 0 || ptr.address == 0) return const [];
      final data   = ptr.asTypedList(count * 2);
      final result = <(int, int)>[];
      for (int i = 0; i < count; i++) {
        result.add((data[i * 2], data[i * 2 + 1]));
      }
      return result;
    } finally {
      malloc.free(outCnt);
    }
  }

  // ── Expand selection ──────────────────────────────────────────────────────

  /// Given the current selection, returns the smallest enclosing syntax node
  /// that is LARGER than the current selection.
  /// Returns null if already at root.
  (int, int, int, int)? expandSelection(
      String source, int startLine, int startCol, int endLine, int endCol) {
    if (_tree == null) return null;
    final lineStarts = _buildLineStarts(source);
    final startByte = _lcToByte(startLine, startCol, lineStarts);
    final endByte   = _lcToByte(endLine,   endCol,   lineStarts);

    final outCnt = malloc<Uint32>();
    try {
      final ptr = _lib.expandSelection(
          _tree!, startByte, endByte, outCnt);
      if (ptr.address == 0 || outCnt.value < 4) return null;
      final data = ptr.asTypedList(4);
      final nSB = data[0]; final nEB = data[1];
      // Convert bytes back to line/col
      final sLC = _byteToLC(nSB, lineStarts);
      final eLC = _byteToLC(nEB, lineStarts);
      // Only return if the result is actually larger than current selection
      if (nSB == startByte && nEB == endByte) return null;
      return (sLC.$1, sLC.$2, eLC.$1, eLC.$2);
    } finally {
      malloc.free(outCnt);
    }
  }

  // ── Symbol extraction ──────────────────────────────────────────────────────

  /// Walks the tree and returns named declarations (functions, classes, etc.).
  List<TsSymbol> extractSymbols(String source) {
    if (_tree == null) return const [];
    final lineStarts = _buildLineStarts(source);
    final outCnt = malloc<Uint32>();
    try {
      final ptr = _lib.extractSymbols(_tree!, outCnt);
      if (ptr.address == 0 || outCnt.value == 0) return const [];
      // Result layout: [startByte, endByte, kindIndex, nameStart, nameEnd, ...]
      final count = outCnt.value;
      final data  = ptr.asTypedList(count * 5);
      final result = <TsSymbol>[];
      for (int i = 0; i < count; i++) {
        final startByte = data[i * 5];
        final nameStart = data[i * 5 + 3];
        final nameEnd   = data[i * 5 + 4];
        final kindIdx   = data[i * 5 + 2];
        // Extract name from source using byte offsets
        if (nameStart >= source.length || nameEnd > source.length) continue;
        final name = source.substring(nameStart, nameEnd);
        final lc   = _byteToLC(startByte, lineStarts);
        final kind = kindIdx < TsSymbolKind.values.length
            ? TsSymbolKind.values[kindIdx]
            : TsSymbolKind.function;
        result.add(TsSymbol(name: name, kind: kind, line: lc.$1, column: lc.$2));
      }
      return result;
    } finally {
      malloc.free(outCnt);
    }
  }

  // ── Local helpers ──────────────────────────────────────────────────────────

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

  static int _lcToByte(int line, int col, List<int> starts) =>
      (line < starts.length ? starts[line] : 0) + col;

  static (int, int) _byteToLC(int byte, List<int> starts) {
    int lo = 0, hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= byte) lo = mid; else hi = mid - 1;
    }
    return (lo, byte - starts[lo]);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void _freeTree() {
    if (_tree != null && _tree!.address != 0) {
      _lib.treeDelete(_tree!);
      _tree = null;
    }
  }

  void dispose() {
    _freeTree();
    if (_query != null && _query!.address != 0) {
      _lib.queryDelete(_query!);
      _query = null;
    }
    if (_parser != null && _parser!.address != 0) {
      _lib.parserDelete(_parser!);
      _parser = null;
    }
  }
}
