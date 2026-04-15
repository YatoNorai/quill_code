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
import 'package:flutter/foundation.dart';
import 'lsp_bridge.dart';
import '../core/char_position.dart';
import '../text/text_range.dart';
import '../diagnostics/diagnostic_region.dart';

// Top-level function required by compute() — Isolate entry points must be
// top-level or static. Parses the JSON LSP message off the main thread.
Map<String, dynamic> _parseJsonMsg(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

void _lspError(String context, Object e, StackTrace st) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: e,
    stack: st,
    library: 'quill_code/lsp_stdio',
    context: ErrorDescription(context),
  ));
}

class LspStdioClient implements LspClient {
  final String executable;
  final List<String> args;
  final String workspacePath;
  final String languageId;
  final Map<String, String>? environment;

  /// Seconds to wait for the `initialize` response.  Set higher for JVM-based
  /// servers (kotlin-language-server, jdtls) which need 20–60 s to start.
  final int initializeTimeoutSeconds;

  late final Process _process;
  final _buffer   = <int>[];
  int   _bufStart = 0; // logical start of unprocessed bytes — avoids O(n) front removal
  final _pending  = <int, Completer<Map<String, dynamic>>>{};
  final _diagCtrl = StreamController<Map<String, dynamic>>.broadcast();
  int  _nextId    = 1;
  bool _ready     = false;
  Future<void> _writeQueue = Future.value();
  /// URIs that have received textDocument/didOpen and not yet didClose.
  /// Guards against double-open (e.g. workspace scan + editor open same file).
  final _openUris = <String>{};
  List<String> _triggerCharacters = const ['.', '(', ','];

  /// Called when the process crashes, writes fail, or messages fail to parse.
  void Function(String message)? onError;

  @override
  bool get isReady => _ready;

  LspStdioClient._({
    required this.executable,
    required this.args,
    required this.workspacePath,
    required this.languageId,
    this.environment,
    this.initializeTimeoutSeconds = 5,
  });

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Start the LSP server process and perform the initialize handshake.
  ///
  /// [onError] is wired before the process starts so early stderr/crash
  /// messages are never lost.  Check [isReady] after this returns to detect
  /// a failed initialize handshake.
  static Future<LspStdioClient> start({
    required String executable,
    required String workspacePath,
    required String languageId,
    List<String> args = const [],
    Map<String, String>? environment,
    int initializeTimeoutSeconds = 5,
    void Function(String message)? onError,
  }) async {
    final client = LspStdioClient._(
      executable:    executable,
      args:          args,
      workspacePath: workspacePath,
      languageId:    languageId,
      environment:   environment,
      initializeTimeoutSeconds: initializeTimeoutSeconds,
    );
    client.onError = onError;  // wire BEFORE _start so early stderr is caught
    await client._start();
    return client;
  }

  Future<void> _start() async {
    _process = await Process.start(executable, args, environment: environment);
    _process.stdout.listen(_onData, onError: (e, st) {
      _lspError('stdout stream error', e, st as StackTrace);
    });
    _process.stderr.listen(
      (d) {
        final msg = utf8.decode(d);
        debugPrint('[LSP stderr] $msg');
        onError?.call('LSP stderr: $msg');
      },
      onError: (_) {},
    );
    _process.exitCode.then((code) {
      debugPrint('[LSP] process exited with code $code');
      if (code != 0) onError?.call('LSP process exited with code $code');
      _cleanup();   // release pending completers + stream on unexpected exit
    });
    await _initialize();
  }

  // ── LSP wire protocol ─────────────────────────────────────────────────────

  void _onData(List<int> data) {
    try {
      _buffer.addAll(data);
      while (true) {
        final sep = _findHeaderEnd(); // relative offset from _bufStart
        if (sep == -1) return;
        final headerStr = utf8.decode(_buffer.sublist(_bufStart, _bufStart + sep));
        final match = _clRx.firstMatch(headerStr);
        if (match == null) { _buffer.clear(); _bufStart = 0; return; }
        final length   = int.parse(match.group(1)!);
        final msgStart = sep + 4; // past \r\n\r\n (relative to _bufStart)
        final msgEnd   = _bufStart + msgStart + length;
        if (_buffer.length < msgEnd) return;
        final bodyBytes = _buffer.sublist(_bufStart + msgStart, msgEnd);
        // Advance the logical start — O(1), no copy.
        _bufStart = msgEnd;
        // Compact only when the wasted prefix is large enough to matter (64 KB).
        // This amortises the O(n) removeRange over many messages.
        if (_bufStart > 65536) {
          _buffer.removeRange(0, _bufStart);
          _bufStart = 0;
        }
        final bodyStr = utf8.decode(bodyBytes);
        // Use an Isolate only for large messages — compute() has ~2 ms dispatch
        // overhead that exceeds the benefit for small messages (< 8 KB).
        // Hover, definition, and most notifications are well under 8 KB;
        // large completion responses from das can be 50–500 KB.
        if (bodyStr.length > 8192) {
          compute(_parseJsonMsg, bodyStr).then(_onMessage).catchError((Object e, StackTrace st) {
            _lspError('processing LSP message', e, st);
            onError?.call('LSP message error: $e');
          });
        } else {
          try {
            _onMessage(jsonDecode(bodyStr) as Map<String, dynamic>);
          } catch (e, st) {
            _lspError('processing LSP message', e, st);
            onError?.call('LSP message error: $e');
          }
        }
      }
    } catch (e, st) {
      _lspError('_onData (LSP framing)', e, st);
    }
  }

  // Compiled once — avoids per-call RegExp allocation.
  static final _clRx = RegExp(r'Content-Length:\s*(\d+)');

  // Returns the offset of the \r\n\r\n separator *relative to _bufStart*,
  // or -1 if not yet arrived. Searching from _bufStart skips already-consumed bytes.
  int _findHeaderEnd() {
    final end = _buffer.length - 3;
    for (int i = _bufStart; i < end; i++) {
      if (_buffer[i]   == 13 && _buffer[i+1] == 10 &&
          _buffer[i+2] == 13 && _buffer[i+3] == 10) return i - _bufStart;
    }
    return -1;
  }

  void _onMessage(Map<String, dynamic> msg) {
    final id     = msg['id'];
    final method = msg['method'] as String?;

    if (id != null && _pending.containsKey(id)) {
      // Response to one of our own requests.
      _pending.remove(id)!.complete(msg);
    } else if (method != null) {
      if (id != null) {
        // Server-initiated request (e.g. jdtls `workspace/configuration`).
        // We must reply or the server stalls waiting.  Return null for every
        // method we don't know about — servers must tolerate unknown config.
        _handleServerRequest(id, method, msg['params']);
      } else {
        // Pure notification (no id).
        _onNotification(method, msg);
      }
    }
  }

  /// Responds to server-initiated requests that we receive during or after
  /// initialization.  jdtls sends `workspace/configuration` early; without a
  /// response it can block the initialize handshake indefinitely.
  void _handleServerRequest(dynamic id, String method, dynamic params) {
    switch (method) {
      case 'workspace/configuration':
        // Return a null entry for every configuration item requested.
        final items = params is List ? params : (params is Map ? params['items'] ?? [] : []);
        _write({
          'jsonrpc': '2.0',
          'id': id,
          'result': List.filled((items as List).length, null),
        });

      case 'workspace/applyEdit':
        // Acknowledge but do not apply — we have no write-back mechanism yet.
        _write({'jsonrpc': '2.0', 'id': id, 'result': {'applied': false}});

      case 'window/showMessageRequest':
        // Dismiss by returning null (user clicked nothing).
        _write({'jsonrpc': '2.0', 'id': id, 'result': null});

      default:
        // Unknown server request — send a "method not found" error so the
        // server can give up waiting rather than hanging.
        _write({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32601, 'message': 'Method not found: $method'},
        });
    }
  }

  void _onNotification(String method, Map<String, dynamic> msg) {
    if (method == 'textDocument/publishDiagnostics') {
      _diagCtrl.add(msg);
    }
    // window/logMessage, window/showMessage, $/progress, etc. are silently
    // dropped — we don't surface them in the UI yet.
  }

  Future<Map<String, dynamic>> _sendRequest(
      String method, Map<String, dynamic> params, {int? timeoutSeconds}) async {
    final id        = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id]    = completer;
    // Requests need a flush so the server receives the data before we await
    // the response. Notifications skip flush (fire-and-forget).
    await _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params},
        flush: true);
    final secs = timeoutSeconds ?? 5;
    return completer.future.timeout(
      Duration(seconds: secs),
      onTimeout: () { _pending.remove(id); return {}; },
    );
  }

  /// Send a notification. Pass [flush]=false only for high-frequency
  /// notifications like textDocument/didChange where the data will be flushed
  /// by the next outgoing request anyway.
  Future<void> _sendNotification(String method, Map<String, dynamic> params,
      {bool flush = true}) {
    return _write({'jsonrpc': '2.0', 'method': method, 'params': params},
        flush: flush);
  }

  // Serialises all writes through a queue so concurrent callers never race
  // on stdin. Requests always flush; high-frequency notifications may skip it.
  Future<void> _write(Map<String, dynamic> msg, {bool flush = true}) {
    return _writeQueue = _writeQueue.then((_) async {
      final body   = utf8.encode(jsonEncode(msg));
      final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
      // Two separate add() calls instead of [...header, ...body] — avoids
      // allocating a merged list that can be 100 KB+ for large requests.
      _process.stdin.add(header);
      _process.stdin.add(body);
      if (flush) {
        // Timeout guards against hanging when the LSP process's stdin buffer
        // fills up (server busy/crashed) — without this the write queue stalls
        // forever and the editor freezes.
        await _process.stdin.flush()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
      }
    }).catchError((e) {
      debugPrint('[LSP] write error: $e');
      onError?.call('LSP write error: $e');
    });
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
            'contextSupport': true,           // server must honour context.triggerCharacter
            'completionItem': {
              'snippetSupport': true,
              'documentationFormat': ['markdown', 'plaintext'],
              'resolveSupport': {'properties': ['documentation', 'detail']},
            },
          },
          'hover': {'contentFormat': ['markdown', 'plaintext']},
          'definition': {'linkSupport': false},
          'references': {},
          'publishDiagnostics': {'relatedInformation': true},
          'formatting': {},
          'codeAction': {'codeActionLiteralSupport': {'codeActionKind': {'valueSet': ['quickfix', 'refactor']}}},
        },
        'workspace': {
          'workspaceFolders': true,
          // Advertise configuration support so jdtls sends workspace/configuration
          // requests that we can respond to (via _handleServerRequest) rather than
          // blocking indefinitely waiting for a capability we never declared.
          'configuration': true,
        },
      },
      'workspaceFolders': [
        {'uri': _pathToUri(workspacePath), 'name': workspacePath.split('/').last},
      ],
    }, timeoutSeconds: initializeTimeoutSeconds);  // JVM servers need 20–60 s
    if (result.isNotEmpty) {
      await _sendNotification('initialized', {});
      _ready = true;
      // Read server-advertised trigger characters so the editor can react to them.
      final cp = result['result']?['capabilities']?['completionProvider']
                 ?? result['capabilities']?['completionProvider'];
      if (cp is Map) {
        final tc = cp['triggerCharacters'];
        if (tc is List && tc.isNotEmpty) {
          _triggerCharacters = tc.cast<String>();
        }
      }
    } else {
      final msg = 'LSP $languageId: initialize timed out after ${initializeTimeoutSeconds}s';
      debugPrint('[LSP] $msg');
      onError?.call(msg);
    }
  }

  @override
  List<String> get triggerCharacters => _triggerCharacters;

  // ── LspClient interface ───────────────────────────────────────────────────

  @override
  Future<void> didOpen({
    required String uri,
    required String languageId,
    required String text,
    required int version,
  }) async {
    if (!_ready) return;
    if (_openUris.contains(uri)) return; // already open — skip duplicate
    _openUris.add(uri);
    // Flush immediately so the server indexes the file right away and can
    // start sending publishDiagnostics without waiting for the next request.
    await _sendNotification('textDocument/didOpen', {
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
    // flush: false — flushed by the next request (completion/hover/definition).
    // This avoids blocking the write queue on every keystroke debounce cycle.
    _sendNotification('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': version},
      'contentChanges': [{'text': text}],
    }, flush: false);
  }

  @override
  Future<void> didClose({required String uri}) async {
    if (!_ready) return;
    if (!_openUris.remove(uri)) return; // wasn't open — skip
    // flush: false — low priority, server will process when stdin is next flushed.
    _sendNotification('textDocument/didClose', {
      'textDocument': {'uri': uri},
    }, flush: false);
  }

  @override
  Future<LspCompletionList> completion({
    required String uri,
    required CharPosition position,
    String? triggerCharacter,
    bool retriggerIncomplete = false,
  }) async {
    if (!_ready) return LspCompletionList.empty;
    final params = <String, dynamic>{
      'textDocument': {'uri': uri},
      'position': {'line': position.line, 'character': position.column},
    };
    if (retriggerIncomplete) {
      // User typed more chars after an incomplete completion — ask server to
      // continue the previous list (triggerKind=3).
      params['context'] = {'triggerKind': 3};
    } else if (triggerCharacter != null) {
      params['context'] = {
        'triggerKind': 2,             // TriggerCharacter
        'triggerCharacter': triggerCharacter,
        'isRetrigger': false,
      };
    } else {
      params['context'] = {'triggerKind': 1}; // Invoked
    }
    final resp = await _sendRequest('textDocument/completion', params);
    final result = resp['result'];
    final isIncomplete = result is Map ? (result['isIncomplete'] as bool? ?? false) : false;
    final items = _extractItems(result);
    return LspCompletionList(
      items: items.map(_parseCompletion).toList(),
      isIncomplete: isIncomplete,
    );
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

  @override
  StreamSubscription<List<LspDiagnostic>> listenDiagnostics(
      String uri, void Function(List<LspDiagnostic>) onDiag) {
    return _diagCtrl.stream
        .where((m) => (m['params']?['uri'] as String?) == uri)
        .map((m) {
          // try/catch is CRITICAL here: an exception inside .map() becomes a
          // stream error. Without onError on .listen(), that error is unhandled
          // and crashes the app invisibly.
          try {
            final rawDiags = (m['params']?['diagnostics'] as List?) ?? [];
            final diags = rawDiags
                .map((d) => _parseDiagnostic(d as Map))
                .toList();
            _diagMap[uri] = diags;
            return diags;
          } catch (e, st) {
            _lspError('parsing publishDiagnostics notification', e, st);
            return <LspDiagnostic>[];
          }
        })
        .listen(onDiag, onError: (_) {});  // belt-and-suspenders: silence any
                                            // stream errors that slip through
  }

  @override
  StreamSubscription<void> listenAllDiagnostics(
      void Function(String uri, List<LspDiagnostic>) onDiag) {
    return _diagCtrl.stream.listen((m) {
      final uri = m['params']?['uri'] as String?;
      if (uri == null) return;
      try {
        final rawDiags = (m['params']?['diagnostics'] as List?) ?? [];
        final diags = rawDiags.map((d) => _parseDiagnostic(d as Map)).toList();
        _diagMap[uri] = diags;
        onDiag(uri, diags);
      } catch (e, st) {
        _lspError('listenAllDiagnostics', e, st);
      }
    }, onError: (_) {});
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
    try {
      final resp = await _sendRequest('textDocument/documentSymbol', {
        'textDocument': {'uri': uri},
      });
      final result = resp['result'];
      if (result is! List) return [];
      return result.map((s) => _parseSymbol(s as Map)).toList();
    } catch (e, st) { _lspError('documentSymbols', e, st); return []; }
  }

  LspDocumentSymbol _parseSymbol(Map s) {
    final children = (s['children'] as List? ?? [])
        .map((c) => _parseSymbol(c as Map))
        .toList();
    // selectionRange is required in DocumentSymbol but optional in
    // SymbolInformation — fall back to range when absent.
    final rangeMap       = s['range'] as Map?;
    final range          = rangeMap != null
        ? _decodeRange(rangeMap)
        : const EditorRange(CharPosition(0, 0), CharPosition(0, 0));
    final selectionRange = s['selectionRange'] != null
        ? _decodeRange(s['selectionRange'] as Map)
        : range;
    return LspDocumentSymbol(
      name:           s['name'] as String? ?? '',
      detail:         s['detail'] as String?,
      kind:           s['kind'] as int? ?? 1,
      range:          range,
      selectionRange: selectionRange,
      children:       children,
    );
  }

  @override
  Future<List<EditorRange>> documentHighlight({
    required String uri,
    required CharPosition position,
  }) async {
    if (!_ready) return [];
    try {
      final resp = await _sendRequest('textDocument/documentHighlight', {
        'textDocument': {'uri': uri},
        'position': {'line': position.line, 'character': position.column},
      });
      final result = resp['result'];
      if (result is! List) return [];
      return result.map((h) => _decodeRange((h as Map)['range'] as Map)).toList();
    } catch (e, st) { _lspError('documentHighlight', e, st); return []; }
  }

  @override
  Future<List<LspInlayHint>> inlayHints({
    required String uri,
    required EditorRange range,
  }) async {
    if (!_ready) return [];
    try {
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
    } catch (e, st) { _lspError('inlayHints', e, st); return []; }
  }

  @override
  Future<List<LspCodeLens>> codeLens({required String uri}) async {
    if (!_ready) return [];
    try {
      final resp = await _sendRequest('textDocument/codeLens', {
        'textDocument': {'uri': uri},
      });
      final result = resp['result'];
      if (result is! List) return [];
      return result.map((item) {
        final m = item as Map;
        final range = _decodeRange(m['range'] as Map);
        final cmd = m['command'] as Map?;
        return LspCodeLens(
          range:       range,
          title:       cmd?['title'] as String?,
          command:     cmd?['command'] as String?,
          commandArgs: cmd?['arguments'] as List?,
          data:        m['data'] as Map<String, dynamic>?,
        );
      }).toList();
    } catch (e, st) { _lspError('codeLens', e, st); return []; }
  }

  @override
  Future<LspCodeLens?> resolveCodeLens(LspCodeLens item) async {
    if (!_ready || item.data == null) return item;
    try {
      final resp = await _sendRequest('codeLens/resolve', {
        'range': _encodeRange(item.range),
        if (item.data != null) 'data': item.data,
      });
      final result = resp['result'];
      if (result is! Map) return null;
      final cmd = result['command'] as Map?;
      return LspCodeLens(
        range:       item.range,
        title:       cmd?['title'] as String? ?? item.title,
        command:     cmd?['command'] as String? ?? item.command,
        commandArgs: cmd?['arguments'] as List? ?? item.commandArgs,
        data:        item.data,
      );
    } catch (e, st) { _lspError('resolveCodeLens', e, st); return null; }
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
    } catch (e, st) { _lspError('resolveCompletion', e, st); return null; }
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
    await _sendNotification('exit', {});
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
    bool isSnippet = (item['insertTextFormat'] as int? ?? 1) == 2;

    // LSP spec: textEdit.newText takes priority over insertText (§Completion Item).
    // The Dart analysis server uses textEdit with proper snippet markers.
    final textEdit = item['textEdit'] as Map?;
    String insertText = (textEdit != null
        ? textEdit['newText'] as String?
        : null)
        ?? item['insertText'] as String?
        ?? item['label'] as String? ?? '';

    // Some servers use "Foo(...)" or "Foo(…)" (Unicode ellipsis U+2026) to
    // signal "callable with arguments". Convert to a proper $1 snippet so the
    // cursor lands inside the parens. Apply even if insertTextFormat=2 was set,
    // since the server may have forgotten to escape its ellipsis as a snippet.
    if (!insertText.contains(r'$')) {
      if (insertText.endsWith('(...)')) {
        insertText = '${insertText.substring(0, insertText.length - 5)}(\$1)';
        isSnippet = true;
      } else if (insertText.endsWith('(\u2026)')) {
        // Unicode ellipsis (…) is a single code unit: length = 3 for "(…)"
        insertText = '${insertText.substring(0, insertText.length - 3)}(\$1)';
        isSnippet = true;
      }
    }
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
      filterText:    item['filterText'] as String?,
      sortText:      item['sortText'] as String?,
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
