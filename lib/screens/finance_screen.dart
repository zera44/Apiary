import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/fin_accounts.dart';
import '../data/finance.dart';
import '../data/repository.dart';
import '../logic/fin_period.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/nav_drawer.dart';
import '../ui/date_picker.dart';
import '../services/fin_export.dart';
import '../ui/fin_export_sheet.dart';
import '../ui/fin_period_card.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import 'fin_add_screen.dart';
import 'fin_category_screen.dart';
import '../l10n/l10n.dart';

/// Рядок журналу: значок категорії, що й на скільки, дата, сума.
class FinEntryTile extends StatelessWidget {
  final FinEntry entry;
  final Map<String, FinCategory> cats;

  /// Рахунки (для значка й назви рахунку в підрядку); без них рядок як раніше.
  final Map<String, FinAccount> accounts;
  final VoidCallback onTap;
  const FinEntryTile(
      {super.key,
      required this.entry,
      required this.cats,
      required this.onTap,
      this.accounts = const {}});

  @override
  Widget build(BuildContext context) {
    final c = entry.categoryId == null ? null : cats[entry.categoryId];
    final name = entry.fromStock ? kFinStockCategoryName : (c?.name ?? tr.noCategory);
    final muted = entry.cancelled;
    final sign = entry.isExpense ? '−' : '+';
    final acc = entry.fromStock ? null : accounts[entry.accountId];
    final sub = TextStyle(color: AppColors.textMuted, fontSize: 12.5);
    final sep = TextSpan(text: ' · ', style: sub);
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
              Text.rich(
                  TextSpan(style: sub, children: [
                    TextSpan(text: finDay(entry.date)),
                    if (acc != null) ...[
                      sep,
                      WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: FinBadge(icon: acc.icon, color: acc.color, size: 16)),
                      TextSpan(text: ' ${acc.name}', style: sub.copyWith(color: AppColors.text)),
                    ],
                    if (entry.title.isNotEmpty) ...[sep, TextSpan(text: entry.title)],
                    if (muted) ...[sep, TextSpan(text: tr.cancelledMark)],
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$sign${uah(entry.amount)}',
                style: TextStyle(
                    color: finAmountColor(entry),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: muted ? TextDecoration.lineThrough : null)),
            if (acc != null && acc.foreign && entry.accountAmount != null)
              Text(money(entry.accountAmount!, acc.currency),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }
}

/// Що зробити із записом журналу.
enum _EntryAction { close, edit, cancel }

/// Відкрити запис журналу: деталі, «Змінити» (власні операції) і
/// «Скасувати запис» (на складі теж). Повертає true, якщо щось змінилось.
Future<bool> openFinEntry(BuildContext context, Repository repo, FinEntry e,
    Map<String, FinCategory> cats,
    {Map<String, FinAccount> accounts = const {}}) async {
  final c = e.categoryId == null ? null : cats[e.categoryId];
  final name = e.fromStock ? kFinStockCategoryName : (c?.name ?? tr.noCategory);
  final what = e.title.isEmpty ? '' : '\n${e.title}';
  final note = (e.comment ?? '').isEmpty || e.fromStock ? '' : '\n«${e.comment}»';
  final text = tr.finEntryText(name, e.isExpense, uah(e.amount), '${finDay(e.date)}$what$note')
      + (e.fromStock ? tr.finFromStockNote : '')
      + (e.lines.isEmpty
          ? ''
          : '\n\n${tr.finBoughtTitle}\n${e.lines.map((l) => '• ${l.name} - ${_plain(l.qty)} ${l.unit} × ${uah(l.price)} = ${uah(l.total)}').join('\n')}')
      + (!e.fromStock && e.lineCount > 0 ? tr.finLinesNote : '');
  if (e.cancelled) {
    await showInfo(context, '$text${tr.finCancelledNote}', title: tr.record);
    return false;
  }
  final action = await showModalBottomSheet<_EntryAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _FinEntrySheet(entry: e, cats: cats, accounts: accounts),
  );
  if (!context.mounted || action == null || action == _EntryAction.close) return false;
  if (action == _EntryAction.edit) return _editFinEntry(context, repo, e);
  // як на складі: скасування - лише після підтвердження
  final ok = await showConfirm(context,
      title: tr.recordCancelTitle,
      text: tr.finCancelText(name, uah(e.amount), finDay(e.date)),
      confirmText: tr.recordCancel,
      cancelText: tr.close);
  if (!ok || !context.mounted) return false;
  try {
    await repo.cancelFinEntry(e);
    return true;
  } on StateError catch (err) {
    if (context.mounted) await showInfo(context, err.message, title: tr.notCancelled);
    return false;
  } catch (err) {
    if (context.mounted) await showInfo(context, '$err', title: tr.notCancelled);
    return false;
  }
}

/// Картка запису: що, скільки, з якого рахунку, далі що куплено й коментар;
/// знизу «Закрити» / «Змінити» і окремо «Скасувати запис» (щоб не влучити).
class _FinEntrySheet extends StatelessWidget {
  final FinEntry entry;
  final Map<String, FinCategory> cats;
  final Map<String, FinAccount> accounts;
  const _FinEntrySheet({required this.entry, required this.cats, required this.accounts});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final c = e.categoryId == null ? null : cats[e.categoryId];
    final name = e.fromStock ? kFinStockCategoryName : (c?.name ?? tr.noCategory);
    final acc = e.fromStock ? null : accounts[e.accountId];
    final sign = e.isExpense ? '−' : '+';
    final sub = [
      finDay(e.date),
      if (e.title.isNotEmpty) e.title,
    ].join(' · ');
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 13);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
                width: 44,
                height: 5,
                decoration:
                    BoxDecoration(color: AppColors.darkBtn, borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 14),
          Row(children: [
            e.fromStock
                ? const FinBadge(icon: 'home', color: 'olive', size: 52)
                : FinBadge(icon: c?.icon ?? 'other', color: c?.color ?? 'nut', size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$sign${uah(e.amount)}',
                    key: const ValueKey('fin-entry-amount'),
                    style: TextStyle(
                        color: finAmountColor(e), fontSize: 32, fontWeight: FontWeight.w700)),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration:
                  BoxDecoration(color: AppColors.darkBtn, borderRadius: BorderRadius.circular(10)),
              child: Text(e.isExpense ? tr.expense : tr.income,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          ]),
          if (acc != null && acc.foreign && e.accountAmount != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(tr.finEntryWrittenOff(money(e.accountAmount!, acc.currency)), style: muted),
            ),
          if (acc != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('fin-entry-account'),
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                FinBadge(icon: acc.icon, color: acc.color, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr.finAccount, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text(acc.foreign ? '${acc.name} · ${acc.currency}' : acc.name,
                        style: TextStyle(
                            color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ]),
            ),
          ],
          if (e.lines.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(tr.finBoughtTitle.replaceAll(':', '').toUpperCase(),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, letterSpacing: 0.6)),
            const SizedBox(height: 6),
            for (final l in e.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(l.name, style: TextStyle(color: AppColors.text, fontSize: 14))),
                  const SizedBox(width: 10),
                  Text('${_plain(l.qty)} ${l.unit} × ${_plain(l.price)} = ${uah(l.total)}',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                ]),
              ),
          ],
          if ((e.comment ?? '').isNotEmpty && !e.fromStock) ...[
            const SizedBox(height: 10),
            Text('«${e.comment}»',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 14, fontStyle: FontStyle.italic)),
          ],
          if (e.fromStock) ...[
            const SizedBox(height: 10),
            Text(tr.finFromStockNote.trim(), style: muted),
          ],
          if (!e.fromStock && e.lineCount > 0) ...[
            const SizedBox(height: 6),
            Text(tr.finLinesNote.trim(), style: muted),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: PillButton(
                  text: tr.close,
                  bg: AppColors.neutralBtn,
                  fg: AppColors.text,
                  height: 46,
                  onPressed: () => Navigator.pop(context, _EntryAction.close)),
            ),
            if (!e.fromStock) ...[
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(
                    text: tr.edit,
                    bg: AppColors.accent,
                    height: 46,
                    onPressed: () => Navigator.pop(context, _EntryAction.edit)),
              ),
            ],
          ]),
          // небезпечна дія - окремо, щоб не влучити замість «Закрити»
          const SizedBox(height: 12),
          TextButton(
            key: const ValueKey('fin-entry-cancel'),
            onPressed: () => Navigator.pop(context, _EntryAction.cancel),
            child: Text(tr.recordCancel,
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

/// «Змінити запис»: той самий екран, що й нова витрата чи дохід, але заповнений
/// тим, що було обрано (категорія, рахунок, дата, сума, рядки, коментар).
Future<bool> _editFinEntry(BuildContext context, Repository repo, FinEntry e) async {
  final r = await Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => FinAddScreen(repo: repo, edit: e)));
  return r != null;
}

String _plain(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', ',');

Map<FinPeriod, String> get _periodNames => {
  FinPeriod.day: tr.periodDay,
  FinPeriod.week: tr.periodWeek,
  FinPeriod.month: tr.periodMonth,
  FinPeriod.year: tr.periodYear,
  FinPeriod.custom: tr.periodCustom,
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // відкриваємо на поточному дні
  FinPeriod _period = FinPeriod.day;
  DateTime _anchor = _today();
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

  // поточна дата пристрою без часу; рахуємо щоразу, бо екран може
  // лишатися відкритим після півночі
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // у майбутнє (день, тиждень, місяць, рік) не гортаємо: наступний період
  // має починатися не пізніше сьогодні
  bool get _canGoForward => !_range.$2.isAfter(_today());

  void _shift(int d) {
    final a = _anchor;
    final DateTime next;
    switch (_period) {
      case FinPeriod.day:
        next = DateTime(a.year, a.month, a.day + d);
      case FinPeriod.week:
        next = DateTime(a.year, a.month, a.day + 7 * d);
      case FinPeriod.month:
        next = DateTime(a.year, a.month + d, 1);
      case FinPeriod.year:
        next = DateTime(a.year + d, 1, 1);
      case FinPeriod.custom:
        return;
    }
    if (d > 0 && !_canGoForward) return;
    _anchor = next;
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
        // з вкладки на вкладку - завжди поточний день, тиждень, місяць, рік
        final t = _today();
        _anchor = p == FinPeriod.month ? DateTime(t.year, t.month, 1) : t;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SnackText(msg)));
    }
  }

  Future<void> _history({String? categoryId, bool onlyStock = false, String? title}) async {
    final (f, t) = _range;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FinHistoryScreen(
              repo: repo,
              from: f,
              to: t,
              title: title ?? tr.finOperationsOf(_title),
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

  // усі п'ять вкладок завжди видно: на великому шрифті ряд трохи
  // зменшується, а не ховає «Період» за край
  Widget _periodTabs() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FittedBox(
        fit: BoxFit.scaleDown,
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
        ),
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
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height && size.height < 500;
    final donut = landscape ? 200.0 : 250.0;
    final Widget summary = Container(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      decoration: BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        _periodTabs(),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_period != FinPeriod.custom)
            IconButton(
                onPressed: () => _shift(-1),
                tooltip: tr.earlier,
                icon: Icon(TablerIcons.chevron_left, color: AppColors.text)),
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
                onPressed: _canGoForward ? () => _shift(1) : null,
                tooltip: tr.later,
                icon: Icon(TablerIcons.chevron_right,
                    color: _canGoForward ? AppColors.text : AppColors.textMuted.withValues(alpha: 0.35))),
        ]),
        SizedBox(
          width: donut,
          height: donut,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size(donut, donut),
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
                Text(tr.finBalance(uah(s.balance)),
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
    );
    final rows = <Widget>[
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
              child: Text(tr.finNothingInPeriod,
                  style: TextStyle(color: AppColors.textMuted))),
        ),
      for (final e in items)
        Builder(builder: (_) {
          final c = e.key == null ? null : _cats[e.key];
          final pct = total > 0 ? (e.value / total * 100).round() : 0;
          final name = e.key == null
              ? kFinStockCategoryName
              : (c?.name ?? tr.noCategory);
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
                  const SizedBox(width: 10),
                  // сума над відсотком; найбільший шрифт на вузькому
                  // телефоні - зменшується, а не вилазить за край
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(uah(e.value),
                                style: TextStyle(color: AppColors.text, fontSize: 16)),
                            Text('$pct%',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 13.5)),
                          ]),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
    ];
    return Scaffold(
      key: _scaffoldKey,
      drawer: NavDrawer(repo: repo, current: NavSection.finances, finSection: FinSection.home),
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(
              title: tr.finances,
              onBack: () => Navigator.pop(context),
              onTitleTap: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FinSegment(
                labels: [tr.expenses, tr.income],
                selected: _expense ? 0 : 1,
                onChanged: (i) => setState(() => _kind = i == 0 ? kFinExpense : kFinIncome),
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : landscape
                      // телефон боком: діаграма ліворуч, категорії праворуч - обидва
                      // видно без прокрутки
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 300,
                            child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 8, 16), children: [summary]),
                          ),
                          Expanded(
                            child: ListView(
                                padding: const EdgeInsets.fromLTRB(8, 0, 16, 100),
                                children: rows),
                          ),
                        ])
                      // знизу - місце під кнопку «+» (не закриває суму в останньому рядку)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          children: [summary, const SizedBox(height: 12), ...rows]),
            ),
          ]),
          Positioned(
            // на планшеті - біля вмісту (він по центру), а не в кутку екрана
            right: 20 + math.max(0, (MediaQuery.sizeOf(context).width - kContentMaxWidth) / 2),
            bottom: 24,
            child: Material(
              color: const Color(0xFFFBC02D),
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _add,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Tooltip(
                      message: tr.finNewOperation, child: const Icon(TablerIcons.plus, size: 36, color: Color(0xFF1D1611))),
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

  /// Усі операції поточного місяця (пункт меню «Операції»).
  factory FinHistoryScreen.thisMonth({Key? key, required Repository repo}) {
    final n = DateTime.now();
    return FinHistoryScreen(
        key: key,
        repo: repo,
        from: DateTime(n.year, n.month, 1),
        to: DateTime(n.year, n.month + 1, 1),
        title: finMonthTitle(n));
  }

  @override
  State<FinHistoryScreen> createState() => _FinHistoryScreenState();
}

class _FinHistoryScreenState extends State<FinHistoryScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<FinEntry> _entries = [];
  Map<String, FinCategory> _cats = {};
  Map<String, FinAccount> _accounts = {};
  late int _filter = widget.filter;
  bool _loaded = false;

  /// Вибраний період (лише для списку всіх операцій; зі скритих екранів
  /// категорії період заданий ззовні).
  late final FinPeriodSel _sel =
      FinPeriodSel(period: FinPeriod.month, anchor: DateTime(widget.from.year, widget.from.month, 1));

  Repository get repo => widget.repo;
  bool get _scoped => widget.categoryId != null || widget.onlyStock;
  (DateTime, DateTime) get _range => _scoped ? (widget.from, widget.to) : _sel.range;

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
    final accounts = await repo.finAccountMap();
    final (f, t) = _range;
    final list = await repo.listFinEntries(from: f, to: t);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _accounts = accounts;
      _entries = list;
      _loaded = true;
    });
  }

  void _select(FinPeriod p) {
    if (p == FinPeriod.custom) {
      _customPeriod();
      return;
    }
    setState(() => _sel.select(p));
    _reload();
  }

  void _shift(int d) {
    if (!_sel.shift(d)) return;
    setState(() {});
    _reload();
  }

  Future<void> _customPeriod() async {
    final (f, t) = _sel.range;
    final r = await showFinCustomPeriod(context,
        from: f,
        to: DateTime(t.year, t.month, t.day - 1),
        load: (a, b) => repo.listFinEntries(from: a, to: b));
    if (r == null || !mounted) return;
    setState(() => _sel.setCustom(r.$1, r.$2));
    _reload();
  }

  Future<void> _export() async {
    final (f, _) = _sel.range;
    final choice = await showFinExportSheet(context,
        entries: _entries,
        periodTitle: _sel.title,
        from: f,
        lastDay: _sel.lastDay,
        initial: switch (_filter) {
          1 => FinExportKind.expenses,
          2 => FinExportKind.income,
          _ => FinExportKind.all,
        });
    if (choice == null || !mounted) return;
    String? err;
    try {
      final bytes = buildFinWorkbook(
          entries: _entries,
          cats: _cats,
          kind: choice.kind,
          accounts: _accounts,
          includeSummary: choice.summary,
          includeComment: choice.comment,
          includeAccount: choice.account);
      err = await shareFinExport(
          bytes: bytes, fileName: finExportFileName(f, _sel.lastDay, choice.kind));
    } catch (e) {
      err = tr.fileBuildFailed('$e');
    }
    if (err != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: SnackText(err, kind: SnackKind.error)));
    }
  }

  Widget _exportButton() => Tooltip(
        message: tr.finExportTitle,
        child: Material(
          color: AppColors.roundBtn,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _loaded ? _export : null,
            child: SizedBox.square(
                dimension: 44,
                child: Icon(TablerIcons.file_spreadsheet, size: 24, color: AppColors.text)),
          ),
        ),
      );

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
      key: _scaffoldKey,
      drawer: NavDrawer(repo: repo, current: NavSection.finances, finSection: FinSection.ops),
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(
              title: tr.finOps,
              onBack: () => Navigator.pop(context),
              onTitleTap: () => _scaffoldKey.currentState?.openDrawer(),
              trailing: _scoped ? null : _exportButton(),
            ),
            if (_scoped)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 15, fontWeight: FontWeight.w700)),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FinPeriodCard(
                    sel: _sel,
                    onSelect: _select,
                    onShift: _shift,
                    onCustomTap: _customPeriod),
              ),
            if (!_scoped)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FinSegment(
                  labels: [tr.all, tr.expenses, tr.incomes],
                  selected: _filter,
                  onChanged: (i) => setState(() => _filter = i),
                ),
              ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? Center(
                          child: Text(tr.finNoOperations, style: TextStyle(color: AppColors.textMuted)))
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                          for (final e in shown)
                            FinEntryTile(
                              entry: e,
                              cats: _cats,
                              accounts: _accounts,
                              onTap: () async {
                                if (await openFinEntry(context, repo, e, _cats, accounts: _accounts)) _reload();
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
