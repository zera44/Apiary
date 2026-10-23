/// Переведення одиниць виміру для помічника: маса (т, ц, кг, г), об'єм (л, мл).
/// Між масою й об'ємом - через густину речовини (мед ≈ 1,4 кг/л).
library;

const _mass = {'т': 1000.0, 'ц': 100.0, 'кг': 1.0, 'г': 0.001};
const _volume = {'л': 1.0, 'мл': 0.001};

/// Густина (кг/л) за коренем назви речовини: «мед», «меду», «липовий мед»…
const kDensityByStem = {
  'мед': 1.4,
  'вод': 1.0,
  'сироп': 1.3,
  'олі': 0.92,
  'віск': 0.96,
  'молок': 1.03,
};

/// «Кілограм», «кіло», «кг.», «літрів», «мл» -> кг, л, мл…; невідома - null.
String? normalizeUnit(String raw) {
  final u = raw.trim().toLowerCase().replaceAll('.', '');
  if (_mass.containsKey(u) || _volume.containsKey(u)) return u;
  if (u.startsWith('тонн')) return 'т';
  if (u.startsWith('центнер')) return 'ц';
  if (u.startsWith('кілограм') || u.startsWith('кіло') || u == 'кгр') return 'кг';
  if (u.startsWith('грам') || u == 'гр') return 'г';
  if (u.startsWith('літр')) return 'л';
  if (u.startsWith('мілілітр')) return 'мл';
  return null;
}

/// Густина речовини в кг/л; null - невідома.
double? densityOf(String? substance) {
  final s = (substance ?? '').trim().toLowerCase();
  if (s.isEmpty) return null;
  for (final e in kDensityByStem.entries) {
    if (s.contains(e.key)) return e.value;
  }
  return null;
}

class UnitConversion {
  final double value;
  final String unit;

  /// Густина (кг/л), якщо переводили між масою й об'ємом.
  final double? density;
  const UnitConversion(this.value, this.unit, {this.density});
}

/// [value] з одиниці [from] в [to]. Між масою й об'ємом потрібна [density]
/// (кг/л), інакше ArgumentError.
UnitConversion convertUnits(double value, String from, String to, {double? density}) {
  final f = normalizeUnit(from), t = normalizeUnit(to);
  if (f == null) throw ArgumentError('Невідома одиниця «$from»: вмію т, ц, кг, г, л, мл');
  if (t == null) throw ArgumentError('Невідома одиниця «$to»: вмію т, ц, кг, г, л, мл');
  if (_mass.containsKey(f) && _mass.containsKey(t)) {
    return UnitConversion(value * _mass[f]! / _mass[t]!, t);
  }
  if (_volume.containsKey(f) && _volume.containsKey(t)) {
    return UnitConversion(value * _volume[f]! / _volume[t]!, t);
  }
  if (density == null || density <= 0) {
    throw ArgumentError('Між масою («$f») і об\'ємом («$t») потрібна густина речовини: '
        'вкажіть substance (мед, вода, сироп, олія, віск, молоко) або density у кг/л');
  }
  if (_mass.containsKey(f)) {
    final liters = value * _mass[f]! / density; // кг -> л
    return UnitConversion(liters / _volume[t]!, t, density: density);
  }
  final kg = value * _volume[f]! * density; // л -> кг
  return UnitConversion(kg / _mass[t]!, t, density: density);
}
