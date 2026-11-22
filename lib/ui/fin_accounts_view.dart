import 'package:flutter/material.dart';

import '../data/fin_accounts.dart';
import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/fin_analytics.dart';
import '../logic/fin_period.dart';
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

/// Вкладка «Рахунки» у статистиці: дохід і витрати кожного рахунку за період.
/// Торкнутися рахунку - розподіл його витрат за категоріями. Перекази між
/// рахунками показані окремим рядком і не рахуються ні доходом, ні витратою.
class FinAccountsView extends StatefulWidget {
  final Repository repo;
  const FinAccountsView({super.key, required this.repo});

  @override
  State<FinAccountsView> createState() => _FinAccountsViewState();
}

class _FinAccountsViewState extends State<FinAccountsView> {
  final _sel = FinPeriodSel(period: FinPeriod.month, anchor: DateTime(DateTime.now().year, DateTime.now().month, 1));
  List<FinEntry> _entries = const [];
  List<FinAccount> _accounts = const [];
  List<FinTransfer> _transfers = const [];
  Map<String, FinCategory> _cats = const {};
  Map<String, double> _rates = const {kFinUah: 1};
  String? _open;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final (f, t) = _sel.range;
    final repo = widget.repo;
    final list = await repo.listFinEntries(from: f, to: t);
    final accounts = await repo.listFinAccounts();
    final transfers = await repo.listFinTransfers(from: f, to: t);
    final cats = await repo.finCategoryMap();
    final rates = await repo.finRates();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _accounts = accounts;
      _transfers = transfers;
      _cats = cats;
      _rates = rates;
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
      _open = null;
    });
    _reload();
  }

  void _shift(int d) {
    if (!_sel.shift(d)) return;
    setState(() => _open = null);
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
      _open = null;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final all = FinSummary.of(_entries);
    final byAccount = <String, List<FinEntry>>{};
    for (final e in _entries) {
      final a = e.accountId;
      if (a != null) byAccount.putIfAbsent(a, () => []).add(e);
    }
    final rows = <(FinAccount, FinSummary)>[
      for (final a in _accounts)
        if (byAccount.containsKey(a.id)) (a, FinSummary.of(byAccount[a.id]!))
    ];
    final maxV = rows.fold(
        1.0, (m, r) => [m, r.$2.income, r.$2.expense].reduce((x, y) => x > y ? x : y));
    final trans = finTransfersTotal(_transfers, {for (final a in _accounts) a.id: a}, _rates);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      FinPeriodCard(sel: _sel, onSelect: _select, onShift: _shift, onCustomTap: _custom),
      const SizedBox(height: 12),
      if (!_loaded)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else if (all.income == 0 && all.expense == 0 && _transfers.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text(tr.finNothingInPeriod, style: TextStyle(color: AppColors.textMuted))),
        )
      else ...[
        FinSummaryCard(income: all.income, expense: all.expense),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Text(tr.finAccountSplitHint,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        for (final r in rows) ...[
          _accountCard(r.$1, r.$2, maxV),
          if (_open == r.$1.id) _split(r.$1, r.$2),
        ],
        if (_transfers.isNotEmpty)
          Container(
            key: const ValueKey('acc-transfers'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tr.finTransfersBetween}: ${uah(trans)}',
                  style: TextStyle(
                      color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(tr.finTransfersNote,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ]),
          ),
      ],
    ]);
  }

  Widget _bar(double v, double maxV, Color c) => Container(
        height: 6,
        decoration: BoxDecoration(
            color: AppColors.darkBtn, borderRadius: BorderRadius.circular(3)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (v / maxV).clamp(0.0, 1.0),
          child: Container(
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        ),
      );

  Widget _accountCard(FinAccount a, FinSummary s, double maxV) {
    final net = s.balance;
    final c = net >= 0 ? finColor('sky') : finColor('terra');
    final open = _open == a.id;
    return Container(
      key: ValueKey('acc-${a.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open = open ? null : a.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FinBadge(icon: a.icon, color: a.color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name,
                      style: TextStyle(
                          color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _bar(s.expense, maxV, finColor('honey'))),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 84,
                        child: Text(s.expense > 0 ? '−${uah(s.expense)}' : uah(0),
                            textAlign: TextAlign.right,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _bar(s.income, maxV, finColor('olive'))),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 84,
                        child: Text(s.income > 0 ? '+${uah(s.income)}' : uah(0),
                            textAlign: TextAlign.right,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${net > 0 ? '+' : ''}${uah(net)}',
                    style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w700)),
                Text(net >= 0 ? tr.finProfit : tr.finLossOne,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// Розподіл витрат рахунку за категоріями: смуга й рядки.
  Widget _split(FinAccount a, FinSummary s) {
    final slices = finParetoSlices(s.expenseByCategory);
    final total = slices.fold(0.0, (x, y) => x + y.amount);
    return Container(
      key: ValueKey('acc-split-${a.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: slices.isEmpty
          ? Text(tr.finNothingInPeriod, style: TextStyle(color: AppColors.textMuted))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tr.finSplitOf} · ${a.name}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 10),
              FinSliceBar(slices: slices, cats: _cats),
              const SizedBox(height: 8),
              for (final sl in slices)
                FinSliceRow(slice: sl, total: total, cats: _cats, expense: true, dense: true),
            ]),
    );
  }
}
