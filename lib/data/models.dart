import 'dart:convert';
import '../l10n/l10n.dart';

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

  /// Мінімальний залишок (null — не стежити): досягли — «час докупити».
  final double? minQuantity;

  const StockItem({
    required this.id,
    required this.name,
    required this.unit,
    this.quantity,
    this.photo,
    this.minQuantity,
  });

  /// Час докупити: залишок дійшов до мінімального.
  bool get low => minQuantity != null && (quantity ?? 0) <= minQuantity! + 1e-9;

  factory StockItem.fromRow(Map<String, Object?> r) => StockItem(
        id: r['id'] as String,
        name: r['name'] as String,
        unit: r['unit'] as String,
        quantity: (r['quantity'] as num?)?.toDouble(),
        photo: r['photo'] as String?,
        minQuantity: (r['min_quantity'] as num?)?.toDouble(),
      );
}

/// Типи даних параметра.
class DataTypes {
  static const text = 'text';
  static const int_ = 'int';
  static const float_ = 'float';
  static const date = 'date';
  static const color = 'color';
  static const bool_ = 'bool';

  /// Вибір зі списку значень, які задають у параметрі ([Parameter.options]).
  static const choice = 'choice';

  static const yes = 'Так';
  static const no = 'Ні';

  static const keys = [text, int_, float_, date, bool_, choice, color];

  /// Типи з назвами поточною мовою.
  static List<(String, String)> get all =>
      [for (var i = 0; i < keys.length; i++) (keys[i], tr.dataTypeLabels[i])];

  static String label(String? key) {
    for (final (k, l) in all) {
      if (k == key) return l;
    }
    return tr.dataTypeLabels.first;
  }
}

/// Параметр із каталогу («Таблиця параметрів»).
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

  /// Для типу «Список» — варіанти, з яких обирають під час огляду.
  final List<String> options;

  const Parameter({
    required this.id,
    required this.name,
    this.unit,
    this.options = const [],
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
        options: decodeOptions(m['options'] as String?),
      );

  /// Варіанти списку зберігаються JSON-масивом рядків.
  static List<String> decodeOptions(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      if (v is List) return [for (final e in v) if (e is String && e.trim().isNotEmpty) e.trim()];
    } catch (_) {}
    return const [];
  }

  static String encodeOptions(List<String> options) => jsonEncode(options);

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

  /// Власник (id на сервері); null - своя пасіка (власник цього телефона).
  /// Не null - пасіка, до якої мене запросили помічником.
  final String? ownerId;

  const Apiary({
    required this.id,
    required this.name,
    this.lat,
    this.lon,
    this.deleted = false,
    this.updatedAt = 0,
    this.visitPeriod,
    this.ownerId,
  });

  bool get hasLocation => lat != null && lon != null;

  /// Своя пасіка (а не та, де я помічник).
  bool get isMine => ownerId == null;

  factory Apiary.fromMap(Map<String, Object?> m) => Apiary(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Пасіка',
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        deleted: ((m['deleted'] as num?) ?? 0) != 0,
        updatedAt: ((m['updated_at'] as num?) ?? 0).toDouble(),
        visitPeriod: (m['visit_period'] as num?)?.toInt(),
        ownerId: m['owner_id'] as String?,
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

/// Вулик (або група-вулик) у «Звіті по пасіці».
class ReportHive {
  final EntityRef ref;
  final String label;
  const ReportHive({required this.ref, required this.label});
}

/// Один запис історії у «Звіті по пасіці».
class ReportRecord {
  final String hive;
  final String parameterId;
  final String? value;
  final double createdAt;
  const ReportRecord({
    required this.hive,
    required this.parameterId,
    required this.value,
    required this.createdAt,
  });
}

/// Дані «Звіту по пасіці»: вулики × параметри + історія.
class ApiaryReport {
  final List<ReportHive> hives;
  final List<Parameter> parameters;
  final Map<EntityRef, Map<String, String?>> latest;
  final List<ReportRecord> history;
  const ApiaryReport({
    required this.hives,
    required this.parameters,
    required this.latest,
    required this.history,
  });
}

/// Група параметрів у «Конструкторі»: заголовок і впорядковані id параметрів
/// під ним. Групи спільні для всіх вуликів; на панелі показуються лише ті
/// параметри групи, що обрані для цього вулика.
class ParamGroup {
  final String id;
  String name;
  List<String> ids;
  ParamGroup({required this.id, required this.name, List<String>? ids}) : ids = ids ?? [];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ids': ids};

  factory ParamGroup.fromJson(Map<String, dynamic> j) => ParamGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        ids: [for (final x in (j['ids'] as List? ?? const [])) x as String],
      );
}
