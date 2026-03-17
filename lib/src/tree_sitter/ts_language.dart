// lib/src/tree_sitter/ts_language.dart
//
// A QuillLanguage mixin/wrapper that automatically uses tree-sitter
// when libquill_ts.so is available, and falls back to the regex backend
// when it is not.
//
// Usage in a language file:
//   class DartLanguage extends RegexLanguage with TsLanguageMixin {
//     @override String get name => 'dart';
//     @override String get tsName => 'dart';   // name in libquill_ts
//     ...
//   }

import '../highlighting/analyze_manager.dart';
import '../language/language.dart';
import 'ts_analyze_manager.dart';
import 'ts_ffi.dart';

/// Mixin that overrides [createAnalyzeManager] to return a [TsAnalyzeManager]
/// when tree-sitter is available, otherwise falls back to the existing impl.
mixin TsLanguageMixin on QuillLanguage {
  /// Language identifier used in [TsQueries] and in libquill_ts.so.
  /// Defaults to [name] — override only if they differ.
  String get tsName => name;

  @override
  AnalyzeManager createAnalyzeManager() {
    if (QuillTsLib.isAvailable) {
      return TsAnalyzeManager(language: this);
    }
    // Fallback: use whatever the base class provides (regex)
    return super.createAnalyzeManager();
  }
}
