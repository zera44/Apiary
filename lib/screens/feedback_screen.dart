import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/feedback.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../l10n/l10n.dart';

/// Зворотний зв'язок (пункт бічного меню): поле для тексту, який
/// надсилається листом розробникам (див. [FeedbackService]).
class FeedbackScreen extends StatefulWidget {
  /// Відправник — підміняється в тестах.
  final Future<FeedbackResult> Function(String message) send;
  const FeedbackScreen({super.key, this.send = FeedbackService.send});

  static String get intro => tr.feedbackIntro;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = tr.feedbackTooShort);
      return;
    }
    if (_sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _sending = true;
    });
    final result = await widget.send(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (result == FeedbackResult.sent) {
      _ctrl.clear();
      // без окремого вікна з «Гаразд»: коротке повідомлення внизу й назад
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.feedbackThanks)),
      );
      Navigator.of(context).pop();
      return;
    }
    await _showFailure(text, notConfigured: result == FeedbackResult.notConfigured);
  }

  /// Не вдалося надіслати: текст лишається в полі, а його можна скопіювати й
  /// надіслати з пошти вручну.
  Future<void> _showFailure(String text, {required bool notConfigured}) {
    final reason = notConfigured
        ? tr.feedbackNotConfigured
        : tr.feedbackSendFailed;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.notSent),
        content: Text(
          tr.feedbackCopyHint(reason, notConfigured, FeedbackService.email),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.text),
        ),
        actions: [
          Row(children: [
            Expanded(
              child: PillButton(
                text: tr.copyAction,
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                      text: tr.feedbackTo(FeedbackService.email, text)));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr.feedbackCopied)),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                  text: tr.ok, bg: AppColors.accent, onPressed: () => Navigator.pop(ctx)),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: tr.feedbackTitle, onBack: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                FeedbackScreen.intro,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.35),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  maxLength: FeedbackService.maxLength,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(hintText: tr.yourMessage),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PillButton(
                text: _sending ? tr.sending : tr.send,
                bg: AppColors.accent,
                height: 50,
                radius: 16,
                width: double.infinity,
                onPressed: _sending ? null : _send,
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
