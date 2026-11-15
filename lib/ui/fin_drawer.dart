import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../screens/fin_accounts_screen.dart';
import '../screens/fin_categories_screen.dart';
import '../screens/fin_stats_screen.dart';
import '../screens/finance_screen.dart';
import 'theme.dart';

/// Розділи блоку «Фінанси» (пункти бокового меню).
enum FinSection { home, accounts, stats, categories, ops }

/// Бокове меню блоку «Фінанси»: Головна, Рахунки, Статистика, Категорії, Операції та
/// вихід до пасіки. Головна лежить під усіма іншими розділами, а вони
/// замінюють один одного, тож «назад» завжди йде на екран назад: з розділу
/// на Головну фінансів, звідти до пасіки.
class FinDrawer extends StatelessWidget {
  final Repository repo;
  final FinSection current;
  const FinDrawer({super.key, required this.repo, required this.current});

  void _go(BuildContext context, FinSection target) {
    final nav = Navigator.of(context);
    nav.pop(); // закрити меню
    if (target == current) return;
    if (target == FinSection.home) {
      nav.pop(); // розділ лежить просто над Головною
      return;
    }
    final route = MaterialPageRoute<void>(builder: (_) => switch (target) {
          FinSection.accounts => FinAccountsScreen(repo: repo),
          FinSection.stats => FinStatsScreen(repo: repo),
          FinSection.categories => FinCategoriesScreen(repo: repo),
          _ => FinHistoryScreen.thisMonth(repo: repo),
        });
    if (current == FinSection.home) {
      nav.push(route);
    } else {
      nav.pushReplacement(route);
    }
  }

  void _toApiary(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop(); // закрити меню
    nav.pop(); // поточний екран
    if (current != FinSection.home) nav.pop(); // і Головна фінансів
  }

  @override
  Widget build(BuildContext context) {
    Widget item(FinSection s, IconData icon, String label) {
      final on = s == current;
      final color = on ? AppColors.create : AppColors.text;
      return Container(
        decoration: BoxDecoration(
          color: on ? AppColors.create.withValues(alpha: 0.16) : null,
          border: Border(left: BorderSide(color: on ? AppColors.create : Colors.transparent, width: 4)),
        ),
        child: ListTile(
          leading: Icon(icon, color: color, size: 28),
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
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Row(children: [
              Icon(TablerIcons.wallet, color: AppColors.text, size: 32),
              const SizedBox(width: 16),
              Text(tr.finances,
                  style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
            ]),
          ),
          Divider(height: 1, color: AppColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          item(FinSection.home, TablerIcons.chart_donut, tr.finHome),
          item(FinSection.accounts, TablerIcons.building_bank, tr.finAccounts),
          item(FinSection.stats, TablerIcons.chart_bar, tr.finStats),
          item(FinSection.categories, TablerIcons.list, tr.finCategories),
          item(FinSection.ops, TablerIcons.receipt, tr.finOps),
          const Spacer(),
          Divider(height: 1, color: AppColors.textMuted.withValues(alpha: 0.3)),
          ListTile(
            leading: Icon(TablerIcons.arrow_back_up, color: AppColors.text, size: 28),
            title: Text(tr.finBackToApiary, style: TextStyle(color: AppColors.text, fontSize: 16)),
            onTap: () => _toApiary(context),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
