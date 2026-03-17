library quill_code;

export 'src/core/editor_controller.dart';
export 'src/core/editor_props.dart';
export 'src/core/cursor.dart';
export 'src/core/char_position.dart';
export 'src/core/symbol_pair.dart';

export 'src/text/content.dart';
export 'src/text/content_line.dart';
export 'src/text/undo_manager.dart';
export 'src/text/text_range.dart';
export 'src/text/line_separator.dart';
export 'src/text/rope.dart';

export 'src/diff/git_diff.dart';

export 'src/language/language.dart';
export 'src/language/plain_text_language.dart';
export 'src/language/dart_language.dart';
export 'src/language/javascript_language.dart';
export 'src/language/python_language.dart';
export 'src/language/json_language.dart';
export 'src/language/html_language.dart';
export 'src/language/css_language.dart';
export 'src/language/cpp_language.dart';
export 'src/language/xml_language.dart';
export 'src/language/yaml_language.dart';
export 'src/language/bash_language.dart';
export 'src/language/kotlin_language.dart';
export 'src/language/rust_language.dart';

export 'src/highlighting/span.dart';
export 'src/highlighting/styles.dart';
export 'src/highlighting/analyze_manager.dart';
export 'src/highlighting/incremental_analyze_manager.dart';
export 'src/highlighting/code_block.dart';
export 'src/highlighting/inlay_hint_model.dart';
export 'src/highlighting/line_style.dart';
export 'src/highlighting/text_style_token.dart';

export 'src/completion/completion_item.dart';
export 'src/completion/completion_publisher.dart';
export 'src/completion/snippet.dart';
export 'src/completion/snippet_controller.dart';
export 'src/completion/vscode_snippets.dart';

export 'src/lsp/lsp_bridge.dart';
export 'src/lsp/lsp_hover_panel.dart';
export 'src/lsp/lsp_signature_panel.dart';
export 'src/lsp/quill_lsp_config.dart';

export 'src/search/editor_searcher.dart';
export 'src/search/search_options.dart';

export 'src/diagnostics/diagnostic_region.dart';
export 'src/diagnostics/diagnostics_container.dart';
export 'src/diagnostics/quick_fix.dart';

export 'src/theme/editor_theme.dart';
export 'src/theme/font_loader.dart';
export 'src/theme/indent_program.dart';
export 'src/theme/color_scheme.dart';
export 'src/theme/theme_dark.dart';
export 'src/theme/theme_light.dart';

export 'src/theme/theme_github.dart';
export 'src/theme/theme_monokai.dart';
export 'src/theme/theme_dracula.dart';

export 'src/events/editor_event.dart';
export 'src/events/event_manager.dart';

export 'src/widgets/quill_code_editor.dart';
export 'src/widgets/completion_popup.dart';
export 'src/widgets/diagnostic_tooltip.dart';
export 'src/widgets/diagnostics_panel.dart';
export 'src/widgets/search_bar_widget.dart';
export 'src/widgets/symbol_input_bar.dart';
export 'src/widgets/minimap_widget.dart';

export 'src/actions/code_action.dart';
export 'src/actions/code_action_provider.dart';
export 'src/actions/symbol_analyzer.dart';
export 'src/actions/lightbulb_widget.dart';
export 'src/actions/symbol_info_panel.dart';

export 'src/lsp/lsp_controller_mixin.dart';
export 'src/lsp/lsp_stdio_client.dart';
export 'src/lsp/lsp_socket_client.dart';
export 'src/text/bracket_matcher.dart';

export 'src/completion/ghost_text_controller.dart';
export 'src/completion/ghost_text_providers.dart';
export 'src/completion/flutter_snippets.dart';
export 'src/theme/vscode_theme_parser.dart';
export 'src/theme/theme_helpers.dart';
export 'src/language/dart_formatter.dart';
export 'src/actions/standard_actions.dart';
export 'src/widgets/actions_menu_widget.dart';
export 'src/theme/theme_dark_modern.dart';
export 'src/theme/theme_github_dark.dart';

// ── Tree-sitter (Android FFI) ──────────────────────────────────────────────
export 'src/tree_sitter/ts_ffi.dart'           show QuillTsLib;
export 'src/tree_sitter/ts_language.dart'      show TsLanguageMixin;
export 'src/tree_sitter/ts_analyze_manager.dart' show TsAnalyzeManager;
export 'src/tree_sitter/ts_parser.dart'        show TsParser, TsHighlightSpan;
export 'src/tree_sitter/ts_token_mapper.dart'  show TsTokenMapper;
export 'src/tree_sitter/ts_symbol.dart';
export 'src/tree_sitter/ts_semantic.dart' show TsSemantic;
