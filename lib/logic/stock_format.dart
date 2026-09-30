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

/// Причини списання (вибуття).
const kWriteOffReasons = ['Підгодівля', 'Лікування', 'Продаж', 'Використано', 'Зіпсовано', 'Інше'];

/// Назва операції складу для історії.
String stockMoveTitle(String kind, String? reason) => switch (kind) {
      'out' => reason == null || reason.isEmpty ? 'Списано' : 'Списано: $reason',
      'set' => 'Перезаписано (старий запис)',
      _ => 'Прихід',
    };
