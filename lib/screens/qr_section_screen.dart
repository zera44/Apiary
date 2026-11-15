import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/app_drawer.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'map_screen.dart';
import 'qr_generate_screen.dart';

/// Розділ «QR-код» зі своїм меню (як Фінанси): сканувати, генерувати, прив'язати
/// підряд й вихід до пасіки.
class QrSectionScreen extends StatefulWidget {
  final Repository repo;
  const QrSectionScreen({super.key, required this.repo});

  @override
  State<QrSectionScreen> createState() => _QrSectionScreenState();
}

class _QrSectionScreenState extends State<QrSectionScreen> {
  final _key = GlobalKey<ScaffoldState>();

  Repository get repo => widget.repo;

  Future<Apiary?> _apiary() async {
    final a = await repo.startApiary() ?? (await repo.listApiaries()).firstOrNull;
    if (a == null && mounted) await showInfo(context, tr.qrCreateApiaryFirst);
    return a;
  }

  void _scan() => AppDrawer.openHiveByQr(Navigator.of(context), repo);

  Future<void> _generate() async {
    final nav = Navigator.of(context);
    final a = await _apiary();
    if (a == null || !nav.mounted) return;
    await nav.push(MaterialPageRoute<void>(builder: (_) => QrGenerateScreen(repo: repo, apiary: a)));
  }

  Future<void> _bindRow() async {
    final nav = Navigator.of(context);
    final a = await _apiary();
    if (a == null || !nav.mounted) return;
    await nav.push(
        MaterialPageRoute<void>(builder: (_) => MapScreen(repo: repo, apiary: a, bindRowOnOpen: true)));
  }

  /// Пункт меню: закрити меню й виконати дію.
  void _menu(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: AppColors.text, size: 28),
        title: Text(label, style: TextStyle(color: AppColors.text, fontSize: 17)),
        onTap: onTap,
      );

  Widget _card(IconData icon, String title, String hint, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(icon, color: AppColors.create, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: TextStyle(
                            color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(hint, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _key,
      drawer: Drawer(
        backgroundColor: AppColors.card,
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              child: Row(children: [
                AppIcon('qr', color: AppColors.text, size: 32),
                const SizedBox(width: 16),
                Text(tr.qrCode,
                    style: TextStyle(
                        color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
              ]),
            ),
            Divider(height: 1, color: AppColors.textMuted.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            _drawerItem(TablerIcons.scan, tr.scan, () => _menu(_scan)),
            _drawerItem(TablerIcons.qrcode, tr.generate, () => _menu(_generate)),
            _drawerItem(TablerIcons.list_numbers, tr.qrBindRow, () => _menu(_bindRow)),
            const Spacer(),
            Divider(height: 1, color: AppColors.textMuted.withValues(alpha: 0.3)),
            _drawerItem(TablerIcons.arrow_back_up, tr.finBackToApiary, () {
              Navigator.of(context).pop(); // меню
              Navigator.of(context).pop(); // розділ
            }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: tr.qrCode, onTitleTap: () => _key.currentState?.openDrawer()),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 16), children: [
                _card(TablerIcons.scan, tr.scan, tr.qrScanHint, _scan),
                _card(TablerIcons.qrcode, tr.generate, tr.qrGenerateHint, _generate),
                _card(TablerIcons.list_numbers, tr.qrBindRow, tr.qrBindRowHint, _bindRow),
              ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
