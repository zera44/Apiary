import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../screens/apiary_list_screen.dart';
import '../screens/feedback_chat_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/history_hub_screen.dart';
import '../screens/map_screen.dart';
import '../screens/qr_generate_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/tutorial_screen.dart';
import 'common.dart';
import 'guide_bubble.dart';
import 'icons.dart';
import 'theme.dart';

/// Меню навігації (три смужки на карті пасіки): Мої пасіки / Склад / Історія
/// (і звіт Excel) / QR-код ▾ (сканувати, генерувати, прив'язати підряд) /
/// Навчання / Налаштування / Зворотний зв'язок. «Що нового» —
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

  /// Урок: «завершити навчання» — посилання над реплікою пасічника.
  final VoidCallback? onFinishTutorial;
  const AppDrawer(
      {super.key,
      this.hint,
      this.onFinishTutorial,
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
    final code = await scanQrCode(nav.context, receiptRepo: repo);
    if (code == null || !nav.mounted) return;
    final found = await repo.findByQr(code);
    if (!nav.mounted) return;
    if (found == null) {
      final why = await repo.qrProblem(code);
      if (!nav.mounted) return;
      final bind = await showConfirm(
        nav.context,
        title: 'Вулик не знайдено',
        text: '${why ?? 'Цей QR-код ще не прив\'язаний до жодного вулика.'}\n\nКод: $code\n\n'
            'Прив\'язати його до вулика зараз?',
        confirmText: 'Прив\'язати до вулика',
        cancelText: 'Закрити',
        danger: false,
      );
      if (!bind || !nav.mounted) return;
      final a = await repo.startApiary();
      if (!nav.mounted) return;
      if (a == null) {
        await showInfo(nav.context, 'Спершу створіть пасіку й вулики на карті.');
        return;
      }
      // карта: торкнутися вулика - код прив'язується й одразу відкривається огляд
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(
          builder: (_) => MapScreen(repo: repo, apiary: a, bindCode: code)));
      return;
    }
    openHive(nav, repo, found.apiary, found.element.id, fill: true, next: NextHive.qr);
  }

  /// Обхід: карта пасіки поверх головного екрана, без форми - вулики, які
  /// пора оглянути, обведені червоним, а «Сканувати» відкриває огляд.
  static void openRound(NavigatorState nav, Repository repo, Apiary apiary) {
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => MapScreen(repo: repo, apiary: apiary)));
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
    const TextSpan(text: ' - рамки, корми, ліки: прихід, списання й переоблік.'),
  ],
  [
    GuideBubble.highlight('Фінанси'),
    const TextSpan(text: ' - витрати й доходи пасіки: записуй вручну або фотографуй чек.'),
  ],
  [
    GuideBubble.highlight('Історія'),
    const TextSpan(text: ' - цікаво глянути зміни показників чи в складі? Тобі сюди.'),
  ],
  [
    GuideBubble.highlight('QR-код'),
    const TextSpan(
        text: ' - обхід без записів - час на вітер. Скануй код з вулика, а новий - прив\'язуй до вулика.'),
  ],
  [
    GuideBubble.highlight('Навчання'),
    const TextSpan(text: ' - щось не зрозумів? Пройди спеціалізоване навчання.'),
  ],
  [
    GuideBubble.highlight('Налаштування'),
    const TextSpan(text: ' - розмір шрифту, шаблони, акаунт і резервні копії.'),
  ],
  [
    GuideBubble.highlight('Зворотний зв\'язок'),
    const TextSpan(text: ' - хочеш поділитись ідеєю чи дати зворотний зв\'язок? Тобі сюди.'),
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
        // який це крок екскурсії
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (hint == null)
            for (var i = 0; i < kDrawerTour.length; i++)
              Container(
                width: i == _step ? 16 : 7,
                height: 7,
                margin: const EdgeInsets.only(right: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: i == _step ? AppColors.create : AppColors.create.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
        ]),
        const SizedBox(height: 6),
        // пасічник із газетою говорить хмаркою (як у навчанні) і стоїть
        // руками на кнопці «Продовжити»
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Image.asset(kLessonBeekeeperNewspaper, height: 84, filterQuality: FilterQuality.medium),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: AppColors.card,
                // гострий кут - до пасічника
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(3),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: AppColors.create, width: 1.5),
              ),
              child: Text.rich(
                TextSpan(children: text),
                style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.3),
              ),
            ),
          ),
        ]),
        // «Продовжити» - як в уроках; під нею - менша жовта «Завершити»
        LessonContinue(
          label: last ? 'Зрозуміло' : 'Продовжити',
          padding: EdgeInsets.zero,
          onContinue: () {
            if (last) {
              Navigator.of(context).pop(); // закрити меню
            } else {
              setState(() => _step++);
            }
          },
          onFinish: widget.tour ? widget.onFinishTutorial : null,
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
          _t(2, _item(context, '', 'Фінанси',
              widget.tour ? () {} : () => _open(nav, FinanceScreen(repo: repo)),
              iconData: Icons.account_balance_wallet_outlined)),
          // «Звіт по пасіці (Excel)» — усередині «Історії»
          _t(3, _item(context, 'history', 'Історія',
              widget.tour ? () {} : () => _open(nav, HistoryHubScreen(repo: repo, apiary: currentApiary)))),
          // QR — одним пунктом; натиснули — розкрились дії
          _t(4, _group(context, AppIcon('qr', color: AppColors.text, size: 30), 'QR-код', [
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
          _t(5, _item(context, '', 'Навчання',
              widget.tour ? () {} : () => _open(nav, TutorialScreen(realRepo: repo)),
              iconData: Icons.school_outlined)),
          _t(6, _item(context, '', 'Налаштування',
              widget.tour ? () {} : () => _open(nav, SettingsScreen(repo: repo)),
              iconData: Icons.settings)),
          _t(7, _item(context, 'pencil', "Зворотний зв'язок", widget.tour ? () {} : () {
            nav.pop(); // закрити меню
            openFeedback(nav);
          })),
          ])),
          if (widget.tour || widget.hint != null) _tourFooter(),
        ]),
      ),
    );
  }

  /// Пункт, що розгортається (QR-код).
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
