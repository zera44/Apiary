import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/fin_period.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/fin_stats_view.dart';
import '../ui/fin_style.dart';
import '../ui/nav_drawer.dart';

/// Статистика фінансів: дві вкладки, «Категорії» й «Рахунки», з однією логікою -
/// період, лінія результату (витрат, доходу) із середнім і межами нормальності,
/// під нею розподіл. Період спільний для обох вкладок.
class FinStatsScreen extends StatefulWidget {
  final Repository repo;
  const FinStatsScreen({super.key, required this.repo});

  @override
  State<FinStatsScreen> createState() => _FinStatsScreenState();
}

class _FinStatsScreenState extends State<FinStatsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sel = FinPeriodSel(
      period: FinPeriod.month, anchor: DateTime(DateTime.now().year, DateTime.now().month, 1));

  /// Вкладка: 0 категорії, 1 рахунки.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: NavDrawer(repo: widget.repo, current: NavSection.finances, finSection: FinSection.stats),
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(
                title: tr.finStats,
                onBack: () => Navigator.pop(context),
                onTitleTap: () => _scaffoldKey.currentState?.openDrawer()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FinSegment(
                key: const ValueKey('stat-tabs'),
                labels: [tr.finCategories, tr.finAccounts],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
                child: FinStatsView(
                    key: ValueKey('stat-view-$_tab'),
                    repo: widget.repo,
                    sel: _sel,
                    byAccount: _tab == 1)),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
