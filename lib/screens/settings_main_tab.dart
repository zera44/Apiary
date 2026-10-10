import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../services/backups.dart';
import '../ui/common.dart';
import '../ui/sync_status.dart';
import '../ui/theme.dart';
import 'backups_screen.dart';

/// Налаштування → «Головне». Тут - усе про дані користувача: синхронізація,
/// резервні копії (а далі - мобільний інтернет, акаунт, політика
/// конфіденційності).
///
/// [lesson] - вкладку показує урок (пісочниця): лише перегляд, без кнопок,
/// що чіпають справжні дані.
class MainSettingsTab extends StatefulWidget {
  final Repository repo;
  final bool lesson;
  const MainSettingsTab({super.key, required this.repo, this.lesson = false});

  @override
  State<MainSettingsTab> createState() => _MainSettingsTabState();
}

class _MainSettingsTabState extends State<MainSettingsTab> {
  String? _backups;

  @override
  void initState() {
    super.initState();
    if (!widget.lesson) _loadBackups();
  }

  Future<void> _loadBackups() async {
    try {
      final latest = await (await BackupService.of(widget.repo)).latest();
      if (mounted) setState(() => _backups = backupsSummary(latest));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SettingsSection(
            title: tr.syncSection,
            children: const [SyncStatusLine(textAlign: TextAlign.start, fontSize: 13.5)],
          ),
          if (!widget.lesson)
            SettingsSection(
              title: tr.backupsSection,
              children: [
                Text(_backups ?? '',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
                const SizedBox(height: 10),
                PillButton(
                  text: tr.backupsSection,
                  bg: AppColors.darkBtn,
                  fg: AppColors.text,
                  height: 40,
                  width: double.infinity,
                  onPressed: () async {
                    await BackupsScreen.open(context, widget.repo);
                    await _loadBackups();
                  },
                ),
              ],
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
