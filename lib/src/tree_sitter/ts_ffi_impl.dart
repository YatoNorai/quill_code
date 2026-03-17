// lib/src/tree_sitter/ts_ffi.dart
//
// Low-level Dart FFI bindings to libquill_ts.so.
// All types map directly to the C structs in quill_ts_bridge.c.
// Higher-level code should use TsParser / TsHighlighter instead.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Opaque handle types
// ─────────────────────────────────────────────────────────────────────────────

final class TSParser  extends Opaque {}
final class TSTree    extends Opaque {}
final class TSQuery   extends Opaque {}
final class TSLanguage extends Opaque {}

// ─────────────────────────────────────────────────────────────────────────────
// Native function typedefs
// ─────────────────────────────────────────────────────────────────────────────

// --- version
typedef _VersionNative = Uint32 Function();
typedef _VersionDart   = int    Function();

// --- language
typedef _LangForNameNative = Pointer<TSLanguage> Function(Pointer<Utf8>);
typedef _LangForNameDart   = Pointer<TSLanguage> Function(Pointer<Utf8>);

// --- parser
typedef _ParserNewNative    = Pointer<TSParser> Function(Pointer<Utf8>);
typedef _ParserNewDart      = Pointer<TSParser> Function(Pointer<Utf8>);
typedef _ParserDeleteNative = Void Function(Pointer<TSParser>);
typedef _ParserDeleteDart   = void Function(Pointer<TSParser>);

// --- parse
typedef _ParseNative    = Pointer<TSTree> Function(
    Pointer<TSParser>, Pointer<Utf8>, Uint32, Pointer<TSTree>);
typedef _ParseDart      = Pointer<TSTree> Function(
    Pointer<TSParser>, Pointer<Utf8>, int, Pointer<TSTree>);
typedef _TreeDeleteNative = Void Function(Pointer<TSTree>);
typedef _TreeDeleteDart   = void Function(Pointer<TSTree>);

// --- highlight
typedef _HighlightNative = Pointer<Uint32> Function(
    Pointer<TSTree>, Pointer<TSQuery>, Pointer<Utf8>,
    Uint32, Uint32, Uint32, Pointer<Uint32>);
typedef _HighlightDart = Pointer<Uint32> Function(
    Pointer<TSTree>, Pointer<TSQuery>, Pointer<Utf8>,
    int, int, int, Pointer<Uint32>);

// --- blocks
typedef _BlocksNative = Pointer<Uint32> Function(Pointer<TSTree>, Pointer<Uint32>);
typedef _BlocksDart   = Pointer<Uint32> Function(Pointer<TSTree>, Pointer<Uint32>);

// --- errors
typedef _ErrorsNative = Pointer<Uint32> Function(Pointer<TSTree>, Pointer<Uint32>);
typedef _ErrorsDart   = Pointer<Uint32> Function(Pointer<TSTree>, Pointer<Uint32>);

// --- expand selection
typedef _ExpandSelNative = Pointer<Uint32> Function(
    Pointer<TSTree>, Uint32, Uint32, Pointer<Uint32>);
typedef _ExpandSelDart = Pointer<Uint32> Function(
    Pointer<TSTree>, int, int, Pointer<Uint32>);

// --- extract symbols
typedef _ExtractSymNative = Pointer<Uint32> Function(Pointer<TSTree>, Pointer<Uint32>);
typedef _ExtractSymDart   = Pointer<Uint32> Function(Pointer<TSTree>, Pointer<Uint32>);

// --- builtin query
typedef _BuiltinQueryNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _BuiltinQueryDart   = Pointer<Utf8> Function(Pointer<Utf8>);

// --- query
typedef _QueryNewNative = Pointer<TSQuery> Function(
    Pointer<TSLanguage>, Pointer<Utf8>, Uint32,
    Pointer<Uint32>, Pointer<Uint32>);
typedef _QueryNewDart = Pointer<TSQuery> Function(
    Pointer<TSLanguage>, Pointer<Utf8>, int,
    Pointer<Uint32>, Pointer<Uint32>);
typedef _QueryDeleteNative      = Void   Function(Pointer<TSQuery>);
typedef _QueryDeleteDart        = void   Function(Pointer<TSQuery>);
typedef _QueryCapCountNative    = Uint32 Function(Pointer<TSQuery>);
typedef _QueryCapCountDart      = int    Function(Pointer<TSQuery>);
typedef _QueryCapNameNative     = Pointer<Utf8> Function(Pointer<TSQuery>, Uint32, Pointer<Uint32>);
typedef _QueryCapNameDart       = Pointer<Utf8> Function(Pointer<TSQuery>, int,    Pointer<Uint32>);

// --- incremental edit
typedef _EditNative = Void Function(
    Pointer<TSTree>,
    Uint32, Uint32, Uint32,
    Uint32, Uint32, Uint32, Uint32, Uint32, Uint32);
typedef _EditDart = void Function(
    Pointer<TSTree>,
    int, int, int,
    int, int, int, int, int, int);

// ─────────────────────────────────────────────────────────────────────────────
// QuillTsLib  — loads the .so and binds all functions
// ─────────────────────────────────────────────────────────────────────────────

class QuillTsLib {
  static QuillTsLib? _instance;
  static QuillTsLib get instance => _instance ??= QuillTsLib._load();

  final DynamicLibrary _lib;

  late final _VersionDart    version;
  late final _LangForNameDart languageForName;
  late final _ParserNewDart   parserNew;
  late final _ParserDeleteDart parserDelete;
  late final _ParseDart        parse;
  late final _TreeDeleteDart   treeDelete;
  late final _HighlightDart    highlight;
  late final _BlocksDart       extractBlocks;
  late final _ErrorsDart       extractErrors;
  late final _ExpandSelDart   expandSelection;
  late final _ExtractSymDart  extractSymbols;
  late final _BuiltinQueryDart builtinQuery;
  late final _QueryNewDart     queryNew;
  late final _QueryDeleteDart  queryDelete;
  late final _QueryCapCountDart queryCapCount;
  late final _QueryCapNameDart  queryCapName;
  late final _EditDart          treeEdit;

  QuillTsLib._load() : _lib = _openLib() {
    version        = _lib.lookupFunction<_VersionNative,    _VersionDart>   ('quill_ts_version');
    languageForName= _lib.lookupFunction<_LangForNameNative,_LangForNameDart>('quill_ts_language_for_name');
    parserNew      = _lib.lookupFunction<_ParserNewNative,  _ParserNewDart>  ('quill_ts_parser_new');
    parserDelete   = _lib.lookupFunction<_ParserDeleteNative,_ParserDeleteDart>('quill_ts_parser_delete');
    parse          = _lib.lookupFunction<_ParseNative,      _ParseDart>      ('quill_ts_parse');
    treeDelete     = _lib.lookupFunction<_TreeDeleteNative, _TreeDeleteDart> ('quill_ts_tree_delete');
    highlight      = _lib.lookupFunction<_HighlightNative,  _HighlightDart>  ('quill_ts_highlight');
    extractBlocks  = _lib.lookupFunction<_BlocksNative,     _BlocksDart>     ('quill_ts_extract_blocks');
    extractErrors  = _lib.lookupFunction<_ErrorsNative,     _ErrorsDart>     ('quill_ts_errors');
    // Optional: new functions added in later builds — graceful fallback if missing
    try {
      expandSelection= _lib.lookupFunction<_ExpandSelNative,  _ExpandSelDart>  ('quill_ts_expand_selection');
      extractSymbols = _lib.lookupFunction<_ExtractSymNative, _ExtractSymDart> ('quill_ts_extract_symbols');
    } catch (_) {
      // Old .so without these functions — use no-op stubs
      expandSelection = (Pointer<TSTree> _, int __, int ___, Pointer<Uint32> ____) =>
          Pointer<Uint32>.fromAddress(0);
      extractSymbols  = (Pointer<TSTree> _, Pointer<Uint32> __) =>
          Pointer<Uint32>.fromAddress(0);
    }
    builtinQuery   = _lib.lookupFunction<_BuiltinQueryNative,_BuiltinQueryDart>('quill_ts_get_builtin_query');
    queryNew       = _lib.lookupFunction<_QueryNewNative,   _QueryNewDart>   ('quill_ts_query_new');
    queryDelete    = _lib.lookupFunction<_QueryDeleteNative,_QueryDeleteDart>('quill_ts_query_delete');
    queryCapCount  = _lib.lookupFunction<_QueryCapCountNative,_QueryCapCountDart>('quill_ts_query_capture_count');
    queryCapName   = _lib.lookupFunction<_QueryCapNameNative, _QueryCapNameDart> ('quill_ts_query_capture_name');
    treeEdit       = _lib.lookupFunction<_EditNative,       _EditDart>       ('quill_ts_tree_edit');
  }

  static DynamicLibrary _openLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libquill_ts.so');
    }
    throw UnsupportedError(
      'QuillCode Tree-sitter: platform ${Platform.operatingSystem} not yet supported. '
      'Android is the currently supported platform.');
  }

  /// Returns true if libquill_ts.so loaded successfully.
  static bool get isAvailable {
    try {
      instance; // triggers lazy load
      return true;
    } catch (_) {
      return false;
    }
  }
}
