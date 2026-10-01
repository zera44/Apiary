// Моделі даних застосунку "Моя пасіка".
//
// Схема таблиць навмисно збігається зі старою Python-версією (db.py), тож
// стару базу apiary.db можна відкрити без конвертації.

/// Об'єкт на карті — вулик ('hive') або перешкода ('obstacle').
///
/// Координати — клітинки сітки; вісь y спрямована ВГОРУ (як у старій
/// версії): клітинка (x, y + 1) — над клітинкою (x, y).
class MapElement {
  final String id;
  final int x;
  final int y;
  final String type;
  final String? label;
  final int rotation;
  final bool archived;
  final bool deleted;
  final double updatedAt;
  final bool synced;
  final String? groupId;
  final String? variant;
  final String? icon;
  final String? color;
  final String? apiaryId;

  const MapElement({
    required this.id,
    required this.x,
    required this.y,
    this.type = 'hive',
    this.label,
    this.rotation = 0,
    this.archived = false,
    this.deleted = false,
    this.updatedAt = 0,
    this.synced = false,
    this.groupId,
    this.variant,
    this.icon,
    this.color,
    this.apiaryId,
  });

  bool get isHive => type == 'hive';

  factory MapElement.fromMap(Map<String, Object?> m) => MapElement(
        id: m['id'] as String,
        x: (m['x'] as num).toInt(),
        y: (m['y'] as num).toInt(),
        type: (m['type'] as String?) ?? 'hive',
        label: m['label'] as String?,
        rotation: ((m['rotation'] as num?) ?? 0).toInt(),
        archived: ((m['archived'] as num?) ?? 0) != 0,
        deleted: ((m['deleted'] as num?) ?? 0) != 0,
        updatedAt: ((m['updated_at'] as num?) ?? 0).toDouble(),
        synced: ((m['synced'] as num?) ?? 0) != 0,
        groupId: m['group_id'] as String?,
        variant: m['variant'] as String?,
        icon: m['icon'] as String?,
        color: m['color'] as String?,
        apiaryId: m['apiary_id'] as String?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'x': x,
        'y': y,
        'type': type,
        'label': label,
        'rotation': rotation,
        'archived': archived ? 1 : 0,
        'deleted': deleted ? 1 : 0,
        'updated_at': updatedAt,
        'synced': synced ? 1 : 0,
        'group_id': groupId,
        'variant': variant,
        'icon': icon,
        'color': color,
        'apiary_id': apiaryId,
      };

  /// Посилання на "сутність", до якої чіпляються параметри: вся група,
  /// якщо об'єкт у групі, інакше — сам об'єкт.
  EntityRef get entity =>
      groupId != null ? EntityRef.group(groupId!) : EntityRef.element(id);
}

/// Рівно одне з [groupId] / [elementId] заповнене: група означає "всі
/// елементи цієї групи разом".
class EntityRef {
  final String? groupId;
  final String? elementId;

  const EntityRef.group(String this.groupId) : elementId = null;
  const EntityRef.element(String this.elementId) : groupId = null;

  bool get isGroup => groupId != null;

  @override
  bool operator ==(Object other) =>
      other is EntityRef && other.groupId == groupId && other.elementId == elementId;

  @override
  int get hashCode => Object.hash(groupId, elementId);
}

/// Заготовка (шаблон) конфігурації.
///
/// [cells]: {"col,row": значення}; рядок 0 — ВЕРХНІЙ ряд заготовки.
/// Значення — рядок ("hive" / "obstacle:<variant>") або словник
/// {"type","variant","icon","color","parameters"} (див. [CellValue]).
class ApiaryTemplate {
  final String id;
  final String name;
  final int width;
  final int height;
  final Map<String, dynamic> cells;
  final double updatedAt;

  const ApiaryTemplate({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.cells,
    this.updatedAt = 0,
  });
}

/// Номенклатура складу.
class StockItem {
  final String id;
  final String name;
  final String unit;

  /// null — ще жодного разу не заповнювали.
  final double? quantity;

  /// Шлях до фото на цьому пристрої (або null).
  final String? photo;

  const StockItem({
    required this.id,
    required this.name,
    required this.unit,
    this.quantity,
    this.photo,
  });

  factory StockItem.fromRow(Map<String, Object?> r) => StockItem(
        id: r['id'] as String,
        name: r['name'] as String,
        unit: r['unit'] as String,
        quantity: (r['quantity'] as num?)?.toDouble(),
        photo: r['photo'] as String?,
      );
}

/// Типи даних параметра.
class DataTypes {
  static const text = 'text';
  static const int_ = 'int';
  static const float_ = 'float';
  static const date = 'date';
  static const color = 'color';

  static const all = <(String, String)>[
    (text, 'Текст'),
    (int_, 'Число ціле'),
    (float_, 'Число з плаваючою'),
    (date, 'Дата'),
    (color, 'Колір'),
  ];

  static String label(String? key) {
    for (final (k, l) in all) {
      if (k == key) return l;
    }
    return 'Текст';
  }
}

/// Параметр із каталогу ("Список параметрів").
class Parameter {
  final String id;
  final String name;
  final String? unit;
  final String dataType;
  final bool isBase;
  final String? baseType;
  final String? baseKey;
  final bool deleted;
  final double updatedAt;

  const Parameter({
    required this.id,
    required this.name,
    this.unit,
    this.dataType = DataTypes.text,
    this.isBase = false,
    this.baseType,
    this.baseKey,
    this.deleted = false,
    this.updatedAt = 0,
  });

  factory Parameter.fromMap(Map<String, Object?> m) => Parameter(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Параметр',
        unit: m['unit'] as String?,
        dataType: (m['data_type'] as String?) ?? DataTypes.text,
        isBase: ((m['is_base'] as num?) ?? 0) != 0,
        baseType: m['base_type'] as String?,
        baseKey: m['base_key'] as String?,
        deleted: ((m['deleted'] as num?) ?? 0) != 0,
        updatedAt: ((m['updated_at'] as num?) ?? 0).toDouble(),
      );

  String get nameWithUnit =>
      (unit != null && unit!.isNotEmpty) ? '$name ($unit)' : name;
}

/// Пасіка — окрема карта зі своїми вуликами/перешкодами. Застосунок
/// підтримує кілька пасік; [lat]/[lon] — місце на карті (необов'язкове,
/// обране при створенні за геолокацією або вручну).
class Apiary {
  final String id;
  final String name;
  final double? lat;
  final double? lon;
  final bool deleted;
  final double updatedAt;

  /// Періодичність обходу всієї пасіки, днів (null — не задано). Вулик із
  /// власною періодичністю її перекриває.
  final int? visitPeriod;

  const Apiary({
    required this.id,
    required this.name,
    this.lat,
    this.lon,
    this.deleted = false,
    this.updatedAt = 0,
    this.visitPeriod,
  });

  bool get hasLocation => lat != null && lon != null;

  factory Apiary.fromMap(Map<String, Object?> m) => Apiary(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Пасіка',
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        deleted: ((m['deleted'] as num?) ?? 0) != 0,
        updatedAt: ((m['updated_at'] as num?) ?? 0).toDouble(),
        visitPeriod: (m['visit_period'] as num?)?.toInt(),
      );
}

/// Один запис значення параметра (кнопка "Заповнити").
class ParameterRecord {
  final String id;
  final String? groupId;
  final String? elementId;
  final String parameterId;
  final String? value;
  final double createdAt;

  /// Назва об'єкта/групи, якій належить запис (для історії).
  final String entityLabel;

  const ParameterRecord({
    required this.id,
    required this.groupId,
    required this.elementId,
    required this.parameterId,
    required this.value,
    required this.createdAt,
    this.entityLabel = '',
  });
}
