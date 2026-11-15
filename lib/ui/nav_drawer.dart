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
import '../screens/qr_section_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/tutorial_screen.dart';
import 'common.dart';
import 'icons.dart';
import 'theme.dart';

/// Розділи спільного меню навігації.
enum NavSection { apiaries, stock, finances, history, qr, assistant, tutorial, settings, feedback }

/// Спільне меню головних екранів (плашка «≡ назва ⌄» замість стрілки «назад»):
/// той самий вигляд, що в Фінансів, поточний розділ підсвічено. Фінанси й QR-код
/// мають ще й своє меню з розділами. «Назад» - системною кнопкою телефона.
class NavDrawer extends StatelessWidget {
  final Repository repo;
  final NavSection current;
  const NavDrawer({super.key, required this.repo, required this.current});

  void _go(BuildContext context, NavSection target) {
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
        nav.push(MaterialPageRoute<void>(builder: (_) => ApiaryListScreen(repo: repo)));
      case NavSection.stock:
        nav.push(MaterialPageRoute<void>(builder: (_) => StockScreen(repo: repo)));
      case NavSection.finances:
        nav.push(MaterialPageRoute<void>(builder: (_) => FinanceScreen(repo: repo)));
      case NavSection.history:
        // пасік може ще не бути - історія відкривається й без звіту по пасіці
        unawaited(repo.startApiary().then((a) async {
          final apiary = a ?? (await repo.listApiaries()).firstOrNull;
          if (!nav.mounted) return;
          nav.push(MaterialPageRoute<void>(
              builder: (_) => HistoryHubScreen(repo: repo, apiary: apiary)));
        }));
      case NavSection.qr:
        nav.push(MaterialPageRoute<void>(builder: (_) => QrSectionScreen(repo: repo)));
      case NavSection.tutorial:
        nav.push(MaterialPageRoute<void>(builder: (_) => TutorialScreen(realRepo: repo)));
      case NavSection.settings:
        nav.push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(repo: repo)));
      case NavSection.feedback:
        unawaited(openFeedback(nav, repo));
      case NavSection.assistant:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget item(NavSection s, String label, {String? icon, IconData? data}) {
      final on = s == current;
      final color = on ? AppColors.create : AppColors.text;
      return Container(
        decoration: BoxDecoration(
          color: on ? AppColors.create.withValues(alpha: 0.16) : null,
          border: Border(
              left: BorderSide(color: on ? AppColors.create : Colors.transparent, width: 4)),
        ),
        child: ListTile(
          leading: data != null
              ? Icon(data, color: color, size: 28)
              : AppIcon(icon!, color: color, size: 30),
          title: Text(label,
              style: TextStyle(
                  color: color, fontSize: 17, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
          onTap: () => _go(context, s),
        ),
      );
    }

    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
            child: Text(tr.navMenu,
                style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          Divider(height: 1, color: AppColors.textMuted.withValues(alpha: 0.3)),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(top: 8), children: [
              item(NavSection.apiaries, tr.myApiaries, icon: 'apiaries'),
              item(NavSection.stock, tr.stock, icon: 'box'),
              item(NavSection.finances, tr.finances, data: TablerIcons.wallet),
              item(NavSection.history, tr.history, icon: 'history'),
              item(NavSection.qr, tr.qrCode, icon: 'qr'),
              item(NavSection.assistant, tr.aiAssistant, data: TablerIcons.robot),
              item(NavSection.tutorial, tr.tutorial, data: TablerIcons.school),
              item(NavSection.settings, tr.settingsTitle, data: TablerIcons.settings),
              item(NavSection.feedback, tr.feedbackTitle, icon: 'feedback'),
            ]),
          ),
        ]),
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
