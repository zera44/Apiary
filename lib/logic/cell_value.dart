/// Значення клітинки заготовки.
///
/// У JSON шаблону зберігається або рядком ("hive", "obstacle",
/// "obstacle:trees"), або — якщо для клітинки задано власні
/// "Характеристики" — словником {"type","variant","icon","color","parameters"}.
/// Формат сумісний зі старою Python-версією.
class CellValue {
  final String type; // 'hive' | 'obstacle'
  final String? variant; // для перешкоди, типово 'mountain'
  final String? icon;
  final String? color;
  final List<String> parameters;

  const CellValue({
    required this.type,
    this.variant,
    this.icon,
    this.color,
    this.parameters = const [],
  });

  bool get isHive => type == 'hive';

  /// Варіант для малювання (у вулика варіанту немає).
  String? get effectiveVariant => isHive ? null : (variant ?? 'mountain');

  /// Рядок "hive" / "obstacle:<variant>".
  String get typeString => isHive ? 'hive' : 'obstacle:${effectiveVariant!}';

  bool get hasOverrides =>
      icon != null || color != null || parameters.isNotEmpty;

  static CellValue parse(dynamic raw) {
    if (raw is Map) {
      final params = raw['parameters'];
      return CellValue(
        type: (raw['type'] as String?) ?? 'hive',
        variant: raw['variant'] as String?,
        icon: raw['icon'] as String?,
        color: raw['color'] as String?,
        parameters: params is List ? params.map((e) => e.toString()).toList() : const [],
      );
    }
    final s = (raw as String?) ?? 'hive';
    final i = s.indexOf(':');
    if (i >= 0) {
      return CellValue(type: s.substring(0, i), variant: s.substring(i + 1));
    }
    return CellValue(type: s);
  }

  /// Серіалізація назад у JSON шаблону: рядком, якщо перевизначень
  /// немає (як і раніше), інакше — словником.
  dynamic toJson() {
    if (!hasOverrides) return typeString;
    return {
      'type': type,
      'variant': isHive ? null : effectiveVariant,
      'icon': icon,
      'color': color,
      'parameters': parameters,
    };
  }

  CellValue copyWith({
    String? type,
    String? variant,
    Object? icon = _unset,
    Object? color = _unset,
    List<String>? parameters,
  }) =>
      CellValue(
        type: type ?? this.type,
        variant: variant ?? this.variant,
        icon: identical(icon, _unset) ? this.icon : icon as String?,
        color: identical(color, _unset) ? this.color : color as String?,
        parameters: parameters ?? this.parameters,
      );

  /// Ознака "однаковості" для візуального злиття сусідніх клітинок:
  /// тип + варіант (у вулика варіант не враховується) + іконка + колір.
  String get mergeKey => '$typeString|${icon ?? ''}|${color ?? ''}';
}

const Object _unset = Object();

/// Розбір ключа "col,row".
(int, int)? parseCellKey(String key) {
  final parts = key.split(',');
  if (parts.length != 2) return null;
  final c = int.tryParse(parts[0].trim());
  final r = int.tryParse(parts[1].trim());
  if (c == null || r == null) return null;
  return (c, r);
}
