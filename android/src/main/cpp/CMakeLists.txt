cmake_minimum_required(VERSION 3.22.1)
project(quill_tree_sitter VERSION 0.22.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD   11)
set(CMAKE_CXX_STANDARD 17)

# ── Paths ─────────────────────────────────────────────────────────────────────
set(TS_ROOT   "${CMAKE_SOURCE_DIR}/tree-sitter")
set(GRAM_ROOT "${CMAKE_SOURCE_DIR}/grammars")

include_directories(
  "${TS_ROOT}/lib/include"
  "${TS_ROOT}/lib/src"
)

# ══════════════════════════════════════════════════════════════════════════════
# libtree_sitter  (the core runtime)
# ══════════════════════════════════════════════════════════════════════════════
# tree-sitter 0.23+ ships a single lib.c amalgamation.
# Earlier versions have individual .c files. Support both.
if(EXISTS "${TS_ROOT}/lib/src/lib.c")
  set(TS_SRCS "${TS_ROOT}/lib/src/lib.c")
else()
  file(GLOB TS_SRCS "${TS_ROOT}/lib/src/*.c")
endif()

add_library(tree_sitter STATIC ${TS_SRCS})
target_include_directories(tree_sitter PUBLIC
  "${TS_ROOT}/lib/include"
  "${TS_ROOT}/lib/src"
)

# FIX 1: api.h already defines TREE_SITTER_LANGUAGE_VERSION (e.g. 14).
# Passing -D directly causes a redefinition warning. Use -U first to undefine
# whatever the header sets, then redefine to 15 so the runtime accepts all
# grammar ABI versions 13–15.
target_compile_options(tree_sitter PRIVATE
  -UTREE_SITTER_LANGUAGE_VERSION
  -DTREE_SITTER_LANGUAGE_VERSION=15
  -UTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION
  -DTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION=13
  -O2
  -fvisibility=hidden
  -ffunction-sections
  -fdata-sections
)

# ══════════════════════════════════════════════════════════════════════════════
# Queries provided by Dart TsQueries. No C generation needed.

# ══════════════════════════════════════════════════════════════════════════════
# Grammar helper macro
# ══════════════════════════════════════════════════════════════════════════════
macro(add_grammar NAME DIR)
  file(GLOB GRAM_SRCS "${GRAM_ROOT}/${DIR}/src/*.c"
                       "${GRAM_ROOT}/${DIR}/src/*.cc")
  add_library("grammar_${NAME}" STATIC ${GRAM_SRCS})
  target_include_directories("grammar_${NAME}" PRIVATE
    "${TS_ROOT}/lib/include"
    "${GRAM_ROOT}/${DIR}/src"
  )
  # FIX 2: Generated grammar parsers (especially tree-sitter-cpp at 5.8 MB .o)
  # are extremely expensive to compile at -O3 and cause OOM kills on CI runners
  # with limited RAM (~7 GB) when multiple grammars compile in parallel.
  # -O1 is sufficient — grammars are pre-generated, not hand-written hot paths.
  set_source_files_properties(${GRAM_SRCS} PROPERTIES COMPILE_FLAGS
    "-O1 -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-parameter -Wno-sign-compare")
endmacro()

# ══════════════════════════════════════════════════════════════════════════════
# Grammars  (add more by repeating the macro call)
# ══════════════════════════════════════════════════════════════════════════════
add_grammar(dart       tree-sitter-dart)
add_grammar(javascript tree-sitter-javascript)
add_grammar(typescript tree-sitter-typescript/typescript)
add_grammar(python     tree-sitter-python)
add_grammar(kotlin     tree-sitter-kotlin)
add_grammar(rust       tree-sitter-rust)
add_grammar(cpp        tree-sitter-cpp)
add_grammar(c          tree-sitter-c)
add_grammar(html       tree-sitter-html)
add_grammar(css        tree-sitter-css)
add_grammar(json       tree-sitter-json)
add_grammar(yaml       tree-sitter-yaml)
# tree-sitter-yaml/src/schema.generated.cc omits #include <stdint.h> — force-include it.
target_compile_options(grammar_yaml PRIVATE
  "-include" "stdint.h"
)
add_grammar(bash       tree-sitter-bash)
add_grammar(xml        tree-sitter-xml/xml)

# ══════════════════════════════════════════════════════════════════════════════
# quill_ts  — the single shared library loaded by Dart FFI
# ══════════════════════════════════════════════════════════════════════════════
add_library(quill_ts SHARED
  "${CMAKE_SOURCE_DIR}/quill_ts_bridge.c"
)

target_include_directories(quill_ts PRIVATE
  "${TS_ROOT}/lib/include"
  "${CMAKE_BINARY_DIR}/generated"
)

# quill_ts_bridge.c is hand-written hot-path code — keep -O2 here.
# Same -U/-D pattern as tree_sitter to stay consistent and warning-free.
target_compile_options(quill_ts PRIVATE
  -O2
  -fvisibility=hidden
  -ffunction-sections
  -fdata-sections
  -UTREE_SITTER_LANGUAGE_VERSION
  -DTREE_SITTER_LANGUAGE_VERSION=15
  -UTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION
  -DTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION=13
)

target_link_options(quill_ts PRIVATE -Wl,--gc-sections)

target_link_libraries(quill_ts
  tree_sitter
  grammar_dart
  grammar_javascript
  grammar_typescript
  grammar_python
  grammar_kotlin
  grammar_rust
  grammar_cpp
  grammar_c
  grammar_html
  grammar_css
  grammar_json
  grammar_yaml
  grammar_bash
  grammar_xml
  android
  log
)

# Strip debug symbols in release to minimise .so size (~200 KB per grammar)
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_custom_command(TARGET quill_ts POST_BUILD
    COMMAND ${CMAKE_STRIP} --strip-unneeded
            $<TARGET_FILE:quill_ts>
  )
endif()  "${TS_ROOT}/lib/include"
  "${CMAKE_BINARY_DIR}/generated"
)

# quill_ts_bridge.c also prints TREE_SITTER_LANGUAGE_VERSION via macros —
# must define the same version here so the log and check are consistent.
target_compile_definitions(quill_ts PRIVATE
  TREE_SITTER_LANGUAGE_VERSION=15
  TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION=13
)

target_link_libraries(quill_ts
  tree_sitter
  grammar_dart
  grammar_javascript
  grammar_typescript
  grammar_python
  grammar_kotlin
  grammar_rust
  grammar_cpp
  grammar_c
  grammar_html
  grammar_css
  grammar_json
  grammar_yaml
  grammar_bash
  grammar_xml
  android
  log
)

# Strip debug symbols in release to minimise .so size (~200 KB per grammar)
if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_custom_command(TARGET quill_ts POST_BUILD
    COMMAND ${CMAKE_STRIP} --strip-unneeded
            $<TARGET_FILE:quill_ts>
  )
endif()
