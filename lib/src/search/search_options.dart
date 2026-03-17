// lib/src/search/search_options.dart

enum SearchType { plainText, wholeWord, regularExpression }

class SearchOptions {
  final SearchType type;
  final bool caseSensitive;
  const SearchOptions({
    this.type = SearchType.plainText,
    this.caseSensitive = false,
  });
}

class ReplaceOptions {
  final bool preserveCase;
  static const ReplaceOptions defaults = ReplaceOptions();
  const ReplaceOptions({this.preserveCase = false});
}
