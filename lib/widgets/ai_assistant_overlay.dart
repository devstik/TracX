import 'package:flutter/material.dart';

import '../services/ai_assistant_service.dart';

class AiAssistantOverlay extends StatefulWidget {
  const AiAssistantOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<AiAssistantOverlay> createState() => _AiAssistantOverlayState();
}

class _AiAssistantOverlayState extends State<AiAssistantOverlay> {
  static const Color _bg = Color(0xFF08111F);
  static const Color _surface = Color(0xFF0F1B2D);
  static const Color _surfaceAlt = Color(0xFF14243A);
  static const Color _primary = Color(0xFFD8B840);
  static const Color _text = Color(0xFFF8FAFC);
  static const Color _muted = Color(0xFF94A3B8);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<AiAssistantMessage> _messages = [
    const AiAssistantMessage(
      role: 'assistant',
      content:
          'Assistente pronto. Pergunte sobre apontamentos, registros, estoque, tinturaria, planejamento ou pendencias do TracX.',
    ),
  ];

  bool _open = false;
  bool _sending = false;
  int _composerVersion = 0;
  String? _error;

  static const List<String> _quickPrompts = [
    'Quantos apontamentos foram feitos hoje?',
    'Qual foi a movimentacao de estoque hoje?',
    'Resuma os apontamentos de hoje por setor',
    'Mostre 5 apontamentos de hoje com nome, setor e quantidade',
    'Quais pedidos pendentes da tinturaria merecem prioridade?',
    'Quais registros foram feitos hoje?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? _controller.text).trim();
    if (_sending) return;
    await _analyzeData(text);
  }

  void _toggleOpen() {
    setState(() => _open = !_open);
  }

  Future<void> _analyzeData([String foco = '']) async {
    if (_sending) return;

    final textoUsuario = foco.trim().isEmpty
        ? 'Analise os dados operacionais atuais do TracX e destaque o que merece atencao.'
        : foco.trim();
    final history = List<AiAssistantMessage>.from(
      _messages.where(
        (message) => message.role == 'user' || message.role == 'assistant',
      ),
    );

    _clearComposer();

    setState(() {
      _messages.add(AiAssistantMessage(role: 'user', content: textoUsuario));
      _sending = true;
      _error = null;
      _open = true;
    });
    _scrollToBottom();

    try {
      final response = await AiAssistantService.enviarMensagem(
        message: textoUsuario,
        history: history,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiAssistantMessage(role: 'assistant', content: response.answer),
        );
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _clear() {
    setState(() {
      _messages
        ..clear()
        ..add(
          const AiAssistantMessage(
            role: 'assistant',
            content:
                'Conversa reiniciada. Pergunte sobre os dados do TracX para eu consultar o backend da IA.',
          ),
        );
      _error = null;
    });
  }

  void _clearComposer() {
    _controller
      ..clear()
      ..clearComposing()
      ..selection = const TextSelection.collapsed(offset: 0);
    _inputFocus.unfocus();
    _composerVersion++;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_open)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(color: Colors.black.withValues(alpha: 0.08)),
            ),
          ),
        Positioned(
          right: 14,
          bottom: 14 + MediaQuery.viewInsetsOf(context).bottom,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _open ? _buildPanel(context) : const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                _buildBubble(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBubble() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _toggleOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: _primary,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE8CE7A), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            _open ? Icons.close_rounded : Icons.psychology_alt_rounded,
            color: _bg,
            size: 29,
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isNarrow = size.width < 560;
    final width = isNarrow ? size.width - 28 : 420.0;
    final height = isNarrow ? size.height * 0.66 : 560.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height.clamp(360.0, size.height - 110),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              _buildHeader(),
              _buildInsightAction(),
              _buildQuickPrompts(),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_sending && index == _messages.length) {
                      return _TypingBubble(
                        surface: _surface,
                        border: const Color(0xFF26364E),
                      );
                    }
                    return _MessageBubble(
                      message: _messages[index],
                      primary: _primary,
                      surface: _surface,
                      text: _text,
                      bg: _bg,
                    );
                  },
                ),
              ),
              if (_error != null) _buildError(),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.psychology_alt_rounded, color: _bg),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assistente IA',
                  style: TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Alertas, gargalos e leitura dos dados',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _sending ? null : _clear,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.cleaning_services_rounded,
                  color: _sending ? const Color(0xFF475569) : _muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightAction() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: FilledButton.icon(
        onPressed: _sending ? null : _analyzeData,
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: _bg,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: _sending
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.analytics_rounded),
        label: Text(
          _sending ? 'Consultando...' : 'Consultar dados do TracX',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildQuickPrompts() {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tips_and_updates_rounded,
                color: _primary,
                size: 15,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Perguntas uteis',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickPrompts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final text = _quickPrompts[index];
                return ActionChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  onPressed: _sending ? null : () => _send(text),
                  backgroundColor: _surfaceAlt,
                  side: const BorderSide(color: Color(0xFF334155)),
                  labelStyle: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF451A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF991B1B)),
      ),
      child: Text(
        _error!,
        style: const TextStyle(
          color: Color(0xFFFEE2E2),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('ai-composer-$_composerVersion'),
              controller: _controller,
              focusNode: _inputFocus,
              enabled: !_sending,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(
                color: _text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              onSubmitted: (_) => _sending ? null : _send(),
              decoration: InputDecoration(
                hintText: 'Pergunte sobre o TracX...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                filled: true,
                fillColor: _surfaceAlt,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: FilledButton(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: _primary,
                foregroundColor: _bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.primary,
    required this.surface,
    required this.text,
    required this.bg,
  });

  final AiAssistantMessage message;
  final Color primary;
  final Color surface;
  final Color text;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? primary : surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isUser ? const Color(0xFFE8CE7A) : const Color(0xFF26364E),
          ),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? bg : text,
            fontSize: 13,
            height: 1.34,
            fontWeight: isUser ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.surface, required this.border});

  final Color surface;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            Text(
              'Pensando...',
              style: TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
