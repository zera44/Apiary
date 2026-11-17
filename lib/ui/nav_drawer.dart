import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../assistant/assistant_chat_screen.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../screens/apiary_list_screen.dart';
import '../screens/feedback_chat_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/history_hub_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/tutorial_screen.dart';
import 'common.dart';
import 'fin_drawer.dart';
import 'qr_actions.dart';
import 'settings_part.dart';
import 'icons.dart';
import 'theme.dart';

/// Розділи спільного меню навігації.
enum NavSection {
  apiaries,
  stock,
  finances,
  history,
  qr,
  assistant,
  tutorial,
  settings,
  feedback,
}

/// Спільне меню головних екранів (плашка «≡ назва ⌄» замість стрілки «назад»):
/// той самий вигляд, що в Фінансів, поточний розділ підсвічено. Фінанси й QR-код
/// мають ще й своє меню з розділами. «Назад» - системною кнопкою телефона.
class NavDrawer extends StatefulWidget {
  final Repository repo;
  final NavSection current;

  /// Поточний підрозділ Фінансів (лише для екранів Фінансів): «Фінанси» в меню
  /// розкриваються списком підрозділів, а розділи нижче ховаються.
  final FinSection? finSection;

  /// Поточний розділ «Налаштувань» і вибір іншого (екран Налаштувань сам міняє вміст).
  final SettingsPart? settingsPart;
  final ValueChanged<SettingsPart>? onSettingsPart;

  const NavDrawer({
    super.key,
    required this.repo,
    required this.current,
    this.finSection,
    this.settingsPart,
    this.onSettingsPart,
  });

  @override
  State<NavDrawer> createState() => _NavDrawerState();
}

class _NavDrawerState extends State<NavDrawer> {
  Repository get repo => widget.repo;
  NavSection get current => widget.current;
  late bool _finOpen = widget.finSection != null;
  late bool _setOpen = widget.settingsPart != null;
  late bool _qrOpen = widget.current == NavSection.qr;

  void _go(BuildContext context, NavSection target) {
    if (target == NavSection.finances) {
      setState(() => _finOpen = !_finOpen); // розкрити/згорнути підрозділи
      return;
    }
    if (target == NavSection.qr) {
      setState(() => _qrOpen = !_qrOpen);
      return;
    }
    if (target == NavSection.settings) {
      setState(() => _setOpen = !_setOpen);
      return;
    }
    final nav = Navigator.of(context);
    nav.pop(); // закрити меню
    if (target == NavSection.assistant) {
      unawaited(AssistantChatScreen.open(nav, repo));
      return;
    }
    if (target == current) return;
    // розділи лежать просто над головним екраном і замінюють один одного
    nav.popUntil((r) => r.isFirst);
    switch (target) {
      case NavSection.apiaries:
        nav.push(
          MaterialPageRoute<void>(builder: (_) => ApiaryListScreen(repo: repo)),
        );
      case NavSection.stock:
        nav.push(
          MaterialPageRoute<void>(builder: (_) => StockScreen(repo: repo)),
        );
      case NavSection.finances:
        nav.push(
          MaterialPageRoute<void>(builder: (_) => FinanceScreen(repo: repo)),
        );
      case NavSection.history:
        // пасік може ще не бути - історія відкривається й без звіту по пасіці
        unawaited(
          repo.startApiary().then((a) async {
            final apiary = a ?? (await repo.listApiaries()).firstOrNull;
            if (!nav.mounted) return;
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => HistoryHubScreen(repo: repo, apiary: apiary),
              ),
            );
          }),
        );
      case NavSection.qr:
        break; // розкривається в меню (див. _go)
      case NavSection.tutorial:
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => TutorialScreen(realRepo: repo),
          ),
        );
      case NavSection.settings:
        nav.push(
          MaterialPageRoute<void>(builder: (_) => SettingsScreen(repo: repo)),
        );
      case NavSection.feedback:
        unawaited(openFeedback(nav, repo));
      case NavSection.assistant:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget sub(FinSection s, IconData icon, String label) {
      final on = s == widget.finSection;
      final color = on ? AppColors.text : AppColors.textMuted;
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 2, 12, 2),
        child: Material(
          color: on ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: Icon(icon, color: color, size: 24),
            title: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            onTap: () => widget.finSection != null
                ? FinDrawer.goSection(context, repo, widget.finSection!, s)
                : FinDrawer.openFrom(context, repo, s),
          ),
        ),
      );
    }

    Widget actionSub(NavAction a) => Padding(
      padding: const EdgeInsets.fromLTRB(40, 2, 12, 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(a.icon, color: AppColors.textMuted, size: 24),
        title: Text(
          a.label,
          style: TextStyle(color: AppColors.textMuted, fontSize: 16),
        ),
        onTap: () {
          Navigator.of(context).pop(); // закрити меню
          a.onTap();
        },
      ),
    );

    Widget setSub(SettingsPart p) {
      final on = p == widget.settingsPart;
      final color = on ? AppColors.text : AppColors.textMuted;
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 2, 12, 2),
        child: Material(
          color: on ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: Icon(p.icon, color: color, size: 24),
            title: Text(
              p.label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop(); // закрити меню
              if (widget.onSettingsPart != null) {
                widget.onSettingsPart!(p);
                return;
              }
              // з іншого екрана: відкрити Налаштування одразу на цьому розділі
              nav.popUntil((r) => r.isFirst);
              nav.push(MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(repo: repo, part: p)));
            },
          ),
        ),
      );
    }

    Widget item(NavSection s, String label, {String? icon, IconData? data}) {
      final on = s == current;
      final color = on ? AppColors.create : AppColors.text;
      return Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: on ? AppColors.create : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        // фон - у Material, щоб ListTile бачив його (інакше підсвітка ховається)
        child: Material(
          color: on
              ? AppColors.create.withValues(alpha: 0.16)
              : Colors.transparent,
          child: ListTile(
            leading: data != null
                ? Icon(data, color: color, size: 28)
                : AppIcon(icon!, color: color, size: 30),
            title: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            trailing: s == NavSection.finances
                ? Icon(
                    _finOpen
                        ? TablerIcons.chevron_up
                        : TablerIcons.chevron_down,
                    color: color,
                  )
                : s == NavSection.settings
                ? Icon(
                    _setOpen
                        ? TablerIcons.chevron_up
                        : TablerIcons.chevron_down,
                    color: color,
                  )
                : null,
            onTap: () => _go(context, s),
          ),
        ),
      );
    }

    final finOpen = _finOpen;
    final setOpen = _setOpen;
    final qrOpen = _qrOpen;

    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
              child: Text(
                tr.navMenu,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Divider(
              height: 1,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  item(NavSection.apiaries, tr.myApiaries, icon: 'apiaries'),
                  item(NavSection.stock, tr.stock, icon: 'box'),
                  item(
                    NavSection.finances,
                    tr.finances,
                    data: TablerIcons.wallet,
                  ),
                  if (finOpen) ...[
                    sub(FinSection.home, TablerIcons.chart_donut, tr.finHome),
                    sub(
                      FinSection.accounts,
                      TablerIcons.building_bank,
                      tr.finAccounts,
                    ),
                    sub(FinSection.stats, TablerIcons.chart_bar, tr.finStats),
                    sub(
                      FinSection.categories,
                      TablerIcons.list,
                      tr.finCategories,
                    ),
                    sub(FinSection.ops, TablerIcons.receipt, tr.finOps),
                  ] else if (qrOpen) ...[
                    // «QR-код» розкритий: решта розділів нижче ховається
                    item(NavSection.history, tr.history, icon: 'history'),
                    item(NavSection.qr, tr.qrCode, icon: 'qr'),
                    for (final a in qrActions(context, repo)) actionSub(a),
                  ] else if (!setOpen) ...[
                    item(NavSection.history, tr.history, icon: 'history'),
                    item(NavSection.qr, tr.qrCode, icon: 'qr'),
                    item(
                      NavSection.assistant,
                      tr.aiAssistant,
                      data: TablerIcons.robot,
                    ),
                    item(
                      NavSection.tutorial,
                      tr.tutorial,
                      data: TablerIcons.school,
                    ),
                    item(
                      NavSection.settings,
                      tr.settingsTitle,
                      data: TablerIcons.settings,
                    ),
                    item(
                      NavSection.feedback,
                      tr.feedbackTitle,
                      icon: 'feedback',
                    ),
                  ] else ...[
                    // Налаштування розкриті: решта розділів ховається, нижче - лише підрозділи
                    item(
                      NavSection.settings,
                      tr.settingsTitle,
                      data: TablerIcons.settings,
                    ),
                    for (final p in SettingsPart.values) setSub(p),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шапка головного екрана: плашка «≡ назва ⌄» відкриває [NavDrawer] найближчого
/// [Scaffold] (екран має передати його як `drawer`).
class NavTopBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const NavTopBar({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => TopBar(
    title: title,
    trailing: trailing,
    onTitleTap: () => Scaffold.of(context).openDrawer(),
  );
}
