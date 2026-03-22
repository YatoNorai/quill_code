// lib/src/highlighting/analyze_manager.dart
import 'package:flutter/foundation.dart' show VoidCallback;
import 'styles.dart';
import '../text/content.dart';

typedef StylesUpdatedCallback = void Function(Styles newStyles);

abstract class AnalyzeManager {
  StylesUpdatedCallback? onStylesUpdated;
  VoidCallback?          onTokenizationComplete;
  Styles _styles = Styles.empty;
  Styles get styles => _styles;

  // Viewport hint: set by the render object on every paint so the manager
  // can limit highlight work to visible lines only (Monaco-style).
  int viewportFirstLine = 0;
  int viewportLastLine  = 9999;

  void init(Content content);
  void onContentChanged(ContentChangeEvent event, Content content);
  void reanalyze(Content content);
  void destroy();

  void pushStyles(Styles styles) {
    _styles = styles;
    onStylesUpdated?.call(styles);
  }
}
