cmake_minimum_required(VERSION 3.22.1)
project(quill_perf_native VERSION 1.0 LANGUAGES C)

# ── Rust target detection ──────────────────────────────────────────────────────
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

set(RUST_ROOT "${CMAKE_SOURCE_DIR}/../rust")

if(NOT RUST_TARGET STREQUAL "")
  set(RUST_LIB "${RUST_ROOT}/target/${RUST_TARGET}/release/libquill_perf.a")
else()
  set(RUST_LIB "${RUST_ROOT}/target/release/libquill_perf.a")
endif()

# ── Use pre-built .a (built by Gradle buildRust_* task before CMake runs) ──────
if(EXISTS "${RUST_LIB}")
  message(STATUS "quill_perf: found ${RUST_LIB}")
  add_library(quill_perf_static STATIC IMPORTED)
  set_target_properties(quill_perf_static PROPERTIES IMPORTED_LOCATION "${RUST_LIB}")
else()
  message(FATAL_ERROR
    "Rust library not found: ${RUST_LIB}\n"
    "Make sure Rust is installed and cargo ran successfully.\n"
    "The Gradle buildRust_<abi> task should have built it before CMake.")
endif()

# ── Minimal C stub — needed so CMake produces a real .so ───────────────────────
# A pure IMPORTED STATIC lib cannot be loaded at runtime; we need a SHARED lib.
# This stub just re-exports everything from libquill_perf.a.
add_library(quill_perf SHARED
  "${CMAKE_SOURCE_DIR}/quill_perf_stub.c"
)

target_link_libraries(quill_perf
  quill_perf_static
  log
)

target_link_options(quill_perf PRIVATE -Wl,--gc-sections)

set_target_properties(quill_perf PROPERTIES
  C_VISIBILITY_PRESET   hidden
  LINK_FLAGS            "-Wl,--export-dynamic"
)

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_custom_command(TARGET quill_perf POST_BUILD
    COMMAND ${CMAKE_STRIP} --strip-unneeded $<TARGET_FILE:quill_perf>)
endif()
