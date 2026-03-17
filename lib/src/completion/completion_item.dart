// lib/src/completion/completion_item.dart
//
// Lazy resolve support (inspired by Monaco's resolveCompletionItem):
//
//  • Items from LSP arrive with label+kind but may lack full documentation.
//  • `isResolved = false` items have `_rawLspData` stored for later.
//  • When the user highlights an item in the popup, the controller calls
//    `resolveCompletionItem(index)` which fetches full docs from the LSP
//    and replaces the item in the list — no full-list re-fetch needed.

enum CompletionItemKind {
  keyword,
  function_,
  variable,
  field,
  constant,
  class_,
  interface_,
  module,
  snippet,
  text,
  method,
  constructor,
  enum_,
  property,
  event,
  operator_,
  typeParameter,
}

/// A single auto-completion item.
class CompletionItem {
  final String label;
  final CompletionItemKind kind;
  final String insertText;
  final String? detail;
  final String? documentation;
  final String? filterText;
  final String? sortText;
  final bool isSnippet;
  final int? iconCodePoint;

  /// Whether full documentation has already been fetched from the LSP.
  /// Local items are always considered resolved.
  /// LSP items start as unresolved (documentation may be null/empty) and
  /// become resolved after `resolveCompletionItem()` is called.
  final bool isResolved;

  /// Opaque raw LSP data stored so the bridge can make a
  /// `completionItem/resolve` request without re-fetching everything.
  /// This field is intentionally dynamic — the bridge owns its type.
  final dynamic rawLspData;

  const CompletionItem({
    required this.label,
    required this.kind,
    required this.insertText,
    this.detail,
    this.documentation,
    this.filterText,
    this.sortText,
    this.isSnippet = false,
    this.iconCodePoint,
    this.isResolved = true,
    this.rawLspData,
  });

  /// Return a copy of this item with the resolved fields filled in.
  CompletionItem withResolved({String? documentation, String? detail}) {
    return CompletionItem(
      label:         label,
      kind:          kind,
      insertText:    insertText,
      detail:        detail ?? this.detail,
      documentation: documentation ?? this.documentation,
      filterText:    filterText,
      sortText:      sortText,
      isSnippet:     isSnippet,
      iconCodePoint: iconCodePoint,
      isResolved:    true,
      rawLspData:    rawLspData,
    );
  }

  String get effectiveFilterText => filterText ?? label;
  String get effectiveSortText   => sortText   ?? label;
}
