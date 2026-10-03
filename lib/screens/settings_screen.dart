import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'parameters_screen.dart';
import 'templates_screen.dart';

/// Шестерня «Налаштування» (карта й головний екран).
class GearButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;
  final Color? bg;
  const GearButton({super.key, required this.onPressed, this.size = 48, this.bg});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Налаштування',
        child: Material(
          color: bg ?? AppColors.roundBtn,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
                dimension: size,
                child: Icon(Icons.settings, size: size * 0.55, color: AppColors.text)),
          ),
        ),
      );
}

/// «Налаштування»: вкладки «Головна» (поки порожня), «Характеристики» й
/// «Шаблони». Історії тут немає - вона лише по картах.
class SettingsScreen extends StatefulWidget {
  final Repository repo;
  const SettingsScreen({super.key, required this.repo});

  static Future<void> open(NavigatorState nav, Repository repo) =>
      nav.push(MaterialPageRoute(builder: (_) => SettingsScreen(repo: repo)));

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tab = 0;

  Widget _tabButton(String text, int i) => Expanded(
        child: PillButton(
          text: text,
          bg: _tab == i ? AppColors.accent : AppColors.darkBtn,
          fg: _tab == i ? Colors.white : AppColors.text,
          height: 40,
          fontSize: 13,
          onPressed: () => setState(() => _tab = i),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Налаштування', onBack: () => Navigator.maybePop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                _tabButton('Головна', 0),
                const SizedBox(width: 8),
                _tabButton('Характеристики', 1),
                const SizedBox(width: 8),
                _tabButton('Шаблони', 2),
              ]),
            ),
            Expanded(
              child: switch (_tab) {
                0 => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Загальні налаштування з\'являться тут згодом.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                1 => ParametersScreen.catalog(
                    key: const ValueKey('settings-params'), repo: widget.repo, embedded: true),
                _ => TemplatesScreen(
                    key: const ValueKey('settings-templates'), repo: widget.repo, embedded: true),
              },
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
