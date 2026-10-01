import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../screens/apiary_list_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/history_hub_screen.dart';
import '../screens/map_screen.dart';
import '../screens/parameters_screen.dart';
import '../screens/qr_generate_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/templates_screen.dart';
import '../screens/tutorial_screen.dart';
import '../services/autostart.dart';
import 'common.dart';
import 'icons.dart';
import 'theme.dart';

/// Меню навігації (три смужки на карті пасіки): Мої пасіки / Склад / Історія
/// (і звіт Excel) / QR-код ▾ (сканувати, генерувати, прив'язати підряд) /
/// Налаштування ▾ (характеристики, шаблони) / Навчання / Зворотний зв'язок. «Що нового» —
/// лише на головному екрані, туди — кнопкою «назад». Є лише на карті.
class AppDrawer extends StatelessWidget {
  final Repository repo;

  /// Пасіка, з карти якої відкрито меню (меню є лише на карті пасіки):
  /// генератор кодів відкривається одразу для неї.
  final Apiary currentApiary;

  /// Викликається після повернення з екранів меню (шаблони, характеристики,
  /// генератор QR): там могли змінити дані, які показує карта.
  final Future<void> Function()? onReturn;

  /// «Прив'язати наліпки підряд» (робить сама карта).
  final VoidCallback? onBindQrRow;
  const AppDrawer(
      {super.key, required this.repo, required this.currentApiary, this.onReturn, this.onBindQrRow});

  Future<void> _open(NavigatorState nav, Widget screen) async {
    nav.pop(); // закрити меню
    await nav.push(MaterialPageRoute(builder: (_) => screen));
    await onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        // пункти прокручуються (на невисокому екрані всі вміщуються)
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Меню навігації',
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          _item(context, 'beehive', 'Мої пасіки', () {
            nav.pop(); // закрити меню
            nav.popUntil((r) => r.isFirst);
            nav.push(MaterialPageRoute(builder: (_) => ApiaryListScreen(repo: repo)));
          }),
          _item(context, 'box', 'Склад', () => _open(nav, StockScreen(repo: repo))),
          // «Звіт по пасіці (Excel)» — усередині «Історії»
          _item(context, 'history', 'Історія',
              () => _open(nav, HistoryHubScreen(repo: repo, apiary: currentApiary))),
          // QR — одним пунктом; натиснули — розкрились дії
          _group(context, AppIcon('qr', color: AppColors.text, size: 30), 'QR-код', [
            _item(context, 'qr', 'Сканувати', () {
              nav.pop();
              openHiveByQr(nav, repo);
            }),
            _item(context, 'qr', 'Генерувати',
                () => _open(nav, QrGenerateScreen(repo: repo, apiary: currentApiary))),
            if (onBindQrRow != null)
              _item(context, 'qr', 'Прив\'язати підряд', () {
                nav.pop(); // закрити меню
                onBindQrRow!();
              }),
          ]),
          // разове налаштування — рідко, тому згорнуто
          _group(context, Icon(Icons.tune, color: AppColors.text, size: 28), 'Налаштування', [
            _item(context, '', 'Характеристики',
                () => _open(nav, ParametersScreen.catalog(repo: repo)),
                iconData: Icons.list_alt),
            _item(context, 'hexagon', 'Шаблони', () => _open(nav, TemplatesScreen(repo: repo))),
          ]),
          _item(context, '', 'Навчання',
              () => _open(nav, const TutorialScreen()),
              iconData: Icons.school_outlined),
          _item(context, 'pencil', "Зворотний зв'язок", () {
            nav.pop(); // закрити меню
            nav.push(MaterialPageRoute(builder: (_) => const FeedbackScreen()));
          }),
          ])),
          if (Autostart.supported) const _AutostartTile(),
        ]),
      ),
    );
  }

  /// Відсканувати код і відкрити карту пасіки з панеллю цього вулика й
  /// одразу формою «Заповнити».
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
    openHive(nav, repo, found.apiary, found.element.id, fill: true, next: NextHive.qr);
  }

  /// Відкрити карту пасіки з панеллю вулика поверх головного екрана;
  /// [fill] — одразу форма «Заповнити».
  static void openHive(NavigatorState nav, Repository repo, Apiary apiary, String elementId,
      {bool fill = false, NextHive next = NextHive.order}) {
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(
      builder: (_) => MapScreen(
          repo: repo, apiary: apiary, focusElementId: elementId, openFill: fill, next: next),
    ));
  }

  /// Пункт, що розгортається (QR-код, Налаштування).
  Widget _group(BuildContext context, Widget leading, String title, List<Widget> children) =>
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: leading,
          title: Text(title, style: TextStyle(color: AppColors.text, fontSize: 16)),
          iconColor: AppColors.text,
          collapsedIconColor: AppColors.textMuted,
          childrenPadding: const EdgeInsets.only(left: 40),
          children: children,
        ),
      );

  Widget _item(BuildContext context, String icon, String text, VoidCallback onTap,
      {IconData? iconData}) {
    return ListTile(
      leading: iconData != null
          ? Icon(iconData, color: AppColors.text, size: 28)
          : AppIcon(icon, color: AppColors.text, size: 30),
      title: Text(text, style: TextStyle(color: AppColors.text, fontSize: 16)),
      onTap: onTap,
    );
  }
}

/// Перемикач "Запускати разом з Windows" (лише Windows).
class _AutostartTile extends StatefulWidget {
  const _AutostartTile();
  @override
  State<_AutostartTile> createState() => _AutostartTileState();
}

class _AutostartTileState extends State<_AutostartTile> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Autostart.isEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  Future<void> _toggle(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await Autostart.setEnabled(v);
    final now = await Autostart.isEnabled();
    if (!mounted) return;
    setState(() {
      _on = now;
      _busy = false;
    });
    if (!ok) {
      await showInfo(context, 'Не вдалося змінити автозапуск.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _on ?? false,
      onChanged: (_on == null || _busy) ? null : _toggle,
      title: Text('Запускати разом з Windows',
          style: TextStyle(color: AppColors.text, fontSize: 15)),
      subtitle: Text('Щоб приходили нагадування про обхід',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
    );
  }
}
