// lib/src/language/plain_text_language.dart
import 'monarch_language.dart';

class PlainTextLanguage extends MonarchLanguage {
  @override String get name => 'Plain Text';
  @override MonarchRuleSet get monarchRules => MonarchRuleSet({'root': []});
}
