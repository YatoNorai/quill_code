// lib/src/tree_sitter/ts_ffi.dart
//
// Conditional import: uses dart:ffi on mobile/desktop, stub on web.
export 'ts_ffi_stub.dart'
    if (dart.library.ffi) 'ts_ffi_impl.dart';
