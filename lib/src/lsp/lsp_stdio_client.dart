// lib/src/lsp/lsp_stdio_client.dart
// ─────────────────────────────────────────────────────────────────────────────
// Concrete LspClient implementation using a child process (stdio transport).
// Suitable for pyright-langserver, rust-analyzer, clangd, dart language-server,
// etc. — any LSP server that communicates over stdin/stdout.
//
// Usage:
//   final client = await LspStdioClient.start(
//     executable: '/usr/bin/dart',
//     args: ['language-server', '--client-id=quill_code'],
//     workspacePath: '/path/to/project',
//     languageId: 'dart',
//   );
//   await controller.attachLsp(client, uri: 'file:///path/to/file.dart');
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'lsp_bridge.dart';
import '../core/char_position.dart';
import '../text/text_range.dart';
import '../diagnostics/diagnostic_region.dart';

class LspStdioClient implements LspClient {
  final String executable;
  final List<String> args;
  final String workspacePath;
  final String languageId;
  final Map<String, String>? environment;

  late final Process _process;
  final _buffer   = <int>[];
  final _pending  = <int, Completer<Map<String, dynamic>>>{};
  final _diagCtrl = StreamController<Map<String, dynamic>>.broadcast();
  int  _nextId    = 1;
  bool _ready     = false;

  LspStdioClient._({
    required this.executable,
    required this.args,
    required this.workspacePath,
    required this.languageId,
    this.environment,
  });

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Start the LSP server process and perform the initialize handshake.
  static Future<LspStdioClient> start({
    required String executable,
    required String workspacePath,
    required String languageId,
    List<String> args = const [],
    Map<String, String>? environment,
  }) async {
    final client = LspStdioClient._(
      executable:    executable,
      args:          args,
      workspacePath: workspacePath,
      languageId:    languageId,
      environment:   environment,
    );
    await client._start();
    return client;
  }

  Future<void> _start() async {
    _process = await Process.start(executable, args, environment: environment);
    _process.stdout.listen(_onData);
    _process.stderr.listen(
      (d) => debugPrint('[LSP stderr] ${utf8.decode(d)}'),
      onError: (_) {},
    );
    _process.exitCode.then((code) {
      debugPrint('[LSP] process exited with code $code');
      _cleanup();   // release pending completers + stream on unexpected exit
    });
    await _initialize();
  }

  // ── LSP wire protocol ─────────────────────────────────────────────────────

  void _onData(List<int> data) {
    _buffer.addAll(data);
    while (true) {
      final sep = _findHeaderEnd();
      if (sep == -1) return;
      final header = utf8.decode(_buffer.sublist(0, sep));
      final match  = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (match == null) { _buffer.clear(); return; }
      final length = int.parse(match.group(1)!);
      final msgStart = sep + 4; // past \r\n\r\n
      if (_buffer.length < msgStart + length) return;
      final body = _buffer.sublist(msgStart, msgStart + length);
      _buffer.removeRange(0, msgStart + length);
      try {
        _onMessage(jsonDecode(utf8.decode(body)) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('[LSP] parse error: $e');
      }
    }
  }

  int _findHeaderEnd() {
    for (int i = 0; i <= _buffer.length - 4; i++) {
      if (_buffer[i]   == 13 && _buffer[i+1] == 10 &&
          _buffer[i+2] == 13 && _buffer[i+3] == 10) return i;
    }
    return -1;
  }

  void _onMessage(Map<String, dynamic> msg) {
    final id = msg['id'];
    if (id != null && _pending.containsKey(id)) {
      // Response to a request
      _pending.remove(id)!.complete(msg);
    } else if (msg.containsKey('method')) {
      // Server-initiated notification (e.g. publishDiagnostics)
      _onNotification(msg);
    }
  }

  void _onNotification(Map<String, dynamic> msg) {
    final method = msg['method'] as String? ?? '';
    if (method == 'textDocument/publishDiagnostics') {
      _diagCtrl.add(msg);
    }
  }

  Future<Map<String, dynamic>> _sendRequest(
      String method, Map<String, dynamic> params) async {
    final id        = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id]    = completer;
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () { _pending.remove(id); return {}; },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    _write({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void _write(Map<String, dynamic> msg) {
    final body   = utf8.encode(jsonEncode(msg));
    final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
    _process.stdin.add([...header, ...body]);
    _process.stdin.flush();
  }

  // ── Initialize ────────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    final result = await _sendRequest('initialize', {
      'processId': pid,
      'rootUri': _pathToUri(workspacePath),
      'capabilities': {
        'textDocument': {
          'synchronization': {'didOpen': true, 'didChange': true, 'didClose': true},
          'completion': {
            'completionItem': {'snippetSupport': true, 'documentationFormat': ['markdown', 'plaintext']},
          },
          'hover': {'contentFormat': ['markdown', 'plaintext']},
          'definition': {'linkSupport': false},
          'references': {},
          'publishDiagnostics': {'relatedInformation': true},
          'formatting': {},
          'codeAction': {'codeActionLiteralSupport': {'codeActionKind': {'valueSet': ['quickfix', 'refactor']}}},
        },
        'workspace': {'workspaceFolders': true},
      },
      'workspaceFolders': [
        {'uri': _pathToUri(workspacePath), 'name': workspacePath.split('/').last},
      ],
    });
    if (result.isNotEmpty) {
      _sendNotification('initialized', {});
      _ready = true;
    }
  }

  // ── LspClient interface ───────────────────────────────────────────────────

  @override
  Future<void> didOpen({
    required String uri,
    required String languageId,
    required String text,
    required int version,
  }) async {
    if (!_ready) return;
    _sendNotification('textDocument/didOpen', {
      'textDocument': {'uri': uri, 'languageId': languageId, 'version': version, 'text': text},
    });
  }

  @override
  Future<void> didChange({
    required String uri,
    required String text,
    required int version,
  }) async {
    if (!_ready) return;
    _sendNotification('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': version},
      'contentChanges': [{'text': text}],
    });
  }

  @override
  Future<void> didClose({required String uri}) async {
    if (!_ready) return;
    _sendNotification('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });
  }

  @override
  Future<List<LspCompletionResult>> completion({
    required String uri,
    required CharPosition position,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/completion', {
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
    });
    final items = _extractItems(resp['result']);
    return items.map(_parseCompletion).toList();
  }

  @override
  Future<LspHover?> hover({
    required String uri,
    required CharPosition position,
  }) async {
    if (!_ready) return null;
    final resp = await _sendRequest('textDocument/hover', {
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
    });
    final result = resp['result'];
    if (result == null) return null;
    final contents = result['contents'];
    final text = contents is Map
        ? (contents['value'] as String? ?? '')
        : (contents is String ? contents : contents.toString());
    return LspHover(contents: text);
  }

  @override
  Future<List<LspLocation>> definition({
    required String uri,
    required CharPosition position,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/definition', {
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
    });
    return _parseLocations(resp['result']);
  }

  @override
  Future<List<LspLocation>> references({
    required String uri,
    required CharPosition position,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/references', {
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
      'context': {'includeDeclaration': false},
    });
    return _parseLocations(resp['result']);
  }

  // Diagnostics are pushed by the server (publishDiagnostics notification).
  // We hold the latest set per URI.
  final _diagMap = <String, List<LspDiagnostic>>{};

  @override
  Future<List<LspDiagnostic>> diagnostics({required String uri}) async {
    return _diagMap[uri] ?? [];
  }

  /// Call this to start listening for publishDiagnostics from the server.
  /// Returns a StreamSubscription — cancel it when done.
  StreamSubscription<List<LspDiagnostic>> listenDiagnostics(
      String uri, void Function(List<LspDiagnostic>) onDiag) {
    return _diagCtrl.stream
        .where((m) => (m['params']?['uri'] as String?) == uri)
        .map((m) {
          final rawDiags = (m['params']?['diagnostics'] as List?) ?? [];
          final diags = rawDiags.map((d) => _parseDiagnostic(d as Map)).toList();
          _diagMap[uri] = diags;
          return diags;
        })
        .listen(onDiag);
  }

  @override
  Future<List<LspTextEdit>> formatting({required String uri}) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/formatting', {
      'textDocument': {'uri': uri},
      'options': {'tabSize': 2, 'insertSpaces': true},
    });
    return _parseEdits(resp['result']);
  }

  @override
  Future<List<LspTextEdit>> rangeFormatting({
    required String uri,
    required EditorRange range,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/rangeFormatting', {
      'textDocument': {'uri': uri},
      'range': _encodeRange(range),
      'options': {'tabSize': 2, 'insertSpaces': true},
    });
    return _parseEdits(resp['result']);
  }

  @override
  Future<Map<String, List<LspTextEdit>>?> rename({
    required String uri,
    required CharPosition position,
    required String newName,
  }) async {
    if (!_ready) return null;
    final resp = await _sendRequest('textDocument/rename', {
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
      'newName': newName,
    });
    final changes = resp['result']?['changes'] as Map?;
    if (changes == null) return null;
    return changes.map((k, v) => MapEntry(
      k as String,
      (v as List).map((e) => _parseTextEdit(e as Map)).toList(),
    ));
  }

  @override
  Future<List<LspCodeAction>> codeActions({
    required String uri,
    required EditorRange range,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/codeAction', {
      'textDocument': {'uri': uri},
      'range': _encodeRange(range),
      'context': {'diagnostics': []},
    });
    final result = resp['result'];
    if (result is! List) return [];
    return result.map((a) {
      final m = a as Map;
      final edits = <LspTextEdit>[];
      final changes = m['edit']?['changes'] as Map?;
      if (changes != null) {
        for (final v in changes.values) {
          edits.addAll((v as List).map((e) => _parseTextEdit(e as Map)));
        }
      }
      return LspCodeAction(
        title: m['title'] as String? ?? '',
        kind:  m['kind']  as String? ?? 'quickfix',
        edits: edits,
      );
    }).toList();
  }

  @override
  Future<LspSignatureHelp?> signatureHelp({
    required String uri,
    required CharPosition position,
    String? triggerCharacter,
  }) async {
    if (!_ready) return null;
    final params = <String, dynamic>{
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
    };
    if (triggerCharacter != null) {
      params['context'] = {
        'triggerKind': 2,  // TriggerCharacter
        'triggerCharacter': triggerCharacter,
        'isRetrigger': false,
      };
    }
    final resp = await _sendRequest('textDocument/signatureHelp', params);
    final result = resp['result'];
    if (result == null) return null;
    final signatures = result['signatures'] as List?;
    if (signatures == null || signatures.isEmpty) return null;
    final activeSignatureIdx = (result['activeSignature'] as int?) ?? 0;
    final sig = signatures[activeSignatureIdx.clamp(0, signatures.length - 1)] as Map;
    final label = sig['label'] as String? ?? '';
    final rawDoc = sig['documentation'];
    final doc = rawDoc is String ? rawDoc : (rawDoc is Map ? rawDoc['value'] as String? : null);
    final rawParams = sig['parameters'] as List? ?? [];
    final params2 = rawParams.map((p) {
      final pm = p as Map;
      final pl = pm['label'];
      return pl is String ? pl : '';
    }).toList();
    return LspSignatureHelp(
      label:           label,
      documentation:   doc,
      parameters:      params2,
      activeParameter: (result['activeParameter'] as int?) ?? 0,
    );
  }

  @override
  Future<List<LspDocumentSymbol>> documentSymbols({required String uri}) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/documentSymbol', {
      'textDocument': {'uri': uri},
    });
    final result = resp['result'];
    if (result is! List) return [];
    return result.map((s) => _parseSymbol(s as Map)).toList();
  }

  LspDocumentSymbol _parseSymbol(Map s) {
    final children = (s['children'] as List? ?? [])
        .map((c) => _parseSymbol(c as Map))
        .toList();
    return LspDocumentSymbol(
      name:           s['name'] as String? ?? '',
      detail:         s['detail'] as String?,
      kind:           s['kind'] as int? ?? 1,
      range:          _decodeRange(s['range'] as Map),
      selectionRange: _decodeRange(s['selectionRange'] as Map),
      children:       children,
    );
  }

  @override
  Future<List<EditorRange>> documentHighlight({
    required String uri,
    required CharPosition position,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/documentHighlight', {
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
    });
    final result = resp['result'];
    if (result is! List) return [];
    return result.map((h) => _decodeRange((h as Map)['range'] as Map)).toList();
  }

  @override
  Future<List<LspInlayHint>> inlayHints({
    required String uri,
    required EditorRange range,
  }) async {
    if (!_ready) return [];
    final resp = await _sendRequest('textDocument/inlayHint', {
      'textDocument': {'uri': uri},
      'range': _encodeRange(range),
    });
    final result = resp['result'];
    if (result is! List) return [];
    return result.map((h) {
      final m = h as Map;
      final pos = m['position'] as Map;
      final rawLabel = m['label'];
      final label = rawLabel is String ? rawLabel
          : (rawLabel is List ? rawLabel.map((l) => (l as Map)['value'] ?? '').join('') : '');
      return LspInlayHint(
        position:    CharPosition(pos['line'] as int, pos['character'] as int),
        label:       label as String,
        isParameter: (m['kind'] as int? ?? 1) == 2,
      );
    }).toList();
  }

  @override
  Future<LspCompletionResult?> resolveCompletion(LspCompletionResult item) async {
    if (!_ready) return null;
    try {
      // Build the original LSP CompletionItem from what we stored.
      // The server expects us to echo back the item with its data intact.
      final resp = await _sendRequest('completionItem/resolve', {
        'label':      item.label,
        if (item.insertText != null) 'insertText': item.insertText,
        if (item.detail != null) 'detail': item.detail,
        if (item.documentation != null) 'documentation': item.documentation,
      });
      final result = resp['result'];
      if (result is! Map) return null;
      final doc = result['documentation'];
      final docStr = doc is String ? doc
          : (doc is Map ? (doc['value'] ?? '') as String : null);
      return LspCompletionResult(
        label:         item.label,
        insertText:    item.insertText,
        detail:        result['detail'] as String? ?? item.detail,
        documentation: docStr ?? item.documentation,
        kind:          item.kind,
        isSnippet:     item.isSnippet,
      );
    } catch (_) { return null; }
  }

  /// Completes all pending requests with empty responses and closes the
  /// diagnostic stream. Safe to call multiple times (idempotent).
  void _cleanup() {
    _ready = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete({});
    }
    _pending.clear();
    if (!_diagCtrl.isClosed) _diagCtrl.close();
  }

  @override
  Future<void> shutdown() async {
    if (!_ready) return;
    _ready = false;
    await _sendRequest('shutdown', {});
    _sendNotification('exit', {});
    _process.kill();
    _cleanup();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get pid => _process.pid;

  static String _pathToUri(String path) =>
      path.startsWith('file://') ? path : 'file://$path';

  List<Map> _extractItems(dynamic result) {
    if (result == null) return [];
    if (result is List) return result.cast<Map>();
    if (result is Map && result.containsKey('items')) {
      return (result['items'] as List).cast<Map>();
    }
    return [];
  }

  LspCompletionResult _parseCompletion(Map item) {
    final kind = _completionKind(item['kind'] as int? ?? 1);
    final insertText = item['insertText'] as String?
        ?? item['label'] as String? ?? '';
    final isSnippet = (item['insertTextFormat'] as int? ?? 1) == 2;
    String? doc;
    final documentation = item['documentation'];
    if (documentation is String) {
      doc = documentation;
    } else if (documentation is Map) {
      doc = documentation['value'] as String?;
    }
    return LspCompletionResult(
      label:         item['label'] as String? ?? '',
      insertText:    insertText,
      detail:        item['detail'] as String?,
      documentation: doc,
      kind:          kind,
      isSnippet:     isSnippet,
    );
  }

  LspCompletionKind _completionKind(int k) {
    const map = {
      1: LspCompletionKind.text, 2: LspCompletionKind.method,
      3: LspCompletionKind.function_, 4: LspCompletionKind.constructor,
      5: LspCompletionKind.field, 6: LspCompletionKind.variable,
      7: LspCompletionKind.class_, 8: LspCompletionKind.interface,
      9: LspCompletionKind.module, 10: LspCompletionKind.property,
      11: LspCompletionKind.unit, 12: LspCompletionKind.value,
      13: LspCompletionKind.enum_, 14: LspCompletionKind.keyword,
      15: LspCompletionKind.snippet, 16: LspCompletionKind.color,
      17: LspCompletionKind.file, 18: LspCompletionKind.reference,
      19: LspCompletionKind.folder, 20: LspCompletionKind.enumMember,
      21: LspCompletionKind.constant, 22: LspCompletionKind.struct,
      23: LspCompletionKind.event, 24: LspCompletionKind.operator_,
      25: LspCompletionKind.typeParameter,
    };
    return map[k] ?? LspCompletionKind.text;
  }

  List<LspLocation> _parseLocations(dynamic result) {
    if (result == null) return [];
    final list = result is List ? result : [result];
    return list.map((l) {
      final m = l as Map;
      return LspLocation(
        uri:   m['uri'] as String? ?? '',
        range: _decodeRange(m['range'] as Map),
      );
    }).toList();
  }

  LspDiagnostic _parseDiagnostic(Map d) {
    final sev = d['severity'] as int? ?? 1;
    return LspDiagnostic(
      range:    _decodeRange(d['range'] as Map),
      message:  d['message'] as String? ?? '',
      severity: sev == 1 ? DiagnosticSeverity.error
               : sev == 2 ? DiagnosticSeverity.warning
               : DiagnosticSeverity.info,
      source: d['source'] as String?,
      code:   d['code']?.toString(),
    );
  }

  List<LspTextEdit> _parseEdits(dynamic result) {
    if (result is! List) return [];
    return result.map((e) => _parseTextEdit(e as Map)).toList();
  }

  LspTextEdit _parseTextEdit(Map e) => LspTextEdit(
    range:   _decodeRange(e['range'] as Map),
    newText: e['newText'] as String? ?? '',
  );

  EditorRange _decodeRange(Map r) {
    final s = r['start'] as Map;
    final e = r['end']   as Map;
    return EditorRange(
      CharPosition(s['line'] as int, s['character'] as int),
      CharPosition(e['line'] as int, e['character'] as int),
    );
  }

  Map<String, dynamic> _encodeRange(EditorRange r) => {
    'start': {'line': r.start.line, 'character': r.start.column},
    'end':   {'line': r.end.line,   'character': r.end.column},
  };
}
