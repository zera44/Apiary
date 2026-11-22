import '../data/finance.dart';
import '../l10n/l10n.dart';
import 'fin_period.dart';

/// Що малює лінія статистики: результат (дохід − витрати), витрати чи дохід.
enum FinStatKind { result, expense, income }

/// Одна точка лінії: підпис і межі (від початку першого дня до початку дня після останнього).
class FinBucket {
  final String label;
  final DateTime from;
  final DateTime to;
  const FinBucket(this.label, this.from, this.to);

  bool contains(DateTime d) => !d.isBefore(from) && d.isBefore(to);
}

/// Точки для вибраного періоду й індекс точки, що відповідає самому періоду
/// (для власного періоду - null: він охоплює всі точки).
class FinWindow {
  final List<FinBucket> buckets;
  final int? selected;
  const FinWindow(this.buckets, this.selected);

  DateTime get from => buckets.first.from;
  DateTime get to => buckets.last.to;
}

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// Точки лінії для періоду [sel]: тиждень - 12 останніх тижнів, місяць - місяці
/// року, рік - 5 останніх років, власний період - його тижні (чи місяці, чи роки,
/// коли період довгий). Майбутнє не показуємо.
FinWindow finWindow(FinPeriodSel sel, {DateTime? now}) {
  final today = now == null ? FinPeriodSel.today() : DateTime(now.year, now.month, now.day);
  final a = sel.anchor;
  switch (sel.period) {
    case FinPeriod.day:
    case FinPeriod.week:
      final monday = DateTime(a.year, a.month, a.day - (a.weekday - 1));
      final out = [
        for (var i = 11; i >= 0; i--)
          FinBucket(_dm(DateTime(monday.year, monday.month, monday.day - 7 * i)),
              DateTime(monday.year, monday.month, monday.day - 7 * i),
              DateTime(monday.year, monday.month, monday.day - 7 * i + 7))
      ];
      return FinWindow(out, out.length - 1);
    case FinPeriod.month:
      final last = a.year == today.year ? today.month : (a.year < today.year ? 12 : 0);
      final n = last < 1 ? a.month : last;
      final out = [
        for (var m = 1; m <= n; m++)
          FinBucket(tr.monthNames[m].substring(0, 3), DateTime(a.year, m), DateTime(a.year, m + 1))
      ];
      return FinWindow(out, (a.month - 1).clamp(0, out.length - 1));
    case FinPeriod.year:
      final out = [
        for (var y = a.year - 4; y <= a.year; y++)
          FinBucket('$y', DateTime(y), DateTime(y + 1))
      ];
      return FinWindow(out, out.length - 1);
    case FinPeriod.custom:
      final (f, t) = sel.range; // t - день після останнього
      final days = t.difference(f).inDays;
      final out = <FinBucket>[];
      if (days <= 93) {
        for (var s = f; s.isBefore(t); s = DateTime(s.year, s.month, s.day + 7)) {
          final e = DateTime(s.year, s.month, s.day + 7);
          out.add(FinBucket(_dm(s), s, e.isAfter(t) ? t : e));
        }
      } else if (days <= 1100) {
        for (var s = DateTime(f.year, f.month); s.isBefore(t); s = DateTime(s.year, s.month + 1)) {
          final e = DateTime(s.year, s.month + 1);
          out.add(FinBucket(tr.monthNames[s.month].substring(0, 3),
              s.isBefore(f) ? f : s, e.isAfter(t) ? t : e));
        }
      } else {
        for (var y = f.year; y <= t.year && DateTime(y).isBefore(t); y++) {
          out.add(FinBucket('$y', DateTime(y).isBefore(f) ? f : DateTime(y),
              DateTime(y + 1).isAfter(t) ? t : DateTime(y + 1)));
        }
      }
      return FinWindow(out, null);
  }
}

/// Значення лінії за кожну точку. Скасовані й виключені зі статистики записи не
/// рахуються; [where] залишає лише записи однієї категорії чи рахунку.
List<double> finSeries(Iterable<FinEntry> entries, List<FinBucket> buckets, FinStatKind kind,
    {bool Function(FinEntry)? where}) {
  final out = List.filled(buckets.length, 0.0);
  for (final e in entries) {
    if (e.cancelled || e.noStats) continue;
    if (where != null && !where(e)) continue;
    if (kind == FinStatKind.expense && !e.isExpense) continue;
    if (kind == FinStatKind.income && e.isExpense) continue;
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i].contains(e.date)) {
        out[i] += kind == FinStatKind.result && e.isExpense ? -e.amount : e.amount;
        break;
      }
    }
  }
  return out;
}
