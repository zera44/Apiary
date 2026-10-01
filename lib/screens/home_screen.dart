import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../services/auth.dart';
import '../ui/app_drawer.dart';
import '../ui/app_logo.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'apiary_list_screen.dart';
import 'splash_screen.dart';
import 'stock_screen.dart';
import 'tutorial_screen.dart';

/// Головний екран (після «Почати» на заставці): назва застосунку й кнопки
/// «Почати» (мої пасіки), «Сканувати QR-код» (відкрити вулик за наліпкою),
/// «Інвентаризація» (склад), «Пройти навчання». Внизу — хто увійшов і
/// «Вийти» (назад на екран входу).
class HomeScreen extends StatelessWidget {
  final Repository repo;
  final AuthService auth;
  const HomeScreen({super.key, required this.repo, required this.auth});

  /// Гість входить пізніше: дані на пристрої лишаються, головний екран
  /// оновлюється (пошта й «Вийти»).
  Future<void> _signIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.signIn();
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HomeScreen(repo: repo, auth: auth),
      ));
    } on SignInCancelled {
      // передумали
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Не вдалося увійти. Перевірте інтернет і спробуйте ще раз.')));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showConfirm(context,
        title: 'Вийти?',
        text: 'Дані пасік лишаються на цьому пристрої. Далі — знову увійти або продовжити без входу.',
        confirmText: 'Вийти');
    if (!ok || !context.mounted) return;
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SplashScreen(repo: repo, auth: auth)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget button(String text, Color bg, VoidCallback onPressed, {Color fg = Colors.white}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PillButton(
            text: text,
            bg: bg,
            fg: fg,
            width: 240,
            height: 52,
            radius: 18,
            fontSize: 16,
            onPressed: onPressed,
          ),
        );

    final user = auth.user;
    return Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Center(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const AppLogo(size: 128),
                  const SizedBox(height: 20),
                  Text('Vulyk',
                      style: TextStyle(
                          color: AppColors.text, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Моя пасіка', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                  const SizedBox(height: 40),
                  button('Почати', AppColors.accent, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ApiaryListScreen(repo: repo),
                    ));
                  }),
                  button('Сканувати QR-код', AppColors.darkBtn,
                      () => AppDrawer.openHiveByQr(Navigator.of(context), repo),
                      fg: AppColors.text),
                  button('Інвентаризація', AppColors.darkBtn, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StockScreen(repo: repo, initialTab: StockOp.inventory),
                    ));
                  }, fg: AppColors.text),
                  button('Пройти навчання', AppColors.darkBtn, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TutorialScreen(),
                    ));
                  }, fg: AppColors.text),
                  if (user != null) ...[
                    const SizedBox(height: 18),
                    Text(user.email,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    TextButton(
                      onPressed: () => _signOut(context),
                      child: Text('Вийти', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ] else if (auth.configured) ...[
                    // гість: увійти пізніше, щоб синхронізувати (дані лишаються)
                    const SizedBox(height: 18),
                    Text('Дані лише на цьому пристрої',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    TextButton(
                      onPressed: () => _signIn(context),
                      child: Text('Увійти через Google для синхронізації',
                          style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              ),
            ),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
    );
  }
}
