// lib/src/theme/font_loader.dart
//
// QuillCode custom font loader.
//
// USAGE:
//
//   // From asset (add font to pubspec.yaml flutter.fonts OR load manually):
//   await QuillFontLoader.loadFromAsset('JetBrains Mono', 'assets/fonts/JetBrainsMono-Regular.ttf');
//
//   // From raw bytes (e.g. after downloading with http package):
//   final bytes = (await http.get(Uri.parse(url))).bodyBytes;
//   await QuillFontLoader.loadFromBytes('MyFont', bytes);
//
//   // Then use the font in the editor:
//   QuillCodeEditor(
//     controller: ctrl,
//     theme: myTheme.copyWith(fontFamily: 'JetBrains Mono'),
//   )

import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

class QuillFontLoader {
  QuillFontLoader._();

  static final Set<String> _loaded = {};

  /// Returns true if [fontFamily] has already been registered.
  static bool isLoaded(String fontFamily) => _loaded.contains(fontFamily);

  /// Register a font from a Flutter asset path.
  /// The file must be listed under `flutter: fonts:` in pubspec.yaml,
  /// OR declared as a generic asset (in which case only the raw bytes are loaded
  /// without the standard FontManifest entry — works on all platforms).
  ///
  /// Example pubspec.yaml:
  /// ```yaml
  /// flutter:
  ///   assets:
  ///     - assets/fonts/JetBrainsMono-Regular.ttf
  /// ```
  ///
  /// Then call:
  /// ```dart
  /// await QuillFontLoader.loadFromAsset(
  ///   'JetBrains Mono',
  ///   'assets/fonts/JetBrainsMono-Regular.ttf',
  /// );
  /// ```
  static Future<String> loadFromAsset(
    String fontFamily,
    String assetPath, {
    FontWeight weight = FontWeight.normal,
    FontStyle  style  = FontStyle.normal,
  }) async {
    if (_loaded.contains(fontFamily)) return fontFamily;
    final data = await rootBundle.load(assetPath);
    return _register(fontFamily, data.buffer.asUint8List(), weight, style);
  }

  /// Register a font from raw [bytes].
  /// Use this after fetching the font file over the network with the `http` package:
  ///
  /// ```dart
  /// import 'package:http/http.dart' as http;
  ///
  /// final resp = await http.get(Uri.parse('https://example.com/font.ttf'));
  /// await QuillFontLoader.loadFromBytes('MyFont', resp.bodyBytes);
  /// ```
  static Future<String> loadFromBytes(
    String fontFamily,
    Uint8List bytes, {
    FontWeight weight = FontWeight.normal,
    FontStyle  style  = FontStyle.normal,
  }) async {
    if (_loaded.contains(fontFamily)) return fontFamily;
    return _register(fontFamily, bytes, weight, style);
  }

  /// Load multiple weights/styles of the same family.
  ///
  /// [variants] is a list of (assetPath, weight, style) records.
  ///
  /// ```dart
  /// await QuillFontLoader.loadFamily('Fira Code', [
  ///   ('assets/fonts/FiraCode-Regular.ttf', FontWeight.normal, FontStyle.normal),
  ///   ('assets/fonts/FiraCode-Bold.ttf',    FontWeight.bold,   FontStyle.normal),
  /// ]);
  /// ```
  static Future<String> loadFamily(
    String fontFamily,
    List<(String assetPath, FontWeight weight, FontStyle style)> variants,
  ) async {
    if (_loaded.contains(fontFamily)) return fontFamily;
    final loader = FontLoader(fontFamily);
    for (final (path, w, st) in variants) {
      final data = await rootBundle.load(path);
      loader.addFont(Future.value(data));
    }
    await loader.load();
    _loaded.add(fontFamily);
    return fontFamily;
  }

  static Future<String> _register(
    String fontFamily,
    Uint8List bytes,
    FontWeight weight,
    FontStyle style,
  ) async {
    final loader = FontLoader(fontFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(fontFamily);
    return fontFamily;
  }

  /// Remove a font from the loaded cache.
  /// Does NOT unload the font from Flutter's engine (not supported by Flutter).
  static void evict(String fontFamily) => _loaded.remove(fontFamily);

  /// Clear the entire cache.
  static void clearCache() => _loaded.clear();
}

/// Names of popular coding fonts.
abstract class QuillCodingFonts {
  static const jetBrainsMono = 'JetBrains Mono';
  static const firaCode      = 'Fira Code';
  static const sourceCodePro = 'Source Code Pro';
  static const ibmPlexMono   = 'IBM Plex Mono';
  static const robotoMono    = 'Roboto Mono';
  static const inconsolata   = 'Inconsolata';
  static const spaceMono     = 'Space Mono';
  static const cascadiaCode  = 'Cascadia Code';
  static const courierPrime  = 'Courier Prime';

  static const all = [
    jetBrainsMono, firaCode, sourceCodePro, ibmPlexMono,
    robotoMono, inconsolata, spaceMono, cascadiaCode, courierPrime,
  ];
}
