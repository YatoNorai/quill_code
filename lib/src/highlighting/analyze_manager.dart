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

  void init(Content content);
  void onContentChanged(ContentChangeEvent event, Content content);
  void reanalyze(Content content);
  void destroy();

  /// Called whenever the editor viewport scrolls to a new range of lines.
  /// Implementations can use this to prioritize tokenizing visible lines first.
  void notifyVisibleRange(int firstLine, int lastLine) {}

  void pushStyles(Styles styles) {
    _styles = styles;
    onStylesUpdated?.call(styles);
  }
}
