import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/app_drawer.dart';
import '../ui/app_logo.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'apiary_list_screen.dart';
import 'splash_screen.dart';
import 'stock_screen.dart';

/// Головний екран (після «Почати» на заставці): назва застосунку й кнопки
/// «Почати» (мої пасіки), «Сканувати QR-код» (відкрити вулик за наліпкою),
/// «Інвентаризація» (склад). «Назад» — на заставку.
class HomeScreen extends StatelessWidget {
  final Repository repo;
  const HomeScreen({super.key, required this.repo});

  void _toSplash(BuildContext context) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SplashScreen(repo: repo),
    ));
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toSplash(context);
      },
      child: Scaffold(
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
                ]),
              ),
            ),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      ),
    );
  }
}
