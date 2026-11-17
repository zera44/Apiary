import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/nav_drawer.dart';
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
  List<FinEntry> _entries = const [];
  Map<String, FinCategory> _cats = const {};
  bool _loaded = false;

  // обраний стовпчик: індекс місяця й ряд (0 дохід, 1 витрати, 2 прибуток/збитки)
  int? _selM;
  int? _selS;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.listFinEntries(
        from: _byYears ? DateTime(1970) : DateTime(_year, 1, 1),
        to: DateTime(_byYears ? DateTime.now().year + 2 : _year + 1, 1, 1));
    final cats = await widget.repo.finCategoryMap();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _cats = cats;
      _months = _byYears ? finYearlyTotals(list) : finMonthlyTotals(list, _year);
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() {
      _year += d;
      _selM = _selS = null;
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
                labels: [tr.finByYears, tr.finByMonths],
                selected: _byYears ? 0 : 1,
                onChanged: (i) {
                  setState(() {
                    _byYears = i == 0;
                    _selM = _selS = null;
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
                                icon: Icon(TablerIcons.chevron_left, color: AppColors.text)),
                            Text('$_year',
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            IconButton(
                                onPressed: () => _shift(1),
                                tooltip: tr.later,
                                icon: Icon(TablerIcons.chevron_right, color: AppColors.text)),
                          ]),
                          SizedBox(
                            height: 220,
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (var mi = 0; mi < _months.length; mi++)
                                    Expanded(
                                      child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    _bar(mi, 0, _months[mi].income, maxV, green),
                                                    _bar(mi, 1, _months[mi].expense, maxV, yellow),
                                                    // третій стовпчик: прибуток, а коли витрати більші - збитки
                                                    _bar(mi, 2, _months[mi].balance.abs(), maxV,
                                                        _months[mi].balance >= 0 ? profit : loss),
                                                  ]),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(_byYears ? '${_months[mi].month}' : tr.monthNames[_months[mi].month].substring(0, 3),
                                                style: TextStyle(
                                                    color: _selM == null || _selM == mi
                                                        ? AppColors.textMuted
                                                        : AppColors.textMuted.withValues(alpha: 0.5),
                                                    fontSize: 10,
                                                    fontWeight: _selM == mi ? FontWeight.w700 : FontWeight.w400)),
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
                      if (_selM != null) ..._selected() else
                      for (final m in _months.reversed.where((m) => m.income > 0 || m.expense > 0))
                        _monthCard(m),
                    ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  /// Стовпчик, який можна торкнутися: він підсвічується, решта тьмяніє,
  /// над ним - плашка із сумою; повторний дотик знімає вибір.
  Widget _bar(int mi, int series, double v, double maxV, Color c) {
    final sel = _selM == mi && _selS == series;
    final dim = _selM != null && !sel;
    final factor = maxV > 0 ? (v / maxV).clamp(0.0, 1.0) : 0.0;
    final m = _months[mi];
    final tip = series == 2 && m.balance < 0 ? '−${uah(v)}' : uah(v);
    return Expanded(
      child: GestureDetector(
        key: ValueKey('stat-bar-$mi-$series'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          if (sel) {
            _selM = _selS = null;
          } else {
            _selM = mi;
            _selS = series;
          }
        }),
        child: LayoutBuilder(builder: (context, box) {
          final h = box.maxHeight * factor;
          return Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: h,
              child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                      color: dim ? c.withValues(alpha: 0.4) : c,
                      borderRadius: BorderRadius.circular(2))),
            ),
            if (sel)
              Positioned(
                left: -60,
                right: -60,
                bottom: h + 6,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.text, borderRadius: BorderRadius.circular(8)),
                    child: Text(tip,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            color: AppColors.bg, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }

  Widget _monthCard(FinMonthTotal m) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
              child: Text(_byYears ? '${m.month}' : tr.monthNames[m.month],
                  style: TextStyle(color: AppColors.text, fontSize: 16))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('+${uah(m.income)}', style: TextStyle(color: AppColors.text, fontSize: 14)),
            Text('−${uah(m.expense)}', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ]),
        ]),
      );

  /// Розбивка за категоріями для обраного стовпчика (дохід або витрати цього
  /// місяця чи року); для «прибутку» - підсумок місяця.
  List<Widget> _selected() {
    final m = _months[_selM!];
    final series = _selS!;
    final title = _byYears ? '${m.month}' : '${tr.monthNames[m.month]} $_year';
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Text(title,
          style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
    );
    if (series == 2) return [head, _monthCard(m)];
    final inPeriod = _entries.where((e) => _byYears
        ? e.date.year == m.month
        : e.date.year == _year && e.date.month == m.month);
    final sum = FinSummary.of(inPeriod);
    final by = series == 0 ? sum.incomeByCategory : sum.expenseByCategory;
    final items = by.entries.where((e) => e.value > 0.0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = items.fold(0.0, (a, e) => a + e.value);
    return [
      head,
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
              child: Text(tr.finNothingInPeriod, style: TextStyle(color: AppColors.textMuted))),
        ),
      for (final e in items)
        Builder(builder: (context) {
          final c = e.key == null ? null : _cats[e.key];
          final pct = total > 0 ? (e.value / total * 100).round() : 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration:
                BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              e.key == null
                  ? const FinBadge(icon: 'home', color: 'olive', size: 40)
                  : FinBadge(icon: c?.icon ?? 'other', color: c?.color ?? 'nut', size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(e.key == null ? kFinStockCategoryName : (c?.name ?? tr.noCategory),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 16)),
              ),
              const SizedBox(width: 8),
              Text('$pct%', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(width: 12),
              Text(uah(e.value), style: TextStyle(color: AppColors.text, fontSize: 16)),
            ]),
          );
        }),
    ];
  }

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
