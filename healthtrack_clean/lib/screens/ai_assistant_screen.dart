// lib/screens/ai_assistant_screen.dart — Module 19: AI Health Assistant
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/api_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});
  @override State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _ChatMessage {
  final String role, text;
  final DateTime time;
  _ChatMessage(this.role, this.text) : time = DateTime.now();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _api = ApiService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  static const _suggestions = [
    'What foods help lower blood pressure?',
    'How much water should I drink daily?',
    'Tips for better sleep quality',
    'Safe exercises for diabetics',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage('assistant',
        'Hi! I\'m your HealthTrack wellness assistant. I can answer general health and wellness questions. For medical concerns, please consult your doctor. How can I help today?'));
  }

  @override
  void dispose() { _inputCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() { _messages.add(_ChatMessage('user', text)); _sending = true; });
    _inputCtrl.clear();
    _scrollToBottom();

    final history = _messages.map((m) => {'role': m.role, 'content': m.text}).toList();
    final resp = await _api.sendAiMessage(text, history: history.cast<Map<String, String>>());

    setState(() {
      _sending = false;
      if (resp.success) {
        _messages.add(_ChatMessage('assistant', resp.data['reply'] ?? 'Sorry, I couldn\'t process that.'));
      } else {
        _messages.add(_ChatMessage('assistant', 'I\'m having trouble connecting right now. Please try again shortly.'));
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tp = isDark ? AppColors.textOnDark : AppColors.textPrimary;
    final tm = isDark ? AppColors.textMutedDark : AppColors.textMuted;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.mint, AppColors.sage]), borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('🤖', style: TextStyle(fontSize: 16)))),
        const SizedBox(width: 10),
        const Text('Wellness Assistant', style: TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.bold, fontSize: 17)),
      ])),
      body: Column(children: [
        Expanded(child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(16),
          itemCount: _messages.length + (_sending ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _messages.length) {
              return _TypingIndicator(isDark: isDark);
            }
            final m = _messages[i];
            final isUser = m.role == 'user';
            return Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.sage : (isDark ? AppColors.cardDark : Colors.white),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser ? null : Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200),
                ),
                child: Text(m.text, style: TextStyle(fontSize: 14, height: 1.5, color: isUser ? AppColors.navy : tp)),
              ),
            );
          },
        )),

        // Suggestion chips (shown only at start)
        if (_messages.length <= 1)
          SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _suggestions.map((s) => Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
              onTap: () => _send(s),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.sage.withOpacity(0.1), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppColors.sage.withOpacity(0.25))),
                child: Text(s, style: const TextStyle(fontSize: 12, color: AppColors.sage, fontWeight: FontWeight.w600))),
            ))).toList())),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200))),
          child: SafeArea(top: false, child: Row(children: [
            Expanded(child: TextField(
              controller: _inputCtrl,
              decoration: InputDecoration(hintText: 'Ask a wellness question...', filled: true,
                  fillColor: isDark ? const Color(0xFF1A2E45) : Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              onSubmitted: _send,
            )),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => _send(_inputCtrl.text),
              child: Container(width: 44, height: 44, decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.mint, AppColors.sage]), shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: AppColors.navy, size: 20))),
          ])),
        ),
      ]),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final bool isDark;
  const _TypingIndicator({required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.centerLeft, child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: isDark ? AppColors.cardDark : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? const Color(0xFF1E3250) : Colors.grey.shade200)),
      child: const SizedBox(width: 30, height: 12, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.sage)))),
    ));
  }
}