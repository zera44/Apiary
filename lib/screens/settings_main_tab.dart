import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../ui/sync_status.dart';
import '../ui/theme.dart';

/// Налаштування → «Головне». Тут - усе про дані користувача: синхронізація
/// (а далі - резервні копії, мобільний інтернет, акаунт, політика
/// конфіденційності).
///
/// [lesson] - вкладку показує урок (пісочниця): лише перегляд, без кнопок,
/// що чіпають справжні дані.
class MainSettingsTab extends StatelessWidget {
  final bool lesson;
  const MainSettingsTab({super.key, this.lesson = false});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SettingsSection(
            title: tr.syncSection,
            children: const [SyncStatusLine(textAlign: TextAlign.start, fontSize: 13.5)],
          ),
        ],
      );
}

/// Розділ налаштувань: заголовок і вміст у рамці.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hive.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );
}
