// lib/src/tree_sitter/ts_parser.dart
//
// Conditional import: real FFI implementation on mobile/desktop, stub on web.
export 'ts_parser_stub.dart'
    if (dart.library.ffi) 'ts_parser_impl.dart';
