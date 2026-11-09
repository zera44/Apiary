import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';

/// Статистика фінансів: дохід і витрати за кожен місяць обраного року.
class FinStatsScreen extends StatefulWidget {
  final Repository repo;
  const FinStatsScreen({super.key, required this.repo});

  @override
  State<FinStatsScreen> createState() => _FinStatsScreenState();
}

class _FinStatsScreenState extends State<FinStatsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _year = DateTime.now().year;
  bool _byYears = false;
  List<FinMonthTotal> _months = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.listFinEntries(
        from: _byYears ? DateTime(1970) : DateTime(_year, 1, 1),
        to: DateTime(_byYears ? DateTime.now().year + 2 : _year + 1, 1, 1));
    if (!mounted) return;
    setState(() {
      _months = _byYears ? finYearlyTotals(list) : finMonthlyTotals(list, _year);
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() {
      _year += d;
      _loaded = false;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final inc = _months.fold(0.0, (a, m) => a + m.income);
    final exp = _months.fold(0.0, (a, m) => a + m.expense);
    final maxV = _months.fold(0.0, (a, m) => [a, m.income, m.expense].reduce((x, y) => x > y ? x : y));
    final green = finColor('olive'), yellow = finColor('honey');
    final profit = finColor('sky'), loss = finColor('terra');
    return Scaffold(
      key: _scaffoldKey,
      drawer: FinDrawer(repo: widget.repo, current: FinSection.stats),
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
                labels: [tr.finByYears, tr.finByMonths],
                selected: _byYears ? 0 : 1,
                onChanged: (i) {
                  setState(() {
                    _byYears = i == 0;
                    _loaded = false;
                  });
                  _reload();
                },
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                        decoration: BoxDecoration(
                            color: AppColors.card, borderRadius: BorderRadius.circular(20)),
                        child: Column(children: [
                          if (_byYears) const SizedBox(height: 12),
                          if (!_byYears)
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            IconButton(
                                onPressed: () => _shift(-1),
                                tooltip: tr.earlier,
                                icon: Icon(Icons.chevron_left, color: AppColors.text)),
                            Text('$_year',
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            IconButton(
                                onPressed: () => _shift(1),
                                tooltip: tr.later,
                                icon: Icon(Icons.chevron_right, color: AppColors.text)),
                          ]),
                          SizedBox(
                            height: 220,
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (final m in _months)
                                    Expanded(
                                      child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    _bar(m.income, maxV, green),
                                                    _bar(m.expense, maxV, yellow),
                                                    // третій стовпчик: прибуток, а коли витрати більші - збитки
                                                    _bar(m.balance.abs(), maxV, m.balance >= 0 ? profit : loss),
                                                  ]),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(_byYears ? '${m.month}' : tr.monthNames[m.month].substring(0, 3),
                                                style: TextStyle(
                                                    color: AppColors.textMuted, fontSize: 10)),
                                          ]),
                                    ),
                                ]),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 18,
                              runSpacing: 6,
                              children: [
                                _dot(green, tr.income),
                                _dot(yellow, tr.expenses),
                                _dot(profit, tr.finProfit),
                                _dot(loss, tr.finLoss),
                              ]),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      _total(tr.income, uah(inc), AppColors.text),
                      _total(tr.expenses, uah(exp), AppColors.text),
                      _total(tr.finBalance(''), uah(inc - exp),
                          inc - exp < 0 ? AppColors.danger : AppColors.text),
                      const SizedBox(height: 8),
                      for (final m in _months.reversed.where((m) => m.income > 0 || m.expense > 0))
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            Expanded(
                                child: Text(_byYears ? '${m.month}' : tr.monthNames[m.month],
                                    style: TextStyle(color: AppColors.text, fontSize: 16))),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('+${uah(m.income)}',
                                  style: TextStyle(color: AppColors.text, fontSize: 14)),
                              Text('−${uah(m.expense)}',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                            ]),
                          ]),
                        ),
                    ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _bar(double v, double maxV, Color c) => Expanded(
        child: FractionallySizedBox(
          heightFactor: maxV > 0 ? (v / maxV).clamp(0.0, 1.0) : 0,
          alignment: Alignment.bottomCenter,
          child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        ),
      );

  Widget _dot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]);

  Widget _total(String label, String value, Color c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label.trim(), style: TextStyle(color: AppColors.textMuted))),
          Text(value, style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      );
}
