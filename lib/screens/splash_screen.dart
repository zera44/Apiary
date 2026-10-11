import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../services/auth.dart';
import '../services/server.dart';
import '../ui/app_logo.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'home_screen.dart';

/// Заставка = екран входу: іконка, назва, «Увійти через Google» і
/// «Продовжити без входу» (дані лише на цьому пристрої; увійти й
/// синхронізуватись можна пізніше з головного екрана). Хто вже обрав,
/// цей екран не бачить — застосунок одразу відкриває головний екран.
class SplashScreen extends StatefulWidget {
  final Repository repo;
  final AuthService auth;
  const SplashScreen({super.key, required this.repo, required this.auth});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn();
      HomeScreen.signedInMail = widget.auth.user?.email;
      unawaited(Server.connect(widget.repo, widget.auth)); // і на сервер - одразу
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HomeScreen(repo: widget.repo, auth: widget.auth),
      ));
    } on SignInCancelled {
      // передумали — лишаємось на екрані входу без помилки
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не вдалося увійти. Перевірте інтернет і спробуйте ще раз.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    if (_busy) return;
    _busy = true; // подвійний тап не відкриває два головні екрани
    try {
      await widget.auth.continueAsGuest();
    } catch (_) {
      _busy = false;
      rethrow;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HomeScreen(repo: widget.repo, auth: widget.auth),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(),
                  const SizedBox(height: 28),
                  Text('Vulyk',
                      style: TextStyle(
                          color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Моя пасіка', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                  const SizedBox(height: 48),
                  PillButton(
                    text: _busy ? 'Входимо…' : 'Увійти через Google',
                    bg: AppColors.accent,
                    width: 260,
                    height: 52,
                    radius: 18,
                    fontSize: 16,
                    onPressed: _busy ? null : _signIn,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: 12),
                  PillButton(
                    text: 'Продовжити без входу',
                    bg: AppColors.darkBtn,
                    fg: AppColors.text,
                    width: 260,
                    height: 48,
                    radius: 18,
                    fontSize: 15,
                    onPressed: _busy ? null : _guest,
                  ),
                  const SizedBox(height: 14),
                  Text('Без входу дані зберігаються лише на цьому пристрої. Увійти й '
                      'синхронізувати їх можна пізніше на головному екрані - нічого не загубиться.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
