// lib/src/tree_sitter/ts_ffi_stub.dart
//
// Stub for platforms where dart:ffi is unavailable (web/Chrome).
// QuillTsLib.isAvailable returns false so TsAnalyzeManager
// automatically falls back to the regex backend.

// Opaque stub types — never instantiated on web.
final class TSParser  {}
final class TSTree    {}
final class TSQuery   {}
final class TSLanguage {}

class QuillTsLib {
  QuillTsLib._();
  static bool get isAvailable => false;
  // All methods unreachable on web — stub signatures satisfy the type system.
  static QuillTsLib get instance =>
      throw UnsupportedError('QuillTsLib not available on this platform');
}
