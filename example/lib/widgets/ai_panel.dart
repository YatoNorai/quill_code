// example/lib/widgets/ai_panel.dart
//
// Painel lateral de IA: Chat + Code Review
// Mostra o status do Ghost Text e permite interagir com o assistente.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/gemini_service.dart';
import '../app_state.dart';

class AiPanel extends StatefulWidget {
  final AppState state;
  final String   currentCode;
  final String   currentLanguage;
  final VoidCallback onClose;

  const AiPanel({
    super.key,
    required this.state,
    required this.currentCode,
    required this.currentLanguage,
    required this.onClose,
  });

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _chatCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _messages = <_Msg>[];
  bool _loading   = false;
  bool _reviewing = false;
  String _reviewResult = '';

  static const _bg      = Color(0xFF1E1E2E);
  static const _surface = Color(0xFF181825);
  static const _surface2 = Color(0xFF24243A);
  static const _accent  = Color(0xFF89B4FA);
  static const _accent2 = Color(0xFFCBA6F7);
  static const _text    = Color(0xFFCDD6F4);
  static const _subtext = Color(0xFF9399B2);
  static const _green   = Color(0xFFA6E3A1);
  static const _red     = Color(0xFFF38BA8);
  static const _yellow  = Color(0xFFF9E2AF);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _messages.add(_Msg(
      role: 'assistant',
      text: '👋 Olá! Sou seu assistente de código com Gemini ${widget.state.ai.geminiModel}.\n\n'
        '${widget.state.ai.isConfigured ? "✅ API configurada. Pronto para ajudar!" : "⚠️ Configure sua chave Gemini nas configurações para ativar o assistente."}\n\n'
        'Posso ajudar com:\n• Explicar código\n• Refatorar funções\n• Depurar erros\n• Gerar testes\n• Code review completo',
    ));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  GeminiService? get _svc {
    final ai = widget.state.ai;
    if (!ai.isConfigured) return null;
    return GeminiService(
      apiKey: ai.geminiApiKey,
      model: ai.geminiModel,
      maxTokens: 1024,
      temperature: 0.7,
    );
  }

  Future<void> _sendMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(_Msg(role: 'user', text: text));
      _loading = true;
    });
    _chatCtrl.clear();
    _scrollToBottom();

    final svc = _svc;
    if (svc == null) {
      setState(() {
        _messages.add(_Msg(role: 'assistant',
            text: '⚠️ Configure sua chave Gemini API nas configurações para usar o chat.'));
        _loading = false;
      });
      return;
    }

    final reply = await svc.chat(text, code: widget.currentCode);
    setState(() {
      _messages.add(_Msg(role: 'assistant', text: reply));
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _startReview() async {
    setState(() { _reviewing = true; _reviewResult = ''; });

    final svc = _svc;
    if (svc == null) {
      setState(() { _reviewing = false; _reviewResult = '⚠️ Configure a API Gemini primeiro.'; });
      return;
    }

    if (widget.currentCode.trim().isEmpty) {
      setState(() { _reviewing = false; _reviewResult = '⚠️ O editor está vazio.'; });
      return;
    }

    final result = await svc.reviewCode(widget.currentCode, widget.currentLanguage);
    setState(() { _reviewing = false; _reviewResult = result; });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ai = widget.state.ai;
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: _bg,
        border: Border(left: BorderSide(color: _surface2, width: 1.5)),
      ),
      child: Column(children: [
        // Header
        Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _accent2.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('🤖', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI Agent', style: TextStyle(color: _text, fontSize: 15,
                    fontWeight: FontWeight.w700)),
                Text(ai.isConfigured
                    ? 'Gemini ${ai.geminiModel}'
                    : 'Sem API configurada',
                    style: TextStyle(
                      color: ai.isConfigured ? _green : _red,
                      fontSize: 11,
                    )),
              ])),
              IconButton(
                icon: const Icon(Icons.close, color: _subtext, size: 18),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
              ),
            ]),
            const SizedBox(height: 8),
            // Status chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _statusChip(
                  ai.ghostTextEnabled && ai.isConfigured ? '👻 Ghost ON' : '👻 Ghost OFF',
                  ai.ghostTextEnabled && ai.isConfigured ? _green : _subtext,
                ),
                const SizedBox(width: 6),
                _statusChip('⚡ ${ai.geminiModel.split('-').take(2).join('-')}', _accent),
                const SizedBox(width: 6),
                _statusChip('🌡 ${ai.temperature}', _yellow),
              ]),
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabs,
              indicatorColor: _accent,
              labelColor: _accent,
              unselectedLabelColor: _subtext,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: '💬 Chat'),
                Tab(text: '🔍 Review'),
              ],
            ),
          ]),
        ),

        // Body
        Expanded(child: TabBarView(
          controller: _tabs,
          children: [_buildChat(), _buildReview()],
        )),
      ]),
    );
  }

  Widget _buildChat() => Column(children: [
    // Messages
    Expanded(
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length + (_loading ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _messages.length) return _buildTypingIndicator();
          return _buildMessage(_messages[i]);
        },
      ),
    ),

    // Quick actions
    Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _quickBtn('Explique este código', Icons.help_outline),
          const SizedBox(width: 6),
          _quickBtn('Adicione testes', Icons.science_outlined),
          const SizedBox(width: 6),
          _quickBtn('Refatore', Icons.auto_fix_high),
          const SizedBox(width: 6),
          _quickBtn('Encontre bugs', Icons.bug_report_outlined),
        ]),
      ),
    ),
    const SizedBox(height: 6),

    // Input
    Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _surface2)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _chatCtrl,
            style: const TextStyle(color: _text, fontSize: 13),
            maxLines: 3, minLines: 1,
            onSubmitted: (_) => _sendMessage(),
            decoration: InputDecoration(
              hintText: 'Pergunte sobre o código...',
              hintStyle: TextStyle(color: _subtext.withOpacity(0.6), fontSize: 13),
              filled: true, fillColor: _surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sendMessage,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _loading ? _subtext.withOpacity(0.2) : _accent.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _loading ? _subtext : _accent),
            ),
            child: Icon(_loading ? Icons.hourglass_empty : Icons.send,
                color: _loading ? _subtext : _accent, size: 16),
          ),
        ),
      ]),
    ),
  ]);

  Widget _buildReview() => SingleChildScrollView(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Info card
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _accent2.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accent2.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🔍 Code Review com IA',
              style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Analisa o código atual (${widget.currentCode.split('\n').length} linhas) '
               'e retorna feedback detalhado.',
              style: const TextStyle(color: _subtext, fontSize: 12)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _reviewing ? _subtext.withOpacity(0.15) : _accent2.withOpacity(0.2),
                foregroundColor: _reviewing ? _subtext : _accent2,
                side: BorderSide(color: _reviewing ? _subtext : _accent2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _reviewing
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent2))
                : const Icon(Icons.play_arrow, size: 18),
              label: Text(_reviewing ? 'Analisando...' : 'Iniciar Review'),
              onPressed: _reviewing ? null : _startReview,
            ),
          ),
        ]),
      ),

      if (_reviewResult.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Resultado:', style: TextStyle(color: _subtext, fontSize: 12,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Spacer(),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: _reviewResult)),
                child: const Icon(Icons.copy, color: _subtext, size: 14),
              ),
            ]),
            Text(_reviewResult,
                style: const TextStyle(color: _text, fontSize: 13, height: 1.5)),
          ]),
        ),
      ],
    ]),
  );

  Widget _buildMessage(_Msg msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _accent2.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => Clipboard.setData(ClipboardData(text: msg.text)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? _accent.withOpacity(0.15) : _surface2,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 16 : 4),
                    topRight: Radius.circular(isUser ? 4 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  border: Border.all(
                    color: isUser ? _accent.withOpacity(0.3) : Colors.transparent,
                  ),
                ),
                child: Text(msg.text,
                    style: TextStyle(
                      color: isUser ? _accent : _text,
                      fontSize: 13, height: 1.5,
                    )),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('👤', style: TextStyle(fontSize: 14))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: _accent2.withOpacity(0.2), shape: BoxShape.circle),
        child: const Center(child: Text('🤖', style: TextStyle(fontSize: 14))),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: _surface2,
            borderRadius: BorderRadius.circular(16)),
        child: const _TypingDots(),
      ),
    ]),
  );

  Widget _quickBtn(String label, IconData icon) => GestureDetector(
    onTap: () {
      _chatCtrl.text = label;
      _sendMessage();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _subtext.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _subtext, size: 13),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: _subtext, fontSize: 12)),
      ]),
    ),
  );

  Widget _statusChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11,
        fontWeight: FontWeight.w600)),
  );
}

class _Msg { final String role, text; const _Msg({required this.role, required this.text}); }

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override void initState() { super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) {
      final v = _ctrl.value;
      return Row(mainAxisSize: MainAxisSize.min, children: [0, 1, 2].map((i) {
        final active = (v * 3).floor() == i;
        return Container(
          width: 7, height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF89B4FA) : const Color(0xFF6C7086),
            shape: BoxShape.circle,
          ),
        );
      }).toList());
    },
  );
}
