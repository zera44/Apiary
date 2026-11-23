import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../l10n/l10n.dart';
import '../logic/fin_period.dart';
import 'common.dart';
import 'date_picker.dart';
import 'fin_style.dart';
import 'theme.dart';

String _periodName(FinPeriod p) => switch (p) {
      FinPeriod.day => tr.periodDay,
      FinPeriod.week => tr.periodWeek,
      FinPeriod.month => tr.periodMonth,
      FinPeriod.year => tr.periodYear,
      FinPeriod.custom => tr.periodCustom,
    };

/// Блок вибору періоду, як на екрані «Фінанси»: вкладки День, Тиждень, Місяць,
/// Рік, Період, нижче стрілки ‹ › і підпис періоду.
class FinPeriodCard extends StatelessWidget {
  final FinPeriodSel sel;
  final ValueChanged<FinPeriod> onSelect;
  final ValueChanged<int> onShift;

  /// Дотик по підпису власного періоду (змінити межі).
  final VoidCallback onCustomTap;

  /// Які вкладки показати (за замовчуванням усі).
  final List<FinPeriod> periods;

  /// Чи є куди гортати назад (стрілка ‹ згасає, коли раніше даних немає).
  final bool canGoBack;
  const FinPeriodCard(
      {super.key,
      required this.sel,
      required this.onSelect,
      required this.onShift,
      required this.onCustomTap,
      this.periods = FinPeriod.values,
      this.canGoBack = true});

  @override
  Widget build(BuildContext context) {
    final custom = sel.period == FinPeriod.custom;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        // усі вкладки завжди видно: на великому шрифті ряд зменшується
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(children: [
              for (final p in periods)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: p == sel.period ? AppColors.create : Colors.transparent,
                              width: 3)),
                    ),
                    child: Text(_periodName(p),
                        style: TextStyle(
                            color: p == sel.period ? AppColors.create : AppColors.textMuted,
                            fontSize: 15,
                            fontWeight: p == sel.period ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ),
            ]),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (!custom)
            IconButton(
                onPressed: canGoBack ? () => onShift(-1) : null,
                tooltip: tr.earlier,
                icon: Icon(TablerIcons.chevron_left,
                    color: canGoBack
                        ? AppColors.text
                        : AppColors.textMuted.withValues(alpha: 0.35))),
          Flexible(
            child: GestureDetector(
              onTap: custom ? onCustomTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: Text(sel.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          if (!custom)
            IconButton(
                onPressed: sel.canGoForward ? () => onShift(1) : null,
                tooltip: tr.later,
                icon: Icon(TablerIcons.chevron_right,
                    color: sel.canGoForward
                        ? AppColors.text
                        : AppColors.textMuted.withValues(alpha: 0.35))),
        ]),
      ]),
    );
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Нижня панель «Свій період»: швидкі діапазони, дві дати й підсумок
/// (скільки операцій і на яку суму потрапить у список). null - закрили.
Future<(DateTime, DateTime)?> showFinCustomPeriod(
  BuildContext context, {
  required DateTime from,
  required DateTime to,
  required Future<List<FinEntry>> Function(DateTime from, DateTime toExclusive) load,
}) =>
    showModalBottomSheet<(DateTime, DateTime)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomPeriodSheet(from: _day(from), to: _day(to), load: load),
    );

class _CustomPeriodSheet extends StatefulWidget {
  final DateTime from, to;
  final Future<List<FinEntry>> Function(DateTime, DateTime) load;
  const _CustomPeriodSheet({required this.from, required this.to, required this.load});

  @override
  State<_CustomPeriodSheet> createState() => _CustomPeriodSheetState();
}

class _CustomPeriodSheetState extends State<_CustomPeriodSheet> {
  late DateTime _from = widget.from;
  late DateTime _to = widget.to;
  List<FinEntry> _entries = const [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  (DateTime, DateTime) get _ordered => _to.isBefore(_from) ? (_to, _from) : (_from, _to);

  Future<void> _refresh() async {
    final id = ++_seq;
    final (a, b) = _ordered;
    final list = await widget.load(a, DateTime(b.year, b.month, b.day + 1));
    if (!mounted || id != _seq) return;
    setState(() => _entries = list);
  }

  void _set(DateTime a, DateTime b) {
    setState(() {
      _from = _day(a);
      _to = _day(b);
    });
    _refresh();
  }

  Future<void> _pick(bool first) async {
    final d = parseDdMmYyyy(await showAppDatePicker(context, formatDdMmYyyy(first ? _from : _to)));
    if (d == null || !mounted) return;
    first ? _set(d, _to) : _set(_from, d);
  }

  bool _is(DateTime a, DateTime b) => _from == _day(a) && _to == _day(b);

  @override
  Widget build(BuildContext context) {
    final t = FinPeriodSel.today();
    final presets = <(String, DateTime, DateTime)>[
      (tr.finPresetThisMonth, DateTime(t.year, t.month), t),
      (tr.finPresetLastMonth, DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0)),
      (tr.finPresetQuarter, DateTime(t.year, t.month - 2), t),
      (tr.finPresetYtd, DateTime(t.year), t),
    ];
    final s = FinSummary.of(_entries);
    final count = _entries.where((e) => !e.cancelled).length;
    Widget dateChip(String label, DateTime d, bool first) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pick(first),
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.create, width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(formatDdMmYyyy(d),
                    style: TextStyle(
                        color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ]),
            ),
          ),
        );
    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: AppColors.textMuted, fontSize: 14))),
            Text(v,
                style: TextStyle(
                    color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: AppColors.darkBtn, borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(height: 12),
            Text(tr.finCustomTitle,
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in presets)
                ChoiceButton(text: p.$1, selected: _is(p.$2, p.$3), onTap: () => _set(p.$2, p.$3)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              dateChip(tr.finFromDate, _ordered.$1, true),
              const SizedBox(width: 8),
              dateChip(tr.finToDate, _ordered.$2, false),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                line(tr.finOpsCount, '$count'),
                line(tr.expenses, '−${uah(s.expense)}'),
                line(tr.incomes, '+${uah(s.income)}'),
              ]),
            ),
            const SizedBox(height: 14),
            PillButton(
              text: tr.finShow,
              bg: AppColors.accent,
              height: 48,
              width: double.infinity,
              onPressed: () => Navigator.pop(context, _ordered),
            ),
          ]),
        ),
      ),
    );
  }
}
