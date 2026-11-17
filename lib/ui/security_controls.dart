import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../screens/telegram_login_screen.dart';
import '../services/app_config.dart';
import '../services/server.dart';
import '../services/telegram_login.dart';
import 'common.dart';
import 'theme.dart';

/// «Захист входу» у налаштуваннях акаунта: Telegram, PIN, вихід на всіх
/// пристроях. Показується лише тому, хто ввійшов на сервер.
class SecurityControls extends StatefulWidget {
  /// Після «Вийти на всіх пристроях»: вийти й тут (екран входу).
  final Future<void> Function() afterSignOutEverywhere;

  /// У тестах - підміна.
  final TelegramAuthApi? api;
  final Future<String> Function()? accessToken;
  const SecurityControls({super.key, required this.afterSignOutEverywhere, this.api, this.accessToken});

  @override
  State<SecurityControls> createState() => _SecurityControlsState();
}

class _SecurityControlsState extends State<SecurityControls> {
  PinStatus? _status;
  bool _failed = false, _busy = false;

  TelegramAuthApi? get _api => widget.api ?? TelegramAuthApi.of(AppConfig.current);
  Future<String> _token() => (widget.accessToken ?? () => Server.api!.accessToken())();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final s = await api.pinStatus(await _token());
      if (mounted) {
        setState(() {
          _status = s;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SnackText(t)));

  String _error(Object e) {
    if (e is TelegramApiError) {
      return switch (e.code) {
        'wrong_pin' => tr.pinWrong,
        'locked' => tr.pinLocked(_mmss(e.retryIn ?? 900)),
        'bad_pin' => e.message ?? tr.tgFailed,
        'offline' => tr.tgOffline,
        _ => tr.tgFailed,
      };
    }
    return tr.tgFailed;
  }

  String _mmss(int secs) => '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';

  /// Вікно з полями PIN. Повертає введене або null.
  Future<List<String>?> _ask(String title, String? hint, List<String> labels) {
    final ctrls = [for (final _ in labels) TextEditingController()];
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(hint, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
              ),
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: ctrls[i],
                  autofocus: i == 0,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(hintText: labels[i]),
                ),
              ),
          ]),
        ),
        actions: [
          PillButton(
              text: tr.cancel, bg: AppColors.neutralBtn, fg: AppColors.text, onPressed: () => Navigator.pop(ctx)),
          PillButton(
              text: tr.secSave,
              bg: AppColors.accent,
              onPressed: () => Navigator.pop(ctx, [for (final c in ctrls) c.text])),
        ],
      ),
    );
  }

  Future<void> _showRecovery(String code) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(tr.recoveryTitle),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.recoveryText, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            const SizedBox(height: 14),
            Center(
              child: SelectableText(code,
                  key: const Key('sec-recovery'),
                  style: TextStyle(
                      color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: 'monospace')),
            ),
          ]),
          actions: [
            PillButton(
                text: tr.copyAction,
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                onPressed: () => Clipboard.setData(ClipboardData(text: code))),
            PillButton(text: tr.recoveryWritten, bg: AppColors.accent, onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      );

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) _say(_error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _enable() async {
    final v = await _ask(tr.pinSetupTitle, tr.pinSetupText, [tr.pinField, tr.pinRepeat]);
    if (v == null || !mounted) return;
    if (v[0] != v[1]) return _say(tr.pinMismatch);
    await _run(() async {
      final code = await _api!.pinSet(await _token(), newPin: v[0]);
      if (!mounted) return;
      await _showRecovery(code);
      if (mounted) _say(tr.secPinEnabled);
    });
  }

  Future<void> _change() async {
    final v = await _ask(tr.secPinChange, null, [tr.secPinCurrent, tr.pinNewField, tr.pinRepeat]);
    if (v == null || !mounted) return;
    if (v[1] != v[2]) return _say(tr.pinMismatch);
    await _run(() async {
      final code = await _api!.pinSet(await _token(), current: v[0], newPin: v[1]);
      if (!mounted) return;
      await _showRecovery(code);
      if (mounted) _say(tr.secPinChanged);
    });
  }

  Future<void> _disable() async {
    final v = await _ask(tr.secPinDisable, tr.secPinDisableWarn, [tr.secPinCurrent]);
    if (v == null || !mounted) return;
    await _run(() async {
      final at = await _api!.pinDisable(await _token(), v[0]);
      if (!mounted) return;
      _say(at == null ? tr.secPinDisabledNow : tr.secPinScheduled(_when(at)));
    });
  }

  String _when(DateTime at) {
    final d = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _link() async {
    final api = _api;
    if (api == null) return;
    final token = await _token();
    if (!mounted) return;
    final res = await Navigator.of(context)
        .push<TelegramLoginResult>(MaterialPageRoute(builder: (_) => TelegramLoginScreen(api: api, accessToken: token)));
    if (res?.linked == true && mounted) _say(tr.secLinkedOk);
    await _load();
  }

  Future<void> _signOutAll() async {
    final ok = await showConfirm(context,
        title: tr.secSignOutAll, text: tr.secSignOutAllText, confirmText: tr.secSignOutAll, cancelText: tr.cancel);
    if (!ok || !mounted) return;
    await _run(() async {
      await _api!.signOutEverywhere(await _token());
      await widget.afterSignOutEverywhere();
    });
  }

  Widget _text(String t) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)));

  Widget _btn(String text, VoidCallback onTap, {bool primary = false, Key? key}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: PillButton(
          key: key,
          text: text,
          bg: primary ? AppColors.accent : AppColors.darkBtn,
          fg: primary ? Colors.white : AppColors.text,
          height: 40,
          width: double.infinity,
          onPressed: _busy ? null : onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (_api == null) return const SizedBox.shrink();
    if (s == null) {
      return _failed
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _text(tr.secLoadFailed),
              _btn(tr.tgTryAgain, _load),
            ])
          : const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      if (s.phone != null)
        _text(tr.secTelegramLinked(s.phone!))
      else ...[
        _text(tr.secTelegramNone),
        _btn(tr.secLinkTelegram, _link, key: const Key('sec-link')),
      ],
      if (s.state == 'on' || s.state == 'locked') ...[
        _text(s.disableAt != null ? tr.secPinScheduled(_when(s.disableAt!)) : tr.secPinOn),
        if (s.state == 'locked') _text(tr.secPinLocked),
        _btn(tr.secPinChange, _change, key: const Key('sec-change')),
        _btn(tr.secPinDisable, _disable, key: const Key('sec-disable')),
      ] else ...[
        _text(tr.secPinOff),
        _btn(tr.secPinEnable, _enable, primary: true, key: const Key('sec-enable')),
      ],
      _btn(tr.secSignOutAll, _signOutAll, key: const Key('sec-signout')),
    ]);
  }
}
