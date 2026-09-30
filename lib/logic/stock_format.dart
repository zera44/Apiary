/// Числа складу: введення з комою або крапкою, показ — з комою, без зайвих нулів.

/// Розібрати введену кількість. null — не число або від'ємне.
double? parseAmount(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
  return v;
}

/// 5 → "5", 2.5 → "2,5", 0.125 → "0,125", 1/3 → "0,333".
String formatAmount(double v) {
  final r = (v * 1000).roundToDouble() / 1000;
  if (r == r.truncateToDouble()) return r.toInt().toString();
  var s = r.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

/// Готові одиниці виміру (можна ввести й свою).
const kStockUnits = ['шт', 'кг', 'г', 'л', 'мл', 'м', 'рамка', 'упаковка'];

/// Гроші: 2 знаки після коми, без зайвих нулів (12 → "12", 6.5 → "6,50").
String formatMoney(double v) {
  final r = (v * 100).roundToDouble() / 100;
  if (r == r.truncateToDouble()) return r.toInt().toString();
  return r.toStringAsFixed(2).replaceAll('.', ',');
}

/// Назва операції складу для історії ([amount] — для інвентаризації різниця зі знаком).
String stockMoveTitle(String kind, String? reason, {double amount = 0}) => switch (kind) {
      'out' => reason == null || reason.isEmpty ? 'Списано' : 'Списано: $reason',
      'inv' => amount < 0
          ? 'Інвентаризація: нестача'
          : (amount > 0 ? 'Інвентаризація: надлишок' : 'Інвентаризація: без розбіжностей'),
      'cancel' => 'Скасування запису',
      'set' => 'Перезаписано (старий запис)',
      _ => 'Прихід',
    };
