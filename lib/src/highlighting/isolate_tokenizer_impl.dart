// lib/src/highlighting/isolate_tokenizer.dart
//
// Persistent isolate for full-document tokenization + code-block extraction.
//
// Architecture
// ────────────
//   • One long-lived Dart Isolate per editor instance (spawned lazily).
//     RegExp objects compiled once in the isolate, reused across jobs.
//   • UI thread sends jobs via SendPort; isolate replies via its own SendPort.
//   • Jobs are versioned — stale results silently discarded on the UI side.
//   • Result data transferred as TransferableTypedData (zero-copy channel).
//   • Progressive span updates every _kChunk lines for large files.
//
// Message protocol
// ────────────────
// UI → Isolate:
//   {'cmd':'job','lines':List<String>,'version':int,
//    /* first job */ 'rules':[{'p':pattern,'t':typeIdx}], 'wordMap':{...}}
//   {'cmd':'destroy'}
//
// Isolate → UI:
//   {'cmd':'ready','port':SendPort}                    (once, on spawn)
//   {'cmd':'progress','version':int,'data':TTD}        (Uint32List spans)
//   {'cmd':'spans',   'version':int,'data':TTD}        (Uint32List final spans)
//   {'cmd':'blocks',  'version':int,'data':TTD}        (Int32List blocks)

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'span.dart';
import 'code_block.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Encoding / decoding (UI thread + isolate both use these)
// ══════════════════════════════════════════════════════════════════════════════

// Uint32List: [lineCount, per-line: spanCount, col_0,type_0, col_1,type_1, ...]
Uint32List _encodeSpans(List<List<CodeSpan>> spans) {
  int sz = 1;
  for (final ls in spans) sz += 1 + ls.length * 2;
  final buf = Uint32List(sz);
  buf[0] = spans.length;
  int i = 1;
  for (final ls in spans) {
    buf[i++] = ls.length;
    for (final sp in ls) { buf[i++] = sp.column; buf[i++] = sp.type.index; }
  }
  return buf;
}

List<List<CodeSpan>> decodeSpans(Uint32List buf) {
  final lc  = buf[0];
  final out = List<List<CodeSpan>>.filled(lc, const [], growable: false);
  int i = 1;
  for (int li = 0; li < lc; li++) {
    final sc = buf[i++];
    if (sc == 0) continue;
    final row = List<CodeSpan>.filled(sc, const CodeSpan(column: 0, type: TokenType.normal));
    for (int si = 0; si < sc; si++) {
      row[si] = CodeSpan(column: buf[i++], type: TokenType.values[buf[i++]]);
    }
    out[li] = row;
  }
  return out;
}

// Int32List: [blockCount, start_0,end_0,indent_0, ...]
Int32List _encodeBlocks(List<(int, int, int)> blocks) {
  final buf = Int32List(1 + blocks.length * 3);
  buf[0] = blocks.length;
  int i = 1;
  for (final (s, e, ind) in blocks) { buf[i++] = s; buf[i++] = e; buf[i++] = ind; }
  return buf;
}

List<CodeBlock> decodeBlocks(Int32List buf) {
  final n   = buf[0];
  final out = <CodeBlock>[];
  for (int i = 0; i < n; i++) {
    final b = 1 + i * 3;
    out.add(CodeBlock(startLine: buf[b], endLine: buf[b+1], indent: buf[b+2]));
  }
  return out;
}

// ══════════════════════════════════════════════════════════════════════════════
// Isolate-side — NO Flutter dependencies; runs in isolate heap
// ══════════════════════════════════════════════════════════════════════════════

const int _kChunk = 400; // lines per progress pulse

class _IsoRule {
  final RegExp re;
  final int    typeIdx;
  _IsoRule(String p, this.typeIdx) : re = RegExp(p);
}

// Module-level variables live in isolate heap → survive between jobs.
List<_IsoRule>   _isoRules   = const [];
Map<String, int> _isoWordMap = const {};

List<CodeSpan> _tokenizeLine(String line) {
  if (line.isEmpty) return const [];
  final rules   = _isoRules;
  final wordMap = _isoWordMap;
  final spans   = <CodeSpan>[];
  final len     = line.length;
  int pos = 0;

  while (pos < len) {
    final c0      = line.codeUnitAt(pos);
    final isWord  = (c0 >= 65 && c0 <= 90) || (c0 >= 97 && c0 <= 122) || c0 == 95;

    if (isWord) {
      // Consume entire identifier in one pass (avoids re-entering rule loop
      // for every character of a long name like `_cachedFoldFree`).
      int end = pos + 1;
      while (end < len) {
        final c = line.codeUnitAt(end);
        if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95) end++;
        else break;
      }
      final word = line.substring(pos, end);

      final mapped = wordMap[word]; // O(1): keyword / type / built-in
      if (mapped != null) {
        spans.add(CodeSpan(column: pos, type: TokenType.values[mapped]));
        pos = end; continue;
      }
      if (c0 >= 65 && c0 <= 90) {          // UpperCase → class/type
        spans.add(CodeSpan(column: pos, type: TokenType.type_));
        pos = end; continue;
      }
      if (end < len && line.codeUnitAt(end) == 40) { // followed by '(' → func
        spans.add(CodeSpan(column: pos, type: TokenType.function_));
        pos = end; continue;
      }
      if (spans.isEmpty || spans.last.type != TokenType.identifier) {
        spans.add(CodeSpan(column: pos, type: TokenType.identifier));
      }
      pos = end; continue;
    }

    // Non-word char: try full rule list (strings, comments, numbers, ops...).
    bool hit = false;
    for (final r in rules) {
      final m = r.re.matchAsPrefix(line, pos);
      if (m != null && m.end > pos) {
        spans.add(CodeSpan(column: pos, type: TokenType.values[r.typeIdx]));
        pos = m.end; hit = true; break;
      }
    }
    if (!hit) {
      if (spans.isEmpty || spans.last.type != TokenType.normal) {
        spans.add(CodeSpan(column: pos, type: TokenType.normal));
      }
      pos++;
    }
  }
  return spans;
}

// ── Code-block extractor (pure Dart) ─────────────────────────────────────────

bool _blk(String s) {
  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i); if (c != 32 && c != 9) return false;
  }
  return true;
}

int _ls(String s, int tab) {
  int sp = 0;
  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 32) sp++; else if (c == 9) sp += tab; else break;
  }
  return sp;
}

List<(int, int, int)> _extractBlocks(List<String> lines) {
  final stack  = <(int, int)>[];
  final result = <(int, int, int)>[];
  int tab = 2;
  for (final l in lines) {
    if (_blk(l)) continue;
    final sp = _ls(l, 2); if (sp > 0 && sp < tab) tab = sp;
  }
  if (tab < 1) tab = 2;

  for (int i = 0; i < lines.length; i++) {
    final ln = lines[i]; if (_blk(ln)) continue;
    bool s1 = false, s2 = false, tpl = false;
    final llen = ln.length;
    for (int j = 0; j < llen; j++) {
      final c = ln.codeUnitAt(j);
      if (c == 47 && j+1 < llen && ln.codeUnitAt(j+1) == 47) break; // line comment
      if (!s1 && !s2 && !tpl) {
        if      (c == 39)  s1 = true;
        else if (c == 34)  s2 = true;
        else if (c == 96)  tpl = true;
        else if (c == 123 || c == 40) stack.add((i, c));
        else if (c == 125 || c == 41) {
          if (stack.isNotEmpty) {
            final (sl, _) = stack.removeLast();
            if (i > sl) result.add((sl, i, _ls(lines[sl], tab) ~/ tab));
          }
        }
      } else {
        if (s1  && c == 39 && (j==0 || ln.codeUnitAt(j-1) != 92)) s1  = false;
        if (s2  && c == 34 && (j==0 || ln.codeUnitAt(j-1) != 92)) s2  = false;
        if (tpl && c == 96)                                          tpl = false;
      }
    }
    final tr = ln.trimRight();
    if (tr.isNotEmpty && tr.codeUnitAt(tr.length-1) == 58) stack.add((i, 58));
  }
  final last = lines.length - 1;
  while (stack.isNotEmpty) {
    final (sl, _) = stack.removeLast();
    if (last > sl) result.add((sl, last, _ls(lines[sl], tab) ~/ tab));
  }
  return result;
}

// ── Isolate entry point (MUST be top-level) ───────────────────────────────────

void isolateEntry(SendPort mainPort) {
  final rp = ReceivePort();
  mainPort.send(<String, dynamic>{'cmd': 'ready', 'port': rp.sendPort});

  rp.listen((dynamic raw) {
    final msg = raw as Map<String, dynamic>;
    final cmd = msg['cmd'] as String;

    if (cmd == 'destroy') { rp.close(); return; }

    if (cmd == 'job') {
      // Rules sent once on first job; stay in module vars for subsequent jobs.
      if (msg.containsKey('rules')) {
        final rawR = msg['rules'] as List<dynamic>;
        _isoRules = rawR.map<_IsoRule>((r) {
          final m = r as Map<String, dynamic>;
          return _IsoRule(m['p'] as String, m['t'] as int);
        }).toList();
        final rawW = msg['wordMap'] as Map<dynamic, dynamic>? ?? const {};
        _isoWordMap = {for (final e in rawW.entries) e.key as String: e.value as int};
      }
      final lines   = (msg['lines'] as List<dynamic>).cast<String>();
      final version = msg['version'] as int;
      _runJob(mainPort, lines, version);
    }
  });
}

void _runJob(SendPort out, List<String> lines, int version) {
  final lc  = lines.length;
  final all = List<List<CodeSpan>>.filled(lc, const [], growable: false);

  for (int i = 0; i < lc; i++) {
    all[i] = _tokenizeLine(lines[i]);
    if ((i + 1) % _kChunk == 0 && i + 1 < lc) {
      // Progress pulse — lets editor show partial colors during long analysis.
      // 'upTo' tells the UI which lines (0..upTo) are freshly tokenised so it
      // can merge: keep old spans for untouched lines instead of going grey.
      final enc = _encodeSpans(all);
      out.send(<String, dynamic>{
        'cmd': 'progress', 'version': version, 'upTo': i,
        'data': TransferableTypedData.fromList(<TypedData>[enc]),
      });
    }
  }

  // Send final spans.
  out.send(<String, dynamic>{
    'cmd': 'spans', 'version': version,
    'data': TransferableTypedData.fromList(<TypedData>[_encodeSpans(all)]),
  });

  // Code-blocks run immediately after tokenisation in the SAME job invocation
  // so the UI never blocks on either.
  final blocks = _extractBlocks(lines);
  out.send(<String, dynamic>{
    'cmd': 'blocks', 'version': version,
    'data': TransferableTypedData.fromList(<TypedData>[_encodeBlocks(blocks)]),
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// UI-side wrapper
// ══════════════════════════════════════════════════════════════════════════════

/// [upTo] is the last line index that was freshly tokenised in this batch.
/// -1 on final delivery (all lines are final).
typedef SpansCallback  = void Function(int version, List<List<CodeSpan>> spans, bool isFinal, int upTo);
typedef BlocksCallback = void Function(int version, List<CodeBlock> blocks);

/// Long-lived isolate wrapper.  One instance per [IncrementalAnalyzeManager].
class IsolateTokenizer {
  final SpansCallback  onSpans;
  final BlocksCallback onBlocks;

  Isolate?         _isolate;
  SendPort?        _toIsolate;
  ReceivePort?     _fromIsolate;
  Completer<void>? _spawnFut;   // serialise concurrent spawn calls

  bool _destroyed  = false;
  bool _rulesSent  = false;
  int  _currentVer = -1;

  List<Map<String, dynamic>>? _rulePay;
  Map<String, int>?           _wordPay;

  IsolateTokenizer({required this.onSpans, required this.onBlocks});

  void setRules(List<Map<String, dynamic>> rules, Map<String, int> wordMap) {
    _rulePay   = rules;
    _wordPay   = wordMap;
    _rulesSent = false;
  }

  Future<void> _ensureSpawned() async {
    if (_isolate != null) return;
    if (_spawnFut != null) return _spawnFut!.future;

    final c  = Completer<void>();
    _spawnFut = c;

    final rp = ReceivePort();
    _fromIsolate = rp;
    bool ready = false;

    rp.listen((dynamic raw) {
      if (_destroyed) return;
      final msg = raw as Map<String, dynamic>;
      if (!ready) {
        ready       = true;
        _toIsolate  = msg['port'] as SendPort;
        c.complete();
        return;
      }
      _onMsg(msg);
    });

    _isolate = await Isolate.spawn(
      isolateEntry, rp.sendPort,
      debugName: 'QuillTokenizerIsolate',
      errorsAreFatal: false,
    );
    await c.future;
    _spawnFut = null;
  }

  void _onMsg(Map<String, dynamic> msg) {
    if (_destroyed) return;
    final cmd = msg['cmd'] as String;
    final ver = msg['version'] as int;
    if (ver != _currentVer) return; // stale — discard

    final td = msg['data'] as TransferableTypedData;
    if (cmd == 'progress') {
      final upTo = msg['upTo'] as int? ?? -1;
      onSpans(ver, decodeSpans(td.materialize().asUint32List()), false, upTo);
    } else if (cmd == 'spans') {
      onSpans(ver, decodeSpans(td.materialize().asUint32List()), true, -1);
    } else if (cmd == 'blocks') {
      onBlocks(ver, decodeBlocks(td.materialize().asInt32List()));
    }
  }

  /// Submit a full-tokenisation job (non-blocking).
  /// If the isolate is busy with an older job, UI will simply discard
  /// the stale result when it arrives.
  Future<void> tokenize(List<String> lines, int version) async {
    if (_destroyed) return;
    _currentVer = version;
    await _ensureSpawned();
    if (_destroyed) return;

    final msg = <String, dynamic>{'cmd': 'job', 'lines': lines, 'version': version};
    if (!_rulesSent && _rulePay != null) {
      msg['rules']   = _rulePay!;
      msg['wordMap'] = _wordPay ?? const <String, int>{};
      _rulesSent     = true;
    }
    _toIsolate!.send(msg);
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    try { _toIsolate?.send(<String, dynamic>{'cmd': 'destroy'}); } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _fromIsolate?.close();
    _isolate = _toIsolate = _fromIsolate = null;
  }
}
