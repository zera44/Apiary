import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../assistant/assistant_chat_screen.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../screens/apiary_list_screen.dart';
import '../screens/feedback_chat_screen.dart';
import '../screens/history_hub_screen.dart';
import '../screens/map_screen.dart';
import '../screens/qr_scan_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/tutorial_screen.dart';
import 'common.dart';
import 'nav_drawer.dart';
import 'qr_actions.dart';
import 'guide_bubble.dart';
import 'fin_drawer.dart';
import 'icons.dart';
import 'settings_part.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

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
        title: tr.qrHiveNotFound,
        text: tr.qrBindAsk(why ?? tr.qrNotBound, code),
        confirmText: tr.qrBindToHive,
        cancelText: tr.close,
        danger: false,
      );
      if (!bind || !nav.mounted) return;
      final a = await repo.startApiary();
      if (!nav.mounted) return;
      if (a == null) {
        await showInfo(nav.context, tr.qrCreateApiaryFirst);
        return;
      }
      // карта: торкнутися вулика - код прив'язується й одразу відкривається огляд
      nav.push(MaterialPageRoute(
          builder: (_) => MapScreen(repo: repo, apiary: a, bindCode: code)));
      return;
    }
    openHive(nav, repo, found.apiary, found.element.id, fill: true, next: NextHive.qr);
  }

  /// Обхід: карта пасіки поверх поточного екрана («назад» повертає на нього), без форми - вулики, які
  /// пора оглянути, обведені червоним, а «Сканувати» відкриває огляд.
  static void openRound(NavigatorState nav, Repository repo, Apiary apiary) {
    nav.push(MaterialPageRoute(builder: (_) => MapScreen(repo: repo, apiary: apiary)));
  }

  /// Відкрити карту пасіки з панеллю вулика поверх поточного екрана;
  /// [fill] — одразу форма «Оглянути».
  static void openHive(NavigatorState nav, Repository repo, Apiary apiary, String elementId,
      {bool fill = false, NextHive next = NextHive.order}) {
    nav.push(MaterialPageRoute(
      builder: (_) => MapScreen(
          repo: repo, apiary: apiary, focusElementId: elementId, openFill: fill, next: next),
    ));
  }
}

/// Кроки екскурсії по меню: що розповідає пасічник про кожен пункт.

List<List<InlineSpan>> get kDrawerTour => [
  [
    GuideBubble.highlight(tr.myApiaries),
    TextSpan(text: tr.tourApiaries),
  ],
  [
    GuideBubble.highlight(tr.stock),
    TextSpan(text: tr.tourStock),
  ],
  [
    GuideBubble.highlight(tr.finances),
    TextSpan(text: tr.tourFinances),
  ],
  [
    GuideBubble.highlight(tr.history),
    TextSpan(text: tr.tourHistory),
  ],
  [
    GuideBubble.highlight(tr.qrCode),
    TextSpan(text: tr.tourQr),
  ],
  [
    GuideBubble.highlight(tr.aiAssistant),
    TextSpan(text: tr.tourAssistant),
  ],
  [
    GuideBubble.highlight(tr.tutorial),
    TextSpan(text: tr.tourTutorial),
  ],
  [
    GuideBubble.highlight(tr.settingsTitle),
    TextSpan(text: tr.tourSettings),
  ],
  [
    GuideBubble.highlight(tr.feedbackTitle),
    TextSpan(text: tr.tourFeedback),
  ],
];

/// Малюнок пасічника для кожного пункту огляду меню (порядок - як у [kDrawerTour]).
const kTourPics = [
  kLessonBeekeeper,
  kLessonBeekeeperLaptop,
  'assets/guide/beekeeper_scheming.webp',
  kLessonBeekeeperNewspaper,
  'assets/guide/beekeeper_blueprint.webp',
  kLessonBear,
  kLessonBeekeeperProfessor,
  kLessonBeekeeperTemplates,
  kLessonBeekeeperMailbox,
];

class _AppDrawerState extends State<AppDrawer> {
  int _step = 0;
  /// Розкритий розділ меню: 'fin', 'qr' або 'set' (його підрозділи під назвою).
  String? _openRow;

  void _toggle(String row) => setState(() => _openRow = _openRow == row ? null : row);

  Widget? _chev(String row) => widget.tour
      ? null
      : Icon(_openRow == row ? TablerIcons.chevron_up : TablerIcons.chevron_down,
          color: AppColors.text);

  /// Підрозділ: закриває меню й виконує дію.
  Widget _sub(IconData icon, String label, VoidCallback onTap, {bool close = true}) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 2, 12, 2),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(icon, color: AppColors.textMuted, size: 24),
          title: Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
          onTap: () {
            if (close) Navigator.of(context).pop(); // закрити меню
            onTap();
          },
        ),
      );

  Repository get repo => widget.repo;
  Apiary get currentApiary => widget.currentApiary;
  Future<void> Function()? get onReturn => widget.onReturn;
  VoidCallback? get onBindQrRow => widget.onBindQrRow;

  /// Урок: пункт [i] підсвічено, натискання вимкнено.
  Widget _t(int i, Widget child) => widget.tour
      ? IgnorePointer(child: HoneyRing(on: _step == i, radius: 12, child: child))
      // одна репліка («пройди навчання») - підсвічено «Навчання», натискати можна
      : widget.hint != null
          ? HoneyRing(on: i == 6, radius: 12, child: child)
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
          Image.asset(hint == null ? kTourPics[_step % kTourPics.length] : kLessonBeekeeperProfessor,
              height: 84, filterQuality: FilterQuality.medium),
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
          label: last ? tr.gotIt : tr.continueAction,
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
            child: Text(tr.navMenu,
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          // розділи по порядку; розкритий - зі своїми підрозділами одразу під ним
          ...navWithOther(
            open: widget.tour ? null : _openRow,
            items: [
              (key: 'apiaries', label: tr.myApiaries, widget: _t(0, _item(context, 'apiaries', tr.myApiaries, widget.tour ? () {} : () {
                nav.pop(); // закрити меню
                nav.popUntil((r) => r.isFirst);
                nav.push(MaterialPageRoute(builder: (_) => ApiaryListScreen(repo: repo)));
              }))),
              (key: 'stock', label: tr.stock, widget: _t(1, _item(context, 'box', tr.stock,
                  widget.tour ? () {} : () => _open(nav, StockScreen(repo: repo))))),
              (key: 'fin', label: tr.finances, widget: _t(2, _item(context, '', tr.finances,
                  widget.tour ? () {} : () => _toggle('fin'),
                  iconData: TablerIcons.wallet, trailing: _chev('fin')))),
              // «Звіт по пасіці (Excel)» — усередині «Історії»
              (key: 'history', label: tr.history, widget: _t(3, _item(context, 'history', tr.history,
                  widget.tour ? () {} : () => _open(nav, HistoryHubScreen(repo: repo, apiary: currentApiary))))),
              // QR-код: тап розкриває Сканувати, Генерувати, Прив'язати
              (key: 'qr', label: tr.qrCode, widget: _t(4, _item(context, 'qr', tr.qrCode,
                  widget.tour ? () {} : () => _toggle('qr'),
                  trailing: _chev('qr')))),
              // ШІ-помічник: відкрити розмову (в огляді меню - лише показати)
              (key: 'ai', label: tr.aiAssistant, widget: _t(5, _item(context, '', tr.aiAssistant, widget.tour ? () {} : () {
                nav.pop(); // закрити меню
                unawaited(AssistantChatScreen.open(nav, repo));
              }, iconData: TablerIcons.robot))),
              (key: 'tutorial', label: tr.tutorial, widget: _t(6, _item(context, '', tr.tutorial,
                  widget.tour ? () {} : () => _open(nav, TutorialScreen(realRepo: repo)),
                  iconData: TablerIcons.school))),
              (key: 'set', label: tr.settingsTitle, widget: _t(7, _item(context, '', tr.settingsTitle,
                  widget.tour ? () {} : () => _toggle('set'),
                  iconData: TablerIcons.settings, trailing: _chev('set')))),
              (key: 'feedback', label: tr.feedbackTitle, widget: _t(8, _item(context, 'feedback', tr.feedbackTitle, widget.tour ? () {} : () {
                nav.pop(); // закрити меню
                openFeedback(nav, repo);
              }))),
            ],
            subs: switch (_openRow) {
              'fin' => [
                  _sub(TablerIcons.chart_donut, tr.finHome, () => FinDrawer.openFrom(context, repo, FinSection.home), close: false),
                  _sub(TablerIcons.building_bank, tr.finAccounts, () => FinDrawer.openFrom(context, repo, FinSection.accounts), close: false),
                  _sub(TablerIcons.chart_bar, tr.finStats, () => FinDrawer.openFrom(context, repo, FinSection.stats), close: false),
                  _sub(TablerIcons.list, tr.finCategories, () => FinDrawer.openFrom(context, repo, FinSection.categories), close: false),
                  _sub(TablerIcons.receipt, tr.finOps, () => FinDrawer.openFrom(context, repo, FinSection.ops), close: false),
                ],
              'qr' => [for (final a in qrActions(context, repo)) _sub(a.icon, a.label, a.onTap)],
              'set' => [
                  for (final p in SettingsPart.values)
                    _sub(p.icon, p.label, () {
                      nav.popUntil((r) => r.isFirst);
                      nav.push(MaterialPageRoute<void>(
                          builder: (_) => SettingsScreen(repo: repo, part: p)));
                    }),
                ],
              _ => const [],
            },
            onOther: () => setState(() => _openRow = null),
          ),
          ])),
          if (widget.tour || widget.hint != null) _tourFooter(),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, String icon, String text, VoidCallback onTap,
      {IconData? iconData, Widget? trailing}) {
    return ListTile(
      trailing: trailing,
      leading: iconData != null
          ? Icon(iconData, color: AppColors.text, size: 28)
          : AppIcon(icon, color: AppColors.text, size: 30),
      title: Text(text, style: TextStyle(color: AppColors.text, fontSize: 16)),
      onTap: onTap,
    );
  }
}
