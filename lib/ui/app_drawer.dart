import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../screens/map_screen.dart';
import '../screens/parameters_screen.dart';
import '../screens/qr_generate_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/templates_screen.dart';
import 'common.dart';
import 'icons.dart';
import 'theme.dart';

/// Бічне меню (відкривається трьома смужками): Головна / Шаблони /
/// Характеристики.
class AppDrawer extends StatelessWidget {
  final Repository repo;

  /// Пасіка, з карти якої відкрито меню: генератор кодів тоді одразу
  /// відкривається для неї, без питання "Для якої пасіки?".
  final Apiary? currentApiary;
  const AppDrawer({super.key, required this.repo, this.currentApiary});

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
          _item(context, 'qr', 'Генерувати QR-коди', () {
            nav.pop();
            openQrGenerator(nav, repo, current: currentApiary);
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

  /// Обрати пасіку (якщо їх кілька) і відкрити генератор кодів.
  static Future<void> openQrGenerator(NavigatorState nav, Repository repo,
      {Apiary? current}) async {
    if (current != null) {
      await nav.push(MaterialPageRoute(
        builder: (_) => QrGenerateScreen(repo: repo, apiary: current),
      ));
      return;
    }
    final list = await repo.listApiaries();
    if (!nav.mounted) return;
    if (list.isEmpty) {
      await showInfo(nav.context, 'Спершу створіть пасіку.');
      return;
    }
    Apiary? apiary = list.length == 1 ? list.first : null;
    apiary ??= await showDialog<Apiary>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        title: const Text('Для якої пасіки?'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: PillButton(
                    text: a.name,
                    bg: AppColors.darkBtn,
                    fg: AppColors.text,
                    height: 44,
                    width: double.infinity,
                    onPressed: () => Navigator.pop(ctx, a),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
    if (apiary == null || !nav.mounted) return;
    final chosen = apiary;
    await nav.push(MaterialPageRoute(
      builder: (_) => QrGenerateScreen(repo: repo, apiary: chosen),
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
