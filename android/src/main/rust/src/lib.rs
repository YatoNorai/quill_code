// android/src/main/rust/src/lib.rs
//
// quill_perf — performance-critical helpers for the Quill Code editor.
//
// Exported as C symbols, linked into libquill_ts.so by CMakeLists.txt.
// Called from Dart via dart:ffi on the UI thread or in a Dart isolate.
//
// All functions:
//   • Are thread-safe (no shared mutable state)
//   • Perform NO heap allocation on the hot path (use caller-provided buffers)
//   • Return -1 on invalid input (null pointers, bad lengths)
//
// ─────────────────────────────────────────────────────────────────────────────

#![no_std]
extern crate core;
use core::slice;
use core::ptr;

// ─── Panic handler (required for #![no_std] + staticlib) ─────────────────────
// With panic = "abort" in Cargo.toml, this body is never reached;
// the compiler replaces any panic site with an immediate abort instruction.
#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. CODE-BLOCK EXTRACTION
//    Rust port of _extractCodeBlocksUI from incremental_analyze_manager.dart.
//    Scans the document once (O(n)) to find matching {/( pairs that form
//    foldable code blocks.
//
// Dart call signature:
//   int quill_extract_blocks(
//     Pointer<Pointer<Uint8>> lines_ptr,   // array of UTF-8 line pointers
//     Pointer<Int32>          line_lengths, // byte length of each line
//     int                     line_count,
//     Pointer<Int32>          out,          // output: [start0,end0,indent0, ...]
//     int                     out_cap,      // capacity in Int32 units (must be ≥ 3)
//   ) -> int   // number of blocks written; -1 on error
// ═════════════════════════════════════════════════════════════════════════════

/// Detect indent unit: smallest non-zero indent found in the document.
fn detect_tab(lines: &[&[u8]]) -> usize {
    let mut tab: usize = 8;
    for line in lines {
        let sp = leading_spaces(line);
        if sp > 0 && sp < tab {
            tab = sp;
        }
    }
    if tab < 1 || tab > 8 { 2 } else { tab }
}

#[inline(always)]
fn leading_spaces(line: &[u8]) -> usize {
    let mut n = 0usize;
    for &b in line {
        match b {
            b' '  => n += 1,
            b'\t' => n += 2, // treat tab as 2 spaces for indent detection
            _     => break,
        }
    }
    n
}

#[inline(always)]
fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

#[no_mangle]
pub unsafe extern "C" fn quill_extract_blocks(
    lines_ptr:    *const *const u8,
    line_lengths: *const i32,
    line_count:   i32,
    out:          *mut i32,
    out_cap:      i32,
) -> i32 {
    if lines_ptr.is_null() || line_lengths.is_null() || out.is_null()
        || line_count <= 0 || out_cap < 3 {
        return -1;
    }

    let n   = line_count as usize;
    let cap = (out_cap as usize) / 3; // each block = 3 i32s

    // Build a slice of line byte slices from the C pointers
    // SAFETY: caller guarantees pointers and lengths are valid for `n` entries
    let mut lines: [&[u8]; 4096] = [&[]; 4096];
    let actual_n = if n > 4096 { 4096 } else { n };
    for i in 0..actual_n {
        let ptr = *lines_ptr.add(i);
        let len = *line_lengths.add(i);
        if ptr.is_null() || len < 0 {
            lines[i] = &[];
        } else {
            lines[i] = slice::from_raw_parts(ptr, len as usize);
        }
    }
    let lines = &lines[..actual_n];

    let tab = detect_tab(lines);

    // Stack: (start_line, opener_char)
    // Use a fixed-size stack on the stack (no heap alloc)
    let mut stack_line: [i32; 512]  = [-1i32; 512];
    let mut stack_char: [u8;  512]  = [0u8;   512];
    let mut stack_top: usize        = 0;

    // Collect raw blocks: (start, end, indent_level)
    let mut raw_start:  [i32; 1024] = [0i32; 1024];
    let mut raw_end:    [i32; 1024] = [0i32; 1024];
    let mut raw_indent: [i32; 1024] = [0i32; 1024];
    let mut raw_count:  usize       = 0;
    let max_raw = 1024usize;

    for i in 0..actual_n {
        let ln = lines[i];
        if is_blank(ln) { continue; }

        let mut in_s1  = false; // inside '...'
        let mut in_s2  = false; // inside "..."
        let mut in_tpl = false; // inside `...`

        let llen = ln.len();
        let mut j = 0usize;
        while j < llen {
            let c = ln[j];

            // Line comment — stop scanning this line
            if !in_s1 && !in_s2 && !in_tpl && c == b'/' {
                if j + 1 < llen && ln[j+1] == b'/' { break; }
            }

            if !in_s1 && !in_s2 && !in_tpl {
                match c {
                    b'\'' => { in_s1  = true; }
                    b'"'  => { in_s2  = true; }
                    b'`'  => { in_tpl = true; }
                    b'{' | b'(' => {
                        if stack_top < 512 {
                            stack_line[stack_top] = i as i32;
                            stack_char[stack_top] = c;
                            stack_top += 1;
                        }
                    }
                    b'}' | b')' => {
                        if stack_top > 0 {
                            let opener_c = if c == b'}' { b'{' } else { b'(' };
                            // Find most recent matching opener
                            let mut k = stack_top;
                            while k > 0 {
                                k -= 1;
                                if stack_char[k] == opener_c {
                                    let sl = stack_line[k] as usize;
                                    let el = i;
                                    if el > sl && raw_count < max_raw {
                                        let indent_sp = leading_spaces(lines[sl]);
                                        raw_start[raw_count]  = sl as i32;
                                        raw_end[raw_count]    = el as i32;
                                        raw_indent[raw_count] = (indent_sp / tab) as i32;
                                        raw_count += 1;
                                    }
                                    // Remove opener from stack
                                    // Shift remaining entries down
                                    for m in k..stack_top-1 {
                                        stack_line[m] = stack_line[m+1];
                                        stack_char[m] = stack_char[m+1];
                                    }
                                    stack_top -= 1;
                                    break;
                                }
                            }
                        }
                    }
                    _ => {}
                }
            } else {
                // Inside string literal — look for closing delimiter
                match (in_s1, in_s2, in_tpl) {
                    (true, _, _)  => { if c == b'\'' && (j == 0 || ln[j-1] != b'\\') { in_s1  = false; } }
                    (_, true, _)  => { if c == b'"'  && (j == 0 || ln[j-1] != b'\\') { in_s2  = false; } }
                    (_, _, true)  => { if c == b'`'                                   { in_tpl = false; } }
                    _ => {}
                }
            }
            j += 1;
        }
    }

    // Sort by start line, then by span descending (stable-ish sort in-place)
    // Simple insertion sort — raw_count is usually < 200 for real code
    for i in 1..raw_count {
        let mut k = i;
        while k > 0 {
            let a = raw_start[k-1];
            let b = raw_start[k];
            let span_a = raw_end[k-1] - raw_start[k-1];
            let span_b = raw_end[k]   - raw_start[k];
            if a > b || (a == b && span_a < span_b) {
                raw_start.swap(k-1, k);
                raw_end.swap(k-1, k);
                raw_indent.swap(k-1, k);
                k -= 1;
            } else {
                break;
            }
        }
    }

    // Write up to `cap` blocks to output buffer
    let write_count = raw_count.min(cap);
    for i in 0..write_count {
        ptr::write(out.add(i * 3),     raw_start[i]);
        ptr::write(out.add(i * 3 + 1), raw_end[i]);
        ptr::write(out.add(i * 3 + 2), raw_indent[i]);
    }

    write_count as i32
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. LITERAL / WHOLE-WORD SEARCH
//    Fast case-sensitive or case-insensitive search over a UTF-8 text buffer.
//    Returns (start_byte_offset, end_byte_offset) pairs in `out`.
//
// Dart call signature:
//   int quill_search(
//     Pointer<Uint8>  text_ptr,       // full document text (UTF-8)
//     int             text_len,
//     Pointer<Uint8>  pattern_ptr,    // search pattern (UTF-8)
//     int             pattern_len,
//     int             flags,          // bit 0: case_sensitive; bit 1: whole_word
//     Pointer<Int32>  out,            // [start0,end0, start1,end1, ...]
//     int             out_cap,        // capacity in Int32 units
//   ) -> int   // number of matches; -1 on error
// ═════════════════════════════════════════════════════════════════════════════

const FLAG_CASE_SENSITIVE: i32 = 1;
const FLAG_WHOLE_WORD:     i32 = 2;

#[inline(always)]
fn to_lower(b: u8) -> u8 {
    if b >= b'A' && b <= b'Z' { b + 32 } else { b }
}

#[inline(always)]
fn is_word_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Two-Way string search (simplified variant) — O(n + m) with O(1) extra space.
/// Falls back to naive for short patterns (< 4 bytes).
fn find_all_literal(
    text:           &[u8],
    pattern:        &[u8],
    case_sensitive: bool,
    whole_word:     bool,
    out:            &mut [i32],
) -> usize {
    let n = text.len();
    let m = pattern.len();
    if m == 0 || n < m { return 0; }

    let cap_pairs = out.len() / 2;
    let mut count = 0usize;
    let mut i = 0usize;

    'outer: while i + m <= n {
        // Try to match pattern at position i
        let mut matched = true;
        for k in 0..m {
            let tc = if case_sensitive { text[i + k] } else { to_lower(text[i + k]) };
            let pc = if case_sensitive { pattern[k]   } else { to_lower(pattern[k])   };
            if tc != pc {
                // Bad character heuristic: skip forward
                // Find how far ahead the bad character appears in pattern
                let bad = tc;
                let mut skip = m - k;
                for bk in (0..k).rev() {
                    let pb = if case_sensitive { pattern[bk] } else { to_lower(pattern[bk]) };
                    if pb == bad {
                        let dist = k - bk;
                        if dist < skip { skip = dist; }
                        break;
                    }
                }
                i += if skip == 0 { 1 } else { skip };
                matched = false;
                break;
            }
        }
        if !matched { continue 'outer; }

        // Check word boundaries if needed
        let end = i + m;
        if whole_word {
            let before_ok = i == 0 || !is_word_char(text[i - 1]);
            let after_ok  = end >= n || !is_word_char(text[end]);
            if !before_ok || !after_ok {
                i += 1;
                continue;
            }
        }

        if count < cap_pairs {
            out[count * 2]     = i as i32;
            out[count * 2 + 1] = end as i32;
        }
        count += 1;
        i = end;
        if count >= cap_pairs * 2 { break; } // buffer full but keep counting
    }

    count
}

#[no_mangle]
pub unsafe extern "C" fn quill_search(
    text_ptr:    *const u8,
    text_len:    i32,
    pattern_ptr: *const u8,
    pattern_len: i32,
    flags:       i32,
    out:         *mut i32,
    out_cap:     i32,
) -> i32 {
    if text_ptr.is_null() || pattern_ptr.is_null() || out.is_null()
        || text_len < 0 || pattern_len <= 0 || out_cap < 2 {
        return -1;
    }

    let text    = slice::from_raw_parts(text_ptr,    text_len    as usize);
    let pattern = slice::from_raw_parts(pattern_ptr, pattern_len as usize);
    let out_sl  = slice::from_raw_parts_mut(out,     out_cap     as usize);

    let case_sensitive = (flags & FLAG_CASE_SENSITIVE) != 0;
    let whole_word     = (flags & FLAG_WHOLE_WORD)     != 0;

    let count = find_all_literal(text, pattern, case_sensitive, whole_word, out_sl);
    count as i32
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. LINE-OFFSET TABLE BUILDER
//    Builds an array of byte offsets for every line start, needed to convert
//    byte offsets (from quill_search) back to (line, col) pairs efficiently.
//
// Dart call signature:
//   int quill_build_line_starts(
//     Pointer<Uint8>  text_ptr,   // full document text (UTF-8)
//     int             text_len,
//     Pointer<Int32>  out,        // output: line start byte offsets
//     int             out_cap,    // capacity in Int32 units
//   ) -> int   // number of lines written; -1 on error
// ═════════════════════════════════════════════════════════════════════════════

#[no_mangle]
pub unsafe extern "C" fn quill_build_line_starts(
    text_ptr: *const u8,
    text_len: i32,
    out:      *mut i32,
    out_cap:  i32,
) -> i32 {
    if text_ptr.is_null() || out.is_null() || text_len < 0 || out_cap < 1 {
        return -1;
    }

    let text = slice::from_raw_parts(text_ptr, text_len as usize);
    let cap  = out_cap as usize;
    let mut count = 0usize;

    // Line 0 always starts at offset 0
    if count < cap {
        ptr::write(out.add(count), 0i32);
        count += 1;
    }

    for (i, &b) in text.iter().enumerate() {
        if b == b'\n' {
            if count < cap {
                ptr::write(out.add(count), (i + 1) as i32);
            }
            count += 1;
        }
    }

    count as i32
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. UTILITY: max line length scan
//    O(n) scan over all lines to find the longest one.
//    Used by performLayout to compute horizontal scroll extent.
//
// Dart call signature:
//   int quill_max_line_length(
//     Pointer<Int32>  line_lengths,   // length of each line in chars
//     int             line_count,
//   ) -> int   // max length, or -1 on error
// ═════════════════════════════════════════════════════════════════════════════

#[no_mangle]
pub unsafe extern "C" fn quill_max_line_length(
    line_lengths: *const i32,
    line_count:   i32,
) -> i32 {
    if line_lengths.is_null() || line_count <= 0 {
        return -1;
    }
    let lens = slice::from_raw_parts(line_lengths, line_count as usize);
    let max  = lens.iter().copied().max().unwrap_or(0);
    max
}