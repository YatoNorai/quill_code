cmake_minimum_required(VERSION 3.22.1)
project(quill_tree_sitter VERSION 0.22.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD   11)
set(CMAKE_CXX_STANDARD 17)

# Paths
set(TS_ROOT   "${CMAKE_SOURCE_DIR}/tree-sitter")
set(GRAM_ROOT "${CMAKE_SOURCE_DIR}/grammars")
set(RUST_ROOT "${CMAKE_SOURCE_DIR}/../rust")

include_directories("${TS_ROOT}/lib/include" "${TS_ROOT}/lib/src")

# libtree_sitter
if(EXISTS "${TS_ROOT}/lib/src/lib.c")
  set(TS_SRCS "${TS_ROOT}/lib/src/lib.c")
else()
  file(GLOB TS_SRCS "${TS_ROOT}/lib/src/*.c")
endif()
add_library(tree_sitter STATIC ${TS_SRCS})
target_include_directories(tree_sitter PUBLIC "${TS_ROOT}/lib/include" "${TS_ROOT}/lib/src")
target_compile_options(tree_sitter PRIVATE
  -UTREE_SITTER_LANGUAGE_VERSION -DTREE_SITTER_LANGUAGE_VERSION=15
  -UTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION -DTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION=13
  -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)

macro(add_grammar NAME DIR)
  file(GLOB GRAM_SRCS "${GRAM_ROOT}/${DIR}/src/*.c" "${GRAM_ROOT}/${DIR}/src/*.cc")
  add_library("grammar_${NAME}" STATIC ${GRAM_SRCS})
  target_include_directories("grammar_${NAME}" PRIVATE "${TS_ROOT}/lib/include" "${GRAM_ROOT}/${DIR}/src")
  set_source_files_properties(${GRAM_SRCS} PROPERTIES COMPILE_FLAGS
    "-O1 -fvisibility=hidden -ffunction-sections -fdata-sections -Wno-unused-parameter -Wno-sign-compare")
endmacro()

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
target_compile_options(grammar_yaml PRIVATE "-include" "stdint.h")
add_grammar(bash       tree-sitter-bash)
add_grammar(xml        tree-sitter-xml/xml)

# ── quill_perf: Rust static library (optional — graceful degradation) ─────────
#
# Strategy:
#   1. Map ABI → Rust target triple.
#   2. Check if the pre-built .a already exists (built by build_rust.bat / .sh).
#   3. If it exists   → import it and link; Dart FFI bridge will use Rust.
#   4. If it doesn't  → define a no-op INTERFACE library; Dart falls back to
#      pure-Dart implementations (search, block extraction) transparently.
#
# To pre-build on Windows:
#   android\src\main\rust\build_rust.bat
# To pre-build on Linux/macOS:
#   android/src/main/rust/build_rust.sh
# ──────────────────────────────────────────────────────────────────────────────

if(ANDROID_ABI STREQUAL "arm64-v8a")
  set(RUST_TARGET "aarch64-linux-android")
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
  set(RUST_TARGET "armv7-linux-androideabi")
elseif(ANDROID_ABI STREQUAL "x86_64")
  set(RUST_TARGET "x86_64-linux-android")
elseif(ANDROID_ABI STREQUAL "x86")
  set(RUST_TARGET "i686-linux-android")
else()
  set(RUST_TARGET "")
endif()

if(NOT RUST_TARGET STREQUAL "")
  set(RUST_PREBUILT "${RUST_ROOT}/target/${RUST_TARGET}/release/libquill_perf.a")
else()
  set(RUST_PREBUILT "${RUST_ROOT}/target/release/libquill_perf.a")
endif()

if(EXISTS "${RUST_PREBUILT}")
  message(STATUS "quill_perf: using pre-built Rust library at ${RUST_PREBUILT}")
  add_library(quill_perf STATIC IMPORTED)
  set_target_properties(quill_perf PROPERTIES IMPORTED_LOCATION "${RUST_PREBUILT}")
  set(QUILL_PERF_AVAILABLE TRUE)
else()
  # Gradle should have built this before CMake runs.
  # If we're here, it means:
  #   a) Rust/cargo is not installed, OR
  #   b) The Gradle buildRust task failed (check the Gradle output above).
  #
  # Action: install Rust (https://rustup.rs) and re-run flutter run.
  # The build will still SUCCEED using pure-Dart fallbacks.
  message(WARNING "quill_perf.a not found at ${RUST_PREBUILT}")
  message(WARNING "Rust acceleration disabled — install Rust to enable it.")
  message(WARNING "  https://rustup.rs")
  add_library(quill_perf INTERFACE)
  set(QUILL_PERF_AVAILABLE FALSE)
endif()

# ── quill_ts: the single shared library loaded by Dart FFI ────────────────────
add_library(quill_ts SHARED "${CMAKE_SOURCE_DIR}/quill_ts_bridge.c")
target_include_directories(quill_ts PRIVATE
  "${TS_ROOT}/lib/include"
  "${CMAKE_BINARY_DIR}/generated")
target_compile_options(quill_ts PRIVATE
  -O2 -fvisibility=hidden -ffunction-sections -fdata-sections
  -UTREE_SITTER_LANGUAGE_VERSION -DTREE_SITTER_LANGUAGE_VERSION=15
  -UTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION
  -DTREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION=13)
target_compile_definitions(quill_ts PRIVATE
  TREE_SITTER_LANGUAGE_VERSION=15
  TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION=13)
target_link_options(quill_ts PRIVATE -Wl,--gc-sections)

target_link_libraries(quill_ts
  quill_perf
  tree_sitter
  grammar_dart grammar_javascript grammar_typescript grammar_python
  grammar_kotlin grammar_rust grammar_cpp grammar_c grammar_html
  grammar_css grammar_json grammar_yaml grammar_bash grammar_xml
  android log)

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_custom_command(TARGET quill_ts POST_BUILD
    COMMAND ${CMAKE_STRIP} --strip-unneeded $<TARGET_FILE:quill_ts>)
endif()
