import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../l10n/l10n.dart';
import 'date_picker.dart';
import 'fin_style.dart';
import 'theme.dart';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Швидкий вибір дати: сьогодні, вчора, позавчора і календар.
class FinDateRow extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onPickCalendar;
  const FinDateRow({super.key, required this.date, required this.onChanged, required this.onPickCalendar});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = [for (var i = 0; i < 3; i++) now.subtract(Duration(days: i))];
    final words = [tr.today, tr.yesterday, tr.dayBeforeYesterday];
    final custom = !days.any((d) => _sameDay(date, d));
    Widget chip(Widget child, bool on, VoidCallback tap) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: on ? AppColors.card : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? AppColors.create : AppColors.darkBtn, width: on ? 1.5 : 1),
              ),
              child: child,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
        for (var i = 0; i < 3; i++) ...[
          chip(
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(finDay(days[i]),
                    style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(words[i], style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ]),
            ),
            _sameDay(date, days[i]),
            () => onChanged(i == 0 ? DateTime.now() : days[i]),
          ),
          const SizedBox(width: 8),
        ],
        chip(
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(TablerIcons.calendar, size: 24, color: AppColors.create),
              if (custom)
                Text(formatDdMmYyyy(date), style: TextStyle(color: AppColors.text, fontSize: 11.5)),
            ]),
          ),
          custom,
          onPickCalendar,
        ),
      ]),
    );
  }
}
