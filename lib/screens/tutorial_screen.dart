import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';

/// Режим навчання: покроково показує, що вміє застосунок («натисни тут…»).
/// Поки що заготовка — вміст додамо за окремим завданням.
class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Навчання')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Material(
                color: AppColors.hive,
                shape: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: AppIcon('beekeeper', color: Colors.white, size: 56),
                ),
              ),
              const SizedBox(height: 18),
              Text('Режим навчання',
                  style: TextStyle(
                      color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('Незабаром тут з\'являться підказки, як користуватися застосунком.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 24),
              PillButton(
                text: 'Назад',
                bg: AppColors.darkBtn,
                fg: AppColors.text,
                width: 160,
                height: 44,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
