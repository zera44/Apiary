import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import 'fin_add_screen.dart';
import 'fin_category_screen.dart';

DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

/// Рядок журналу: значок категорії, що й на скільки, дата, сума.
class FinEntryTile extends StatelessWidget {
  final FinEntry entry;
  final Map<String, FinCategory> cats;
  final VoidCallback onTap;
  const FinEntryTile({super.key, required this.entry, required this.cats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = entry.categoryId == null ? null : cats[entry.categoryId];
    final name = entry.fromStock ? kFinStockCategoryName : (c?.name ?? 'Без категорії');
    final muted = entry.cancelled;
    final sign = entry.isExpense ? '−' : '+';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Opacity(
            opacity: muted ? 0.4 : 1,
            child: entry.fromStock
                ? const FinBadge(icon: 'home', color: 'olive')
                : FinBadge(icon: c?.icon ?? 'other', color: c?.color ?? 'nut'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: TextStyle(
                      color: muted ? AppColors.textMuted : AppColors.text,
                      fontSize: 15,
                      decoration: muted ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 2),
              Text(
                  [
                    finDay(entry.date),
                    if (entry.title.isNotEmpty) entry.title,
                    if (muted) 'скасовано',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Text('$sign${uah(entry.amount)}',
              style: TextStyle(
                  color: finAmountColor(entry),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  decoration: muted ? TextDecoration.lineThrough : null)),
        ]),
      ),
    );
  }
}

/// Відкрити запис журналу: деталі й «Скасувати запис» (на складі теж).
/// Повертає true, якщо щось змінилось.
Future<bool> openFinEntry(BuildContext context, Repository repo, FinEntry e,
    Map<String, FinCategory> cats) async {
  final c = e.categoryId == null ? null : cats[e.categoryId];
  final name = e.fromStock ? kFinStockCategoryName : (c?.name ?? 'Без категорії');
  final what = e.title.isEmpty ? '' : '\n${e.title}';
  final text = '$name · ${e.isExpense ? 'витрата' : 'дохід'} ${uah(e.amount)}\n'
      '${finDay(e.date)}$what'
      '${e.fromStock ? '\n\nПрихід внесено на складі. Скасування тут скасує його й на складі.' : ''}'
      '${!e.fromStock && e.lineCount > 0 ? '\n\nСкасування скасує й приходи цієї операції на складі.' : ''}';
  if (e.cancelled) {
    await showInfo(context, '$text\n\nЦей запис скасовано.', title: 'Запис');
    return false;
  }
  final ok = await showConfirm(context,
      title: 'Запис', text: text, confirmText: 'Скасувати запис', cancelText: 'Закрити');
  if (!ok || !context.mounted) return false;
  try {
    await repo.cancelFinEntry(e);
    return true;
  } on StateError catch (err) {
    if (context.mounted) await showInfo(context, err.message, title: 'Не скасовано');
    return false;
  } catch (err) {
    if (context.mounted) await showInfo(context, '$err', title: 'Не скасовано');
    return false;
  }
}

/// Розподіл за категоріями: значок, назва, сума, частка смужкою.
class FinBreakdown extends StatelessWidget {
  final Map<String?, double> byCategory;
  final Map<String, FinCategory> cats;
  final void Function(FinCategory)? onCategory;
  const FinBreakdown({super.key, required this.byCategory, required this.cats, this.onCategory});

  @override
  Widget build(BuildContext context) {
    final items = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = items.fold(0.0, (a, e) => a + e.value);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Поки порожньо', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(children: [
      for (final e in items)
        Builder(builder: (_) {
          final c = e.key == null ? null : cats[e.key];
          final share = total > 0 ? e.value / total : 0.0;
          return InkWell(
            onTap: c != null && onCategory != null ? () => onCategory!(c) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                e.key == null
                    ? const FinBadge(icon: 'home', color: 'olive', size: 34)
                    : FinBadge(icon: c?.icon ?? 'other', color: c?.color ?? 'nut', size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(e.key == null ? kFinStockCategoryName : (c?.name ?? 'Без категорії'),
                            style: TextStyle(color: AppColors.text, fontSize: 14.5)),
                      ),
                      Text(uah(e.value), style: TextStyle(color: AppColors.text, fontSize: 14.5)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 5,
                        backgroundColor: AppColors.darkBtn,
                        color: finColor(c?.color ?? 'olive'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        }),
    ]);
  }
}

class _MonthBar extends StatelessWidget {
  final String title;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthBar({required this.title, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            onPressed: onPrev, icon: Icon(Icons.chevron_left, color: AppColors.text), tooltip: 'Раніше'),
        SizedBox(
          width: 170,
          child: Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        IconButton(
            onPressed: onNext, icon: Icon(Icons.chevron_right, color: AppColors.text), tooltip: 'Пізніше'),
      ]);
}

/// Фінанси: огляд місяця. Вхід у процес - кнопки «Витрата» і «Дохід».
class FinanceScreen extends StatefulWidget {
  final Repository repo;
  const FinanceScreen({super.key, required this.repo});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  DateTime _month = _firstOfMonth(DateTime.now());
  List<FinEntry> _entries = [];
  Map<String, FinCategory> _cats = {};
  bool _loaded = false;

  Repository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    repo.stockChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    repo.stockChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final cats = await repo.finCategoryMap();
    final list = await repo.listFinEntries(from: _month, to: DateTime(_month.year, _month.month + 1));
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _entries = list;
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() => _month = DateTime(_month.year, _month.month + d));
    _reload();
  }

  Future<void> _add(String kind) async {
    final msg = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => FinAddScreen(repo: repo, kind: kind)));
    if (!mounted) return;
    await _reload();
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _editCategory(FinCategory c) async {
    await Navigator.of(context).push(
        MaterialPageRoute<String>(builder: (_) => FinCategoryScreen(repo: repo, category: c)));
    await _reload();
  }

  Widget _stat(String label, double v, Color color) => Expanded(
        child: Column(children: [
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(uah(v),
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = FinSummary.of(_entries);
    final recent = _entries.take(5).toList();
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(
              title: 'Фінанси',
              onBack: () => Navigator.pop(context),
              trailing: IconButton(
                tooltip: 'Підсумок сезону',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.insights_outlined, color: AppColors.text),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => FinSeasonScreen(repo: repo))),
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
                      _MonthBar(
                          title: finMonthTitle(_month), onPrev: () => _shift(-1), onNext: () => _shift(1)),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                            color: AppColors.card, borderRadius: BorderRadius.circular(18)),
                        child: Row(children: [
                          _stat('Витрати', s.expense, AppColors.text),
                          _stat('Доходи', s.income, AppColors.grass),
                          _stat('Баланс', s.balance,
                              s.balance < 0 ? AppColors.danger : AppColors.create),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Text('Витрати за категоріями',
                          style: TextStyle(
                              color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      FinBreakdown(
                          byCategory: s.expenseByCategory, cats: _cats, onCategory: _editCategory),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: Text('Останні операції',
                              style: TextStyle(
                                  color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => FinHistoryScreen(repo: repo, month: _month)));
                            if (mounted) _reload();
                          },
                          child: Text('Усі →', style: TextStyle(color: AppColors.create)),
                        ),
                      ]),
                      if (recent.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('У цьому місяці ще нічого немає',
                              style: TextStyle(color: AppColors.textMuted)),
                        ),
                      for (final e in recent)
                        FinEntryTile(
                          entry: e,
                          cats: _cats,
                          onTap: () async {
                            if (await openFinEntry(context, repo, e, _cats)) _reload();
                          },
                        ),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(children: [
                Expanded(
                  child: PillButton(
                    text: '− Витрата',
                    bg: AppColors.accent,
                    height: 52,
                    radius: 26,
                    fontSize: 16,
                    onPressed: () => _add(kFinExpense),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    text: '+ Дохід',
                    bg: AppColors.addObject,
                    height: 52,
                    radius: 26,
                    fontSize: 16,
                    onPressed: () => _add(kFinIncome),
                  ),
                ),
              ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}

/// Усі операції за місяць (фільтр: усі / витрати / доходи).
class FinHistoryScreen extends StatefulWidget {
  final Repository repo;
  final DateTime month;
  const FinHistoryScreen({super.key, required this.repo, required this.month});

  @override
  State<FinHistoryScreen> createState() => _FinHistoryScreenState();
}

class _FinHistoryScreenState extends State<FinHistoryScreen> {
  late DateTime _month = _firstOfMonth(widget.month);
  List<FinEntry> _entries = [];
  Map<String, FinCategory> _cats = {};
  int _filter = 0; // 0 - усі, 1 - витрати, 2 - доходи
  bool _loaded = false;

  Repository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    repo.stockChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    repo.stockChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final cats = await repo.finCategoryMap();
    final list = await repo.listFinEntries(from: _month, to: DateTime(_month.year, _month.month + 1));
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _entries = list;
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() => _month = DateTime(_month.year, _month.month + d));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final e in _entries)
        if (_filter == 0 || (_filter == 1 && e.isExpense) || (_filter == 2 && !e.isExpense)) e
    ];
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Операції', onBack: () => Navigator.pop(context)),
            _MonthBar(title: finMonthTitle(_month), onPrev: () => _shift(-1), onNext: () => _shift(1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FinSegment(
                labels: const ['Усі', 'Витрати', 'Доходи'],
                selected: _filter,
                onChanged: (i) => setState(() => _filter = i),
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? Center(
                          child: Text('Операцій немає', style: TextStyle(color: AppColors.textMuted)))
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                          for (final e in shown)
                            FinEntryTile(
                              entry: e,
                              cats: _cats,
                              onTap: () async {
                                if (await openFinEntry(context, repo, e, _cats)) _reload();
                              },
                            ),
                        ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}

/// Підсумок сезону (календарний рік): гроші по місяцях і за категоріями.
class FinSeasonScreen extends StatefulWidget {
  final Repository repo;
  const FinSeasonScreen({super.key, required this.repo});

  @override
  State<FinSeasonScreen> createState() => _FinSeasonScreenState();
}

class _FinSeasonScreenState extends State<FinSeasonScreen> {
  int _year = DateTime.now().year;
  List<FinEntry> _entries = [];
  Map<String, FinCategory> _cats = {};
  bool _loaded = false;

  Repository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final cats = await repo.finCategoryMap();
    final list = await repo.listFinEntries(from: DateTime(_year), to: DateTime(_year + 1));
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _entries = list;
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() => _year += d);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = FinSummary.of(_entries);
    final months = [
      for (var m = 1; m <= 12; m++)
        FinSummary.of(_entries.where((e) => e.date.month == m)),
    ];
    final peak = months.fold(0.0, (a, x) => [a, x.expense, x.income].reduce((p, q) => p > q ? p : q));
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Підсумок сезону', onBack: () => Navigator.pop(context)),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                      _MonthBar(title: '$_year', onPrev: () => _shift(-1), onNext: () => _shift(1)),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: AppColors.card, borderRadius: BorderRadius.circular(18)),
                        child: Column(children: [
                          Text('Баланс сезону', style: TextStyle(color: AppColors.textMuted)),
                          const SizedBox(height: 4),
                          Text(uah(s.balance),
                              style: TextStyle(
                                  color: s.balance < 0 ? AppColors.danger : AppColors.create,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                                child: Column(children: [
                              Text('Доходи', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                              Text(uah(s.income),
                                  style: TextStyle(color: AppColors.grass, fontWeight: FontWeight.w700)),
                            ])),
                            Expanded(
                                child: Column(children: [
                              Text('Витрати', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                              Text(uah(s.expense),
                                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                            ])),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Text('По місяцях',
                          style: TextStyle(
                              color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      for (var m = 0; m < 12; m++)
                        if (months[m].expense > 0 || months[m].income > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              SizedBox(
                                width: 34,
                                child: Text(finMonthTitle(DateTime(_year, m + 1)).substring(0, 3),
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  _bar(months[m].expense, peak, AppColors.create),
                                  const SizedBox(height: 3),
                                  _bar(months[m].income, peak, AppColors.grass),
                                ]),
                              ),
                              SizedBox(
                                width: 92,
                                child: Text(uah(months[m].balance),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: months[m].balance < 0
                                            ? AppColors.danger
                                            : AppColors.text,
                                        fontSize: 13)),
                              ),
                            ]),
                          ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Icon(Icons.circle, size: 10, color: AppColors.create),
                          Text('  витрати    ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          Icon(Icons.circle, size: 10, color: AppColors.grass),
                          Text('  доходи', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      Text('Витрати за категоріями',
                          style: TextStyle(
                              color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      FinBreakdown(byCategory: s.expenseByCategory, cats: _cats),
                      const SizedBox(height: 14),
                      Text('Доходи за категоріями',
                          style: TextStyle(
                              color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      FinBreakdown(byCategory: s.incomeByCategory, cats: _cats),
                    ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _bar(double v, double peak, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: peak > 0 ? v / peak : 0,
          minHeight: 6,
          backgroundColor: AppColors.darkBtn,
          color: color,
        ),
      );
}
