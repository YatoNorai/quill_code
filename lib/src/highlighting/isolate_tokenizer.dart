// lib/src/highlighting/isolate_tokenizer.dart
// Conditional export: real isolate on native, sync stub on web.
export 'isolate_tokenizer_stub.dart'
    if (dart.library.isolate) 'isolate_tokenizer_impl.dart';
