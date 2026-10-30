import 'dart:async';

import 'package:flutter/material.dart';

import '../services/feedback_chat.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'feedback_screen.dart';
import '../l10n/l10n.dart';

/// Куди ведуть кнопки «Відгук»: розмова з розробником (є сервер у збірці) або
/// старий екран з листом через форму.
Future<void> openFeedback(NavigatorState nav) {
  final chat = FeedbackChat.current;
  return nav.push(MaterialPageRoute(
      builder: (_) => chat != null && chat.available
          ? FeedbackChatScreen(chat: chat)
          : const FeedbackScreen()));
}

/// «Відгук» як розмова: те, що людина написала, і відповіді розробника
/// (вони приходять самі: поки екран відкрито - раз на 20 с, інакше - значок
/// на вулику-поштоматі й сповіщення).
class FeedbackChatScreen extends StatefulWidget {
  final FeedbackChat chat;
  const FeedbackChatScreen({super.key, required this.chat});

  @override
  State<FeedbackChatScreen> createState() => _FeedbackChatScreenState();
}

class _FeedbackChatScreenState extends State<FeedbackChatScreen> {
  FeedbackChat get chat => widget.chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<FeedbackMsg> _msgs = const [];
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    chat.changes.addListener(_load);
    unawaited(_open());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(chat.poll()));
  }

  Future<void> _open() async {
    await _load();
    await chat.poll();
    await chat.markRead();
  }

  @override
  void dispose() {
    _timer?.cancel();
    chat.changes.removeListener(_load);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final m = await chat.messages();
    if (!mounted) return;
    final grew = m.length > _msgs.length;
    setState(() => _msgs = m);
    if (grew) {
      unawaited(chat.markRead());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    await chat.send(text);
    if (mounted) setState(() => _sending = false);
  }

  String _when(DateTime d) {
    final n = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == n.year && d.month == n.month && d.day == n.day) return hm;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar(title: tr.feedbackTitle, onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                  child: Text(
                    _msgs.isEmpty ? FeedbackScreen.intro : hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.35),
                  ),
                ),
                for (final m in _msgs) _bubble(m),
              ],
            ),
          ),
          Container(
            color: AppColors.panel,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('feedback-input'),
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: maxLength,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: AppColors.text, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: tr.yourMessage,
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.input,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const ValueKey('feedback-send'),
                tooltip: tr.send,
                style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static String get hint => tr.feedbackChatHint;
  static const maxLength = 5000;

  Widget _bubble(FeedbackMsg m) {
    final dev = m.fromDev;
    return Align(
      alignment: dev ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
        decoration: BoxDecoration(
          color: dev ? AppColors.card : AppColors.input,
          border: dev ? Border.all(color: AppColors.hive, width: 1.5) : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(dev ? 3 : 16),
            bottomRight: Radius.circular(dev ? 16 : 3),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (dev)
            Text(tr.developer,
                style: TextStyle(
                    color: AppColors.create, fontSize: 12.5, fontWeight: FontWeight.w800)),
          SelectableText(m.body,
              style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.3)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_when(m.at), style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            if (m.pending) ...[
              const SizedBox(width: 6),
              Icon(Icons.schedule, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text(tr.waitingInternet,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ]),
        ]),
      ),
    );
  }
}
