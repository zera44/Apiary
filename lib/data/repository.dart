import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../logic/cell_value.dart';
import '../logic/geometry.dart';
import '../logic/visit_reminders.dart';
import 'models.dart';

/// Назва базової характеристики "дата останнього обходу" (ключ visit_start;
/// раніше називалась "Дата початку обходу").
const kVisitDateName = 'Дата останнього обходу';
const _kOldVisitDateName = 'Дата початку обходу';

/// Базові характеристики: обов'язкові для КОЖНОГО об'єкта свого типу.
/// (стабільний ключ, назва за замовчуванням, одиниця, тип даних)
const Map<String, List<(String, String, String?, String)>> kBaseParameters = {
  'hive': [
    ('visit_period', 'Періодичність обходу', 'днів', DataTypes.int_),
    ('visit_start', kVisitDateName, null, DataTypes.date),
    ('queen_mark', 'Мітка матки', null, DataTypes.color),
  ],
};

/// Таблиці, що синхронізуються з сервером.
const kSyncTables = [
  'apiaries',
  'elements',
  'templates',
  'parameters',
  'element_parameters',
  'parameter_records',
  'qr_codes',
];

/// Усі операції з локальною базою (порт db.py).
class Repository {
  final Database db;
  Repository(this.db);

  /// Лічильник "дані карти змінились" — список пасік слухає його й
  /// оновлює мініатюри (зокрема, коли карту відкрили не з самого списку,
  /// а, наприклад, через сканер QR).
  final ValueNotifier<int> mapChanges = ValueNotifier<int>(0);

  /// Лічильник "могли змінитись дані, від яких залежать нагадування про
  /// обхід" (вулики, пасіки, періодичність, дата обходу) — на нього
  /// підписаний сервіс нагадувань і перебудовує план.
  final ValueNotifier<int> remindersChanged = ValueNotifier<int>(0);
  void _remindersDirty() => remindersChanged.value++;

  static const _uuid = Uuid();
  static String newId() => _uuid.v4();

  /// Unix-час у секундах (дробовий) — так само, як у старій версії.
  static double now() => DateTime.now().microsecondsSinceEpoch / 1e6;

  /// Одноразова ініціалізація після відкриття бази.
  Future<void> init() async {
    await ensureBaseParameters();
    await ensureLegacyApiary();
  }

  // ---------------------------------------------------------------------
  // Пасіки (кілька окремих карт)
  // ---------------------------------------------------------------------

  /// Стара база (з версії до підтримки кількох пасік) мала елементи без
  /// apiary_id — тут вони один раз переносяться в автоматично створену
  /// пасіку "Моя пасіка", щоб не зникли з очей.
  Future<void> ensureLegacyApiary() async {
    final orphans = await db
        .rawQuery('SELECT COUNT(*) c FROM elements WHERE apiary_id IS NULL');
    if (((orphans.first['c'] as num?) ?? 0) == 0) return;
    final existing =
        await db.rawQuery('SELECT id FROM apiaries WHERE deleted = 0 ORDER BY updated_at ASC LIMIT 1');
    final apiaryId = existing.isNotEmpty
        ? existing.first['id'] as String
        : await addApiary('Моя пасіка');
    await db.rawUpdate(
        'UPDATE elements SET apiary_id = ? WHERE apiary_id IS NULL', [apiaryId]);
  }

  Future<String> addApiary(String name, {double? lat, double? lon}) async {
    final id = newId();
    await db.insert('apiaries', {
      'id': id,
      'name': name,
      'lat': lat,
      'lon': lon,
      'updated_at': now(),
      'synced': 0,
      'deleted': 0,
    });
    return id;
  }

  Future<List<Apiary>> listApiaries() async {
    final rows =
        await db.rawQuery('SELECT * FROM apiaries WHERE deleted = 0 ORDER BY rowid ASC');
    return rows.map(Apiary.fromMap).toList();
  }

  Future<Apiary?> getApiary(String id) async {
    final rows = await db.query('apiaries', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Apiary.fromMap(rows.first);
  }

  /// М'яке видалення пасіки разом з усіма її об'єктами (в одній
  /// транзакції). Історія значень лишається (як і для видалених об'єктів),
  /// а самі рядки остаточно прибирає [purgeDeleted] після синхронізації.
  Future<void> deleteApiary(String id) async {
    final t = now();
    await db.transaction((txn) async {
      await txn.update('apiaries', {'deleted': 1, 'synced': 0, 'updated_at': t},
          where: 'id = ?', whereArgs: [id]);
      await txn.update('elements', {'deleted': 1, 'synced': 0, 'updated_at': t},
          where: 'apiary_id = ? AND deleted = 0', whereArgs: [id]);
    });
    _remindersDirty();
  }

  Future<void> updateApiary(String id, {String? name, double? lat, double? lon}) async {
    final fields = <String, Object?>{'updated_at': now(), 'synced': 0};
    if (name != null) fields['name'] = name;
    if (lat != null) fields['lat'] = lat;
    if (lon != null) fields['lon'] = lon;
    await db.update('apiaries', fields, where: 'id = ?', whereArgs: [id]);
    if (name != null) _remindersDirty(); // назва пасіки — у заголовку сповіщення
  }

  // ---------------------------------------------------------------------
  // Базові характеристики
  // ---------------------------------------------------------------------

  /// Ідемпотентно створює базові характеристики. Шукає їх за СТАБІЛЬНИМ
  /// ключем base_key (а не за назвою, як раніше), тож перейменування
  /// більше не породжує дублів.
  ///
  /// Старі записи без ключа (стара база) підхоплюються ЗА ПОРЯДКОМ
  /// СТВОРЕННЯ (rowid), а не за назвою: рядки завжди створювались у тому
  /// самому порядку, що й [kBaseParameters], тож зіставлення позицією
  /// коректне навіть якщо характеристику вже перейменували. Кожен легасі-
  /// рядок обробляється РІВНО ОДИН РАЗ (LIMIT-подібна поведінка через
  /// покроковий обхід списку), тож і випадкові дублікати без base_key не
  /// плодяться — зайві просто лишаються без base_key й більше не
  /// зважуються базовими (див. [baseParameterIds]).
  Future<void> ensureBaseParameters() async {
    for (final entry in kBaseParameters.entries) {
      final baseType = entry.key;
      final legacy = await db.rawQuery(
        'SELECT id FROM parameters WHERE is_base = 1 AND base_type = ? '
        'AND base_key IS NULL AND deleted = 0 ORDER BY rowid ASC',
        [baseType],
      );
      var legacyIdx = 0;
      for (final (key, name, unit, dataType) in entry.value) {
        final exists = await db.rawQuery(
          'SELECT id FROM parameters WHERE is_base = 1 AND base_type = ? AND base_key = ? '
          'AND deleted = 0 LIMIT 1',
          [baseType, key],
        );
        if (exists.isNotEmpty) {
          // стара типова назва → нова (якщо її самі не перейменовували)
          if (key == 'visit_start') {
            await db.rawUpdate(
              'UPDATE parameters SET name = ?, updated_at = ?, synced = 0 WHERE id = ? AND name = ?',
              [kVisitDateName, now(), exists.first['id'], _kOldVisitDateName],
            );
          }
          continue;
        }
        if (legacyIdx < legacy.length) {
          await db.rawUpdate(
            'UPDATE parameters SET base_key = ? WHERE id = ?',
            [key, legacy[legacyIdx]['id']],
          );
          if (key == 'visit_start') {
            await db.rawUpdate(
              'UPDATE parameters SET name = ?, updated_at = ?, synced = 0 WHERE id = ? AND name = ?',
              [kVisitDateName, now(), legacy[legacyIdx]['id'], _kOldVisitDateName],
            );
          }
          legacyIdx++;
          continue;
        }
        await db.insert('parameters', {
          'id': newId(),
          'name': name,
          'unit': unit,
          'data_type': dataType,
          'is_base': 1,
          'base_type': baseType,
          'base_key': key,
          'updated_at': now(),
          'synced': 0,
        });
      }
    }
  }

  /// Id базових характеристик для типу об'єкта — у фіксованому порядку
  /// (як у [kBaseParameters]), незалежно від редагувань.
  Future<List<String>> baseParameterIds(String? elType) async {
    if (elType == null) return [];
    final rows = await db.rawQuery(
      'SELECT id, base_key, updated_at FROM parameters '
      'WHERE is_base = 1 AND base_type = ? AND base_key IS NOT NULL AND deleted = 0',
      [elType],
    );
    final defs = kBaseParameters[elType] ?? const <(String, String, String?, String)>[];
    final order = [for (final b in defs) b.$1];
    int rank(Map<String, Object?> r) {
      final i = order.indexOf((r['base_key'] as String?) ?? '');
      return i < 0 ? order.length : i;
    }

    final sorted = [...rows]..sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        if (c != 0) return c;
        return ((a['updated_at'] as num?) ?? 0).compareTo((b['updated_at'] as num?) ?? 0);
      });
    return [for (final r in sorted) r['id'] as String];
  }

  /// Id базової характеристики за стабільним ключем (наприклад 'visit_start').
  Future<String?> baseParameterId(String elType, String key) async {
    final rows = await db.rawQuery(
      'SELECT id FROM parameters WHERE is_base = 1 AND base_type = ? AND base_key = ? '
      'AND deleted = 0 ORDER BY rowid ASC LIMIT 1',
      [elType, key],
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<Set<String>> allBaseParameterIds() async {
    final rows = await db.rawQuery('SELECT id FROM parameters WHERE is_base = 1');
    return {for (final r in rows) r['id'] as String};
  }

  // ---------------------------------------------------------------------
  // Елементи карти
  // ---------------------------------------------------------------------

  Future<String> addElement(String apiaryId, int x, int y,
      {String type = 'hive', String? label, String? groupId, String? variant}) async {
    final id = newId();
    await db.insert('elements', {
      'id': id,
      'apiary_id': apiaryId,
      'x': x,
      'y': y,
      'type': type,
      'label': label,
      'rotation': 0,
      'updated_at': now(),
      'synced': 0,
      'group_id': groupId,
      'variant': variant,
    });
    return id;
  }

  /// Назва нового екземпляра шаблону з порядковим номером (у межах ЦІЄЇ
  /// пасіки): якщо вже є 2 групи "Лежак…", новий отримає "Лежак 3".
  Future<String> nextGroupLabel(String apiaryId, String name) async {
    final rows = await db.rawQuery(
      'SELECT label FROM elements WHERE deleted = 0 AND group_id IS NOT NULL '
      'AND apiary_id = ? GROUP BY group_id',
      [apiaryId],
    );
    final pattern = RegExp('^${RegExp.escape(name)}(?: \\d+)?\$');
    final count = rows.where((r) {
      final l = r['label'] as String?;
      return l != null && pattern.hasMatch(l);
    }).length;
    return '$name ${count + 1}';
  }

  /// Розмістити заготовку на карті (у пасіці [apiaryId]) як один
  /// згрупований об'єкт. Координати клітинок — відносні, (0,0) — верхній
  /// лівий кут заготовки. Повертає group_id.
  ///
  /// ВИПРАВЛЕНО: вставка елементів і прив'язка параметрів шаблону тепер
  /// в ОДНІЙ транзакції — якщо прив'язка параметрів не вдасться, елементи
  /// теж не збережуться (раніше збій міг лишити елементи на карті без
  /// жодного з параметрів шаблону).
  Future<String> addGroup(String apiaryId, Map<String, dynamic> cells, int anchorX, int anchorY,
      {String? groupLabel}) async {
    final groupId = newId();
    final t = now();
    final allParams = <String>[]; // упорядковано, без дублів
    await db.transaction((txn) async {
      // усі клітинки — одним пакетом (один виклик у SQLite замість N)
      final batch = txn.batch();
      for (final e in cells.entries) {
        final pos = parseCellKey(e.key);
        if (pos == null) continue;
        final (col, row) = pos;
        final v = CellValue.parse(e.value);
        for (final pid in v.parameters) {
          if (!allParams.contains(pid)) allParams.add(pid);
        }
        batch.insert('elements', {
          'id': newId(),
          'apiary_id': apiaryId,
          'x': anchorX + col,
          'y': anchorY - row,
          'type': v.type,
          'label': groupLabel,
          'rotation': 0,
          'updated_at': t,
          'synced': 0,
          'group_id': groupId,
          'variant': v.isHive ? null : v.effectiveVariant,
          'icon': v.icon,
          'color': v.color,
        });
      }
      await batch.commit(noResult: true);
      if (allParams.isNotEmpty) {
        await setAttachedParameters(allParams, EntityRef.group(groupId), exec: txn);
      }
    });
    return groupId;
  }

  Future<List<MapElement>> listElements(String apiaryId, {bool includeArchived = false}) async {
    final rows = await db.rawQuery(
      'SELECT * FROM elements WHERE deleted = 0 AND apiary_id = ?'
      '${includeArchived ? '' : ' AND archived = 0'}',
      [apiaryId],
    );
    return rows.map(MapElement.fromMap).toList();
  }

  /// Елементи кількох пасік ОДНИМ запитом (для мініатюр у списку пасік;
  /// раніше — окремий запит на кожну пасіку).
  Future<Map<String, List<MapElement>>> listElementsByApiary(Iterable<String> apiaryIds) async {
    final ids = apiaryIds.toList();
    final out = {for (final id in ids) id: <MapElement>[]};
    const chunk = 400; // запас під ліміт змінних SQLite
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
      final rows = await db.rawQuery(
        'SELECT * FROM elements WHERE deleted = 0 AND archived = 0 '
        'AND apiary_id IN (${List.filled(part.length, '?').join(',')})',
        part,
      );
      for (final r in rows) {
        out[r['apiary_id'] as String]?.add(MapElement.fromMap(r));
      }
    }
    return out;
  }

  Future<MapElement?> getElement(String id) async {
    final rows = await db.query('elements', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : MapElement.fromMap(rows.first);
  }

  Future<List<MapElement>> getGroupElements(String groupId) async {
    final rows = await db.query('elements',
        where: 'group_id = ? AND deleted = 0', whereArgs: [groupId]);
    return rows.map(MapElement.fromMap).toList();
  }

  Future<void> updateElement(String id, Map<String, Object?> fields) async {
    if (fields.isEmpty) return;
    await db.update('elements', {...fields, 'updated_at': now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
    if (_affectsReminders(fields)) _remindersDirty();
  }

  /// Зміни, що впливають на нагадування: видалення/архів/назва/тип.
  static bool _affectsReminders(Map<String, Object?> f) =>
      f.containsKey('deleted') ||
      f.containsKey('archived') ||
      f.containsKey('label') ||
      f.containsKey('type');

  Future<void> updateGroup(String groupId, Map<String, Object?> fields) async {
    if (fields.isEmpty) return;
    await db.update('elements', {...fields, 'updated_at': now(), 'synced': 0},
        where: 'group_id = ?', whereArgs: [groupId]);
    if (_affectsReminders(fields)) _remindersDirty();
  }

  Future<void> moveElement(String id, int x, int y) => updateElement(id, {'x': x, 'y': y});

  Future<void> moveGroup(String groupId, int dx, int dy) async {
    if (dx == 0 && dy == 0) return;
    await db.rawUpdate(
      'UPDATE elements SET x = x + ?, y = y + ?, updated_at = ?, synced = 0 WHERE group_id = ?',
      [dx, dy, now(), groupId],
    );
  }

  Future<void> rotateElement(String id) async {
    final el = await getElement(id);
    if (el == null) return;
    await updateElement(id, {'rotation': (el.rotation + 90) % 360});
  }

  /// Повернути групу на 90° як жорстку фігуру (цілочисельно).
  Future<void> rotateGroup(String groupId) async {
    final els = await getGroupElements(groupId);
    if (els.isEmpty) return;
    final newPos = rotatedPositions({for (final e in els) e.id: (e.x, e.y)});
    final t = now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in els) {
        final (nx, ny) = newPos[e.id]!;
        batch.update(
          'elements',
          {'x': nx, 'y': ny, 'rotation': (e.rotation + 90) % 360, 'updated_at': t, 'synced': 0},
          where: 'id = ?',
          whereArgs: [e.id],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> archiveElement(String id) => updateElement(id, {'archived': 1});
  Future<void> archiveGroup(String groupId) => updateGroup(groupId, {'archived': 1});

  /// М'яке видалення — рядок лишається до синхронізації.
  Future<void> deleteElement(String id) => updateElement(id, {'deleted': 1});
  Future<void> deleteGroup(String groupId) => updateGroup(groupId, {'deleted': 1});

  Future<void> renameGroup(String groupId, String name) => updateGroup(groupId, {'label': name});
  Future<void> setGroupIcon(String groupId, String? icon) => updateGroup(groupId, {'icon': icon});
  Future<void> setGroupColor(String groupId, String? color) =>
      updateGroup(groupId, {'color': color});

  /// "На крок назад": записати назад повний знімок елементів.
  ///
  /// ВИПРАВЛЕНО: раніше тут був UPDATE, і якщо фонова синхронізація
  /// встигла остаточно прибрати видалений рядок, undo мовчки нічого не
  /// відновлював. Тепер — INSERT OR REPLACE, рядок відновлюється завжди.
  Future<void> restoreElements(List<MapElement> rows) async {
    if (rows.isEmpty) return;
    final t = now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        final m = r.toMap()
          ..['updated_at'] = t
          ..['synced'] = 0;
        batch.insert('elements', m, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    _remindersDirty();
  }

  /// Поточні (не видалені) прив'язки параметрів об'єкта/групи — повні
  /// рядки, для знімка ПЕРЕД видаленням (див. [restoreParameterBindings]).
  Future<List<Map<String, Object?>>> attachedParameterRows(EntityRef e) async {
    final (w, args) = _ownerWhere(e);
    return db.query('element_parameters', where: '$w AND deleted = 0', whereArgs: args);
  }

  /// ВИПРАВЛЕНО: "крок назад" після видалення об'єкта раніше відновлював
  /// лише сам об'єкт (таблицю elements), а прив'язані до нього параметри
  /// (не базові) губились, якщо фонова синхронізація встигла остаточно
  /// прибрати їх з бази до натискання "Крок назад". Тепер прив'язки
  /// відновлюються зі знімка, зробленого перед видаленням.
  Future<void> restoreParameterBindings(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final t = now();
    await db.transaction((txn) async {
      for (final r in rows) {
        final m = {...r, 'updated_at': t, 'synced': 0, 'deleted': 0};
        await txn.insert('element_parameters', m, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ---------------------------------------------------------------------
  // QR-коди вуликів
  // ---------------------------------------------------------------------

  /// Нормалізація відсканованого тексту: без пробілів/переносів по краях.
  static String normalizeQr(String raw) => raw.trim();

  /// Префікс кодів, які генерує сам застосунок. Такий код — не посилання:
  /// його розуміє лише "Моя пасіка" (сканер у меню).
  static const appQrPrefix = 'MYAPIARY:H:';

  /// Номер наліпки з коду застосунку ("MYAPIARY:H:12:ab34cd56" -> 12).
  static int? appQrNumber(String code) {
    final m = RegExp('^${RegExp.escape(appQrPrefix)}(\\d+):').firstMatch(code);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Номер наліпки, введений вручну: "12", "#12", "№ 0012".
  static int? typedQrNumber(String text) {
    final m = RegExp(r'^[#№]?\s*(\d{1,9})$').firstMatch(text.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Прив'язати [code] до об'єкта/групи. Попередня прив'язка цього коду (до
  /// іншого вулика) і попередній код цього вулика знімаються — завжди
  /// "один код — один вулик".
  Future<void> linkQr(String code, EntityRef e) async {
    final c = normalizeQr(code);
    if (c.isEmpty) return;
    final t = now();
    final (w, args) = _ownerWhere(e);
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE qr_codes SET deleted = 1, synced = 0, updated_at = ? '
        'WHERE deleted = 0 AND (code = ? OR ($w))',
        [t, c, ...args],
      );
      await txn.insert('qr_codes', {
        'id': newId(),
        'code': c,
        'number': appQrNumber(c),
        'group_id': e.groupId,
        'element_id': e.elementId,
        'deleted': 0,
        'updated_at': t,
        'synced': 0,
      });
    });
  }

  /// Згенерувати НОВІ коди застосунку для вуликів [els] (кожен вулик — свій
  /// код, навіть усередині групи). Попередній власний код вулика стає
  /// неактивним: стара наліпка більше нічого не відкриває. Результат — у
  /// тому ж порядку, що й [els].
  Future<List<({String elementId, String code, int? number})>> generateQrForElements(
      List<MapElement> els) async {
    final out = <({String elementId, String code, int? number})>[];
    final t = now();
    await db.transaction((txn) async {
      final maxRow = await txn.rawQuery('SELECT MAX(number) AS m FROM qr_codes');
      var next = ((maxRow.first['m'] as num?) ?? 0).toInt() + 1;
      for (final el in els) {
        await txn.rawUpdate(
          'UPDATE qr_codes SET deleted = 1, synced = 0, updated_at = ? '
          'WHERE deleted = 0 AND element_id = ? AND group_id IS NULL',
          [t, el.id],
        );
        final n = next++;
        final code = '$appQrPrefix$n:${newId().replaceAll('-', '').substring(0, 8)}';
        await txn.insert('qr_codes', {
          'id': newId(),
          'code': code,
          'number': n,
          'group_id': null,
          'element_id': el.id,
          'deleted': 0,
          'updated_at': t,
          'synced': 0,
        });
        out.add((elementId: el.id, code: code, number: n));
      }
    });
    return out;
  }

  /// Id об'єктів пасіки, що вже мають QR-код (власний або своєї групи).
  Future<Set<String>> elementIdsWithQr(String apiaryId) async {
    final rows = await db.rawQuery(
      'SELECT e.id FROM elements e WHERE e.apiary_id = ? AND e.deleted = 0 AND ('
      'EXISTS (SELECT 1 FROM qr_codes q WHERE q.deleted = 0 AND q.element_id = e.id '
      'AND q.group_id IS NULL) OR (e.group_id IS NOT NULL AND EXISTS (SELECT 1 FROM '
      'qr_codes q WHERE q.deleted = 0 AND q.group_id = e.group_id)))',
      [apiaryId],
    );
    return {for (final r in rows) r['id'] as String};
  }

  /// Зняти прив'язку QR-коду з об'єкта/групи.
  Future<void> unlinkQr(EntityRef e) async {
    final (w, args) = _ownerWhere(e);
    await db.rawUpdate(
      'UPDATE qr_codes SET deleted = 1, synced = 0, updated_at = ? WHERE deleted = 0 AND $w',
      [now(), ...args],
    );
  }

  /// Код для панелі об'єкта: власний код вулика, а якщо його немає — код
  /// його групи.
  Future<String?> qrForElement(MapElement el) async =>
      await qrFor(EntityRef.element(el.id)) ??
      (el.groupId != null ? await qrFor(EntityRef.group(el.groupId!)) : null);

  /// Код, прив'язаний до об'єкта/групи, або null.
  Future<String?> qrFor(EntityRef e) async {
    final (w, args) = _ownerWhere(e);
    final rows = await db.rawQuery(
      'SELECT code FROM qr_codes WHERE deleted = 0 AND $w ORDER BY updated_at DESC LIMIT 1',
      args,
    );
    return rows.isEmpty ? null : rows.first['code'] as String?;
  }

  /// Знайти вулик за кодом: елемент (для групи — будь-який її елемент) і
  /// його пасіку. null — код не прив'язаний або вулик/пасіку видалено.
  Future<({MapElement element, Apiary apiary})?> findByQr(String code) async {
    final c = normalizeQr(code);
    if (c.isEmpty) return null;
    // вручну можна ввести лише номер з наліпки
    final typed = typedQrNumber(c);
    final links = typed != null
        ? await db.rawQuery(
            // чужий код теж може складатись лише з цифр — тоді збіг за текстом
            'SELECT group_id, element_id FROM qr_codes WHERE deleted = 0 '
            'AND (number = ? OR code = ?) ORDER BY updated_at DESC',
            [typed, c],
          )
        : await db.rawQuery(
            'SELECT group_id, element_id FROM qr_codes WHERE deleted = 0 AND code = ? '
            'ORDER BY updated_at DESC',
            [c],
          );
    for (final l in links) {
      final gid = l['group_id'] as String?;
      final eid = l['element_id'] as String?;
      MapElement? el;
      if (gid != null) {
        final els = await getGroupElements(gid);
        el = els.isEmpty ? null : els.first;
      } else if (eid != null) {
        final e = await getElement(eid);
        el = (e == null || e.deleted) ? null : e;
      }
      if (el == null || el.archived || el.apiaryId == null) continue;
      final a = await getApiary(el.apiaryId!);
      if (a == null || a.deleted) continue;
      return (element: el, apiary: a);
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Шаблони
  // ---------------------------------------------------------------------

  Future<String> addTemplate(String name, int width, int height, Map<String, dynamic> cells) async {
    final id = newId();
    await db.insert('templates', {
      'id': id,
      'name': name,
      'size': width > height ? width : height,
      'width': width,
      'height': height,
      'cells': jsonEncode(cells),
      'updated_at': now(),
      'synced': 0,
    });
    return id;
  }

  ApiaryTemplate _templateFromRow(Map<String, Object?> r) {
    Map<String, dynamic> cells;
    try {
      final decoded = jsonDecode((r['cells'] as String?) ?? '{}');
      cells = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      cells = {};
    }
    final size = ((r['size'] as num?) ?? 1).toInt();
    return ApiaryTemplate(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? 'Шаблон',
      width: ((r['width'] as num?) ?? size).toInt(),
      height: ((r['height'] as num?) ?? size).toInt(),
      cells: cells,
      updatedAt: ((r['updated_at'] as num?) ?? 0).toDouble(),
    );
  }

  Future<List<ApiaryTemplate>> listTemplates() async {
    final rows = await db.rawQuery(
        'SELECT * FROM templates WHERE deleted = 0 ORDER BY updated_at DESC');
    return rows.map(_templateFromRow).toList();
  }

  Future<ApiaryTemplate?> getTemplate(String id) async {
    final rows = await db.query('templates', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _templateFromRow(rows.first);
  }

  Future<void> updateTemplate(String id,
      {String? name, int? width, int? height, Map<String, dynamic>? cells}) async {
    final fields = <String, Object?>{'updated_at': now(), 'synced': 0};
    if (name != null) fields['name'] = name;
    if (width != null) fields['width'] = width;
    if (height != null) fields['height'] = height;
    if (width != null || height != null) {
      final cur = await getTemplate(id);
      final w = width ?? cur?.width ?? 1;
      final h = height ?? cur?.height ?? 1;
      fields['size'] = w > h ? w : h;
    }
    if (cells != null) fields['cells'] = jsonEncode(cells);
    await db.update('templates', fields, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTemplate(String id) async {
    await db.update('templates', {'deleted': 1, 'synced': 0, 'updated_at': now()},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Каталог параметрів
  // ---------------------------------------------------------------------

  Future<String> addParameter(String name, {String? unit, String dataType = DataTypes.text}) async {
    final id = newId();
    await db.insert('parameters', {
      'id': id,
      'name': name,
      'unit': unit,
      'data_type': dataType,
      'updated_at': now(),
      'synced': 0,
    });
    return id;
  }

  Future<List<Parameter>> listParameters() async {
    final rows = await db.rawQuery(
        'SELECT * FROM parameters WHERE deleted = 0 ORDER BY updated_at DESC');
    return rows.map(Parameter.fromMap).toList();
  }

  Future<Parameter?> getParameter(String id) async {
    final rows = await db.query('parameters', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Parameter.fromMap(rows.first);
  }

  Future<void> updateParameter(String id, Map<String, Object?> fields) async {
    if (fields.isEmpty) return;
    await db.update('parameters', {...fields, 'updated_at': now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteParameter(String id) => updateParameter(id, {'deleted': 1});

  // ---------------------------------------------------------------------
  // Прив'язка параметрів до об'єктів
  // ---------------------------------------------------------------------

  (String, List<Object?>) _ownerWhere(EntityRef e, {String prefix = ''}) {
    if (e.isGroup) return ('${prefix}group_id = ?', [e.groupId]);
    return ('${prefix}element_id = ? AND ${prefix}group_id IS NULL', [e.elementId]);
  }

  /// Id параметрів, прив'язаних до об'єкта/групи, у порядку вибору; попереду
  /// — базові характеристики для [elType] (вони ніколи не зберігаються
  /// окремо, а "домальовуються" для кожного об'єкта свого типу).
  Future<List<String>> attachedParameterIds(EntityRef e, {String? elType}) async {
    final (w, args) = _ownerWhere(e);
    final rows = await db.rawQuery(
      'SELECT parameter_id FROM element_parameters WHERE $w AND deleted = 0 ORDER BY sort_order',
      args,
    );
    final stored = [for (final r in rows) r['parameter_id'] as String];
    final base = [
      for (final id in await baseParameterIds(elType))
        if (!stored.contains(id)) id
    ];
    return [...base, ...stored];
  }

  Future<List<Parameter>> attachedParameters(EntityRef e, {String? elType}) async {
    final ids = await attachedParameterIds(e, elType: elType);
    final result = <Parameter>[];
    for (final id in ids) {
      final p = await getParameter(id);
      if (p != null && !p.deleted) result.add(p);
    }
    return result;
  }

  /// Повністю ЗАМІНИТИ набір прив'язаних параметрів (порядок має
  /// значення). Базові характеристики сюди ніколи не записуються, і так
  /// само ВИПРАВЛЕНО: id уже видалених (deleted=1) параметрів теж
  /// відкидаються — інакше зі старого, ще не оновленого знімка (шаблон,
  /// панель вибору) могла відродитись "зомбі"-прив'язка до параметра,
  /// якого вже немає в каталозі.
  ///
  /// [exec] — необов'язковий виконавець (наприклад, [Transaction] з уже
  /// відкритої транзакції), щоб викликати цей метод атомарно разом з
  /// іншими записами (див. [addGroup]). Без нього метод відкриває свою
  /// власну транзакцію, як і раніше.
  Future<void> setAttachedParameters(List<String> parameterIds, EntityRef e,
      {DatabaseExecutor? exec}) async {
    Future<void> run(DatabaseExecutor x) async {
      final baseRows = await x.rawQuery('SELECT id FROM parameters WHERE is_base = 1');
      final base = {for (final r in baseRows) r['id'] as String};
      final deadRows = await x.rawQuery('SELECT id FROM parameters WHERE deleted = 1');
      final dead = {for (final r in deadRows) r['id'] as String};
      final ids = <String>[];
      for (final id in parameterIds) {
        if (!base.contains(id) && !dead.contains(id) && !ids.contains(id)) ids.add(id);
      }
      final t = now();
      final (w, args) = _ownerWhere(e);
      await x.rawUpdate(
        'UPDATE element_parameters SET deleted = 1, synced = 0, updated_at = ? WHERE $w AND deleted = 0',
        [t, ...args],
      );
      final batch = x.batch();
      for (var i = 0; i < ids.length; i++) {
        batch.insert('element_parameters', {
          'id': newId(),
          'group_id': e.groupId,
          'element_id': e.elementId,
          'parameter_id': ids[i],
          'updated_at': t,
          'synced': 0,
          'sort_order': i,
          'deleted': 0,
        });
      }
      await batch.commit(noResult: true);
    }

    if (exec != null) {
      await run(exec);
    } else {
      await db.transaction((txn) async => run(txn));
    }
  }

  /// Ids видалених параметрів каталогу — щоб прибрати посилання на них
  /// зі знімків, які не проходять через [setAttachedParameters] напряму
  /// (наприклад, список параметрів екземпляра шаблону, що ще не
  /// розміщений на карті).
  Future<Set<String>> deletedParameterIds() async {
    final rows = await db.rawQuery('SELECT id FROM parameters WHERE deleted = 1');
    return {for (final r in rows) r['id'] as String};
  }

  // ---------------------------------------------------------------------
  // Журнал значень ("Заповнити")
  // ---------------------------------------------------------------------

  /// Додати НОВИЙ запис (історія зберігається, нічого не перезаписується).
  Future<void> addParameterRecord(String parameterId, String value, EntityRef e) async {
    await db.insert('parameter_records', {
      'id': newId(),
      'group_id': e.groupId,
      'element_id': e.elementId,
      'parameter_id': parameterId,
      'value': value,
      'created_at': now(),
      'synced': 0,
    });
    _remindersDirty();
  }

  static String formatVisitDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Обхід зроблено: "Дата останнього обходу" вулика = [when] (сьогодні).
  /// Якщо там уже ця дата — новий запис не додається (без сміття в історії).
  Future<void> markVisited(EntityRef e, {String elType = 'hive', DateTime? when}) async {
    final id = await baseParameterId(elType, 'visit_start');
    if (id == null) return;
    final text = formatVisitDate(when ?? DateTime.now());
    final latest = await latestParameterValues(e);
    if (latest[id] == text) return;
    await addParameterRecord(id, text, e);
  }

  /// Усі вулики (для груп — по одному запису на групу) з їхніми
  /// періодичністю й датою останнього обходу — для нагадувань. Тільки
  /// живі, неархівні вулики у не видалених пасіках.
  Future<List<VisitTarget>> visitTargets() async {
    final periodId = await baseParameterId('hive', 'visit_period');
    final startId = await baseParameterId('hive', 'visit_start');
    if (periodId == null || startId == null) return [];
    final els = await db.rawQuery(
      'SELECT e.id, e.label, e.group_id, a.name AS apiary_name FROM elements e '
      'JOIN apiaries a ON a.id = e.apiary_id '
      "WHERE e.deleted = 0 AND e.archived = 0 AND e.type = 'hive' AND a.deleted = 0 "
      'ORDER BY e.rowid ASC',
    );
    final recs = await db.rawQuery(
      'SELECT group_id, element_id, parameter_id, value, created_at FROM parameter_records '
      'WHERE parameter_id IN (?, ?) ORDER BY created_at ASC, rowid ASC',
      [periodId, startId],
    );
    final period = <String, ({String? value, double at})>{};
    final start = <String, String?>{};
    for (final r in recs) {
      final gid = r['group_id'] as String?;
      final eid = r['element_id'] as String?;
      final owner = gid != null ? 'g:$gid' : 'e:$eid';
      if (r['parameter_id'] == periodId) {
        period[owner] = (value: r['value'] as String?, at: ((r['created_at'] as num?) ?? 0).toDouble());
      } else {
        start[owner] = r['value'] as String?;
      }
    }
    final seen = <String>{};
    final out = <VisitTarget>[];
    for (final r in els) {
      final gid = r['group_id'] as String?;
      final id = r['id'] as String;
      final key = gid != null ? 'g:$gid' : 'e:$id';
      if (!seen.add(key)) continue;
      final p = period[key];
      final n = int.tryParse((p?.value ?? '').trim());
      final label = (r['label'] as String?) ?? '';
      final last = (start[key] ?? '').trim();
      out.add(VisitTarget(
        key: key,
        elementId: id,
        apiaryName: (r['apiary_name'] as String?) ?? '',
        name: label.isEmpty ? 'Вулик' : label,
        periodDays: (n != null && n > 0) ? n : null,
        lastVisit: last.isEmpty ? null : last,
        periodSetAt: p == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch((p.at * 1e6).round()),
      ));
    }
    return out;
  }

  /// Останні значення всіх параметрів об'єкта/групи: {parameter_id: value}.
  Future<Map<String, String?>> latestParameterValues(EntityRef e) async {
    final (w, args) = _ownerWhere(e);
    final rows = await db.rawQuery(
      'SELECT parameter_id, value FROM parameter_records WHERE $w ORDER BY created_at ASC',
      args,
    );
    final latest = <String, String?>{};
    for (final r in rows) {
      latest[r['parameter_id'] as String] = r['value'] as String?;
    }
    return latest;
  }

  /// Час останнього внесеного значення будь-якого параметра (для
  /// "Дата оновлення"), або null.
  Future<double?> lastUpdated(EntityRef e) async {
    final (w, args) = _ownerWhere(e);
    final rows = await db.rawQuery(
        'SELECT MAX(created_at) AS m FROM parameter_records WHERE $w', args);
    final m = rows.isEmpty ? null : rows.first['m'];
    return m == null ? null : (m as num).toDouble();
  }

  /// Назва об'єкта/групи для історії; для видаленого — узагальнена.
  Future<String> entityLabel(EntityRef e) async {
    if (e.isGroup) {
      final els = await getGroupElements(e.groupId!);
      String? label;
      for (final el in els) {
        if (el.label != null && el.label!.isNotEmpty) {
          label = el.label;
          break;
        }
      }
      if (label == null && els.isNotEmpty) {
        label = els.first.isHive ? 'Вулик' : 'Перешкода';
      }
      return label ?? 'Видалена група';
    }
    final el = await getElement(e.elementId!);
    if (el != null && !el.deleted) {
      return (el.label != null && el.label!.isNotEmpty)
          ? el.label!
          : (el.isHive ? 'Вулик' : 'Перешкода');
    }
    return "Видалений об'єкт";
  }

  /// Історія значень ОДНОГО параметра — найновіші першими. Без [entity] —
  /// по всіх об'єктах, з [entity] — лише цього об'єкта/групи.
  Future<List<ParameterRecord>> parameterHistory(String parameterId, {EntityRef? entity}) async {
    List<Map<String, Object?>> rows;
    if (entity != null) {
      final (w, args) = _ownerWhere(entity);
      rows = await db.rawQuery(
        'SELECT * FROM parameter_records WHERE parameter_id = ? AND $w ORDER BY created_at DESC',
        [parameterId, ...args],
      );
    } else {
      rows = await db.rawQuery(
        'SELECT * FROM parameter_records WHERE parameter_id = ? ORDER BY created_at DESC',
        [parameterId],
      );
    }
    final cache = <EntityRef, String>{};
    final result = <ParameterRecord>[];
    for (final r in rows) {
      final gid = r['group_id'] as String?;
      final eid = r['element_id'] as String?;
      final ref = gid != null ? EntityRef.group(gid) : EntityRef.element(eid ?? '');
      final label = cache[ref] ??= await entityLabel(ref);
      result.add(ParameterRecord(
        id: r['id'] as String,
        groupId: gid,
        elementId: eid,
        parameterId: r['parameter_id'] as String,
        value: r['value'] as String?,
        createdAt: ((r['created_at'] as num?) ?? 0).toDouble(),
        entityLabel: label,
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Для синхронізації
  // ---------------------------------------------------------------------

  Future<List<Map<String, Object?>>> unsynced(String table) async {
    assert(kSyncTables.contains(table));
    return db.rawQuery('SELECT * FROM $table WHERE synced = 0');
  }

  /// Позначити рядок синхронізованим — лише якщо його не змінили, поки він
  /// відправлявся (інакше нова зміна загубилась би).
  Future<void> markSynced(String table, Map<String, Object?> sentRow) async {
    assert(kSyncTables.contains(table));
    final stamp = sentRow['updated_at'];
    if (stamp != null) {
      await db.rawUpdate('UPDATE $table SET synced = 1 WHERE id = ? AND updated_at = ?',
          [sentRow['id'], stamp]);
    } else {
      await db.rawUpdate('UPDATE $table SET synced = 1 WHERE id = ?', [sentRow['id']]);
    }
  }

  /// Позначити синхронізованими одразу багато рядків однієї таблиці в ОДНІЙ
  /// транзакції (той самий захист від змін під час відправки, що й у
  /// [markSynced]). Раніше кожен рядок — окрема транзакція з fsync.
  Future<void> markSyncedBatch(String table, List<Map<String, Object?>> sentRows) async {
    assert(kSyncTables.contains(table));
    if (sentRows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in sentRows) {
        final stamp = row['updated_at'];
        if (stamp != null) {
          batch.rawUpdate('UPDATE $table SET synced = 1 WHERE id = ? AND updated_at = ?',
              [row['id'], stamp]);
        } else {
          batch.rawUpdate('UPDATE $table SET synced = 1 WHERE id = ?', [row['id']]);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Остаточно прибрати рядки, позначені deleted, що вже синхронізовані
  /// й видалені давніше за [grace]. (Раніше прибирались одразу — і
  /// "крок назад" після видалення переставав працювати.)
  /// Історію значень видалених об'єктів НЕ чіпаємо — вона лишається
  /// доступною з каталогу параметрів як "Видалений об'єкт".
  Future<void> purgeDeleted({Duration grace = const Duration(days: 7)}) async {
    final cutoff = now() - grace.inSeconds;
    await db.transaction((txn) async {
      // прив'язки параметрів до об'єктів, які зараз будуть прибрані
      await txn.rawDelete(
        'DELETE FROM element_parameters WHERE element_id IN '
        '(SELECT id FROM elements WHERE deleted = 1 AND synced = 1 AND updated_at < ?)',
        [cutoff],
      );
      await txn.rawDelete(
        'DELETE FROM element_parameters WHERE group_id IS NOT NULL AND group_id NOT IN '
        '(SELECT DISTINCT group_id FROM elements WHERE group_id IS NOT NULL AND '
        'NOT (deleted = 1 AND synced = 1 AND updated_at < ?))',
        [cutoff],
      );
      await txn.rawDelete(
          'DELETE FROM elements WHERE deleted = 1 AND synced = 1 AND updated_at < ?', [cutoff]);
      await txn.rawDelete(
          'DELETE FROM templates WHERE deleted = 1 AND synced = 1 AND updated_at < ?', [cutoff]);
      await txn.rawDelete(
          'DELETE FROM element_parameters WHERE deleted = 1 AND synced = 1 AND updated_at < ?',
          [cutoff]);
      await txn.rawDelete(
        'DELETE FROM element_parameters WHERE parameter_id IN '
        '(SELECT id FROM parameters WHERE deleted = 1 AND synced = 1 AND updated_at < ?)',
        [cutoff],
      );
      await txn.rawDelete(
        'DELETE FROM parameter_records WHERE parameter_id IN '
        '(SELECT id FROM parameters WHERE deleted = 1 AND synced = 1 AND updated_at < ?)',
        [cutoff],
      );
      await txn.rawDelete(
          'DELETE FROM parameters WHERE deleted = 1 AND synced = 1 AND updated_at < ?', [cutoff]);
      await txn.rawDelete(
          'DELETE FROM apiaries WHERE deleted = 1 AND synced = 1 AND updated_at < ?', [cutoff]);
      await txn.rawDelete(
          'DELETE FROM qr_codes WHERE deleted = 1 AND synced = 1 AND updated_at < ?', [cutoff]);
    });
  }
}
