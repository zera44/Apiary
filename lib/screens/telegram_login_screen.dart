import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../services/app_config.dart';
import '../services/auth.dart';
import '../services/server.dart';
import '../services/telegram_login.dart';
import '../ui/common.dart';
import '../ui/theme.dart';

/// Чим закінчився вхід через Telegram: [signedIn] - увійшли (з новою сесією);
/// [linked] - Telegram прив'язано до акаунта, у якому вже були.
class TelegramLoginResult {
  final TelegramSignedIn? signedIn;
  final bool linked;
  const TelegramLoginResult({this.signedIn, this.linked = false});
}

/// Вхід через Telegram цілком: екран входу, запам'ятати акаунт, підключити
/// сервер. true - увійшли; false - людина передумала. [StateError] - у цій
/// збірці сервер не налаштований.
Future<bool> signInWithTelegram(BuildContext context, Repository repo, AuthService auth,
    {TelegramAuthApi? api}) async {
  final a = api ?? TelegramAuthApi.of(AppConfig.current);
  if (a == null) throw StateError(tr.tgNotConfigured);
  final res = await Navigator.of(context)
      .push<TelegramLoginResult>(MaterialPageRoute(builder: (_) => TelegramLoginScreen(api: a)));
  final done = res?.signedIn;
  if (done == null) return false;
  await auth.signInExternal(AppUser(
    id: done.session.userId,
    email: done.session.email,
    name: done.name.isEmpty ? 'Telegram' : done.name,
  ));
  await Server.connectWithSession(repo, auth, done.session);
  return true;
}

enum _Phase { starting, waiting, pinSetup, pinEnter, recoveryEnter, recoveryShow, failed }

/// Вхід (або прив'язка) через Telegram-бота: число для бота, очікування
/// підтвердження, PIN, код відновлення. Закривається з [TelegramLoginResult]
/// (null - людина передумала).
class TelegramLoginScreen extends StatefulWidget {
  final TelegramAuthApi api;
  final String device;

  /// Задано - прив'язати Telegram до цього акаунта (без входу й PIN).
  final String? accessToken;

  /// Відкрити посилання (у тестах підміняється).
  final Future<bool> Function(Uri url) openUrl;
  final Duration pollEvery;

  TelegramLoginScreen({
    super.key,
    required this.api,
    this.device = 'Android',
    this.accessToken,
    Future<bool> Function(Uri url)? openUrl,
    this.pollEvery = const Duration(seconds: 2),
  }) : openUrl = openUrl ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication));

  @override
  State<TelegramLoginScreen> createState() => _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends State<TelegramLoginScreen> {
  static const lifetime = Duration(minutes: 5);

  _Phase _phase = _Phase.starting;
  TelegramRequest? _req;
  late String _secret;
  DateTime _expires = DateTime.now();
  Timer? _poll, _tick;
  bool _polling = false, _busy = false, _copied = false;
  String? _error;
  int _lockedFor = 0;
  TelegramSignedIn? _result;

  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _recovery = TextEditingController();

  bool get _linking => widget.accessToken != null;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _pin.dispose();
    _pin2.dispose();
    _recovery.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _poll?.cancel();
    _tick?.cancel();
    _poll = _tick = null;
  }

  void _fail(String message) {
    _stopTimers();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
      _busy = false;
    });
  }

  String _messageFor(TelegramApiError e) => switch (e.code) {
        'offline' => tr.tgOffline,
        'too_many' => tr.tgTooMany,
        _ => tr.tgFailed,
      };

  Future<void> _begin() async {
    _stopTimers();
    setState(() {
      _phase = _Phase.starting;
      _error = null;
      _req = null;
      _pin.clear();
      _pin2.clear();
      _recovery.clear();
    });
    _secret = newLoginSecret();
    try {
      final r = await widget.api.start(secret: _secret, device: widget.device, accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _req = r;
        _expires = DateTime.now().add(lifetime);
        _phase = _Phase.waiting;
      });
      _poll = Timer.periodic(widget.pollEvery, (_) => _pollOnce());
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _phase != _Phase.waiting) return;
        if (DateTime.now().isAfter(_expires)) {
          _fail(tr.tgExpired);
        } else {
          setState(() {});
        }
      });
    } on TelegramApiError catch (e) {
      _fail(_messageFor(e));
    }
  }

  Future<void> _open() async {
    final r = _req;
    if (r == null) return;
    var ok = false;
    try {
      ok = await widget.openUrl(r.url);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.tgOpenFailed)));
    }
  }

  Future<void> _pollOnce() async {
    final r = _req;
    if (r == null || _polling || _phase != _Phase.waiting) return;
    _polling = true;
    try {
      final p = await widget.api.poll(r.id, _secret);
      if (!mounted || _phase != _Phase.waiting) return;
      if (p.state == 'cancelled') return _fail(tr.tgCancelled);
      if (p.dead) return _fail(tr.tgExpired);
      if (_linking && p.state == 'done') {
        _stopTimers();
        Navigator.of(context).pop(const TelegramLoginResult(linked: true));
        return;
      }
      if (!p.approved || _linking) return;
      _stopTimers();
      switch (p.next) {
        case TelegramNext.pinSetup:
          setState(() => _phase = _Phase.pinSetup);
        case TelegramNext.pin:
          setState(() => _phase = _Phase.pinEnter);
        case TelegramNext.locked:
          setState(() {
            _lockedFor = p.retryIn;
            _phase = _Phase.pinEnter;
          });
        case TelegramNext.ready:
        case null:
          await _finish();
      }
    } on TelegramApiError catch (e) {
      // немає зв'язку - спробуємо при наступному опитуванні; інше - зупинка
      if (!e.offline) _fail(_messageFor(e));
    } finally {
      _polling = false;
    }
  }

  Future<void> _finish({String? pin, String? recovery, String? newPin}) async {
    final r = _req;
    if (r == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await widget.api.finish(r.id, _secret, pin: pin, recovery: recovery, newPin: newPin);
      if (!mounted) return;
      if (done.recoveryCode != null) {
        setState(() {
          _result = done;
          _phase = _Phase.recoveryShow;
          _busy = false;
        });
      } else {
        Navigator.of(context).pop(TelegramLoginResult(signedIn: done));
      }
    } on TelegramApiError catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'wrong_pin':
          setState(() {
            _error = tr.pinWrong;
            _busy = false;
          });
        case 'locked':
          setState(() {
            _lockedFor = e.retryIn ?? 900;
            _error = null;
            _busy = false;
            _phase = _Phase.pinEnter;
          });
        case 'bad_pin' || 'new_pin_required':
          setState(() {
            _error = e.message ?? tr.tgFailed;
            _busy = false;
          });
        case 'used' || 'not_approved' || 'pin_state_changed':
          _fail(tr.tgExpired);
        default:
          setState(() {
            _error = _messageFor(e);
            _busy = false;
          });
      }
    }
  }

  void _submitSetup() {
    if (_pin.text != _pin2.text) {
      setState(() => _error = tr.pinMismatch);
      return;
    }
    _finish(pin: _pin.text);
  }

  void _submitRecovery() {
    _finish(recovery: _recovery.text, newPin: _pin.text);
  }

  String _mmss(Duration d) {
    final s = d.isNegative ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _field(TextEditingController c, String hint, {bool secret = true, bool autofocus = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          autofocus: autofocus,
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: secret ? TextInputType.visiblePassword : TextInputType.text,
          textCapitalization: secret ? TextCapitalization.none : TextCapitalization.characters,
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(hintText: hint),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      );

  Widget _text(String t, {double size = 14, Color? color, TextAlign align = TextAlign.center, FontWeight? weight}) =>
      Text(t, textAlign: align, style: TextStyle(color: color ?? AppColors.text, fontSize: size, height: 1.35, fontWeight: weight));

  Widget _errorLine() => _error == null
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(bottom: 12), child: _text(_error!, size: 13, color: AppColors.danger));

  Widget _button(String text, VoidCallback? onTap, {bool primary = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PillButton(
          text: text,
          bg: primary ? AppColors.accent : AppColors.darkBtn,
          fg: primary ? Colors.white : AppColors.text,
          width: double.infinity,
          height: 48,
          radius: 16,
          fontSize: 15,
          onPressed: _busy ? null : onTap,
        ),
      );

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.starting:
        return [const SizedBox(height: 40), const Center(child: CircularProgressIndicator()), const SizedBox(height: 16), _text(tr.tgStarting)];
      case _Phase.waiting:
        final left = _expires.difference(DateTime.now());
        return [
          _text(tr.tgNumberLabel, size: 13, color: AppColors.textMuted),
          const SizedBox(height: 6),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(color: AppColors.darkBtn, borderRadius: BorderRadius.circular(18)),
            child: Text('${_req!.match}',
                key: const Key('tg-match'),
                style: TextStyle(color: AppColors.text, fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: 4)),
          ),
          const SizedBox(height: 18),
          _text('1. ${tr.tgStep1}', align: TextAlign.start),
          const SizedBox(height: 6),
          _text('2. ${tr.tgStep2}', align: TextAlign.start),
          const SizedBox(height: 6),
          _text('3. ${tr.tgStep3}', align: TextAlign.start),
          const SizedBox(height: 20),
          _button(tr.tgOpenTelegram, _open),
          const SizedBox(height: 4),
          _text(tr.tgWaiting, size: 13, color: AppColors.textMuted),
          const SizedBox(height: 4),
          _text(tr.tgExpiresIn(_mmss(left)), size: 12.5, color: AppColors.textMuted),
        ];
      case _Phase.pinSetup:
        return [
          _text(tr.pinSetupTitle, size: 20, weight: FontWeight.w700),
          const SizedBox(height: 8),
          _text(tr.pinSetupText, color: AppColors.textMuted),
          const SizedBox(height: 18),
          _field(_pin, tr.pinField, autofocus: true),
          _field(_pin2, tr.pinRepeat),
          _errorLine(),
          _button(tr.pinSave, _submitSetup),
        ];
      case _Phase.pinEnter:
        return [
          _text(tr.pinEnterTitle, size: 20, weight: FontWeight.w700),
          const SizedBox(height: 8),
          _text(tr.pinEnterText, color: AppColors.textMuted),
          const SizedBox(height: 18),
          if (_lockedFor > 0)
            _text(tr.pinLocked(_mmss(Duration(seconds: _lockedFor))), color: AppColors.danger)
          else ...[
            _field(_pin, tr.pinField, autofocus: true),
            _errorLine(),
            _button(tr.pinContinue, () => _finish(pin: _pin.text)),
          ],
          _button(tr.pinForgot, () {
            _pin.clear();
            setState(() {
              _error = null;
              _phase = _Phase.recoveryEnter;
            });
          }, primary: false),
        ];
      case _Phase.recoveryEnter:
        return [
          _text(tr.pinRecoveryTitle, size: 20, weight: FontWeight.w700),
          const SizedBox(height: 8),
          _text(tr.pinRecoveryText, color: AppColors.textMuted),
          const SizedBox(height: 18),
          _field(_recovery, tr.pinRecoveryField, secret: false, autofocus: true),
          _field(_pin, tr.pinNewField),
          _errorLine(),
          _button(tr.pinContinue, _submitRecovery),
        ];
      case _Phase.recoveryShow:
        final code = _result?.recoveryCode ?? '';
        return [
          _text(tr.recoveryTitle, size: 20, weight: FontWeight.w700),
          const SizedBox(height: 8),
          _text(tr.recoveryText, color: AppColors.textMuted),
          const SizedBox(height: 18),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.darkBtn, borderRadius: BorderRadius.circular(16)),
            child: SelectableText(code,
                key: const Key('tg-recovery'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.5, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 12),
          _button(_copied ? tr.recoveryCopied : tr.copyAction, () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (mounted) setState(() => _copied = true);
          }, primary: false),
          _button(tr.recoveryWritten, () => Navigator.of(context).pop(TelegramLoginResult(signedIn: _result))),
        ];
      case _Phase.failed:
        return [
          const SizedBox(height: 30),
          _text(_error ?? tr.tgFailed, color: AppColors.danger),
          const SizedBox(height: 20),
          _button(tr.tgTryAgain, _begin),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _phase == _Phase.recoveryShow;
    return PopScope(
      // код відновлення показується один раз: не дати втекти, не записавши
      canPop: !locked,
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(title: tr.tgTitle, onBack: locked ? null : () => Navigator.of(context).pop()),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _body()),
                ),
              ),
            ]),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      ),
    );
  }
}
