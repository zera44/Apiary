import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import 'fin_add_screen.dart';
import 'fin_category_screen.dart';

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
                  maxLines: 2,
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

/// Період огляду.
enum FinPeriod { day, week, month, year, custom }

const _periodNames = {
  FinPeriod.day: 'День',
  FinPeriod.week: 'Тиждень',
  FinPeriod.month: 'Місяць',
  FinPeriod.year: 'Рік',
  FinPeriod.custom: 'Період',
};

/// Кільцева діаграма: кожна категорія - сегмент її кольору.
class _DonutPainter extends CustomPainter {
  final List<(double, Color)> parts;
  final Color empty;
  _DonutPainter(this.parts, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 40.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final total = parts.fold(0.0, (a, p) => a + p.$1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total <= 0) {
      paint.color = empty;
      canvas.drawArc(rect, 0, 6.283185307, false, paint);
      return;
    }
    var start = -1.5707963;
    final gap = parts.length > 1 ? 0.03 : 0.0;
    for (final p in parts) {
      final sweep = p.$1 / total * 6.283185307;
      paint.color = p.$2;
      canvas.drawArc(rect, start + gap / 2, sweep - gap > 0.001 ? sweep - gap : sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// Фінанси: огляд за період (день / тиждень / місяць / рік / свій період).
/// Кільце за категоріями, під ним список; «+» - нова витрата чи дохід.
class FinanceScreen extends StatefulWidget {
  final Repository repo;
  const FinanceScreen({super.key, required this.repo});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  FinPeriod _period = FinPeriod.month;
  DateTime _anchor = DateTime.now();
  DateTime? _customFrom;
  DateTime? _customTo;
  String _kind = kFinExpense;
  List<FinEntry> _entries = [];
  Map<String, FinCategory> _cats = {};
  bool _loaded = false;

  Repository get repo => widget.repo;
  bool get _expense => _kind == kFinExpense;

  (DateTime, DateTime) get _range {
    final a = _anchor;
    switch (_period) {
      case FinPeriod.day:
        return (DateTime(a.year, a.month, a.day), DateTime(a.year, a.month, a.day + 1));
      case FinPeriod.week:
        final d = a.day - (a.weekday - 1);
        return (DateTime(a.year, a.month, d), DateTime(a.year, a.month, d + 7));
      case FinPeriod.month:
        return (DateTime(a.year, a.month), DateTime(a.year, a.month + 1));
      case FinPeriod.year:
        return (DateTime(a.year), DateTime(a.year + 1));
      case FinPeriod.custom:
        final f = _customFrom ?? DateTime(a.year, a.month);
        final t = _customTo ?? DateTime(a.year, a.month + 1, 0);
        return (f, DateTime(t.year, t.month, t.day + 1));
    }
  }

  String get _title {
    final (f, t) = _range;
    switch (_period) {
      case FinPeriod.day:
        return formatDdMmYyyy(f);
      case FinPeriod.week:
        final last = DateTime(t.year, t.month, t.day - 1);
        return '${finDay(f)} – ${formatDdMmYyyy(last)}';
      case FinPeriod.month:
        return finMonthTitle(f);
      case FinPeriod.year:
        return '${f.year}';
      case FinPeriod.custom:
        final last = DateTime(t.year, t.month, t.day - 1);
        return '${formatDdMmYyyy(f)} – ${formatDdMmYyyy(last)}';
    }
  }

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
    final (f, t) = _range;
    final list = await repo.listFinEntries(from: f, to: t);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _entries = list;
      _loaded = true;
    });
  }

  void _shift(int d) {
    final a = _anchor;
    switch (_period) {
      case FinPeriod.day:
        _anchor = DateTime(a.year, a.month, a.day + d);
      case FinPeriod.week:
        _anchor = DateTime(a.year, a.month, a.day + 7 * d);
      case FinPeriod.month:
        _anchor = DateTime(a.year, a.month + d, 1);
      case FinPeriod.year:
        _anchor = DateTime(a.year + d, 1, 1);
      case FinPeriod.custom:
        return;
    }
    setState(() {});
    _reload();
  }

  Future<void> _setPeriod(FinPeriod p) async {
    if (p == FinPeriod.custom) {
      final f = parseDdMmYyyy(await showAppDatePicker(context, formatDdMmYyyy(_range.$1)));
      if (f == null || !mounted) return;
      final t = parseDdMmYyyy(await showAppDatePicker(context, formatDdMmYyyy(f)));
      if (t == null || !mounted) return;
      setState(() {
        _period = p;
        _customFrom = t.isBefore(f) ? t : f;
        _customTo = t.isBefore(f) ? f : t;
      });
    } else {
      setState(() {
        _period = p;
        if (p == FinPeriod.month) _anchor = DateTime(_anchor.year, _anchor.month, 1);
      });
    }
    _reload();
  }

  Future<void> _add() async {
    final msg = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => FinAddScreen(repo: repo, kind: _kind)));
    if (!mounted) return;
    await _reload();
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _history({String? categoryId, bool onlyStock = false, String? title}) async {
    final (f, t) = _range;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FinHistoryScreen(
              repo: repo,
              from: f,
              to: t,
              title: title ?? 'Операції · $_title',
              filter: _expense ? 1 : 2,
              categoryId: categoryId,
              onlyStock: onlyStock,
            )));
    if (mounted) _reload();
  }

  Future<void> _editCategory(FinCategory c) async {
    await Navigator.of(context).push(
        MaterialPageRoute<String>(builder: (_) => FinCategoryScreen(repo: repo, category: c)));
    await _reload();
  }

  Widget _periodTabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (final p in FinPeriod.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setPeriod(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: p == _period ? AppColors.create : Colors.transparent, width: 3)),
                ),
                child: Text(_periodNames[p]!,
                    style: TextStyle(
                        color: p == _period ? AppColors.create : AppColors.textMuted,
                        fontSize: 15,
                        fontWeight: p == _period ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = FinSummary.of(_entries);
    final by = _expense ? s.expenseByCategory : s.incomeByCategory;
    // категорії з нульовою сумою (напр. прихід на склад без вартості) не показуємо
    final items = by.entries.where((e) => e.value > 0.0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = items.fold(0.0, (a, e) => a + e.value);
    Color colorOf(String? id) => id == null ? finColor('olive') : finColor(_cats[id]?.color ?? 'nut');
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(
              title: 'Фінанси',
              onBack: () => Navigator.pop(context),
              trailing: IconButton(
                tooltip: 'Усі операції',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.receipt_long_outlined, color: AppColors.text),
                onPressed: () => _history(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FinSegment(
                labels: const ['Витрати', 'Дохід'],
                selected: _expense ? 0 : 1,
                onChanged: (i) => setState(() => _kind = i == 0 ? kFinExpense : kFinIncome),
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                        decoration: BoxDecoration(
                            color: AppColors.card, borderRadius: BorderRadius.circular(20)),
                        child: Column(children: [
                          _periodTabs(),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            if (_period != FinPeriod.custom)
                              IconButton(
                                  onPressed: () => _shift(-1),
                                  tooltip: 'Раніше',
                                  icon: Icon(Icons.chevron_left, color: AppColors.text)),
                            Flexible(
                              child: GestureDetector(
                                onTap: _period == FinPeriod.custom
                                    ? () => _setPeriod(FinPeriod.custom)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  child: Text(_title,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: AppColors.text,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                            if (_period != FinPeriod.custom)
                              IconButton(
                                  onPressed: () => _shift(1),
                                  tooltip: 'Пізніше',
                                  icon: Icon(Icons.chevron_right, color: AppColors.text)),
                          ]),
                          SizedBox(
                            width: 250,
                            height: 250,
                            child: Stack(alignment: Alignment.center, children: [
                              CustomPaint(
                                size: const Size(250, 250),
                                painter: _DonutPainter(
                                    [for (final e in items) (e.value, colorOf(e.key))],
                                    AppColors.darkBtn),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 52),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(uah(total),
                                        style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text('баланс ${uah(s.balance)}',
                                      style: TextStyle(
                                          color: s.balance < 0
                                              ? AppColors.danger
                                              : AppColors.textMuted,
                                          fontSize: 12)),
                                ]),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                              child: Text('За цей період нічого немає',
                                  style: TextStyle(color: AppColors.textMuted))),
                        ),
                      for (final e in items)
                        Builder(builder: (_) {
                          final c = e.key == null ? null : _cats[e.key];
                          final pct = total > 0 ? (e.value / total * 100).round() : 0;
                          final name = e.key == null
                              ? kFinStockCategoryName
                              : (c?.name ?? 'Без категорії');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                                color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _history(
                                  categoryId: e.key,
                                  onlyStock: e.key == null,
                                  title: '$name · $_title'),
                              onLongPress: c == null ? null : () => _editCategory(c),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  e.key == null
                                      ? const FinBadge(icon: 'home', color: 'olive', size: 44)
                                      : FinBadge(
                                          icon: c?.icon ?? 'other', color: c?.color ?? 'nut', size: 44),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AppColors.text, fontSize: 16)),
                                  ),
                                  Text('$pct%',
                                      style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                                  const SizedBox(width: 14),
                                  Text(uah(e.value),
                                      style: TextStyle(color: AppColors.text, fontSize: 16)),
                                ]),
                              ),
                            ),
                          );
                        }),
                    ]),
            ),
          ]),
          Positioned(
            right: 20,
            bottom: 24,
            child: Material(
              color: const Color(0xFFFBC02D),
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _add,
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Tooltip(
                      message: 'Нова операція', child: Icon(Icons.add, size: 36, color: Color(0xFF1D1611))),
                ),
              ),
            ),
          ),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}

/// Операції за період: усі, лише витрати чи доходи, або однієї категорії.
class FinHistoryScreen extends StatefulWidget {
  final Repository repo;
  final DateTime from;
  final DateTime to;
  final String title;

  /// 0 - усі, 1 - витрати, 2 - доходи.
  final int filter;
  final String? categoryId;

  /// Лише прихід, внесений на складі.
  final bool onlyStock;
  const FinHistoryScreen(
      {super.key,
      required this.repo,
      required this.from,
      required this.to,
      required this.title,
      this.filter = 0,
      this.categoryId,
      this.onlyStock = false});

  @override
  State<FinHistoryScreen> createState() => _FinHistoryScreenState();
}

class _FinHistoryScreenState extends State<FinHistoryScreen> {
  List<FinEntry> _entries = [];
  Map<String, FinCategory> _cats = {};
  late int _filter = widget.filter;
  bool _loaded = false;

  Repository get repo => widget.repo;
  bool get _scoped => widget.categoryId != null || widget.onlyStock;

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
    final list = await repo.listFinEntries(from: widget.from, to: widget.to);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _entries = list;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final e in _entries)
        if (widget.onlyStock
            ? e.fromStock
            : widget.categoryId != null
                ? (!e.fromStock && e.categoryId == widget.categoryId)
                : (_filter == 0 || (_filter == 1 && e.isExpense) || (_filter == 2 && !e.isExpense)))
          e
    ];
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: widget.title, onBack: () => Navigator.pop(context)),
            if (!_scoped)
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
