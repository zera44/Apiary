import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../ui/app_logo.dart';
import 'home_screen.dart';
import 'tutorial_screen.dart';

/// Заставка при запуску: назва застосунку, «Почати» (головний екран) і
/// «Пройти навчання».
class SplashScreen extends StatelessWidget {
  final Repository repo;
  const SplashScreen({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(),
                const SizedBox(height: 28),
                Text('Vulyk',
                    style: TextStyle(
                        color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Моя пасіка',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                const SizedBox(height: 48),
                PillButton(
                  text: 'Почати',
                  bg: AppColors.accent,
                  width: 200,
                  height: 52,
                  radius: 18,
                  fontSize: 17,
                  onPressed: () {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => HomeScreen(repo: repo),
                    ));
                  },
                ),
                const SizedBox(height: 12),
                PillButton(
                  text: 'Пройти навчання',
                  bg: AppColors.darkBtn,
                  fg: AppColors.text,
                  width: 200,
                  height: 46,
                  radius: 18,
                  fontSize: 15,
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TutorialScreen(),
                    ));
                  },
                ),
              ],
            ),
          ),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
