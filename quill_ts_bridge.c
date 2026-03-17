// android/src/main/cpp/quill_ts_bridge.c
//
// Thin C bridge between the Dart FFI layer and tree-sitter + grammars.
// Compiled into libquill_ts.so by the Android NDK CMake build.
//
// Design goals:
//  • Single .so — Dart FFI loads one library.
//  • Zero heap allocation on the hot path (parse + query cursor reuse).
//  • Thread-safe: each Dart isolate creates its own TSParser instance.
//  • Returns plain integer handles; Dart manages lifetimes via finalizers.

#include "tree-sitter/lib/include/tree_sitter/api.h"
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <android/log.h>

#define TAG "QuillTS"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ── Grammar declarations ──────────────────────────────────────────────────────
extern const TSLanguage *tree_sitter_dart(void);
extern const TSLanguage *tree_sitter_javascript(void);
extern const TSLanguage *tree_sitter_typescript(void);
extern const TSLanguage *tree_sitter_python(void);
extern const TSLanguage *tree_sitter_kotlin(void);
extern const TSLanguage *tree_sitter_rust(void);
extern const TSLanguage *tree_sitter_cpp(void);
extern const TSLanguage *tree_sitter_c(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_css(void);
extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_yaml(void);
extern const TSLanguage *tree_sitter_bash(void);
extern const TSLanguage *tree_sitter_xml(void);

// ── Language registry ─────────────────────────────────────────────────────────
typedef struct {
  const char     *name;
  const TSLanguage *(*fn)(void);
} LangEntry;

static const LangEntry kLanguages[] = {
  {"dart",        tree_sitter_dart},
  {"javascript",  tree_sitter_javascript},
  {"typescript",  tree_sitter_typescript},
  {"python",      tree_sitter_python},
  {"kotlin",      tree_sitter_kotlin},
  {"rust",        tree_sitter_rust},
  {"cpp",         tree_sitter_cpp},
  {"c",           tree_sitter_c},
  {"html",        tree_sitter_html},
  {"css",         tree_sitter_css},
  {"json",        tree_sitter_json},
  {"yaml",        tree_sitter_yaml},
  {"bash",        tree_sitter_bash},
  {"xml",         tree_sitter_xml},
  {NULL, NULL}
};

// ─────────────────────────────────────────────────────────────────────────────
// Public API — all symbols are __attribute__((visibility("default")))
// so they survive the NDK linker's --gc-sections.
// ─────────────────────────────────────────────────────────────────────────────

#define EXPORT __attribute__((visibility("default")))

// ── Language lookup ───────────────────────────────────────────────────────────

/// Returns a pointer to the TSLanguage for the given name, or NULL.
EXPORT const TSLanguage *quill_ts_language_for_name(const char *name) {
  for (int i = 0; kLanguages[i].name != NULL; i++) {
    if (strcmp(kLanguages[i].name, name) == 0) {
      return kLanguages[i].fn();
    }
  }
  LOGE("Unknown language: %s", name);
  return NULL;
}

// ── Parser lifecycle ──────────────────────────────────────────────────────────

EXPORT TSParser *quill_ts_parser_new(const char *lang_name) {
  const TSLanguage *lang = quill_ts_language_for_name(lang_name);
  if (!lang) return NULL;

  // Log version info for diagnostics
  uint32_t ver = ts_language_abi_version(lang);
  LOGI("Language '%s' ABI version: %u (runtime supports %u–%u)",
       lang_name, ver,
       TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION,
       TREE_SITTER_LANGUAGE_VERSION);

  TSParser *p = ts_parser_new();
  if (!ts_parser_set_language(p, lang)) {
    // Should not happen: CMake compiles tree_sitter with LANGUAGE_VERSION=15
    // which accepts all grammar ABIs 13-15. If this still fires, the grammar
    // is using a future ABI not yet supported.
    LOGE("Incompatible language version: %s (ABI %u, runtime max %u)",
         lang_name, ver, TREE_SITTER_LANGUAGE_VERSION);
    ts_parser_delete(p);
    return NULL;
  }
  return p;
}

EXPORT void quill_ts_parser_delete(TSParser *parser) {
  if (parser) ts_parser_delete(parser);
}

// ── Parse ─────────────────────────────────────────────────────────────────────

/// Parse UTF-8 source. old_tree may be NULL for a full parse.
/// Returns a new TSTree* that caller owns (call quill_ts_tree_delete).
EXPORT TSTree *quill_ts_parse(TSParser *parser, const char *source,
                               uint32_t length, TSTree *old_tree) {
  return ts_parser_parse_string(parser, old_tree, source, length);
}

EXPORT void quill_ts_tree_delete(TSTree *tree) {
  if (tree) ts_tree_delete(tree);
}

// ── Highlight query execution ──────────────────────────────────────────────────

// Result buffer layout (Dart reads this as a flat Uint32List):
//   [start_byte, end_byte, capture_id,  start_byte, end_byte, capture_id, ...]
// where capture_id maps to token type via capture name.
#define MAX_RESULTS (1024 * 64)
static uint32_t kResultBuf[MAX_RESULTS * 3];

typedef struct {
  uint32_t *data;   // pointer to kResultBuf
  uint32_t  count;  // number of (start,end,capture) triples written
} HighlightResult;

EXPORT const uint32_t *quill_ts_highlight(
    TSTree       *tree,
    TSQuery      *query,
    const char   *source,
    uint32_t      source_len,
    uint32_t      start_row,
    uint32_t      end_row,
    uint32_t     *out_count)
{
  TSNode root = ts_tree_root_node(tree);
  TSQueryCursor *cur = ts_query_cursor_new();

  TSPoint start_pt = {start_row, 0};
  TSPoint end_pt   = {end_row,   0xFFFFFFFF};
  ts_query_cursor_set_point_range(cur, start_pt, end_pt);
  ts_query_cursor_exec(cur, query, root);

  uint32_t n = 0;
  TSQueryMatch match;
  uint32_t cap_idx;
  while (ts_query_cursor_next_capture(cur, &match, &cap_idx) && n < MAX_RESULTS) {
    const TSQueryCapture *cap = &match.captures[cap_idx];  // use index
    TSNode node = cap->node;
    if (ts_node_is_missing(node)) continue;
    kResultBuf[n * 3 + 0] = ts_node_start_byte(node);
    kResultBuf[n * 3 + 1] = ts_node_end_byte(node);
    kResultBuf[n * 3 + 2] = cap->index;
    n++;
  }

  ts_query_cursor_delete(cur);
  *out_count = n;
  return kResultBuf;
}

// ── Block extraction ──────────────────────────────────────────────────────────

// Result: [startLine, endLine, contentColumn, ...]
// contentColumn is the character-column of the first statement inside the block.
// Dart uses this directly as the guide-line x offset (column * charWidth).
static uint32_t kBlockBuf[1024 * 6];

// Returns true for node types that represent a code block / body:
// matches types ending in "block", "_body", or equal to "compound_statement".
static bool is_block_node(const char *type) {
  size_t len = strlen(type);
  if (len >= 5 && memcmp(type + len - 5, "block", 5) == 0) return true;
  if (len >= 5 && memcmp(type + len - 5, "_body", 5) == 0) return true;
  if (strcmp(type, "compound_statement") == 0) return true;
  return false;
}

/// Walk the tree and collect foldable block nodes (function/class bodies, etc.).
/// Returns pointer to flat triplet buffer; *out_count = number of triplets.
EXPORT const uint32_t *quill_ts_extract_blocks(
    TSTree   *tree,
    uint32_t *out_count)
{
  uint32_t n = 0;
  TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(tree));

  typedef struct { TSNode node; } Frame;
  Frame stack[2048];
  int sp = 0;
  stack[sp++] = (Frame){ts_tree_cursor_current_node(&cursor)};

  while (sp > 0 && n < 1024 * 2) {
    TSNode node = stack[--sp].node;

    TSPoint ep_pt     = ts_node_end_point(node);
    uint32_t start_line = ts_node_start_point(node).row;
    uint32_t end_line   = ep_pt.row;

    uint32_t named_count = ts_node_named_child_count(node);

    // Only collect actual block/body nodes that span ≥ 2 lines
    if (end_line > start_line && named_count > 0
        && is_block_node(ts_node_type(node))) {
      // Use the start column of the first named child as the content indent.
      // This positions the guide line at the actual content indentation,
      // independent of the opening-brace column or tabSize.
      TSNode first_child = ts_node_named_child(node, 0);
      uint32_t content_col = ts_node_start_point(first_child).column;

      if (content_col > 0) {   // skip column-0 blocks (top-level)
        kBlockBuf[n * 3 + 0] = start_line;
        kBlockBuf[n * 3 + 1] = end_line;
        kBlockBuf[n * 3 + 2] = content_col;   // character column, not indent level
        n++;
      }
    }

    // Push children in reverse order so first child is processed first
    for (int32_t i = (int32_t)named_count - 1; i >= 0 && sp < 2047; i--) {
      TSNode child = ts_node_named_child(node, (uint32_t)i);
      if (!ts_node_is_null(child)) stack[sp++] = (Frame){child};
    }
  }

  ts_tree_cursor_delete(&cursor);
  *out_count = n;
  return kBlockBuf;
}

// ── Query lifecycle ────────────────────────────────────────────────────────────

EXPORT TSQuery *quill_ts_query_new(const TSLanguage *lang,
                                    const char *source, uint32_t len,
                                    uint32_t *err_offset, uint32_t *err_type) {
  TSQueryError et = TSQueryErrorNone;
  TSQuery *q = ts_query_new(lang, source, len, err_offset, &et);
  if (err_type) *err_type = (uint32_t)et;
  return q;
}

EXPORT void quill_ts_query_delete(TSQuery *q) {
  if (q) ts_query_delete(q);
}

EXPORT uint32_t quill_ts_query_capture_count(const TSQuery *q) {
  return q ? ts_query_capture_count(q) : 0;
}

EXPORT const char *quill_ts_query_capture_name(const TSQuery *q,
                                                uint32_t id,
                                                uint32_t *len) {
  return q ? ts_query_capture_name_for_id(q, id, len) : NULL;
}

// ── Error detection ───────────────────────────────────────────────────────────

// Result: [startByte, endByte, startByte, endByte, ...]
static uint32_t kErrorBuf[4096];

EXPORT const uint32_t *quill_ts_errors(TSTree *tree, uint32_t *out_count) {
  uint32_t n = 0;
  TSNode root = ts_tree_root_node(tree);
  if (!ts_node_has_error(root)) { *out_count = 0; return kErrorBuf; }

  TSTreeCursor cursor = ts_tree_cursor_new(root);
  typedef struct { TSNode node; } F;
  F stk[2048]; int sp = 0;
  stk[sp++] = (F){root};

  while (sp > 0 && n < 2048) {
    TSNode node = stk[--sp].node;
    if (ts_node_is_error(node) || ts_node_is_missing(node)) {
      kErrorBuf[n * 2]     = ts_node_start_byte(node);
      kErrorBuf[n * 2 + 1] = ts_node_end_byte(node);
      n++;
      continue; // don't recurse into error nodes
    }
    uint32_t cc = ts_node_child_count(node);
    for (int32_t i = (int32_t)cc - 1; i >= 0 && sp < 2047; i--) {
      TSNode child = ts_node_child(node, (uint32_t)i);
      if (!ts_node_is_null(child) && ts_node_has_error(child))
        stk[sp++] = (F){child};
    }
  }
  ts_tree_cursor_delete(&cursor);
  *out_count = n;
  return kErrorBuf;
}

// ── Incremental edit ──────────────────────────────────────────────────────────

EXPORT void quill_ts_tree_edit(
    TSTree  *tree,
    uint32_t start_byte,  uint32_t old_end_byte, uint32_t new_end_byte,
    uint32_t start_row,   uint32_t start_col,
    uint32_t old_end_row, uint32_t old_end_col,
    uint32_t new_end_row, uint32_t new_end_col)
{
  TSInputEdit edit = {
    .start_byte    = start_byte,
    .old_end_byte  = old_end_byte,
    .new_end_byte  = new_end_byte,
    .start_point   = {start_row,   start_col},
    .old_end_point = {old_end_row, old_end_col},
    .new_end_point = {new_end_row, new_end_col},
  };
  ts_tree_edit(tree, &edit);
}

// ── Version probe (used by Dart to verify .so loaded) ────────────────────────
EXPORT uint32_t quill_ts_version(void) {
  return TREE_SITTER_LANGUAGE_VERSION;
}