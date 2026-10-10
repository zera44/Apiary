import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/feedback.dart';
import '../ui/common.dart';
import '../ui/theme.dart';

/// Зворотний зв'язок (пункт бічного меню): поле для тексту, який
/// надсилається листом розробникам (див. [FeedbackService]).
class FeedbackScreen extends StatefulWidget {
  /// Відправник — підміняється в тестах.
  final Future<FeedbackResult> Function(String message) send;
  const FeedbackScreen({super.key, this.send = FeedbackService.send});

  static const intro = 'Бажаєте поділитись чимось цінним, запропонувати ідею чи '
      'поскаржитися на проблеми з додатком? Напишіть, для нас це цінно.';

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
      setState(() => _error = 'Напишіть хоча б кілька слів');
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
        const SnackBar(content: Text('Дякуємо! Ваше повідомлення надіслано.')),
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
        ? 'Надсилання відгуків ще не налаштовано в цій версії застосунку.'
        : 'Не вдалося надіслати. Перевірте інтернет і спробуйте ще раз.';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Не надіслано'),
        content: Text(
          '$reason\n\n${notConfigured ? 'Скопіюйте' : 'Або скопіюйте'} текст і надішліть його на ${FeedbackService.email}',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.text),
        ),
        actions: [
          Row(children: [
            Expanded(
              child: PillButton(
                text: 'Скопіювати',
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(
                      text: 'Кому: ${FeedbackService.email}\n\n$text'));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Текст і адресу скопійовано')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                  text: 'Гаразд', bg: AppColors.accent, onPressed: () => Navigator.pop(ctx)),
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
          Column(children: [
            TopBar(title: "Зворотний зв'язок", onBack: () => Navigator.pop(context)),
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
                  decoration: const InputDecoration(hintText: 'Ваше повідомлення…'),
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
                text: _sending ? 'Надсилаємо…' : 'Надіслати',
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
