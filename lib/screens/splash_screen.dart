import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/common.dart';
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
                // іконка застосунку: пасічник із рамкою меду на кремовому тлі
                // (як на телефоні; малюнок — design/guide/beekeeper_honey_frame.pdf)
                Container(
                  width: 168,
                  height: 168,
                  padding: const EdgeInsets.fromLTRB(26, 16, 26, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBE9C4),
                    borderRadius: BorderRadius.circular(38),
                  ),
                  child: Image.asset('assets/guide/beekeeper_honey_frame.png',
                      filterQuality: FilterQuality.medium),
                ),
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
