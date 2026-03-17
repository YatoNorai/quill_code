// example/lib/ai/gemini_service.dart
//
// GeminiService — chama a API Gemini usando dart:io HttpClient.
// Zero dependências externas.

import 'dart:convert';
import 'dart:io';
import 'package:quill_code/quill_code.dart';

class GeminiService {
  static const _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String apiKey;
  final String model;
  final int    maxTokens;
  final double temperature;
  final String systemPrompt;

  GeminiService({
    required this.apiKey,
    this.model       = 'gemini-2.0-flash',
    this.maxTokens   = 256,
    this.temperature = 0.2,
    this.systemPrompt = _kDefault,
  });

  static const _kDefault =
    'You are a senior Flutter/Dart developer assistant. '
    'The user has typed some code and stopped. Your job is to complete it. '
    'CRITICAL: Reply with ONLY the characters that come AFTER the cursor — '
    'do NOT repeat what the user already typed on the current line. '
    'For example, if the user typed "void ma", reply "in() {\n  \n}" — '
    'NOT "void main() {\n  \n}". '
    'No markdown. No explanations. No code fences. 1-6 lines maximum.';

  // ── Ghost text provider ───────────────────────────────────────────────────

  Future<List<String>> ghostProvider(GhostTextContext ctx) async {
    if (apiKey.isEmpty) return [];
    try {
      final body = jsonEncode({
        'system_instruction': {'parts': [{'text': systemPrompt}]},
        'contents': [{'role': 'user', 'parts': [{'text': _buildPrompt(ctx)}]}],
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxTokens,
          'candidateCount': 1,
          'stopSequences': ['\n\n\n'],
        },
      });

      final data = await _post('$_base/$model:generateContent', body,
          timeout: const Duration(seconds: 8));
      if (data == null) return [];

      final candidates = data['candidates'] as List? ?? [];
      final results = <String>[];
      for (final c in candidates) {
        for (final p in (c['content']?['parts'] as List? ?? [])) {
          final t = (p['text'] as String? ?? '').trim();
          if (t.isNotEmpty) results.add(t);
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  Future<String> chat(String msg, {String? code}) async {
    if (apiKey.isEmpty) return '⚠️ Configure a chave Gemini API nas configurações.';
    final ctx = code != null && code.isNotEmpty
        ? '\n\nCódigo atual:\n```dart\n$code\n```' : '';
    try {
      final data = await _post('$_base/$model:generateContent', jsonEncode({
        'system_instruction': {'parts': [{'text':
          'Você é um assistente expert em Flutter e Dart. '
          'Responda de forma clara e prática.$ctx'}]},
        'contents': [{'role': 'user', 'parts': [{'text': msg}]}],
        'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1024},
      }), timeout: const Duration(seconds: 30));
      if (data == null) return 'Erro: sem resposta do servidor.';

      final cands = data['candidates'] as List? ?? [];
      if (cands.isEmpty) return 'Sem resposta.';
      final parts = (cands.first['content']?['parts'] as List?) ?? [];
      return parts.map((p) => p['text'] as String? ?? '').join('').trim();
    } on HttpException catch (e) {
      if (e.message.contains('401') || e.message.contains('403')) {
        return 'Erro: chave de API inválida ou sem permissão.';
      }
      return 'Erro HTTP: ${e.message}';
    } catch (e) {
      return 'Erro: $e';
    }
  }

  // ── Code review ───────────────────────────────────────────────────────────

  Future<String> reviewCode(String code, String lang) => chat(
    'Faça um code review completo do código $lang. '
    'Organize por: Bugs, Performance, Boas Práticas, Sugestões de Refatoração.',
    code: code,
  );

  // ── Key validation ────────────────────────────────────────────────────────

  Future<bool> validateKey() async {
    if (apiKey.isEmpty) return false;
    try {
      final data = await _post('$_base/$model:generateContent', jsonEncode({
        'contents': [{'role': 'user', 'parts': [{'text': 'Hi'}]}],
        'generationConfig': {'maxOutputTokens': 5},
      }), timeout: const Duration(seconds: 10));
      return data != null && data.containsKey('candidates');
    } catch (_) {
      return false;
    }
  }

  // ── HTTP helper ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _post(String url, String body,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final uri = Uri.parse('$url?key=$apiKey');
    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final req = await client.postUrl(uri)
        ..headers.set(HttpHeaders.contentTypeHeader, 'application/json')
        ..write(body);
      final res = await req.close().timeout(timeout);

      final raw = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw HttpException('${res.statusCode}: auth error');
      }
      if (res.statusCode != 200) return null;

      return jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  // ── Prompt builder ────────────────────────────────────────────────────────

  String _buildPrompt(GhostTextContext ctx) {
    final text   = ctx.documentText;
    final offset = _offset(text, ctx.line, ctx.column);
    var before   = text.substring(0, offset);
    var after    = text.substring(offset);

    if (before.length > 1500) before = '...\n${before.substring(before.length - 1500)}';
    if (after.length > 400)   after   = after.substring(0, 400);

    return 'Complete the code. Output ONLY what goes after <CURSOR>.\n'
        'Line prefix already typed: "\${ctx.linePrefix}" — do NOT repeat it.\n\n'
        '<BEFORE>\n\$before<CURSOR>\n</BEFORE>\n\n'
        '<AFTER>\n\$after\n</AFTER>\n\n'
        'Reply with only the missing code. No markdown.';
  }

  int _offset(String text, int line, int col) {
    int off = 0, l = 0;
    while (off < text.length) {
      if (l == line) {
        final lineStart = off;
        return (lineStart + col).clamp(0, text.length);
      }
      if (text[off] == '\n') l++;
      off++;
    }
    return text.length;
  }
}
