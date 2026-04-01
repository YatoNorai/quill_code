// lib/src/completion/ai_ghost_text_providers.dart
//
// Real AI-backed GhostTextProviders — inline code completions generated from
// the actual document context, totally separate from the snippet autocomplete.
//
// USAGE — Claude (Anthropic):
//   controller.setGhostTextProvider(
//     ClaudeGhostTextProvider(apiKey: 'sk-ant-...').call,
//   );
//
// USAGE — OpenAI / OpenAI-compatible (Ollama, LM Studio, Azure, etc.):
//   controller.setGhostTextProvider(
//     OpenAiGhostTextProvider(apiKey: 'sk-...', model: 'gpt-4o-mini').call,
//   );
//
//   // Local Ollama:
//   controller.setGhostTextProvider(
//     OpenAiGhostTextProvider(
//       apiKey: 'ollama',
//       model: 'codellama:7b-code',
//       baseUrl: 'http://localhost:11434/v1',
//     ).call,
//   );
//
// Both providers use Fill-In-Middle (FIM) context — they see what is
// before AND after the cursor, producing completions that fit the surrounding
// code rather than just extrapolating from the prefix alone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'ghost_text_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/// How many characters of document text to send as context.
/// Larger = better suggestions, slower + more expensive.
const int _kDefaultMaxContextChars = 6000;
const int _kDefaultMaxTokens       = 256;
const Duration _kTimeout           = Duration(seconds: 10);

/// Strip markdown code fences that some models wrap their output in.
String _cleanCompletion(String text) {
  var s = text.trim();
  if (s.startsWith('```')) {
    final nl = s.indexOf('\n');
    if (nl != -1) s = s.substring(nl + 1);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3).trimRight();
  }
  // Also remove standalone backtick markers
  if (s == '`' || s == '``') return '';
  return s;
}

/// Keep only the last [maxChars] of [text] so the context window is bounded.
String _truncateTail(String text, int maxChars) =>
    text.length <= maxChars ? text : text.substring(text.length - maxChars);

/// Keep only the first [maxChars] of [text] (for suffix context).
String _truncateHead(String text, int maxChars) =>
    text.length <= maxChars ? text : text.substring(0, maxChars);

// ─────────────────────────────────────────────────────────────────────────────
// Claude (Anthropic) ghost text provider
// ─────────────────────────────────────────────────────────────────────────────

/// Inline code completion provider backed by Anthropic Claude.
///
/// Sends up to [maxContextChars] of prefix context and up to 500 characters
/// of suffix context so Claude can complete code that fits the surrounding
/// structure (FIM — fill-in-middle).
///
/// Recommended model: `claude-haiku-4-5-20251001` (fast, cheap, good at code).
class ClaudeGhostTextProvider {
  final String apiKey;

  /// Claude model ID. Default: claude-haiku-4-5-20251001 (fastest).
  final String model;

  /// Maximum characters of document text sent as context before the cursor.
  final int maxContextChars;

  /// Maximum characters of document text sent as context after the cursor.
  final int maxSuffixChars;

  /// Maximum completion tokens to generate.
  final int maxTokens;

  /// Anthropic API base URL (override for proxies / enterprise).
  final String baseUrl;

  ClaudeGhostTextProvider({
    required this.apiKey,
    this.model           = 'claude-haiku-4-5-20251001',
    this.maxContextChars = _kDefaultMaxContextChars,
    this.maxSuffixChars  = 500,
    this.maxTokens       = _kDefaultMaxTokens,
    this.baseUrl         = 'https://api.anthropic.com',
  });

  Future<List<String>> call(GhostTextContext ctx) async {
    if (kIsWeb) return const []; // dart:io not available on web

    // Build FIM prefix: everything up to and including the linePrefix
    final docLines  = ctx.documentText.split('\n');
    final linesBefore = docLines.sublist(0, ctx.line.clamp(0, docLines.length));
    final rawPrefix   = linesBefore.isEmpty
        ? ctx.linePrefix
        : '${linesBefore.join('\n')}\n${ctx.linePrefix}';
    final prefix = _truncateTail(rawPrefix, maxContextChars);

    // Suffix: lineSuffix + lines after cursor
    final linesAfter  = ctx.line + 1 < docLines.length
        ? docLines.sublist(ctx.line + 1)
        : <String>[];
    final rawSuffix = ctx.lineSuffix.isEmpty && linesAfter.isEmpty
        ? ''
        : '${ctx.lineSuffix}\n${linesAfter.join('\n')}';
    final suffix = _truncateHead(rawSuffix, maxSuffixChars);

    final userContent = _buildPrompt(prefix, suffix, ctx.languageId);

    try {
      final client  = HttpClient()
        ..connectionTimeout = _kTimeout;
      final request = await client
          .postUrl(Uri.parse('$baseUrl/v1/messages'))
          .timeout(_kTimeout);

      request.headers
        ..set('content-type',     'application/json; charset=utf-8')
        ..set('x-api-key',        apiKey)
        ..set('anthropic-version','2023-06-01');

      request.add(utf8.encode(jsonEncode({
        'model':      model,
        'max_tokens': maxTokens,
        'system':     _systemPrompt(ctx.languageId),
        'messages': [
          {'role': 'user', 'content': userContent},
        ],
      })));

      final response = await request.close().timeout(_kTimeout);
      final body     = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) return const [];

      final json    = jsonDecode(body) as Map<String, dynamic>;
      final content = json['content'] as List?;
      if (content == null || content.isEmpty) return const [];

      final text = (content.first as Map<String, dynamic>)['text'] as String? ?? '';
      final clean = _cleanCompletion(text);
      if (clean.isEmpty) return const [];
      return [clean];
    } catch (_) {
      return const [];
    }
  }

  static String _systemPrompt(String language) =>
      'You are an expert $language code completion engine embedded in a code editor. '
      'The user\'s cursor is at the <|CURSOR|> marker. '
      'Output ONLY the code that should appear at the cursor — '
      'no explanation, no comments, no markdown fences. '
      'Match the surrounding indentation and style exactly.';

  static String _buildPrompt(String prefix, String suffix, String language) {
    final buf = StringBuffer()
      ..writeln('Complete the $language code at the <|CURSOR|> marker.')
      ..writeln()
      ..write(prefix)
      ..write('<|CURSOR|>');
    if (suffix.isNotEmpty) buf.write(suffix);
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OpenAI-compatible ghost text provider
// ─────────────────────────────────────────────────────────────────────────────

/// Inline code completion provider backed by any OpenAI-compatible chat API.
///
/// Works with:
///   • OpenAI (gpt-4o-mini, gpt-4o, o1-mini, …)
///   • Azure OpenAI
///   • Ollama  (http://localhost:11434/v1)
///   • LM Studio (http://localhost:1234/v1)
///   • Any OpenAI-compatible proxy
///
/// Uses FIM-style prompting: prefix + suffix context for better in-context
/// completions rather than just open-ended continuation.
class OpenAiGhostTextProvider {
  final String apiKey;

  /// Model ID. Examples: 'gpt-4o-mini', 'codellama:7b-code', 'deepseek-coder'.
  final String model;

  /// Maximum characters of document text sent as context before the cursor.
  final int maxContextChars;

  /// Maximum characters of document text sent as context after the cursor.
  final int maxSuffixChars;

  /// Maximum completion tokens to generate.
  final int maxTokens;

  /// API base URL. Override for proxies, Ollama, LM Studio, etc.
  final String baseUrl;

  OpenAiGhostTextProvider({
    required this.apiKey,
    this.model           = 'gpt-4o-mini',
    this.maxContextChars = _kDefaultMaxContextChars,
    this.maxSuffixChars  = 500,
    this.maxTokens       = _kDefaultMaxTokens,
    this.baseUrl         = 'https://api.openai.com/v1',
  });

  Future<List<String>> call(GhostTextContext ctx) async {
    if (kIsWeb) return const [];

    // Build prefix up to cursor
    final docLines    = ctx.documentText.split('\n');
    final linesBefore = docLines.sublist(0, ctx.line.clamp(0, docLines.length));
    final rawPrefix   = linesBefore.isEmpty
        ? ctx.linePrefix
        : '${linesBefore.join('\n')}\n${ctx.linePrefix}';
    final prefix = _truncateTail(rawPrefix, maxContextChars);

    // Suffix after cursor
    final linesAfter = ctx.line + 1 < docLines.length
        ? docLines.sublist(ctx.line + 1)
        : <String>[];
    final rawSuffix = ctx.lineSuffix.isEmpty && linesAfter.isEmpty
        ? ''
        : '${ctx.lineSuffix}\n${linesAfter.join('\n')}';
    final suffix = _truncateHead(rawSuffix, maxSuffixChars);

    try {
      final client  = HttpClient()
        ..connectionTimeout = _kTimeout;
      final request = await client
          .postUrl(Uri.parse('$baseUrl/chat/completions'))
          .timeout(_kTimeout);

      request.headers
        ..set('content-type', 'application/json; charset=utf-8')
        ..set('authorization', 'Bearer $apiKey');

      final userMessage = _buildPrompt(prefix, suffix, ctx.languageId);

      request.add(utf8.encode(jsonEncode({
        'model':       model,
        'max_tokens':  maxTokens,
        'temperature': 0.15,
        'messages': [
          {
            'role':    'system',
            'content': 'You are an expert ${ctx.languageId} code completion engine. '
                'Complete ONLY the code that belongs at <|CURSOR|>. '
                'Output raw code only — no explanation, no markdown.',
          },
          {'role': 'user', 'content': userMessage},
        ],
      })));

      final response = await request.close().timeout(_kTimeout);
      final body     = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) return const [];

      final json    = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return const [];

      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final text  = message?['content'] as String? ?? '';
      final clean = _cleanCompletion(text);
      if (clean.isEmpty) return const [];
      return [clean];
    } catch (_) {
      return const [];
    }
  }

  static String _buildPrompt(String prefix, String suffix, String language) {
    final buf = StringBuffer()
      ..writeln('Complete the $language code at <|CURSOR|>.')
      ..writeln()
      ..write(prefix)
      ..write('<|CURSOR|>');
    if (suffix.isNotEmpty) buf.write(suffix);
    return buf.toString();
  }
}
