// lib/src/lsp/lsp_socket_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'package:flutter/foundation.dart' show debugPrint;
import 'lsp_bridge.dart';
import '../core/char_position.dart';
import '../text/text_range.dart';
import '../diagnostics/diagnostic_region.dart';

class LspSocketClient implements LspClient {
  final String serverUrl;
  final String workspacePath;
  final String languageId;

  WebSocket?   _ws;
  final _pending  = <int, Completer<Map<String, dynamic>>>{};
  final _diagMap  = <String, List<LspDiagnostic>>{};
  final _diagCtrl = StreamController<Map<String, dynamic>>.broadcast();
  int  _nextId = 1;
  bool _ready  = false;

  LspSocketClient({required this.serverUrl, required this.workspacePath, required this.languageId});

  Future<void> connect() async {
    _ws = await WebSocket.connect(serverUrl);
    _ws!.listen(
      (data) { try { _onMsg(jsonDecode(data as String) as Map<String, dynamic>); } catch (e) { debugPrint('[LSP] $e'); } },
      onError: (e) { debugPrint('[LSP socket] error: $e'); _cleanup(); },
      onDone:  ()  { debugPrint('[LSP socket] closed'); _cleanup(); },
    );
    await _initialize();
  }

  /// Called on both normal shutdown and abnormal connection loss.
  /// Completes all pending requests with empty responses and closes the
  /// diagnostic stream so subscribers don't leak.
  void _cleanup() {
    _ready = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete({});
    }
    _pending.clear();
    if (!_diagCtrl.isClosed) _diagCtrl.close();
  }

  void _onMsg(Map<String, dynamic> msg) {
    final id = msg['id'];
    if (id != null && _pending.containsKey(id)) { _pending.remove(id)!.complete(msg); return; }
    if (msg['method'] == 'textDocument/publishDiagnostics') {
      final uri = msg['params']?['uri'] as String? ?? '';
      _diagMap[uri] = ((msg['params']?['diagnostics'] as List?) ?? []).map((d) => _diag(d as Map)).toList();
      _diagCtrl.add(msg);
    }
  }

  Future<Map<String, dynamic>> _req(String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final c  = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws?.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () { _pending.remove(id); return {}; });
  }

  void _not(String method, Map<String, dynamic> params) =>
      _ws?.add(jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}));

  Future<void> _initialize() async {
    final r = await _req('initialize', {
      'processId': null, 'rootUri': _uri(workspacePath),
      'capabilities': {'textDocument': {'synchronization': {'didOpen': true, 'didChange': true, 'didClose': true},
        'completion': {'completionItem': {'snippetSupport': true}}, 'hover': {'contentFormat': ['markdown','plaintext']},
        'definition': {}, 'references': {}, 'publishDiagnostics': {'relatedInformation': true},
        'formatting': {}, 'codeAction': {}}, 'workspace': {'workspaceFolders': true}},
      'workspaceFolders': [{'uri': _uri(workspacePath), 'name': workspacePath.split('/').last}],
    });
    if (r.isNotEmpty) { _not('initialized', {}); _ready = true; }
  }

  @override Future<void> didOpen({required String uri, required String languageId, required String text, required int version}) async {
    if (!_ready) return;
    _not('textDocument/didOpen', {'textDocument': {'uri': uri, 'languageId': languageId, 'version': version, 'text': text}});
  }
  @override Future<void> didChange({required String uri, required String text, required int version}) async {
    if (!_ready) return;
    _not('textDocument/didChange', {'textDocument': {'uri': uri, 'version': version}, 'contentChanges': [{'text': text}]});
  }
  @override Future<void> didClose({required String uri}) async {
    if (!_ready) return;
    _not('textDocument/didClose', {'textDocument': {'uri': uri}});
  }

  @override Future<List<LspCompletionResult>> completion({required String uri, required CharPosition position}) async {
    if (!_ready) return [];
    final r = await _req('textDocument/completion', {'textDocument': {'uri': uri}, 'position': _p(position)});
    return _items(r['result']).map(_comp).toList();
  }
  @override Future<LspHover?> hover({required String uri, required CharPosition position}) async {
    if (!_ready) return null;
    final r = await _req('textDocument/hover', {'textDocument': {'uri': uri}, 'position': _p(position)});
    final res = r['result']; if (res == null) return null;
    final c = res['contents'];
    return LspHover(contents: c is Map ? (c['value'] as String? ?? '') : c?.toString() ?? '');
  }
  @override Future<List<LspLocation>> definition({required String uri, required CharPosition position}) async {
    if (!_ready) return [];
    return _locs((await _req('textDocument/definition', {'textDocument': {'uri': uri}, 'position': _p(position)}))['result']);
  }
  @override Future<List<LspLocation>> references({required String uri, required CharPosition position}) async {
    if (!_ready) return [];
    return _locs((await _req('textDocument/references', {'textDocument': {'uri': uri}, 'position': _p(position), 'context': {'includeDeclaration': false}}))['result']);
  }
  @override Future<List<LspDiagnostic>> diagnostics({required String uri}) async => _diagMap[uri] ?? [];

  StreamSubscription<List<LspDiagnostic>> listenDiagnostics(String uri, void Function(List<LspDiagnostic>) cb) =>
      _diagCtrl.stream.where((m) => m['params']?['uri'] == uri).map((_) => _diagMap[uri] ?? <LspDiagnostic>[]).listen(cb);

  @override Future<List<LspTextEdit>> formatting({required String uri}) async {
    if (!_ready) return [];
    return _edits((await _req('textDocument/formatting', {'textDocument': {'uri': uri}, 'options': {'tabSize': 2, 'insertSpaces': true}}))['result']);
  }
  @override Future<List<LspTextEdit>> rangeFormatting({required String uri, required EditorRange range}) async {
    if (!_ready) return [];
    return _edits((await _req('textDocument/rangeFormatting', {'textDocument': {'uri': uri}, 'range': _rng(range), 'options': {'tabSize': 2, 'insertSpaces': true}}))['result']);
  }
  @override Future<Map<String, List<LspTextEdit>>?> rename({required String uri, required CharPosition position, required String newName}) async {
    if (!_ready) return null;
    final r = await _req('textDocument/rename', {'textDocument': {'uri': uri}, 'position': _p(position), 'newName': newName});
    final ch = r['result']?['changes'] as Map?;
    return ch?.map((k, v) => MapEntry(k as String, (v as List).map((e) => _edit(e as Map)).toList()));
  }
  @override Future<List<LspCodeAction>> codeActions({required String uri, required EditorRange range}) async {
    if (!_ready) return [];
    final r = await _req('textDocument/codeAction', {'textDocument': {'uri': uri}, 'range': _rng(range), 'context': {'diagnostics': []}});
    if (r['result'] is! List) return [];
    return (r['result'] as List).map((a) {
      final m = a as Map; final edits = <LspTextEdit>[];
      final ch = m['edit']?['changes'] as Map?;
      if (ch != null) for (final v in ch.values) edits.addAll((v as List).map((e) => _edit(e as Map)));
      return LspCodeAction(title: m['title'] as String? ?? '', kind: m['kind'] as String? ?? 'quickfix', edits: edits);
    }).toList();
  }

  @override Future<LspSignatureHelp?> signatureHelp({required String uri, required CharPosition position, String? triggerCharacter}) async {
    if (!_ready) return null;
    final params = <String, dynamic>{'textDocument': {'uri': uri}, 'position': _p(position)};
    if (triggerCharacter != null) params['context'] = {'triggerKind': 2, 'triggerCharacter': triggerCharacter, 'isRetrigger': false};
    final r = await _req('textDocument/signatureHelp', params);
    final result = r['result']; if (result == null) return null;
    final sigs = result['signatures'] as List?; if (sigs == null || sigs.isEmpty) return null;
    final ai = ((result['activeSignature'] as int?) ?? 0).clamp(0, sigs.length - 1);
    final sig = sigs[ai] as Map;
    final label = sig['label'] as String? ?? '';
    final rawDoc = sig['documentation'];
    final doc = rawDoc is String ? rawDoc : (rawDoc is Map ? rawDoc['value'] as String? : null);
    final params2 = ((sig['parameters'] as List?) ?? []).map((p) {
      final pl = (p as Map)['label']; return pl is String ? pl : '';
    }).toList();
    return LspSignatureHelp(label: label, documentation: doc, parameters: params2,
      activeParameter: (result['activeParameter'] as int?) ?? 0);
  }

  @override Future<List<LspDocumentSymbol>> documentSymbols({required String uri}) async {
    if (!_ready) return [];
    final r = await _req('textDocument/documentSymbol', {'textDocument': {'uri': uri}});
    final result = r['result']; if (result is! List) return [];
    return result.map((s) => _sym(s as Map)).toList();
  }

  LspDocumentSymbol _sym(Map s) => LspDocumentSymbol(
    name: s['name'] as String? ?? '', detail: s['detail'] as String?,
    kind: s['kind'] as int? ?? 1, range: _dr(s['range'] as Map),
    selectionRange: _dr(s['selectionRange'] as Map),
    children: ((s['children'] as List?) ?? []).map((c) => _sym(c as Map)).toList(),
  );

  @override Future<List<EditorRange>> documentHighlight({required String uri, required CharPosition position}) async {
    if (!_ready) return [];
    final r = await _req('textDocument/documentHighlight', {'textDocument': {'uri': uri}, 'position': _p(position)});
    final result = r['result']; if (result is! List) return [];
    return result.map((h) => _dr((h as Map)['range'] as Map)).toList();
  }

  @override Future<List<LspInlayHint>> inlayHints({required String uri, required EditorRange range}) async {
    if (!_ready) return [];
    final r = await _req('textDocument/inlayHint', {'textDocument': {'uri': uri}, 'range': _rng(range)});
    final result = r['result']; if (result is! List) return [];
    return result.map((h) {
      final m = h as Map; final pos = m['position'] as Map;
      final rl = m['label']; final label = rl is String ? rl : (rl is List ? rl.map((l) => (l as Map)['value'] ?? '').join('') : '');
      return LspInlayHint(position: CharPosition(pos['line'] as int, pos['character'] as int),
        label: label as String, isParameter: (m['kind'] as int? ?? 1) == 2);
    }).toList();
  }

  @override Future<LspCompletionResult?> resolveCompletion(LspCompletionResult item) async {
    if (!_ready) return null;
    try {
      final r = await _req('completionItem/resolve', {
        'label': item.label,
        if (item.insertText != null) 'insertText': item.insertText,
        if (item.detail != null) 'detail': item.detail,
      });
      final result = r['result'];
      if (result is! Map) return null;
      final doc = result['documentation'];
      final docStr = doc is String ? doc : (doc is Map ? (doc['value'] ?? '') as String : null);
      return LspCompletionResult(
        label: item.label, insertText: item.insertText,
        detail: result['detail'] as String? ?? item.detail,
        documentation: docStr ?? item.documentation,
        kind: item.kind, isSnippet: item.isSnippet,
      );
    } catch (_) { return null; }
  }

  @override Future<void> shutdown() async {
    if (!_ready) return;
    _ready = false;
    await _req('shutdown', {}); _not('exit', {});
    await _ws?.close();
    _cleanup();
  }

  static String _uri(String p) => p.startsWith('file://') ? p : 'file://$p';
  Map<String, int> _p(CharPosition p) => {'line': p.line, 'character': p.column};
  Map<String, dynamic> _rng(EditorRange r) => {'start': _p(r.start), 'end': _p(r.end)};

  List<Map> _items(dynamic r) {
    if (r == null) return [];
    if (r is List) return r.cast<Map>();
    if (r is Map && r['items'] is List) return (r['items'] as List).cast<Map>();
    return [];
  }
  LspCompletionResult _comp(Map it) {
    String? doc; final d = it['documentation'];
    if (d is String) doc = d; else if (d is Map) doc = d['value'] as String?;
    return LspCompletionResult(label: it['label'] as String? ?? '', insertText: it['insertText'] as String? ?? it['label'] as String? ?? '',
      detail: it['detail'] as String?, documentation: doc, kind: _kind(it['kind'] as int? ?? 1), isSnippet: (it['insertTextFormat'] as int? ?? 1) == 2);
  }
  LspCompletionKind _kind(int k) {
    const m = {1:LspCompletionKind.text,2:LspCompletionKind.method,3:LspCompletionKind.function_,4:LspCompletionKind.constructor,
      5:LspCompletionKind.field,6:LspCompletionKind.variable,7:LspCompletionKind.class_,8:LspCompletionKind.interface,
      9:LspCompletionKind.module,10:LspCompletionKind.property,11:LspCompletionKind.unit,12:LspCompletionKind.value,
      13:LspCompletionKind.enum_,14:LspCompletionKind.keyword,15:LspCompletionKind.snippet,16:LspCompletionKind.color,
      17:LspCompletionKind.file,18:LspCompletionKind.reference,19:LspCompletionKind.folder,20:LspCompletionKind.enumMember,
      21:LspCompletionKind.constant,22:LspCompletionKind.struct,23:LspCompletionKind.event,24:LspCompletionKind.operator_,
      25:LspCompletionKind.typeParameter};
    return m[k] ?? LspCompletionKind.text;
  }
  List<LspLocation> _locs(dynamic r) {
    if (r == null) return [];
    return (r is List ? r : [r]).map((l) {final m = l as Map; return LspLocation(uri: m['uri'] as String? ?? '', range: _dr(m['range'] as Map));}).toList();
  }
  LspDiagnostic _diag(Map d) {
    final s = d['severity'] as int? ?? 1;
    return LspDiagnostic(range: _dr(d['range'] as Map), message: d['message'] as String? ?? '',
      severity: s == 1 ? DiagnosticSeverity.error : s == 2 ? DiagnosticSeverity.warning : DiagnosticSeverity.info,
      source: d['source'] as String?, code: d['code']?.toString());
  }
  List<LspTextEdit> _edits(dynamic r) => r is List ? r.map((e) => _edit(e as Map)).toList() : [];
  LspTextEdit _edit(Map e) => LspTextEdit(range: _dr(e['range'] as Map), newText: e['newText'] as String? ?? '');
  EditorRange _dr(Map r) {
    final s = r['start'] as Map; final e = r['end'] as Map;
    return EditorRange(CharPosition(s['line'] as int, s['character'] as int), CharPosition(e['line'] as int, e['character'] as int));
  }
}
