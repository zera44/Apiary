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
import 'guide_bubble.dart';
import 'icons.dart';
import 'theme.dart';

/// Меню навігації (три смужки на карті пасіки): Мої пасіки / Склад / Історія
/// (і звіт Excel) / QR-код ▾ (сканувати, генерувати, прив'язати підряд) /
/// Налаштування ▾ (характеристики, шаблони) / Навчання / Зворотний зв'язок. «Що нового» —
/// лише на головному екрані, туди — кнопкою «назад». Є лише на карті.
class AppDrawer extends StatefulWidget {
  final Repository repo;

  /// Пасіка, з карти якої відкрито меню (меню є лише на карті пасіки):
  /// генератор кодів відкривається одразу для неї.
  final Apiary currentApiary;

  /// Викликається після повернення з екранів меню (шаблони, характеристики,
  /// генератор QR): там могли змінити дані, які показує карта.
  final Future<void> Function()? onReturn;

  /// «Прив'язати наліпки підряд» (робить сама карта).
  final VoidCallback? onBindQrRow;

  /// Урок: пасічник по черзі розповідає про пункти меню (пункти не натискаються,
  /// кожен підсвічується медовим ободком).
  final bool tour;

  /// Одна репліка пасічника внизу меню (після «Я сам собі маг пасіки»).
  final List<InlineSpan>? hint;
  const AppDrawer(
      {super.key,
      this.hint,
      required this.repo,
      required this.currentApiary,
      this.onReturn,
      this.onBindQrRow,
      this.tour = false});

  @override
  State<AppDrawer> createState() => _AppDrawerState();

  /// Відсканувати код і відкрити карту пасіки з панеллю цього вулика й
  /// одразу формою «Оглянути».
  /// Працює через [NavigatorState] — контекст меню після закриття вже
  /// недійсний.
  static Future<void> openHiveByQr(NavigatorState nav, Repository repo) async {
    final code = await scanQrCode(nav.context);
    if (code == null || !nav.mounted) return;
    final found = await repo.findByQr(code);
    if (!nav.mounted) return;
    if (found == null) {
      final why = await repo.qrProblem(code);
      if (!nav.mounted) return;
      await showInfo(
        nav.context,
        '${why ?? 'Цей QR-код ще не прив\'язаний до жодного вулика.'}\n\n'
        'Щоб прив\'язати: відкрийте пасіку, торкніться вулика й на панелі '
        '«Характеристики» натисніть «Прив\'язати QR-код».\n\nКод: $code',
        title: 'Вулик не знайдено',
      );
      return;
    }
    openHive(nav, repo, found.apiary, found.element.id, fill: true, next: NextHive.qr);
  }

  /// Відкрити карту пасіки з панеллю вулика поверх головного екрана;
  /// [fill] — одразу форма «Оглянути».
  static void openHive(NavigatorState nav, Repository repo, Apiary apiary, String elementId,
      {bool fill = false, NextHive next = NextHive.order}) {
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(
      builder: (_) => MapScreen(
          repo: repo, apiary: apiary, focusElementId: elementId, openFill: fill, next: next),
    ));
  }
}

/// Кроки екскурсії по меню: що розповідає пасічник про кожен пункт.

final List<List<InlineSpan>> kDrawerTour = [
  [
    GuideBubble.highlight('Мої пасіки'),
    const TextSpan(text: ' - усі твої пасіки в одному місці.'),
  ],
  [
    GuideBubble.highlight('Склад'),
    const TextSpan(text: ' - рамки, корми, ліки. А як ще керувати запасами?'),
  ],
  [
    GuideBubble.highlight('Історія'),
    const TextSpan(text: ' - цікаво глянути зміни показників чи в складі? Тобі сюди.'),
  ],
  [
    GuideBubble.highlight('QR-код'),
    const TextSpan(
        text: ' - обхід без записів - час на вітер. Як же тут без сканування коду з вулика?'),
  ],
  [
    GuideBubble.highlight('Налаштування'),
    const TextSpan(text: ' - тут є все: шаблони, характеристики та інше. А що ще треба?'),
  ],
  [
    GuideBubble.highlight('Навчання'),
    const TextSpan(text: ' - щось не зрозумів? Пройди спеціалізоване навчання.'),
  ],
  [
    GuideBubble.highlight('Зворотний зв\'язок'),
    const TextSpan(text: ' - хочеш поділитись ідеєю чи дати зворотній зв\'язок? Тобі сюди.'),
  ],
];

class _AppDrawerState extends State<AppDrawer> {
  int _step = 0;

  Repository get repo => widget.repo;
  Apiary get currentApiary => widget.currentApiary;
  Future<void> Function()? get onReturn => widget.onReturn;
  VoidCallback? get onBindQrRow => widget.onBindQrRow;

  /// Урок: пункт [i] підсвічено, натискання вимкнено.
  Widget _t(int i, Widget child) => widget.tour
      ? IgnorePointer(child: HoneyRing(on: _step == i, radius: 12, child: child))
      // одна репліка («пройди навчання») - підсвічено «Навчання», натискати можна
      : widget.hint != null
          ? HoneyRing(on: i == 5, radius: 12, child: child)
          : child;

  Widget _tourFooter() {
    final hint = widget.hint;
    final last = hint != null || _step == kDrawerTour.length - 1;
    final text = hint ?? kDrawerTour[_step];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
          color: AppColors.popupBg,
          border: Border(top: BorderSide(color: AppColors.hive.withValues(alpha: 0.5)))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // пасічник стоїть руками на кнопці «Далі» - спирається на неї
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Image.asset(kLessonBeekeeperNewspaper, height: 84, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Text.rich(
                TextSpan(children: text),
                style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.3),
              ),
            ),
          ),
        ]),
        PillButton(
          text: last ? 'Зрозуміло' : 'Далі',
          bg: AppColors.accent,
          height: 40,
          width: double.infinity,
          onPressed: () {
            if (last) {
              Navigator.of(context).pop(); // закрити меню
            } else {
              setState(() => _step++);
            }
          },
        ),
      ]),
    );
  }

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
          _t(0, _item(context, 'beehive', 'Мої пасіки', widget.tour ? () {} : () {
            nav.pop(); // закрити меню
            nav.popUntil((r) => r.isFirst);
            nav.push(MaterialPageRoute(builder: (_) => ApiaryListScreen(repo: repo)));
          })),
          _t(1, _item(context, 'box', 'Склад',
              widget.tour ? () {} : () => _open(nav, StockScreen(repo: repo)))),
          // «Звіт по пасіці (Excel)» — усередині «Історії»
          _t(2, _item(context, 'history', 'Історія',
              widget.tour ? () {} : () => _open(nav, HistoryHubScreen(repo: repo, apiary: currentApiary)))),
          // QR — одним пунктом; натиснули — розкрились дії
          _t(3, _group(context, AppIcon('qr', color: AppColors.text, size: 30), 'QR-код', [
            _item(context, 'qr', 'Сканувати', () {
              nav.pop();
              AppDrawer.openHiveByQr(nav, repo);
            }),
            _item(context, 'qr', 'Генерувати',
                () => _open(nav, QrGenerateScreen(repo: repo, apiary: currentApiary))),
            if (onBindQrRow != null)
              _item(context, 'qr', 'Прив\'язати підряд', () {
                nav.pop(); // закрити меню
                onBindQrRow!();
              }),
          ])),
          // разове налаштування — рідко, тому згорнуто
          _t(4, _group(context, Icon(Icons.tune, color: AppColors.text, size: 28), 'Налаштування', [
            _item(context, '', 'Характеристики',
                () => _open(nav, ParametersScreen.catalog(repo: repo)),
                iconData: Icons.list_alt),
            _item(context, 'hexagon', 'Шаблони', () => _open(nav, TemplatesScreen(repo: repo))),
          ])),
          _t(5, _item(context, '', 'Навчання',
              widget.tour ? () {} : () => _open(nav, TutorialScreen(realRepo: repo)),
              iconData: Icons.school_outlined)),
          _t(6, _item(context, 'pencil', "Зворотний зв'язок", widget.tour ? () {} : () {
            nav.pop(); // закрити меню
            nav.push(MaterialPageRoute(builder: (_) => const FeedbackScreen()));
          })),
          ])),
          if (widget.tour || widget.hint != null) _tourFooter(),
          if (Autostart.supported) const _AutostartTile(),
        ]),
      ),
    );
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
