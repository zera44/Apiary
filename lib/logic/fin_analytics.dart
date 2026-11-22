import 'dart:math' as math;

import '../data/finance.dart';

/// Скільки різних кольорів лишаємо в одній діаграмі розподілу.
const kFinMaxColored = 6;

/// Один шматок розподілу: категорія ([key] null - «внесено на складі») або
/// зведене «Інше» ([isRest]).
class FinSlice {
  final String? key;
  final double amount;
  final bool isRest;
  const FinSlice(this.key, this.amount, {this.isRest = false});
}

/// Розподіл за категоріями з правилом Парето: якщо категорій не більше
/// [maxColored], показуємо всі кожну своїм кольором. Інакше беремо найбільші, що
/// разом дають 80% суми (не більше `maxColored - 1`), а решту зводимо в одне «Інше»,
/// яке йде останнім.
List<FinSlice> finParetoSlices(Map<String?, double> byCategory, {int maxColored = kFinMaxColored}) {
  final items = byCategory.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = items.fold(0.0, (a, e) => a + e.value);
  if (items.length <= maxColored) {
    return [for (final e in items) FinSlice(e.key, e.value)];
  }
  final top = <FinSlice>[];
  var cum = 0.0;
  for (final e in items) {
    if (cum / total >= 0.8 || top.length >= maxColored - 1) break;
    top.add(FinSlice(e.key, e.value));
    cum += e.value;
  }
  final rest = total - cum;
  return [...top, if (rest > 0) FinSlice(null, rest, isRest: true)];
}

/// Статистика ряду «одна точка = один місяць» для карти контролю.
class FinControlStats {
  final double mean;
  final double median;

  /// Вибіркове стандартне відхилення (n − 1); для однієї точки 0.
  final double sd;

  /// Межі нормальності: середнє ± 2σ, нижня не менша за нуль.
  final double low;
  final double high;

  /// Індекси точок поза межами нормальності.
  final List<int> outside;
  const FinControlStats(this.mean, this.median, this.sd, this.low, this.high, this.outside);
}

FinControlStats finControlStats(List<double> v) {
  if (v.isEmpty) return const FinControlStats(0, 0, 0, 0, 0, []);
  final n = v.length;
  final mean = v.fold(0.0, (a, b) => a + b) / n;
  final sorted = [...v]..sort();
  final median =
      n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  final sd = n > 1
      ? math.sqrt(v.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / (n - 1))
      : 0.0;
  final high = mean + 2 * sd;
  final low = math.max(0.0, mean - 2 * sd);
  final out = <int>[
    for (var i = 0; i < n; i++)
      if (v[i] > high + 1e-9 || v[i] < low - 1e-9) i
  ];
  return FinControlStats(mean, median, sd, low, high, out);
}

/// Сума категорії [categoryId] за кожен із 12 місяців року [year]
/// (дохід чи витрати за [kind]; скасовані й виключені зі статистики не рахуються).
List<double> finCategoryMonths(Iterable<FinEntry> entries, int year, String? categoryId,
    {required String kind}) {
  final out = List.filled(12, 0.0);
  for (final e in entries) {
    if (e.cancelled || e.noStats || e.kind != kind || e.categoryId != categoryId) continue;
    if (e.date.year != year) continue;
    out[e.date.month - 1] += e.amount;
  }
  return out;
}

/// Скільки місяців року мають дані: для поточного року - до поточного місяця
/// включно, для минулих - усі 12, для майбутніх - 0.
int finMonthsWithData(int year, DateTime now) {
  if (year < now.year) return 12;
  if (year > now.year) return 0;
  return now.month;
}
