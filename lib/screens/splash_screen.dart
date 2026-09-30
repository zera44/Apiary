import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'apiary_list_screen.dart';
import 'tutorial_screen.dart';

/// Заставка при запуску: назва застосунку й кнопка "Почати".
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
                Material(
                  color: AppColors.hive,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: const Padding(
                    padding: EdgeInsets.all(22),
                    child: AppIcon('beekeeper', color: Colors.white, size: 72),
                  ),
                ),
                const SizedBox(height: 28),
                Text('In Riy',
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
                      builder: (_) => ApiaryListScreen(repo: repo),
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
