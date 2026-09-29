import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../screens/map_screen.dart';
import '../screens/parameters_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/templates_screen.dart';
import 'common.dart';
import 'icons.dart';
import 'theme.dart';

/// Бічне меню (відкривається трьома смужками): Головна / Шаблони /
/// Характеристики.
class AppDrawer extends StatelessWidget {
  final Repository repo;
  const AppDrawer({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Моя пасіка',
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          _item(context, 'beehive', 'Головна', () {
            nav.pop(); // закрити меню
            nav.popUntil((r) => r.isFirst);
          }),
          _item(context, 'hexagon', 'Шаблони', () {
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => TemplatesScreen(repo: repo)));
          }),
          _item(context, 'history', 'Характеристики', () {
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => ParametersScreen.catalog(repo: repo)));
          }),
          _item(context, 'qr', 'Сканувати QR вулика', () {
            nav.pop();
            openHiveByQr(nav, repo);
          }),
        ]),
      ),
    );
  }

  /// Відсканувати код і відкрити карту пасіки з панеллю цього вулика.
  /// Працює через [NavigatorState] — контекст меню після закриття вже
  /// недійсний.
  static Future<void> openHiveByQr(NavigatorState nav, Repository repo) async {
    final code = await scanQrCode(nav.context);
    if (code == null || !nav.mounted) return;
    final found = await repo.findByQr(code);
    if (!nav.mounted) return;
    if (found == null) {
      await showInfo(
        nav.context,
        'Цей QR-код ще не прив\'язаний до жодного вулика.\n\n'
        'Щоб прив\'язати: відкрийте пасіку, торкніться вулика й на панелі '
        '«Характеристики» натисніть «Прив\'язати QR-код».\n\nКод: $code',
        title: 'Вулик не знайдено',
      );
      return;
    }
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(
      builder: (_) =>
          MapScreen(repo: repo, apiary: found.apiary, focusElementId: found.element.id),
    ));
  }

  Widget _item(BuildContext context, String icon, String text, VoidCallback onTap) {
    return ListTile(
      leading: AppIcon(icon, color: AppColors.text, size: 30),
      title: Text(text, style: TextStyle(color: AppColors.text, fontSize: 16)),
      onTap: onTap,
    );
  }
}
