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

// Result: [startLine, endLine, indentDepth, startLine, endLine, indentDepth, ...]
static uint32_t kBlockBuf[1024 * 6];

/// Walk the tree and collect foldable block nodes (function/class/if/for bodies).
/// Returns pointer to flat triplet buffer; *out_count = number of triplets.
EXPORT const uint32_t *quill_ts_extract_blocks(
    TSTree   *tree,
    uint32_t *out_count)
{
  uint32_t n = 0;
  TSNode root = ts_tree_root_node(tree);

  // par_start/par_end = start/end row of the direct parent node.
  // Used to detect redundant wrapper nodes:
  //   is_dup       — node has exactly the same range as parent (e.g. Dart
  //                  class_body / function_body that wraps a single child
  //                  at the same lines as the class/function declaration).
  //   is_body_block — node starts one line *after* parent and ends on the
  //                  same line (e.g. Python indented "block" body).
  //   is_doc_wrapper — named "document"; YAML wraps entire content in a
  //                  "document" node that should not become a fold region.
  typedef struct { TSNode node; int depth; uint32_t par_start; uint32_t par_end; } Frame;
  Frame stack[2048];
  int sp = 0;

  // Start DFS from ROOT'S CHILDREN. Pass the root's own row range as the
  // "parent range" so depth-1 nodes can be checked against it.
  uint32_t root_start = ts_node_start_point(root).row;
  uint32_t root_end   = ts_node_end_point(root).row;
  uint32_t root_cc = ts_node_named_child_count(root);
  for (int32_t i = (int32_t)root_cc - 1; i >= 0 && sp < 2047; i--) {
    TSNode child = ts_node_named_child(root, (uint32_t)i);
    if (!ts_node_is_null(child))
      stack[sp++] = (Frame){child, 1, root_start, root_end};
  }

  while (sp > 0 && n < 1024 * 2) {
    Frame f     = stack[--sp];
    TSNode node = f.node;

    TSPoint sp_pt = ts_node_start_point(node);
    TSPoint ep_pt = ts_node_end_point(node);
    uint32_t start_line = sp_pt.row;
    uint32_t end_line   = ep_pt.row;

    if (end_line > start_line && ts_node_named_child_count(node) > 0) {
      // Skip nodes whose range duplicates or trivially shadows the parent.
      int is_dup        = (start_line == f.par_start && end_line == f.par_end);
      int is_body_block = (start_line == f.par_start + 1 && end_line == f.par_end);
      int is_doc_wrap   = (strcmp(ts_node_type(node), "document") == 0);
      if (!is_dup && !is_body_block && !is_doc_wrap) {
        kBlockBuf[n * 3 + 0] = start_line;
        kBlockBuf[n * 3 + 1] = end_line;
        kBlockBuf[n * 3 + 2] = (uint32_t)sp_pt.column / 2;
        n++;
      }
    }

    // Always recurse into children regardless of whether we added a block.
    uint32_t child_count = ts_node_named_child_count(node);
    for (int32_t i = (int32_t)child_count - 1; i >= 0 && sp < 2047; i--) {
      TSNode child = ts_node_named_child(node, (uint32_t)i);
      if (!ts_node_is_null(child))
        stack[sp++] = (Frame){child, f.depth + 1, start_line, end_line};
    }
  }

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

// ── Built-in highlight query ───────────────────────────────────────────────────
// Returns NULL so the Dart layer falls back to TsQueries.forLanguage().
// This stub is required so QuillTsLib can bind the symbol at load time.
EXPORT const char *quill_ts_get_builtin_query(const char *lang_name) {
  (void)lang_name;
  return NULL;
}

// ── Expand selection ──────────────────────────────────────────────────────────
// Given a byte range [start_byte, end_byte], returns the smallest enclosing
// named node that is STRICTLY LARGER than the given range.
// Result: static buffer [newStartByte, newEndByte, 0, 0]; *out_count = 4 on success.
static uint32_t kExpandBuf[4];

EXPORT const uint32_t *quill_ts_expand_selection(
    TSTree   *tree,
    uint32_t  start_byte,
    uint32_t  end_byte,
    uint32_t *out_count)
{
  *out_count = 0;
  if (!tree) return kExpandBuf;

  TSNode root = ts_tree_root_node(tree);
  // Find the deepest named node that covers the entire [start_byte, end_byte] range.
  TSNode node = ts_node_named_descendant_for_byte_range(root, start_byte, end_byte);
  if (ts_node_is_null(node)) return kExpandBuf;

  uint32_t ns = ts_node_start_byte(node);
  uint32_t ne = ts_node_end_byte(node);

  // If this node already covers more than the current selection, return it.
  if (ns < start_byte || ne > end_byte) {
    kExpandBuf[0] = ns;  kExpandBuf[1] = ne;
    kExpandBuf[2] = 0;   kExpandBuf[3] = 0;
    *out_count = 4;
    return kExpandBuf;
  }

  // Walk up parent chain until we find a strictly larger enclosing node.
  for (int guard = 0; guard < 64; guard++) {
    TSNode parent = ts_node_parent(node);
    if (ts_node_is_null(parent)) break;
    uint32_t ps = ts_node_start_byte(parent);
    uint32_t pe = ts_node_end_byte(parent);
    if (ps < ns || pe > ne) {
      kExpandBuf[0] = ps;  kExpandBuf[1] = pe;
      kExpandBuf[2] = 0;   kExpandBuf[3] = 0;
      *out_count = 4;
      return kExpandBuf;
    }
    node = parent;
    ns = ps;
    ne = pe;
  }
  return kExpandBuf; // out_count stays 0 → Dart treats as "already at root"
}

// ── Symbol extraction ──────────────────────────────────────────────────────────
// Walks the AST and collects named declaration nodes.
// Result layout per symbol: [startByte, endByte, kindIndex, nameStart, nameEnd]
// kindIndex maps to TsSymbolKind:
//   0=class_  1=function  2=method  3=variable  4=constant
//   5=enum_   6=interface 7=struct  8=namespace

#define MAX_SYM 512
static uint32_t kSymBuf[MAX_SYM * 5];

// Returns kind index ≥ 0 for declaration nodes, -1 otherwise.
static int _sym_kind(const char *t) {
  if (strstr(t, "class_declaration") || strstr(t, "class_definition") ||
      strstr(t, "class_specifier"))                     return 0;
  if (strstr(t, "struct_item")    || strstr(t, "struct_specifier") ||
      strstr(t, "struct_declaration"))                  return 7;
  if (strstr(t, "interface_declaration") ||
      strstr(t, "interface_definition")  ||
      strstr(t, "trait_item"))                          return 6;
  if (strstr(t, "enum_declaration") || strstr(t, "enum_definition") ||
      strstr(t, "enum_item")        || strstr(t, "enum_specifier")) return 5;
  if (strstr(t, "namespace_definition") ||
      strstr(t, "mod_item")  || strstr(t, "module_declaration"))   return 8;
  if (strstr(t, "method_declaration") ||
      strstr(t, "method_definition"))                   return 2;
  if (strstr(t, "function_declaration") ||
      strstr(t, "function_definition")  ||
      strstr(t, "function_item"))                       return 1;
  if (strstr(t, "const_item"))                          return 4;
  return -1;
}

// Returns the first identifier-like named child (holds the declaration name).
static TSNode _sym_name(TSNode node) {
  uint32_t cc  = ts_node_named_child_count(node);
  uint32_t lim = cc < 4 ? cc : 4;
  for (uint32_t i = 0; i < lim; i++) {
    TSNode child = ts_node_named_child(node, i);
    if (ts_node_is_null(child)) continue;
    const char *t = ts_node_type(child);
    if (strcmp(t, "identifier")          == 0 ||
        strcmp(t, "type_identifier")     == 0 ||
        strcmp(t, "property_identifier") == 0 ||
        strcmp(t, "simple_identifier")   == 0) return child;
  }
  TSNode null_node;
  memset(&null_node, 0, sizeof(null_node));
  return null_node;
}

EXPORT const uint32_t *quill_ts_extract_symbols(
    TSTree   *tree,
    uint32_t *out_count)
{
  *out_count = 0;
  if (!tree) return kSymBuf;

  TSNode root = ts_tree_root_node(tree);
  typedef struct { TSNode node; } SF;
  SF stk[2048];
  int sp = 0;
  stk[sp++] = (SF){root};
  uint32_t n = 0;

  while (sp > 0 && n < MAX_SYM) {
    TSNode node = stk[--sp].node;
    int kind = _sym_kind(ts_node_type(node));
    if (kind >= 0) {
      TSNode nm = _sym_name(node);
      if (!ts_node_is_null(nm)) {
        uint32_t b   = n * 5;
        kSymBuf[b+0] = ts_node_start_byte(node);
        kSymBuf[b+1] = ts_node_end_byte(node);
        kSymBuf[b+2] = (uint32_t)kind;
        kSymBuf[b+3] = ts_node_start_byte(nm);
        kSymBuf[b+4] = ts_node_end_byte(nm);
        n++;
      }
    }
    // Push named children in reverse so first child is processed first.
    uint32_t cc = ts_node_named_child_count(node);
    for (int32_t i = (int32_t)cc - 1; i >= 0 && sp < 2047; i--) {
      TSNode child = ts_node_named_child(node, (uint32_t)i);
      if (!ts_node_is_null(child)) stk[sp++] = (SF){child};
    }
  }
  *out_count = n;
  return kSymBuf;
}