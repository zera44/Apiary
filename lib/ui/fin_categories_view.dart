import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/fin_analytics.dart';
import '../logic/fin_period.dart';
import '../screens/fin_category_trend_screen.dart';
import 'fin_period_card.dart';
import 'fin_slices.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Вкладка «Категорії» у статистиці: розподіл витрат чи доходів за період.
/// До шести категорій - усі своїм кольором; більше - ті, що дають 80%, а решта
/// зведена в сіре «Інше». Торкнутися категорії - її динаміка за рік (карта контролю).
class FinCategoriesView extends StatefulWidget {
  final Repository repo;
  const FinCategoriesView({super.key, required this.repo});

  @override
  State<FinCategoriesView> createState() => _FinCategoriesViewState();
}

class _FinCategoriesViewState extends State<FinCategoriesView> {
  final _sel = FinPeriodSel(period: FinPeriod.month, anchor: DateTime(DateTime.now().year, DateTime.now().month, 1));
  bool _expense = true;
  bool _restOpen = false;
  List<FinEntry> _entries = const [];
  Map<String, FinCategory> _cats = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final (f, t) = _sel.range;
    final list = await widget.repo.listFinEntries(from: f, to: t);
    final cats = await widget.repo.finCategoryMap();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _cats = cats;
      _loaded = true;
    });
  }

  void _select(FinPeriod p) {
    if (p == FinPeriod.custom) {
      _custom();
      return;
    }
    setState(() {
      _sel.select(p);
      _restOpen = false;
    });
    _reload();
  }

  void _shift(int d) {
    if (!_sel.shift(d)) return;
    setState(() => _restOpen = false);
    _reload();
  }

  Future<void> _custom() async {
    final (f, t) = _sel.range;
    final r = await showFinCustomPeriod(context,
        from: f,
        to: DateTime(t.year, t.month, t.day - 1),
        load: (a, b) => widget.repo.listFinEntries(from: a, to: b));
    if (r == null || !mounted) return;
    setState(() {
      _sel.setCustom(r.$1, r.$2);
      _restOpen = false;
    });
    _reload();
  }

  void _openCategory(FinSlice s) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FinCategoryTrendScreen(
            repo: widget.repo,
            categoryId: s.key,
            kind: _expense ? kFinExpense : kFinIncome,
            year: _sel.lastDay.year)));
  }

  @override
  Widget build(BuildContext context) {
    final sum = FinSummary.of(_entries);
    final by = _expense ? sum.expenseByCategory : sum.incomeByCategory;
    final slices = finParetoSlices(by);
    final total = slices.fold(0.0, (a, s) => a + s.amount);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      FinPeriodCard(
          sel: _sel,
          onSelect: _select,
          onShift: _shift,
          onCustomTap: _custom),
      const SizedBox(height: 12),
      FinSegment(
        labels: [tr.expenses, tr.income],
        selected: _expense ? 0 : 1,
        onChanged: (i) => setState(() {
          _expense = i == 0;
          _restOpen = false;
        }),
      ),
      const SizedBox(height: 12),
      if (!_loaded)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else if (slices.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text(tr.finNothingInPeriod, style: TextStyle(color: AppColors.textMuted))),
        )
      else ...[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_expense ? tr.expenses : tr.incomes,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 2),
            Text('${_expense ? '−' : '+'}${uah(total)}',
                key: const ValueKey('cats-total'),
                style: TextStyle(
                    color: _expense ? AppColors.text : finColor('olive'),
                    fontSize: 30,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FinSliceBar(slices: slices, cats: _cats),
          ]),
        ),
        const SizedBox(height: 12),
        for (final s in slices)
          if (s.isRest) ...[
            FinSliceRow(
                key: const ValueKey('cats-rest'),
                slice: s,
                total: total,
                cats: _cats,
                expense: _expense,
                onTap: () => setState(() => _restOpen = !_restOpen)),
            if (_restOpen)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration:
                    BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  for (final m in finRestMembers(by, slices))
                    FinSliceRow(
                        slice: m,
                        total: total,
                        cats: _cats,
                        expense: _expense,
                        dense: true,
                        onTap: () => _openCategory(m)),
                ]),
              ),
          ] else
            FinSliceRow(
                key: ValueKey('cats-row-${s.key}'),
                slice: s,
                total: total,
                cats: _cats,
                expense: _expense,
                onTap: () => _openCategory(s)),
      ],
    ]);
  }
}
