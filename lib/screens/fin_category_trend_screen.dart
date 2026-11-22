import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/fin_analytics.dart';
import '../ui/common.dart';
import '../ui/fin_control_chart.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';

/// Одна категорія за рік: точка на кожен місяць, лінія процесу, середнє, медіана
/// й межі нормальності (середнє ± 2σ). Торкніться двох точок, щоб порівняти місяці.
class FinCategoryTrendScreen extends StatefulWidget {
  final Repository repo;

  /// Категорія (null - «внесено на складі»).
  final String? categoryId;

  /// [kFinExpense] чи [kFinIncome].
  final String kind;
  final int? year;
  const FinCategoryTrendScreen(
      {super.key, required this.repo, required this.categoryId, required this.kind, this.year});

  @override
  State<FinCategoryTrendScreen> createState() => _FinCategoryTrendScreenState();
}

class _FinCategoryTrendScreenState extends State<FinCategoryTrendScreen> {
  late int _year = widget.year ?? DateTime.now().year;
  List<FinEntry> _entries = const [];
  FinCategory? _cat;
  bool _loaded = false;
  // до двох обраних місяців (індекси 0..11), у порядку вибору
  final List<int> _picked = [];

  bool get _expense => widget.kind == kFinExpense;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo
        .listFinEntries(from: DateTime(_year, 1, 1), to: DateTime(_year + 1, 1, 1));
    final cats = await widget.repo.finCategoryMap();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _cat = widget.categoryId == null ? null : cats[widget.categoryId];
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() {
      _year += d;
      _picked.clear();
      _loaded = false;
    });
    _reload();
  }

  void _tap(int i) => setState(() {
        if (_picked.contains(i)) {
          _picked.remove(i);
        } else {
          if (_picked.length == 2) _picked.removeAt(0);
          _picked.add(i);
        }
      });

  String get _name =>
      widget.categoryId == null ? kFinStockCategoryName : (_cat?.name ?? tr.noCategory);

  @override
  Widget build(BuildContext context) {
    final color = finColor(_cat?.color ?? (widget.categoryId == null ? 'olive' : 'nut'));
    final months = finMonthsWithData(_year, DateTime.now());
    final all = finCategoryMonths(_entries, _year, widget.categoryId, kind: widget.kind);
    final values = all.take(months).toList();
    final stats = finControlStats(values);
    final total = values.fold(0.0, (a, b) => a + b);
    final shortMonths = [for (var m = 1; m <= 12; m++) tr.monthNames[m].substring(0, 3)];
    final sign = _expense ? '−' : '+';
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(
                title: '$_name · ${_expense ? tr.expenses.toLowerCase() : tr.incomes.toLowerCase()}',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                        decoration: BoxDecoration(
                            color: AppColors.card, borderRadius: BorderRadius.circular(20)),
                        child: Column(children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            IconButton(
                                onPressed: () => _shift(-1),
                                tooltip: tr.earlier,
                                icon: Icon(TablerIcons.chevron_left, color: AppColors.text)),
                            Text('$_year',
                                key: const ValueKey('trend-year'),
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            IconButton(
                                onPressed: _year < DateTime.now().year ? () => _shift(1) : null,
                                tooltip: tr.later,
                                icon: Icon(TablerIcons.chevron_right, color: AppColors.text)),
                          ]),
                          if (months == 0 || total == 0)
                            Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(tr.finNothingInPeriod,
                                  style: TextStyle(color: AppColors.textMuted)),
                            )
                          else ...[
                            FinControlChart(
                              values: values,
                              labels: shortMonths.take(months).toList(),
                              stats: stats,
                              color: color,
                              selected: _picked.where((i) => i < months).toSet(),
                              onTap: _tap,
                            ),
                            const SizedBox(height: 10),
                            Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 6, children: [
                              _dot(color, tr.finMonthDot),
                              _dot(AppColors.text, tr.finMean),
                              _line(tr.finMedian),
                              _dot(color.withValues(alpha: 0.45), tr.finNormalLimits),
                              if (stats.outside.isNotEmpty)
                                _dot(finColor('terra'), tr.finOutOfLimits),
                            ]),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      _total(total, months, sign),
                      if (months > 0 && total > 0) ...[
                        const SizedBox(height: 12),
                        _statsCard(stats, shortMonths),
                        if (_picked.length == 2) ...[
                          const SizedBox(height: 12),
                          _compare(all),
                        ],
                      ],
                    ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _total(double total, int months, String sign) {
    final avg = months > 0 ? total / months : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('$_name · ${tr.finCategoryByYear}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
          if (months > 0 && total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.darkBtn, borderRadius: BorderRadius.circular(12)),
              child: Text('${uah(avg)} ${tr.finPerMonth}',
                  style: TextStyle(color: AppColors.text, fontSize: 12.5)),
            ),
        ]),
        const SizedBox(height: 4),
        Text('$sign${uah(total)}',
            key: const ValueKey('trend-total'),
            style: TextStyle(
                color: _expense ? AppColors.text : finColor('olive'),
                fontSize: 30,
                fontWeight: FontWeight.w700)),
        if (months > 0 && total > 0 && _picked.length < 2) ...[
          const SizedBox(height: 4),
          Text(tr.finTapTwoPoints, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ]),
    );
  }

  Widget _statsCard(FinControlStats s, List<String> short) {
    Widget item(String label, String v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 2),
            Text(v,
                style: TextStyle(
                    color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        );
    return Container(
      key: const ValueKey('trend-stats'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          item(tr.finMean, uah(s.mean)),
          item(tr.finMedian, uah(s.median)),
        ]),
        const SizedBox(height: 12),
        Row(children: [item(tr.finNormalLimits, '${uah(s.low)} … ${uah(s.high)}')]),
        const SizedBox(height: 10),
        Text(
            s.outside.isEmpty
                ? tr.finAllInRange
                : '${tr.finOutOfLimits}: ${s.outside.map((i) => tr.monthNames[i + 1].toLowerCase()).join(', ')}.',
            key: const ValueKey('trend-outside'),
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]),
    );
  }

  Widget _compare(List<double> all) {
    final a = _picked[0], b = _picked[1];
    // порівнюємо раніший місяць із пізнішим
    final first = a < b ? a : b, second = a < b ? b : a;
    final diff = all[second] - all[first];
    final pct = all[first] > 0 ? (diff / all[first] * 100).round() : null;
    // для витрат ріст - погано (червоний), для доходів - добре
    final good = _expense ? diff <= 0 : diff >= 0;
    final c = diff == 0 ? AppColors.textMuted : (good ? finColor('olive') : finColor('terra'));
    Widget cell(int i) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.monthNames[i + 1],
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 2),
              Text(uah(all[i]),
                  style: TextStyle(
                      color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return Column(key: const ValueKey('trend-compare'), children: [
      Row(children: [cell(first), const SizedBox(width: 10), cell(second)]),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
            '${diff > 0 ? '▲' : (diff < 0 ? '▼' : '=')} ${uah(diff.abs())}'
            '${pct == null ? '' : ' (${diff >= 0 ? '+' : '−'}${pct.abs()}%)'}',
            style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  Widget _dot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]);

  Widget _line(String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('┈', style: TextStyle(color: AppColors.text, fontSize: 14)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]);
}
