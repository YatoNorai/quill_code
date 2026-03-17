// example/lib/screens/git_diff_screen.dart
//
// Demonstrates QuillCode's built-in Git Diff decoration:
//   • Live diff between two editor panes (original vs modified)
//   • Unified diff viewer with hunk navigation
//   • Parse raw `git diff` / `diff -u` output
//   • Switch between diff gutter themes

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quill_code/quill_code.dart';
// DarkEditorTheme is exported from quill_code via theme_dark.dart

// ─── Sample content ───────────────────────────────────────────────────────────

const _kOriginal = r'''import 'dart:async';

/// Handles HTTP communication with the backend API.
class ApiClient {
  final String baseUrl;
  final _client = HttpClient();

  ApiClient({required this.baseUrl});

  Future<Map<String, dynamic>> get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = await _client.getUrl(uri);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return json.decode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = await _client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(json.encode(data));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return json.decode(body) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
''';

const _kModified = r'''import 'dart:async';

/// Handles HTTP communication with the backend API.
/// Refactored to use the `http` package for cross-platform support.
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? headers}) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _client.get(uri, headers: headers);
    _checkStatus(res);
    return json.decode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json', ...?headers},
      body: json.encode(data),
    );
    _checkStatus(res);
    return json.decode(res.body) as Map<String, dynamic>;
  }

  void _checkStatus(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }

  void close() => _client.close();
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  const ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}
''';

// ─── Sample raw unified diff (simulates `git diff` output) ───────────────────

const _kRawGitDiff = r'''--- a/lib/utils/validator.dart
+++ b/lib/utils/validator.dart
@@ -1,18 +1,30 @@
+// Updated: stricter validation rules + async support
+
 class Validator {
-  static bool isEmail(String value) {
-    return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value);
+  static bool isEmail(String value) {
+    final pattern = RegExp(
+      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
+    );
+    return pattern.hasMatch(value.trim());
   }
 
-  static bool isPhone(String value) {
-    return value.length >= 10;
+  static bool isPhone(String value) {
+    final digits = value.replaceAll(RegExp(r'\D'), '');
+    return digits.length >= 10 && digits.length <= 15;
   }
 
-  static String? validatePassword(String value) {
+  static Future<bool> isUsernameAvailable(String username) async {
+    await Future.delayed(const Duration(milliseconds: 300));
+    return !['admin', 'root', 'system'].contains(username.toLowerCase());
+  }
+
+  static String? validatePassword(String value) {
     if (value.length < 8) return 'Mínimo 8 caracteres';
-    return null;
+    if (!value.contains(RegExp(r'[A-Z]'))) return 'Precisa de maiúscula';
+    if (!value.contains(RegExp(r'[0-9]'))) return 'Precisa de número';
+    if (!value.contains(RegExp(r'[!@#\$%^&*]')))
+      return 'Precisa de símbolo especial';
+    return null;
   }
 }
''';

// ─────────────────────────────────────────────────────────────────────────────

class GitDiffScreen extends StatefulWidget {
  const GitDiffScreen({super.key});

  @override
  State<GitDiffScreen> createState() => _GitDiffScreenState();
}

class _GitDiffScreenState extends State<GitDiffScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Tab 0 – live diff
  late final QuillCodeController _origCtrl;
  late final QuillCodeController _modCtrl;
  List<DiffHunk> _liveHunks = [];
  int _hunkIdx = 0;

  // Tab 1 – parse raw git diff
  late final QuillCodeController _rawCtrl;
  late final QuillCodeController _parsedCtrl;
  List<DiffHunk> _parsedHunks = [];

  String _gutterThemeName = 'GitHub';
  DiffGutterTheme _gutterTheme = DiffGutterTheme.github;

  // Debounce timer for async live-diff — prevents blocking the UI on every keystroke.
  Timer? _diffDebounce;

  static const _gutterThemes = {
    'GitHub' : DiffGutterTheme.github,
    'Subtle' : DiffGutterTheme.subtle,
    'Vibrant': DiffGutterTheme.vibrant,
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);

    _origCtrl = QuillCodeController(language: DartLanguage())
      ..setText(_kOriginal);
    _modCtrl  = QuillCodeController(language: DartLanguage())
      ..setText(_kModified);
    _rawCtrl    = QuillCodeController(language: PlainTextLanguage())
      ..setText(_kRawGitDiff);
    _parsedCtrl = QuillCodeController(language: DartLanguage())
      ..setText(_kModified);

    _modCtrl.addListener(_recomputeLiveDiff);

    // Initial computations
    _recomputeLiveDiff();
    _parsePastedDiff();
  }

  @override
  void dispose() {
    _diffDebounce?.cancel();
    _tabs.dispose();
    _origCtrl.dispose();
    _modCtrl.dispose();
    _rawCtrl.dispose();
    _parsedCtrl.dispose();
    super.dispose();
  }

  // ── Live diff ─────────────────────────────────────────────────────────────
  // Uses a 300 ms debounce + async computation so keystrokes never block the UI.

  void _recomputeLiveDiff() {
    _diffDebounce?.cancel();
    _diffDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final orig = _origCtrl.content.fullText;
      final mod  = _modCtrl.content.fullText;
      final hunks = await DiffEngine.diffStringsAsync(orig, mod);
      if (!mounted) return;
      setState(() {
        _liveHunks = hunks;
        _hunkIdx   = 0;
      });
      GitDiffDecoration.apply(_modCtrl, hunks, theme: _gutterTheme);
    });
  }

  // ── Parse raw unified diff ────────────────────────────────────────────────

  void _parsePastedDiff() {
    final raw    = _rawCtrl.content.fullText;
    final hunks  = UnifiedDiffParser.parse(raw);
    setState(() => _parsedHunks = hunks);
    GitDiffDecoration.apply(_parsedCtrl, hunks, theme: _gutterTheme);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _prevHunk(List<DiffHunk> hunks) {
    if (hunks.isEmpty) return;
    setState(() => _hunkIdx = (_hunkIdx - 1 + hunks.length) % hunks.length);
  }

  void _nextHunk(List<DiffHunk> hunks) {
    if (hunks.isEmpty) return;
    setState(() => _hunkIdx = (_hunkIdx + 1) % hunks.length);
  }

  void _applyGutterTheme(String name) {
    setState(() {
      _gutterThemeName = name;
      _gutterTheme     = _gutterThemes[name]!;
    });
    GitDiffDecoration.apply(_modCtrl,    _liveHunks,    theme: _gutterTheme);
    GitDiffDecoration.apply(_parsedCtrl, _parsedHunks,  theme: _gutterTheme);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  // Use the built-in Dark Catppuccin theme — no need to redeclare 70+ fields manually.
  static EditorTheme get _cs => DarkEditorTheme.theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        foregroundColor: const Color(0xFFCDD6F4),
        title: const Text('Git Diff — QuillCode', style: TextStyle(fontSize: 15)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF89B4FA),
          unselectedLabelColor: const Color(0xFF6C7086),
          indicatorColor: const Color(0xFF89B4FA),
          tabs: const [
            Tab(text: '⚡ Live Diff'),
            Tab(text: '📋 Unified Diff'),
          ],
        ),
        actions: [
          // Gutter theme picker
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _gutterThemeName,
                dropdownColor: const Color(0xFF313244),
                style: const TextStyle(color: Color(0xFFCDD6F4), fontSize: 13),
                items: _gutterThemes.keys.map((k) => DropdownMenuItem(
                  value: k,
                  child: Text('🎨 $k'),
                )).toList(),
                onChanged: (v) { if (v != null) _applyGutterTheme(v); },
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildLiveDiffTab(),
          _buildUnifiedDiffTab(),
        ],
      ),
    );
  }

  // ── Tab 0: Live diff ──────────────────────────────────────────────────────

  Widget _buildLiveDiffTab() {
    final addCount = _liveHunks.fold(0, (n, h) => n + h.added.length);
    final delCount = _liveHunks.fold(0, (n, h) => n + h.removed.length);

    return Column(children: [
      // Stats bar
      _StatsBar(
        added: addCount,
        removed: delCount,
        hunks: _liveHunks.length,
        currentHunk: _liveHunks.isEmpty ? 0 : _hunkIdx + 1,
        onPrev: () => _prevHunk(_liveHunks),
        onNext: () => _nextHunk(_liveHunks),
      ),
      Expanded(
        child: Row(children: [
          // Original (read-only)
          Expanded(
            child: Column(children: [
              _paneHeader('ORIGINAL', const Color(0xFF6C7086)),
              Expanded(
                child: QuillCodeEditor(
                  controller: _origCtrl,
                  theme: _cs,
                ),
              ),
            ]),
          ),
          // Divider
          Container(width: 1, color: const Color(0xFF313244)),
          // Modified (editable — diff updates live)
          Expanded(
            child: Column(children: [
              _paneHeader('MODIFIED  ✏️ (edit aqui)', const Color(0xFF89B4FA)),
              Expanded(
                child: QuillCodeEditor(
                  controller: _modCtrl,
                  theme: _cs,
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }

  // ── Tab 1: Parse unified diff ─────────────────────────────────────────────

  Widget _buildUnifiedDiffTab() {
    final addCount = _parsedHunks.fold(0, (n, h) => n + h.added.length);
    final delCount = _parsedHunks.fold(0, (n, h) => n + h.removed.length);

    return Column(children: [
      _StatsBar(
        added: addCount,
        removed: delCount,
        hunks: _parsedHunks.length,
        currentHunk: _parsedHunks.isEmpty ? 0 : _hunkIdx + 1,
        onPrev: () => _prevHunk(_parsedHunks),
        onNext: () => _nextHunk(_parsedHunks),
      ),
      Expanded(
        child: Row(children: [
          // Raw diff input
          Expanded(
            child: Column(children: [
              _paneHeader('RAW UNIFIED DIFF  ✏️', const Color(0xFFFAB387)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: ElevatedButton.icon(
                  onPressed: _parsePastedDiff,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Aplicar diff', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF313244),
                    foregroundColor: const Color(0xFF89B4FA),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              ),
              Expanded(
                child: QuillCodeEditor(
                  controller: _rawCtrl,
                  theme: _cs.copyWith(
                    colorScheme: _cs.colorScheme.copyWith(
                      background: const Color(0xFF181825),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Container(width: 1, color: const Color(0xFF313244)),
          // Decorated result
          Expanded(
            child: Column(children: [
              _paneHeader('RESULTADO COM DECORAÇÕES', const Color(0xFFA6E3A1)),
              Expanded(
                child: QuillCodeEditor(
                  controller: _parsedCtrl,
                  theme: _cs,
                ),
              ),
            ]),
          ),
        ]),
      ),
      // Hunk list
      if (_parsedHunks.isNotEmpty)
        _HunkList(hunks: _parsedHunks),
    ]);
  }

  Widget _paneHeader(String label, Color color) => Container(
    width: double.infinity,
    color: const Color(0xFF181825),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Text(label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        )),
  );
}

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int added, removed, hunks, currentHunk;
  final VoidCallback onPrev, onNext;

  const _StatsBar({
    required this.added,
    required this.removed,
    required this.hunks,
    required this.currentHunk,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF181825),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(children: [
      _badge('+$added', const Color(0xFF3FB950)),
      const SizedBox(width: 8),
      _badge('-$removed', const Color(0xFFF85149)),
      const SizedBox(width: 12),
      Text('$hunks hunk${hunks == 1 ? '' : 's'}',
          style: const TextStyle(color: Color(0xFF6C7086), fontSize: 12)),
      const Spacer(),
      if (hunks > 0) ...[
        Text('$currentHunk / $hunks',
            style: const TextStyle(color: Color(0xFF6C7086), fontSize: 12)),
        const SizedBox(width: 6),
        _navBtn(Icons.keyboard_arrow_up,   onPrev),
        _navBtn(Icons.keyboard_arrow_down, onNext),
      ],
    ]),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _navBtn(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Icon(icon, size: 16, color: const Color(0xFF89B4FA)),
    ),
  );
}

// ── Hunk list ─────────────────────────────────────────────────────────────────

class _HunkList extends StatelessWidget {
  final List<DiffHunk> hunks;
  const _HunkList({required this.hunks});

  @override
  Widget build(BuildContext context) => Container(
    height: 110,
    color: const Color(0xFF181825),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 0, 4),
        child: Text('HUNKS', style: TextStyle(color: Color(0xFF6C7086), fontSize: 10, letterSpacing: 1)),
      ),
      Expanded(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          itemCount: hunks.length,
          itemBuilder: (_, i) {
            final h = hunks[i];
            final added   = h.added.length;
            final removed = h.removed.length;
            return Container(
              width: 140,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF313244),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('@@ +${h.newStart}', style: const TextStyle(color: Color(0xFF89B4FA), fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                if (h.header != null && h.header!.isNotEmpty)
                  Text(h.header!, style: const TextStyle(color: Color(0xFF6C7086), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Row(children: [
                  Text('+$added',   style: const TextStyle(color: Color(0xFF3FB950), fontSize: 11)),
                  const SizedBox(width: 6),
                  Text('-$removed', style: const TextStyle(color: Color(0xFFF85149), fontSize: 11)),
                ]),
              ]),
            );
          },
        ),
      ),
    ]),
  );
}
