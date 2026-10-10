import 'package:flutter/material.dart';

import 'common.dart';
import 'theme.dart';

/// Календар для типу даних "Дата" (порт date_picker.py): місяць/рік зі
/// стрілками, сітка днів з понеділка, «Скасувати» / «Сьогодні» / «Готово».
/// Значення — текст "ДД.ММ.РРРР".

const _monthNames = [
  '', 'Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень',
  'Липень', 'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень',
];
const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

DateTime? parseDdMmYyyy(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final parts = text.trim().split('.');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  var y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  // «05.03.25» - це 2025, а не 25-й рік нашої ери
  if (parts[2].trim().length <= 2 && y >= 0) y += 2000;
  if (y < 1900 || y > 2999) return null;
  final dt = DateTime(y, m, d);
  if (dt.day != d || dt.month != m) return null;
  return dt;
}

/// Перший (понеділок) день сітки календаря для місяця. Календарна
/// арифметика, а не 24-годинні Duration: на переході на літній час
/// subtract(Duration(days: n)) давав 23:00 попереднього дня й зсував усю
/// сітку на день.
DateTime calendarGridStart(int year, int month) {
  final lead = DateTime(year, month, 1).weekday - 1; // понеділок = 0
  return DateTime(year, month, 1 - lead);
}

String formatDdMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String formatDateTime(double unixSeconds) {
  final d = DateTime.fromMicrosecondsSinceEpoch((unixSeconds * 1e6).round());
  return '${formatDdMmYyyy(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Повертає "ДД.ММ.РРРР", "" (очистити) або null (скасовано).
Future<String?> showAppDatePicker(BuildContext context, String? initial) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DatePickerDialog(initial: parseDdMmYyyy(initial)),
  );
}

class _DatePickerDialog extends StatefulWidget {
  final DateTime? initial;
  const _DatePickerDialog({this.initial});
  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late int year;
  late int month;
  DateTime? selected;

  @override
  void initState() {
    super.initState();
    final start = widget.initial ?? DateTime.now();
    year = start.year;
    month = start.month;
    selected = widget.initial;
  }

  void _shift(int delta) {
    setState(() {
      var m = month + delta, y = year;
      if (m == 0) {
        m = 12;
        y--;
      } else if (m == 13) {
        m = 1;
        y++;
      }
      month = m;
      year = y;
    });
  }

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final gridStart = calendarGridStart(year, month);
    final today = DateTime.now();
    final days = [for (var i = 0; i < 42; i++) DateTime(gridStart.year, gridStart.month, gridStart.day + i)];

    return AlertDialog(
      title: const Text('Оберіть дату'),
      // прокручується, щоб на низькому екрані/малому вікні не було
      // переповнення (календар із 6 рядків доволі високий)
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            CircleIconButton(
                icon: 'arrow_left',
                bg: AppColors.roundBtn,
                iconColor: AppColors.text,
                size: 34,
                onPressed: () => _shift(-1)),
            Expanded(
              child: Text('${_monthNames[month]} $year',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            CircleIconButton(
                icon: 'arrow_right',
                bg: AppColors.roundBtn,
                iconColor: AppColors.text,
                size: 34,
                onPressed: () => _shift(1)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final w in _weekdays)
              Expanded(
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ),
          ]),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            childAspectRatio: 1.15,
            children: [
              for (final d in days) _dayCell(d, today),
            ],
          ),
        ])),
      ),
      // три кнопки, кожна закриває календар: скасувати / сьогодні / обрана дата
      actions: [
        Row(children: [
          Expanded(
            child: PillButton(
                text: 'Скасувати',
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                fontSize: 12,
                onPressed: () => Navigator.pop(context)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: PillButton(
              text: 'Сьогодні',
              bg: AppColors.roundBtn,
              fg: AppColors.text,
              fontSize: 12,
              onPressed: () => Navigator.pop(context, formatDdMmYyyy(DateTime.now())),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: PillButton(
              text: 'Готово',
              bg: AppColors.accent,
              fontSize: 12,
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, formatDdMmYyyy(selected!)),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _dayCell(DateTime d, DateTime today) {
    final inMonth = d.month == month;
    final isSel = selected != null && _same(selected!, d);
    final isToday = _same(d, today);
    Color bg = Colors.transparent;
    Color fg = inMonth ? AppColors.text : AppColors.textMuted;
    if (isSel) {
      bg = AppColors.accent;
      fg = Colors.white;
    } else if (isToday) {
      bg = AppColors.roundBtn;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          selected = d;
          year = d.year;
          month = d.month;
        }),
        child: Center(child: Text('${d.day}', style: TextStyle(color: fg, fontSize: 12))),
      ),
    );
  }
}
