/*
 * quill_perf_stub.c
 *
 * Minimal stub so CMake creates a real shared library (.so) from the
 * Rust static archive (libquill_perf.a).
 *
 * A pure STATIC IMPORTED library cannot be dlopen()'d at runtime.
 * Adding this one-line C file makes CMake emit a SHARED library that
 * re-exports all symbols from the linked .a via --export-dynamic.
 *
 * The actual code lives entirely in lib.rs (Rust).
 */

/* No-op sentinel — confirms the library loaded successfully. */
int quill_perf_loaded(void) { return 1; }
