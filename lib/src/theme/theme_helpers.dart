// lib/src/theme/theme_helpers.dart
// Convenience accessors for the default dark theme (used by VsCodeThemeParser).
import 'editor_theme.dart';
import 'color_scheme.dart';
import 'theme_dark.dart';

class DarkEditorTheme {
  static EditorTheme get theme => QuillThemeDark.build();
  static EditorColorScheme get colorScheme => QuillThemeDark.build().colorScheme;
}
