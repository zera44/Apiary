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

  /// Номер першої видимої точки серед усіх (для тижнів і років); для місяця й
  /// власного періоду - 0.
  final int start;

  /// Скільки всього точок є (видимих - [buckets]).
  final int total;
  const FinWindow(this.buckets, this.selected, {this.start = 0, int? total})
      : total = total ?? 0;

  DateTime get from => buckets.first.from;
  DateTime get to => buckets.last.to;
}

/// Де стоїть вікно з [n] видимих точок серед [total], коли вибрано точку [sel]:
/// вікно лишається [start] (null - найновіше), поки вибір не торкнеться краю;
/// тоді воно зсувається так, щоб збоку лишилася ще одна точка. На межі даних
/// вікно далі не їде.
int finWindowStart(int? start, int sel, int n, int total) {
  var st = start ?? total - n;
  if (sel - 1 < st) st = sel - 1;
  if (sel + 1 > st + n - 1) st = sel + 2 - n;
  return st.clamp(0, total > n ? total - n : 0);
}

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// Скільки видимих точок: тижні й роки.
const kFinWeekPoints = 12;
const kFinYearPoints = 5;

/// Точки лінії для періоду [sel]: тиждень - 12 тижнів, рік - 5 років, місяць -
/// місяці року, власний період - його тижні (чи місяці, чи роки, коли період
/// довгий). Майбутнє не показуємо. Для тижнів і років [earliest] - найраніша
/// дата з даними, [start] - де зараз стоїть вікно (див. [finWindowStart]).
FinWindow finWindow(FinPeriodSel sel, {DateTime? now, DateTime? earliest, int? start}) {
  final today = now == null ? FinPeriodSel.today() : DateTime(now.year, now.month, now.day);
  final a = sel.anchor;
  switch (sel.period) {
    case FinPeriod.day:
    case FinPeriod.week:
      DateTime monday(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
      final cur = monday(a.isAfter(today) ? today : a);
      final last = monday(today);
      var first = earliest == null ? last : monday(earliest);
      // завжди є принаймні 12 тижнів до найновішого
      final minFirst = DateTime(last.year, last.month, last.day - 7 * (kFinWeekPoints - 1));
      if (first.isAfter(minFirst)) first = minFirst;
      final all = <FinBucket>[];
      for (var m = first; !m.isAfter(last); m = DateTime(m.year, m.month, m.day + 7)) {
        all.add(FinBucket(_dm(m), m, DateTime(m.year, m.month, m.day + 7)));
      }
      var idx = all.indexWhere((b) => b.contains(cur));
      if (idx < 0) idx = cur.isBefore(first) ? 0 : all.length - 1;
      final st = finWindowStart(start, idx, kFinWeekPoints, all.length);
      return FinWindow(all.sublist(st, st + kFinWeekPoints), idx - st,
          start: st, total: all.length);
    case FinPeriod.month:
      final lastM = a.year == today.year ? today.month : (a.year < today.year ? 12 : 0);
      final n = lastM < 1 ? a.month : lastM;
      final out = [
        for (var m = 1; m <= n; m++)
          FinBucket(tr.monthNames[m].substring(0, 3), DateTime(a.year, m), DateTime(a.year, m + 1))
      ];
      return FinWindow(out, (a.month - 1).clamp(0, out.length - 1), total: out.length);
    case FinPeriod.year:
      var first = earliest == null ? today.year : earliest.year;
      if (first > today.year - (kFinYearPoints - 1)) first = today.year - (kFinYearPoints - 1);
      final all = [
        for (var y = first; y <= today.year; y++) FinBucket('$y', DateTime(y), DateTime(y + 1))
      ];
      var idx = all.indexWhere((b) => b.from.year == a.year);
      if (idx < 0) idx = a.year < first ? 0 : all.length - 1;
      final st = finWindowStart(start, idx, kFinYearPoints, all.length);
      return FinWindow(all.sublist(st, st + kFinYearPoints), idx - st,
          start: st, total: all.length);
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
      return FinWindow(out, null, total: out.length);
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
