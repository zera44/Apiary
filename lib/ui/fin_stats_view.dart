import 'package:flutter/material.dart';

import '../data/fin_accounts.dart';
import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/fin_analytics.dart';
import '../logic/fin_period.dart';
import '../logic/fin_series.dart';
import '../screens/fin_category_trend_screen.dart';
import 'fin_control_chart.dart';
import 'fin_period_card.dart';
import 'fin_slices.dart';
import 'fin_style.dart';
import 'fin_summary_card.dart';
import 'theme.dart';

/// Скільки гривень становлять усі перекази за період (кожен у валюті рахунку-джерела).
double finTransfersTotal(
    Iterable<FinTransfer> transfers, Map<String, FinAccount> accounts, Map<String, double> rates) {
  var sum = 0.0;
  for (final t in transfers) {
    final cur = accounts[t.fromId]?.currency ?? kFinUah;
    sum += t.amount * (rates[cur] ?? 1);
  }
  return sum;
}

/// Статистика за однією логікою для вкладок «Категорії» ([byAccount] = false) і
/// «Рахунки»: період, лінія за точками (результат, витрати чи дохід) із середнім
/// і межами ±2σ, під нею картка й рядки розподілу. Торкнутися рядка - лінія
/// показує лише його, повторно (для категорії) - її динаміка за рік.
class FinStatsView extends StatefulWidget {
  final Repository repo;
  final FinPeriodSel sel;
  final bool byAccount;
  const FinStatsView({super.key, required this.repo, required this.sel, required this.byAccount});

  @override
  State<FinStatsView> createState() => _FinStatsViewState();
}

class _FinStatsViewState extends State<FinStatsView> {
  FinStatKind _kind = FinStatKind.result;

  /// Обраний рядок (категорія чи рахунок); id може бути null - «внесено на складі».
  ({String? id})? _picked;
  bool _restOpen = false;
  List<FinEntry> _entries = const [];
  List<FinAccount> _accounts = const [];
  List<FinTransfer> _transfers = const [];
  Map<String, FinCategory> _cats = const {};
  Map<String, double> _rates = const {kFinUah: 1};
  bool _loaded = false;
  int _seq = 0;

  /// Де стоїть вікно точок (тижні, роки); null - біля найновішого.
  int? _start;

  /// Найраніша дата з даними (межа гортання назад).
  DateTime? _earliest;

  FinPeriodSel get _sel => widget.sel;

  /// Вікно точок; його місце запам'ятовуємо, щоб воно зсувалося лише біля краю.
  FinWindow _window() {
    final w = finWindow(_sel, earliest: _earliest, start: _start);
    _start = w.start;
    return w;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final id = ++_seq;
    final (f, t) = _sel.range;
    final repo = widget.repo;
    // усі записи: з них видно, наскільки далеко назад є дані
    final list = await repo.listFinEntries(
        from: DateTime(1970), to: DateTime(DateTime.now().year + 2));
    final accounts = await repo.listFinAccounts();
    final transfers = await repo.listFinTransfers(from: f, to: t);
    final cats = await repo.finCategoryMap();
    final rates = await repo.finRates();
    if (!mounted || id != _seq) return;
    setState(() {
      _entries = list;
      DateTime? first;
      for (final e in list) {
        if (e.cancelled || e.noStats) continue;
        if (first == null || e.date.isBefore(first)) first = e.date;
      }
      _earliest = first;
      _accounts = accounts;
      _transfers = transfers;
      _cats = cats;
      _rates = rates;
      _loaded = true;
    });
  }

  void _changed() {
    setState(() => _restOpen = false);
    _reload();
  }

  void _select(FinPeriod p) {
    if (p == FinPeriod.custom) {
      _custom();
      return;
    }
    _sel.select(p);
    _start = null;
    _changed();
  }

  void _shift(int d) {
    if (_sel.shift(d)) _changed();
  }

  Future<void> _custom() async {
    final (f, t) = _sel.range;
    final r = await showFinCustomPeriod(context,
        from: f,
        to: DateTime(t.year, t.month, t.day - 1),
        load: (a, b) => widget.repo.listFinEntries(from: a, to: b));
    if (r == null || !mounted) return;
    _sel.setCustom(r.$1, r.$2);
    _start = null;
    _changed();
  }

  /// Дотик до точки лінії - перейти до її місяця, тижня чи року.
  void _tapPoint(FinWindow w, int i) {
    if (i < 0 || i >= w.buckets.length) return;
    final from = w.buckets[i].from;
    switch (_sel.period) {
      case FinPeriod.month:
        _sel.anchor = DateTime(from.year, from.month, 1);
      case FinPeriod.week:
      case FinPeriod.day:
        _sel.anchor = from;
      case FinPeriod.year:
        _sel.anchor = DateTime(from.year, 1, 1);
      case FinPeriod.custom:
        return;
    }
    _changed();
  }

  String? _key(FinEntry e) => widget.byAccount ? e.accountId : e.categoryId;

  void _setKind(FinStatKind k) => setState(() {
        _kind = k;
        _picked = null;
        _restOpen = false;
      });

  void _pick(String? id) => setState(() => _picked = _picked != null && _picked!.id == id ? null : (id: id));

  Color get _lineColor => switch (_kind) {
        FinStatKind.result => finColor('sky'),
        FinStatKind.expense => finColor('honey'),
        FinStatKind.income => finColor('olive'),
      };

  String _pickedName() {
    final id = _picked!.id;
    if (widget.byAccount) {
      for (final a in _accounts) {
        if (a.id == id) return a.name;
      }
      return '';
    }
    return id == null ? kFinStockCategoryName : (_cats[id]?.name ?? tr.noCategory);
  }

  @override
  Widget build(BuildContext context) {
    final (f, t) = _sel.range;
    final inPeriod = _entries.where((e) => !e.date.isBefore(f) && e.date.isBefore(t)).toList();
    final sum = FinSummary.of(inPeriod);
    final w = _window();
    final values = finSeries(
        _entries, w.buckets, _kind,
        where: _picked == null ? null : (e) => _key(e) == _picked!.id);
    final stats = finControlStats(values, allowNegative: _kind == FinStatKind.result);
    final hasData = _entries.any((e) => !e.cancelled && !e.noStats);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      FinPeriodCard(
          sel: _sel,
          periods: const [FinPeriod.week, FinPeriod.month, FinPeriod.year, FinPeriod.custom],
          onSelect: _select,
          onShift: _shift,
          canGoBack: _earliest == null || _sel.range.$1.isAfter(_earliest!),
          onCustomTap: _custom),
      const SizedBox(height: 12),
      FinSegment(
        key: const ValueKey('stat-kind'),
        labels: [tr.finResult, tr.expenses, tr.income],
        selected: _kind.index,
        onChanged: (i) => _setKind(FinStatKind.values[i]),
      ),
      const SizedBox(height: 12),
      if (!_loaded)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else if (!hasData && _transfers.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text(tr.finNothingInPeriod, style: TextStyle(color: AppColors.textMuted))),
        )
      else ...[
        _chartCard(w, values, stats),
        const SizedBox(height: 12),
        ..._block(inPeriod, sum),
        if (widget.byAccount && _transfers.isNotEmpty) _transfersRow(),
      ],
    ]);
  }

  Widget _chartCard(FinWindow w, List<double> values, FinControlStats stats) {
    Widget item(Key k, String label, String v, CrossAxisAlignment a) => Expanded(
          child: Column(crossAxisAlignment: a, children: [
            Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 2),
            Text(v,
                key: k,
                style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_picked != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text(_pickedName(),
                key: const ValueKey('stat-picked'),
                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        FinControlChart(
          values: values,
          labels: [for (final b in w.buckets) b.label],
          stats: stats,
          color: _lineColor,
          signed: _kind == FinStatKind.result,
          height: 230,
          selected: w.selected == null ? const {} : {w.selected!},
          onTap: (i) => _tapPoint(w, i),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            item(const ValueKey('stat-mean'), tr.finMean, uah(stats.mean), CrossAxisAlignment.start),
            item(const ValueKey('stat-limits'), '${tr.finNormalLimits} ±2σ',
                '${uah(stats.low)} … ${uah(stats.high)}', CrossAxisAlignment.end),
          ]),
        ),
      ]),
    );
  }

  /// Картка й рядки під лінією - для самого вибраного періоду.
  List<Widget> _block(List<FinEntry> inPeriod, FinSummary sum) {
    if (_kind == FinStatKind.result) {
      return [
        FinSummaryCard(income: sum.income, expense: sum.expense, showTotals: false),
        const SizedBox(height: 12),
        if (widget.byAccount) ..._accountResultRows(inPeriod) else ...[
          _kindRow(FinStatKind.income, sum.income),
          _kindRow(FinStatKind.expense, sum.expense),
        ],
      ];
    }
    final expense = _kind == FinStatKind.expense;
    final by = widget.byAccount
        ? _byAccount(inPeriod, expense)
        : (expense ? sum.expenseByCategory : sum.incomeByCategory);
    final slices = widget.byAccount
        ? (by.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value)))
            .map((e) => FinSlice(e.key, e.value))
            .toList()
        : finParetoSlices(by);
    final total = slices.fold(0.0, (a, s) => a + s.amount);
    if (slices.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text(tr.finNothingInPeriod, style: TextStyle(color: AppColors.textMuted))),
        )
      ];
    }
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(expense ? tr.expenses : tr.incomes,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 2),
          Text('${expense ? '−' : '+'}${uah(total)}',
              key: const ValueKey('cats-total'),
              style: TextStyle(
                  color: expense ? AppColors.text : finColor('olive'),
                  fontSize: 30,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (widget.byAccount)
            _accountBar(slices)
          else
            FinSliceBar(slices: slices, cats: _cats),
        ]),
      ),
      const SizedBox(height: 12),
      for (final s in slices)
        if (widget.byAccount)
          _accountSliceRow(s, total, expense)
        else if (s.isRest) ...[
          Opacity(
            opacity: _dimRest(by, slices) ? 0.45 : 1,
            child: FinSliceRow(
                key: const ValueKey('cats-rest'),
                slice: s,
                total: total,
                cats: _cats,
                expense: expense,
                onTap: () => setState(() => _restOpen = !_restOpen)),
          ),
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
                      expense: expense,
                      dense: true,
                      onTap: () => _tapCategory(m)),
              ]),
            ),
        ] else
          Opacity(
            opacity: _picked != null && _picked!.id != s.key ? 0.45 : 1,
            child: FinSliceRow(
                key: ValueKey('cats-row-${s.key}'),
                slice: s,
                total: total,
                cats: _cats,
                expense: expense,
                onTap: () => _tapCategory(s)),
          ),
    ];
  }

  bool _dimRest(Map<String?, double> by, List<FinSlice> slices) =>
      _picked != null && !finRestMembers(by, slices).any((m) => m.key == _picked!.id);

  /// Перший дотик до категорії - лінія лише про неї, другий - її динаміка за рік.
  void _tapCategory(FinSlice s) {
    if (_picked != null && _picked!.id == s.key) {
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => FinCategoryTrendScreen(
              repo: widget.repo,
              categoryId: s.key,
              kind: _kind == FinStatKind.expense ? kFinExpense : kFinIncome,
              year: _sel.lastDay.year)));
      return;
    }
    _pick(s.key);
  }

  Map<String?, double> _byAccount(List<FinEntry> inPeriod, bool expense) {
    final out = <String?, double>{};
    for (final e in inPeriod) {
      if (e.cancelled || e.noStats || e.accountId == null || e.isExpense != expense) continue;
      out[e.accountId] = (out[e.accountId] ?? 0) + e.amount;
    }
    return out;
  }

  /// Рядок «Дохід» / «Витрати» під карткою результату: торкнутися - показати їх.
  Widget _kindRow(FinStatKind k, double amount) {
    final expense = k == FinStatKind.expense;
    final color = expense ? finColor('honey') : finColor('olive');
    return Container(
      key: ValueKey('stat-kind-${k.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _setKind(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(expense ? tr.expenses : tr.income,
                      style: TextStyle(color: AppColors.text, fontSize: 16))),
              Text(amount > 0 ? '${expense ? '−' : '+'}${uah(amount)}' : uah(0),
                  style: TextStyle(
                      color: expense ? AppColors.text : finColor('olive'), fontSize: 16)),
            ]),
          ),
        ),
      ),
    );
  }

  FinAccount? _account(String? id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Widget _accountBar(List<FinSlice> slices) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 22,
          child: Row(children: [
            for (var i = 0; i < slices.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (slices[i].amount * 100).round().clamp(1, 1 << 30),
                child: Container(color: finColor(_account(slices[i].key)?.color ?? 'nut')),
              ),
            ],
          ]),
        ),
      );

  Widget _accountRowShell(FinAccount a, Widget content) {
    final dim = _picked != null && _picked!.id != a.id;
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Container(
        key: ValueKey('acc-${a.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _pick(a.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                FinBadge(icon: a.icon, color: a.color, size: 40),
                const SizedBox(width: 12),
                Expanded(child: content),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountSliceRow(FinSlice s, double total, bool expense) {
    final a = _account(s.key);
    if (a == null) return const SizedBox.shrink();
    final pct = total > 0 ? (s.amount / total * 100).round() : 0;
    return _accountRowShell(
        a,
        Row(children: [
          Expanded(
              child: Text(a.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 16))),
          const SizedBox(width: 8),
          Text('$pct%', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(width: 12),
          Text('${expense ? '−' : '+'}${uah(s.amount)}',
              style: TextStyle(color: AppColors.text, fontSize: 16)),
        ]));
  }

  /// Рахунки в режимі «Результат»: підсумок кожного, а під ним «+дохід · −витрати».
  List<Widget> _accountResultRows(List<FinEntry> inPeriod) {
    final byAcc = <String, List<FinEntry>>{};
    for (final e in inPeriod) {
      final a = e.accountId;
      if (a != null) byAcc.putIfAbsent(a, () => []).add(e);
    }
    return [
      for (final a in _accounts)
        if (byAcc.containsKey(a.id))
          () {
            final s = FinSummary.of(byAcc[a.id]!);
            final net = s.balance;
            final c = net >= 0 ? finColor('sky') : finColor('terra');
            return _accountRowShell(
                a,
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name,
                          style: TextStyle(
                              color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('+${uah(s.income)} · −${uah(s.expense)}',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text('${net > 0 ? '+' : ''}${uah(net)}',
                      style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w700)),
                ]));
          }(),
    ];
  }

  Widget _transfersRow() {
    final trans = finTransfersTotal(_transfers, {for (final a in _accounts) a.id: a}, _rates);
    return Container(
      key: const ValueKey('acc-transfers'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${tr.finTransfersBetween}: ${uah(trans)}',
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(tr.finTransfersNote, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]),
    );
  }
}
