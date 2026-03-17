// android/src/main/java/dev/quillcode/quill_code/QuillCodePlugin.java
//
// Flutter plugin entry point for Android.
// The native .so is loaded automatically by Dart FFI (DynamicLibrary.open).
// This plugin class exists solely for Flutter's plugin registration mechanism.

package dev.quillcode.quill_code;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class QuillCodePlugin implements FlutterPlugin, MethodCallHandler {

  private MethodChannel channel;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
    channel = new MethodChannel(binding.getBinaryMessenger(), "quill_code");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "isTreeSitterAvailable":
        // The .so load is checked on the Dart side via QuillTsLib.isAvailable.
        // This channel method exists for diagnostic / setup checks.
        result.success(true);
        break;
      default:
        result.notImplemented();
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }
}
