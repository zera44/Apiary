import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_service.dart';
import 'package:apiary/logic/hive_objects.dart';
import 'package:apiary/logic/value_convert.dart';
import 'package:apiary/logic/visit_reminders.dart';
import 'package:apiary/services/excel_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Repository repo;
  late String apiaryId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
    apiaryId = await repo.addApiary('Тестова пасіка');
  });

  tearDown(() async => repo.db.close());

  test('базові характеристики створюються один раз і в сталому порядку', () async {
    await repo.init();
    await repo.init();
    final ids = await repo.baseParameterIds('hive');
    expect(ids.length, 4);
    final names = [for (final id in ids) (await repo.getParameter(id))!.name];
    expect(names, [
      'Кількість днів до обходу',
      'Періодичність обходу',
      'Дата останнього обходу',
      'Мітка матки'
    ]);
  });

  test('стара назва "Дата початку обходу" міняється на "Дата останнього обходу"', () async {
    final id = (await repo.baseParameterId('hive', 'visit_start'))!;
    await repo.updateParameter(id, {'name': 'Дата початку обходу'});
    await repo.init();
    expect((await repo.getParameter(id))!.name, 'Дата останнього обходу');
    // а власна назва користувача не чіпається
    await repo.updateParameter(id, {'name': 'Мій обхід'});
    await repo.init();
    expect((await repo.getParameter(id))!.name, 'Мій обхід');
  });

  test('обхід: дата останнього обходу = сьогодні, без дубля того ж дня', () async {
    final el = await repo.addElement(apiaryId, 1, 1, label: 'Вулик 5');
    final ref = EntityRef.element(el);
    final startId = (await repo.baseParameterId('hive', 'visit_start'))!;
    expect((await repo.latestParameterValues(ref))[startId], isNull); // за замовчуванням порожньо
    await repo.markVisited(ref, when: DateTime(2026, 10, 3));
    await repo.markVisited(ref, when: DateTime(2026, 10, 3));
    expect((await repo.latestParameterValues(ref))[startId], '03.10.2026');
    expect((await repo.parameterHistory(startId, entity: ref)).length, 1);
  });

  test('цілі нагадувань: період + дата, групи одним записом, видалені не беруться', () async {
    final a = await repo.addElement(apiaryId, 1, 1, label: 'Вулик 5');
    final b = await repo.addElement(apiaryId, 2, 1, label: 'Вулик 6');
    final gone = await repo.addElement(apiaryId, 3, 1, label: 'Вулик 7');
    final periodId = (await repo.baseParameterId('hive', 'visit_period'))!;
    final startId = (await repo.baseParameterId('hive', 'visit_start'))!;
    await repo.addParameterRecord(periodId, '2', EntityRef.element(a));
    await repo.addParameterRecord(startId, '01.10.2026', EntityRef.element(a));
    await repo.addParameterRecord(periodId, 'abc', EntityRef.element(b)); // не число
    await repo.addParameterRecord(periodId, '3', EntityRef.element(gone));
    await repo.deleteElement(gone);
    final targets = await repo.visitTargets();
    expect(targets.map((t) => t.name), ['Вулик 5', 'Вулик 6']);
    expect(targets[0].periodDays, 2);
    expect(targets[0].lastVisit, '01.10.2026');
    expect(targets[0].apiaryName, 'Тестова пасіка');
    expect(targets[1].periodDays, isNull);
  });

  test('нагадування перебудовуються після змін пасіки/вулика/обходу', () async {
    var n = 0;
    repo.remindersChanged.addListener(() => n++);
    final el = await repo.addElement(apiaryId, 1, 1);
    await repo.updateElement(el, {'x': 5}); // рух вулика не впливає
    expect(n, 0);
    await repo.updateElement(el, {'label': 'Вулик 9'});
    await repo.deleteElement(el);
    await repo.markVisited(EntityRef.element(el), when: DateTime(2026, 10, 3));
    await repo.updateApiary(apiaryId, name: 'Нова назва');
    await repo.deleteApiary(apiaryId);
    expect(n, 5);
  });

  test('ВИПРАВЛЕНО: перейменування базової характеристики не створює дубль', () async {
    final ids = await repo.baseParameterIds('hive');
    await repo.updateParameter(ids.first, {'name': 'Обхід'});
    await repo.init(); // "перезапуск"
    final after = await repo.baseParameterIds('hive');
    expect(after, ids);
  });

  test('старі базові записи без base_key підхоплюються', () async {
    // імітуємо стару базу: ключі стерто
    await repo.db.rawUpdate('UPDATE parameters SET base_key = NULL');
    await repo.init();
    final all = (await repo.listParameters()).where((p) => p.isBase).toList();
    expect(all.length, 4);
  });

  test('ВИПРАВЛЕНО: перейменована в старій базі характеристика не дублюється', () async {
    // стара база (без base_key), де користувач ще ДО оновлення застосунку
    // перейменував базову характеристику — міграція за назвою це раніше
    // не підхоплювала й створювала дублікат
    await repo.db.rawUpdate('UPDATE parameters SET base_key = NULL');
    final legacy =
        await repo.db.rawQuery('SELECT id FROM parameters WHERE is_base = 1 ORDER BY rowid ASC');
    await repo.updateParameter(legacy.first['id'] as String, {'name': 'Обхід (перейменовано)'});
    await repo.init(); // "оновлення застосунку"
    final all = (await repo.listParameters()).where((p) => p.isBase).toList();
    expect(all.length, 4); // не 5
    final ids = await repo.baseParameterIds('hive');
    expect(ids.length, 4);
    expect((await repo.getParameter(ids.first))!.name, 'Обхід (перейменовано)');
  });

  test('ВИПРАВЛЕНО: "крок назад" відновлює видалений об\'єкт навіть після очистки', () async {
    final id = await repo.addElement(apiaryId, 1, 1);
    final snap = (await repo.getElement(id))!;
    await repo.deleteElement(id);
    // синхронізація позначила й очистила (без пільгового періоду)
    await repo.db.rawUpdate('UPDATE elements SET synced = 1');
    await repo.purgeDeleted(grace: Duration.zero);
    expect(await repo.getElement(id), isNull);
    await repo.restoreElements([snap]);
    final back = await repo.getElement(id);
    expect(back, isNotNull);
    expect(back!.deleted, isFalse);
  });

  test('пільговий період: свіжовидалене не прибирається одразу', () async {
    final id = await repo.addElement(apiaryId, 2, 2);
    await repo.deleteElement(id);
    await repo.db.rawUpdate('UPDATE elements SET synced = 1');
    await repo.purgeDeleted();
    expect(await repo.getElement(id), isNotNull);
  });

  test('ВИПРАВЛЕНО: "крок назад" повертає й прив\'язані параметри після очистки', () async {
    final id = await repo.addElement(apiaryId, 1, 1);
    final snap = (await repo.getElement(id))!;
    final e = EntityRef.element(id);
    final p = await repo.addParameter('Вага');
    await repo.setAttachedParameters([p], e);
    final paramRows = await repo.attachedParameterRows(e); // знімок "до видалення"
    expect(paramRows, isNotEmpty);

    await repo.deleteElement(id);
    await repo.db.rawUpdate('UPDATE elements SET synced = 1');
    await repo.db.rawUpdate('UPDATE element_parameters SET synced = 1');
    await repo.purgeDeleted(grace: Duration.zero);
    expect(await repo.getElement(id), isNull);
    expect(await repo.attachedParameterIds(e), isEmpty); // прив'язку теж прибрано

    await repo.restoreElements([snap]);
    await repo.restoreParameterBindings(paramRows);
    expect(await repo.getElement(id), isNotNull);
    expect(await repo.attachedParameterIds(EntityRef.element(id)), contains(p));
  });

  test('пасіки: елементи різних пасік не перетинаються', () async {
    final otherId = await repo.addApiary('Друга пасіка');
    await repo.addElement(apiaryId, 5, 5);
    await repo.addElement(otherId, 5, 5); // ті самі координати — інша пасіка
    final mine = await repo.listElements(apiaryId);
    final other = await repo.listElements(otherId);
    expect(mine.length, 1);
    expect(other.length, 1);
    expect(mine.first.apiaryId, apiaryId);
    expect(other.first.apiaryId, otherId);
    // автонумерація груп теж окрема для кожної пасіки
    expect(await repo.nextGroupLabel(apiaryId, 'Лежак'), 'Лежак 1');
    await repo.addGroup(otherId, {'0,0': 'hive'}, 0, 0, groupLabel: 'Лежак 1');
    expect(await repo.nextGroupLabel(apiaryId, 'Лежак'), 'Лежак 1'); // друга пасіка не впливає
  });

  test('ВИПРАВЛЕНО: стара база без apiary_id переноситься в дефолтну пасіку', () async {
    // окремий файл, а не inMemoryDatabasePath: той самий шлях, що вже
    // відкритий у зовнішньому setUp, повернув би те саме з'єднання
    final tmpPath = p.join(Directory.systemTemp.path,
        'apiary_legacy_test_${DateTime.now().microsecondsSinceEpoch}.db');
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, tmpPath);
    final legacyRepo = Repository(db);
    await legacyRepo.init(); // ще немає жодного елемента — нічого мігрувати
    expect(await legacyRepo.listApiaries(), isEmpty);
    // імітуємо стару базу (до підтримки кількох пасік): елемент без apiary_id
    await db.insert('elements',
        {'id': 'legacy-1', 'x': 3, 'y': 4, 'updated_at': 1.0, 'synced': 0});
    await legacyRepo.init();
    final apiaries = await legacyRepo.listApiaries();
    expect(apiaries.length, 1);
    expect(apiaries.first.name, 'Моя пасіка');
    final els = await legacyRepo.listElements(apiaries.first.id);
    expect(els.length, 1);
    expect(els.first.id, 'legacy-1');
    await db.close();
    await File(tmpPath).delete();
  });

  test('розміщення шаблону: група, автонумерація назви, координати', () async {
    final cells = {
      '0,0': 'hive',
      '1,0': {'type': 'obstacle', 'variant': 'trees', 'icon': null, 'color': '#F2B705', 'parameters': <String>[]},
    };
    final l1 = await repo.nextGroupLabel(apiaryId, 'Лежак');
    expect(l1, 'Лежак 1');
    final gid = await repo.addGroup(apiaryId, cells, 10, 20, groupLabel: l1);
    expect(await repo.nextGroupLabel(apiaryId, 'Лежак'), 'Лежак 2');
    final els = await repo.getGroupElements(gid);
    expect(els.length, 2);
    final obstacle = els.firstWhere((e) => e.type == 'obstacle');
    expect((obstacle.x, obstacle.y), (11, 20));
    expect(obstacle.variant, 'trees');
    expect(obstacle.color, '#F2B705');
  });

  test('поворот групи зберігає сусідство клітинок', () async {
    final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0);
    await repo.rotateGroup(gid);
    final els = await repo.getGroupElements(gid);
    expect(els[0].x, els[1].x);
    expect((els[0].y - els[1].y).abs(), 1);
  });

  test('прив\'язка параметрів: порядок зберігається разом із базовими', () async {
    final id = await repo.addElement(apiaryId, 0, 0);
    final e = EntityRef.element(id);
    final p1 = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.float_);
    final p2 = await repo.addParameter('Порода');
    final base = await repo.baseParameterIds('hive');
    await repo.setAttachedParameters([p2, base.first, p1], e);
    final stored = await repo.db.rawQuery(
        'SELECT parameter_id FROM element_parameters WHERE deleted = 0 ORDER BY sort_order');
    // базова теж записана — щоб зберегти її місце в порядку
    expect([for (final r in stored) r['parameter_id']], [p2, base.first, p1]);
    final shown = await repo.attachedParameterIds(e, elType: 'hive');
    // незаписані базові — на початку, решта — у збереженому порядку
    expect(shown, [...base.skip(1), p2, base.first, p1]);
  });

  test('ВИПРАВЛЕНО: видалений параметр не можна прив\'язати повторно', () async {
    final id = await repo.addElement(apiaryId, 0, 0);
    final e = EntityRef.element(id);
    final p = await repo.addParameter('Вага');
    await repo.deleteParameter(p);
    // стале посилання на вже видалений параметр (наприклад, зі старого
    // знімка панелі вибору) не повинне створити нову живу прив'язку
    await repo.setAttachedParameters([p], e);
    final stored =
        await repo.db.rawQuery('SELECT parameter_id FROM element_parameters WHERE deleted = 0');
    expect(stored, isEmpty);
  });

  test('значення: історія, останні значення, дата оновлення', () async {
    final gid = await repo.addGroup(apiaryId, {'0,0': 'hive'}, 0, 0, groupLabel: 'Лежак 1');
    final e = EntityRef.group(gid);
    final p = await repo.addParameter('Вага');
    expect(await repo.lastUpdated(e), isNull);
    await repo.addParameterRecord(p, '10', e);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.addParameterRecord(p, '12', e);
    expect((await repo.latestParameterValues(e))[p], '12');
    expect(await repo.lastUpdated(e), isNotNull);
    final hist = await repo.parameterHistory(p, entity: e);
    expect([for (final r in hist) r.value], ['12', '10']);
    expect(hist.first.entityLabel, 'Лежак 1');
  });

  test('ВИПРАВЛЕНО: у черзі синхронізації всі таблиці', () async {
    final id = await repo.addElement(apiaryId, 0, 0);
    final p = await repo.addParameter('Вага');
    await repo.setAttachedParameters([p], EntityRef.element(id));
    await repo.addParameterRecord(p, '5', EntityRef.element(id));
    await repo.addTemplate('Лежак', 2, 1, {'0,0': 'hive', '1,0': 'hive'});
    await repo.linkQr('https://example.org/hive/1', EntityRef.element(id));
    final item = await repo.addStockItem('Цукор', 'кг');
    await repo.receiveStock(item, 1, total: 30);
    for (final t in kSyncTables) {
      expect(await repo.unsynced(t), isNotEmpty, reason: t);
    }
  });

  test('markSynced не губить зміну, зроблену під час відправки', () async {
    final id = await repo.addElement(apiaryId, 0, 0);
    final sent = (await repo.unsynced('elements')).single;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.moveElement(id, 3, 3); // змінили, поки "відправлялось"
    await repo.markSynced('elements', sent);
    expect(await repo.unsynced('elements'), isNotEmpty);
  });

  test('експорт історії в Excel', () {
    final bytes = buildHistoryWorkbook(
      parameter: const Parameter(id: 'p', name: 'Вага', unit: 'кг'),
      rows: const [
        ParameterRecord(
            id: 'r', groupId: 'g', elementId: null, parameterId: 'p', value: '12', createdAt: 0, entityLabel: 'Лежак 1'),
      ],
    );
    final book = Excel.decodeBytes(bytes);
    final sheet = book.tables['Вага']!;
    expect(sheet.maxRows, 2);
    expect(historyFileName('Мітка матки', null, DateTime(2026, 9, 28, 10, 5, 7)),
        'istoriya_Мітка_матки_20260928_100507.xlsx');
  });

  test('Excel: числа й дати - клітинками потрібного типу', () {
    expect(historyValueCell('7', DataTypes.int_), isA<IntCellValue>());
    final f = historyValueCell('12,5', DataTypes.float_);
    expect(f, isA<DoubleCellValue>());
    expect((f as DoubleCellValue).value, 12.5);
    expect(historyValueCell('01.02.2026', DataTypes.date), isA<DateCellValue>());
    expect(historyValueCell('багато', DataTypes.int_), isA<TextCellValue>());
    expect(historyValueCell('Білий', DataTypes.color), isA<TextCellValue>());
    final bytes = buildHistoryWorkbook(
      parameter: const Parameter(id: 'p', name: 'Дата', dataType: DataTypes.date),
      rows: const [
        ParameterRecord(
            id: 'r', groupId: 'g', elementId: null, parameterId: 'p', value: '01.02.2026',
            createdAt: 1767225600, entityLabel: 'Лежак 1'),
      ],
    );
    expect(Excel.decodeBytes(bytes).tables['Дата']!.maxRows, 2);
  });

  test('P14: звіт по пасіці - вулики × параметри та історія', () async {
    final a = await repo.addElement(apiaryId, 0, 5, label: 'Перший');
    await repo.addElement(apiaryId, 1, 0); // без назви → «Вулик 2»
    await repo.addElement(apiaryId, 3, 3, type: 'obstacle'); // не вулик
    final w = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.int_);
    await repo.setAttachedParameters([w], EntityRef.element(a));
    await repo.addParameterRecord(w, '10', EntityRef.element(a));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.addParameterRecord(w, '12', EntityRef.element(a));

    final report = await repo.apiaryReport(apiaryId);
    expect(report.hives.map((h) => h.label), ['Перший', 'Вулик 2']);
    expect(report.parameters.map((p) => p.id), contains(w));
    expect(report.latest[EntityRef.element(a)]![w], '12');
    expect(report.history.where((r) => r.parameterId == w).map((r) => r.value), ['12', '10']);

    final book = Excel.decodeBytes(buildApiaryWorkbook(report));
    final last = book.tables['Останні значення']!;
    expect(last.maxRows, 3); // заголовок + 2 вулики
    final col = report.parameters.indexWhere((p) => p.id == w) + 1;
    expect((last.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1)).value
            as IntCellValue)
        .value, 12);
    expect(book.tables['Історія']!.maxRows, 1 + report.history.length);
    expect(apiaryReportFileName('Пасіка 1', DateTime(2026, 10, 1, 9, 5)),
        'zvit_Пасіка_1_20261001_0905.xlsx');
  });

  test('тип «Так / Ні» і «Список»: варіанти зберігаються, перетворення значень', () async {
    final id = await repo.addParameter('Сила', dataType: DataTypes.choice, options: ['А', 'Б']);
    expect((await repo.getParameter(id))!.options, ['А', 'Б']);
    await repo.updateParameter(id, {'options': Parameter.encodeOptions(['А', 'Б', 'В'])});
    expect((await repo.getParameter(id))!.options, ['А', 'Б', 'В']);
    expect(convertValue('так', DataTypes.bool_), 'Так');
    expect(convertValue('0', DataTypes.bool_), 'Ні');
    expect(convertValue('може', DataTypes.bool_), isNull);
    expect(convertValue('будь-що', DataTypes.choice), 'будь-що');
  });

  test('безпека: чужа назва таблиці відхиляється навіть у release', () async {
    expect(() => repo.unsynced('sqlite_master'), throwsArgumentError);
    expect(() => repo.markSynced('x; DROP TABLE elements', {'id': '1'}), throwsArgumentError);
  });

  test('markSyncedBatch: не губить зміну, зроблену під час відправки', () async {
    final a = await repo.addElement(apiaryId, 0, 0);
    await repo.addElement(apiaryId, 1, 0);
    final sent = await repo.unsynced('elements');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.moveElement(a, 5, 5); // змінили, поки "відправлялось"
    await repo.markSyncedBatch('elements', sent);
    final left = await repo.unsynced('elements');
    expect(left.map((r) => r['id']), [a]);
  });

  test('syncOnce (заглушка без сервера) позначає все синхронізованим', () async {
    await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0);
    final (ok, total) = await SyncService(repo).syncOnce();
    expect(total, greaterThan(0));
    expect(ok, total);
    for (final t in kSyncTables) {
      expect(await repo.unsynced(t), isEmpty, reason: t);
    }
  });

  test('listElementsByApiary дає те саме, що listElements, для кожної пасіки', () async {
    final other = await repo.addApiary('Друга');
    await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0);
    await repo.addGroup(other, {'0,0': 'obstacle:trees'}, 4, 4);
    final gid = await repo.addGroup(other, {'0,0': 'hive'}, 8, 8);
    await repo.deleteGroup(gid); // видалені не потрапляють у знімок
    final empty = await repo.addApiary('Порожня');
    final all = await repo.listElementsByApiary([apiaryId, other, empty]);
    for (final id in [apiaryId, other, empty]) {
      final single = await repo.listElements(id);
      expect(all[id]!.map((e) => e.id).toSet(), single.map((e) => e.id).toSet(), reason: id);
    }
    expect(all[apiaryId]!.length, 2);
    expect(all[other]!.length, 1);
    expect(all[empty], isEmpty);
    expect(await repo.listElementsByApiary(const []), isEmpty);
  });

  test('пакетна вставка: addGroup зберігає всі клітинки та параметри', () async {
    final pid = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.float_);
    final gid = await repo.addGroup(
        apiaryId, {'0,0': 'hive', '1,0': 'hive', '0,1': 'obstacle:trees'}, 2, 2,
        groupLabel: 'Лежак');
    final els = await repo.getGroupElements(gid);
    expect(els.length, 3);
    expect({for (final e in els) (e.x, e.y)}, {(2, 2), (3, 2), (2, 1)});
    expect((await repo.listElements(apiaryId)).length, 3);
    expect(pid, isNotEmpty); // параметр створено (прив'язка — окремий тест)
  });

  test('порядок пасік не змінюється після перейменування', () async {
    final b = await repo.addApiary('Друга');
    final c = await repo.addApiary('Третя');
    await repo.updateApiary(apiaryId, name: 'Перша (нова назва)');
    final ids = (await repo.listApiaries()).map((a) => a.id).toList();
    expect(ids, [apiaryId, b, c]);
  });

  test('deleteApiary: ховає пасіку з її об\'єктами, інші не чіпає, а purge прибирає рядки', () async {
    final other = await repo.addApiary('Інша');
    await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0);
    await repo.addGroup(other, {'0,0': 'hive'}, 0, 0);
    await repo.deleteApiary(apiaryId);

    expect((await repo.listApiaries()).map((a) => a.id), [other]);
    expect(await repo.listElements(apiaryId), isEmpty);
    expect((await repo.listElements(other)).length, 1);

    // позначається до синхронізації, а після неї й пільгового терміну зникає
    expect((await repo.unsynced('apiaries')).map((r) => r['id']), contains(apiaryId));
    await SyncService(repo).syncOnce();
    await repo.purgeDeleted(grace: Duration.zero);
    expect(await repo.getApiary(apiaryId), isNull);
    expect(await repo.getApiary(other), isNotNull);
    expect((await repo.listElements(other)).length, 1);
  });

  group('QR-коди вуликів', () {
    test('прив\'язка, пошук і відв\'язка', () async {
      final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0,
          groupLabel: 'Лежак 1');
      final g = EntityRef.group(gid);
      expect(await repo.findByQr('https://x/h/1'), isNull);
      await repo.linkQr('  https://x/h/1\n', g); // пробіли по краях не заважають
      expect(await repo.qrFor(g), 'https://x/h/1');
      final f = (await repo.findByQr('https://x/h/1'))!;
      expect(f.element.groupId, gid);
      expect(f.apiary.id, apiaryId);
      await repo.unlinkQr(g);
      expect(await repo.qrFor(g), isNull);
      expect(await repo.findByQr('https://x/h/1'), isNull);
    });

    test('один код - один вулик; один вулик - один код', () async {
      final a = await repo.addElement(apiaryId, 0, 0);
      final b = await repo.addElement(apiaryId, 1, 0);
      await repo.linkQr('K1', EntityRef.element(a));
      await repo.linkQr('K1', EntityRef.element(b)); // перенесли на b
      expect((await repo.findByQr('K1'))!.element.id, b);
      expect(await repo.qrFor(EntityRef.element(a)), isNull);
      await repo.linkQr('K2', EntityRef.element(b)); // замінили код b
      expect(await repo.qrFor(EntityRef.element(b)), 'K2');
      expect(await repo.findByQr('K1'), isNull);
    });

    test('код застосунку з іншим «хвостом», але тим самим номером - знаходить вулик', () async {
      final a = await repo.addElement(apiaryId, 0, 0);
      await repo.linkQr('MYAPIARY:H:3:aaaa1111', EntityRef.element(a));
      expect((await repo.findByQr('MYAPIARY:H:3:aaaa1111'))!.element.id, a);
      expect((await repo.findByQr('MYAPIARY:H:3:bbbb2222'))!.element.id, a);
      expect(await repo.findByQr('MYAPIARY:H:4:bbbb2222'), isNull);
    });

    test('видалений вулик чи пасіка не знаходяться за кодом', () async {
      final a = await repo.addElement(apiaryId, 0, 0);
      await repo.linkQr('K', EntityRef.element(a));
      await repo.deleteElement(a);
      expect(await repo.findByQr('K'), isNull);

      final other = await repo.addApiary('Інша');
      final gid = await repo.addGroup(other, {'0,0': 'hive'}, 0, 0);
      await repo.linkQr('G', EntityRef.group(gid));
      expect(await repo.findByQr('G'), isNotNull);
      await repo.deleteApiary(other);
      expect(await repo.findByQr('G'), isNull);
    });
  });

  test('номер нової групи - найбільший + 1 (без повторів після видалення чи перейменування)',
      () async {
    final g1 = await repo.addGroup(apiaryId, {'0,0': 'hive'}, 0, 0, groupLabel: 'Лежак 1');
    await repo.addGroup(apiaryId, {'0,0': 'hive'}, 2, 0, groupLabel: 'Лежак 2');
    final g3 = await repo.addGroup(apiaryId, {'0,0': 'hive'}, 4, 0, groupLabel: 'Лежак 3');
    await repo.deleteGroup(g1);
    expect(await repo.nextGroupLabel(apiaryId, 'Лежак'), 'Лежак 4');
    await repo.renameGroup(g3, 'Південний');
    expect(await repo.nextGroupLabel(apiaryId, 'Лежак'), 'Лежак 3');
    expect(await repo.nextGroupLabel(apiaryId, 'Інший'), 'Інший 1');
  });

  test('колір/іконка змінюються лише для злитого об\'єкта, не для всієї групи', () async {
    final gid = await repo.addGroup(
        apiaryId, {'0,0': 'hive', '1,0': 'hive', '3,0': 'hive', '0,1': 'obstacle:trees'}, 0, 0);
    final all = await repo.getGroupElements(gid);
    final first = all.firstWhere((e) => e.x == 0 && e.isHive);
    final obj = mergedObjectOf(first, all);
    expect(obj.map((e) => (e.x, e.y)).toSet(), {(0, 0), (1, 0)}); // окремий вулик (3,0) і дерева — ні
    await repo.updateElements([for (final e in obj) e.id], {'color': '#FF0000'});
    final after = await repo.getGroupElements(gid);
    for (final e in after) {
      expect(e.color, obj.any((o) => o.id == e.id) ? '#FF0000' : isNull, reason: '${e.x},${e.y}');
    }
  });

  test('розміщення шаблону: окремі об\'єкти, параметри лише вуликам', () async {
    final p = await repo.addParameter('Порода');
    final ids = await repo.placeTemplate(apiaryId, {
      '0,0': 'hive',
      '1,0': 'hive', // злитий з (0,0) — один вулик
      '3,0': {'type': 'hive', 'parameters': [p]},
      '0,1': {'type': 'obstacle', 'variant': 'trees', 'parameters': [p]},
    }, 0, 0, name: 'Т');
    expect(ids.length, 3);
    final groups = [for (final g in ids) await repo.getGroupElements(g)];
    expect(groups[0].map((e) => (e.x, e.y)).toSet(), {(0, 0), (1, 0)});
    expect(groups[0].first.label, 'Т 1');
    expect(groups[1].single.label, 'Т 2');
    expect(groups[2].single.isHive, isFalse);
    expect(await repo.attachedParameterIds(EntityRef.group(ids[0])), isEmpty);
    expect(await repo.attachedParameterIds(EntityRef.group(ids[1])), [p]);
    expect(await repo.attachedParameterIds(EntityRef.group(ids[2])), isEmpty); // перешкода — без параметрів
    // наступне розміщення продовжує нумерацію
    final more = await repo.placeTemplate(apiaryId, {'0,0': 'hive'}, 9, 9, name: 'Т');
    expect((await repo.getGroupElements(more.single)).single.label, 'Т 3');
  });

  test('склад: прихід і вибуття - окремі записи, залишок рахується', () async {
    final id = await repo.addStockItem(' Цукор ', 'кг');
    var it = (await repo.listStockItems()).single;
    expect(it.name, 'Цукор');
    expect(it.quantity, isNull);
    // загальна вартість 150 грн за 5 кг → 30 грн/кг
    expect(await repo.receiveStock(id, 5, date: DateTime(2026, 9, 1), total: 150), 5);
    expect(await repo.receiveStock(id, 2.5, total: 100, comment: 'чек 12'), 7.5);
    expect(await repo.writeOffStock(id, 3, comment: 'підгодівля'), 4.5);
    // більше за залишок — не можна, залишок не змінюється
    await expectLater(repo.writeOffStock(id, 5), throwsStateError);
    expect(() => repo.receiveStock(id, 0, total: 10), throwsArgumentError);
    expect(() => repo.receiveStock(id, 1, total: -1), throwsArgumentError);
    expect(await repo.writeOffStock(id, 4.5), 0);
    it = (await repo.getStockItem(id))!;
    expect(it.quantity, 0);
    final moves = await repo.stockMoves(id);
    expect([for (final m in moves) m['kind']], ['in', 'in', 'out', 'out']);
    expect([for (final m in moves) m['quantity_after']], [5, 7.5, 4.5, 0]);
    expect(moves.first['total'], 150);
    expect(moves.first['price'], 30);
    expect(moves[1]['price'], 40);
    expect(moves[1]['comment'], 'чек 12');
    // дата операції — обрана, а не дата введення (1 вересня — найраніший запис)
    expect(DateTime.fromMicrosecondsSinceEpoch(((moves.first['op_date'] as num) * 1e6).round()),
        DateTime(2026, 9, 1));
    await repo.updateStockItem(id, name: 'Цукор білий', unit: 'г', photo: ('/x/stock_photos/a.jpg',));
    it = (await repo.getStockItem(id))!;
    expect((it.name, it.unit, it.photo), ('Цукор білий', 'г', '/x/stock_photos/a.jpg'));
    await repo.updateStockItem(id, photo: (null,));
    expect((await repo.getStockItem(id))!.photo, isNull);
    expect(await repo.unsynced('stock_items'), isNotEmpty);
    await repo.deleteStockItem(id);
    expect(await repo.listStockItems(), isEmpty);
  });

  test('склад: переоблік записує різницю, скасування повертає залишок', () async {
    final id = await repo.addStockItem('Цукор', 'кг');
    await repo.receiveStock(id, 10, total: 300);
    // фактично 8 → нестача −2
    expect(await repo.inventoryStock(id, 8), 8);
    var moves = await repo.stockMoves(id);
    expect(moves.last['kind'], 'inv');
    expect(moves.last['amount'], -2);
    // фактично 9 → надлишок +1
    expect(await repo.inventoryStock(id, 9), 9);
    expect((await repo.stockMoves(id)).last['amount'], 1);

    // скасувати помилкове списання: запис лишається, залишок повертається
    await repo.writeOffStock(id, 4);
    moves = await repo.stockMoves(id);
    final outId = moves.last['id'] as String;
    expect(await repo.cancelStockMove(outId), 9);
    moves = await repo.stockMoves(id);
    expect(moves.firstWhere((m) => m['id'] == outId)['cancelled'], 1);
    expect(moves.last['kind'], 'cancel');
    expect(moves.last['ref_id'], outId);
    expect(moves.last['amount'], 4);
    // двічі не можна; скасування не скасовується
    await expectLater(repo.cancelStockMove(outId), throwsStateError);
    await expectLater(repo.cancelStockMove(moves.last['id'] as String), throwsStateError);
    // скасувати переоблік «+1» → 8
    final invId = moves.lastWhere((m) => m['kind'] == 'inv')['id'] as String;
    expect(await repo.cancelStockMove(invId), 8);
    // прихід 10, з якого вже списали б більше залишку, — не скасовується
    await repo.writeOffStock(id, 5);
    final inId = moves.first['id'] as String;
    await expectLater(repo.cancelStockMove(inId), throwsStateError);
    expect((await repo.getStockItem(id))!.quantity, 3);
  });

  test('rotateGroups повертає кілька груп разом як одну фігуру', () async {
    final ids = await repo.placeTemplate(apiaryId, {'0,0': 'hive', '2,0': 'hive'}, 0, 0, name: 'Р');
    Future<Set<(int, int)>> pos() async => {
          for (final g in ids)
            for (final e in await repo.getGroupElements(g)) (e.x, e.y)
        };
    expect(await pos(), {(0, 0), (2, 0)});
    await repo.rotateGroups(ids);
    final r = await pos();
    // жорстке обертання: відстань між вуликами зберігається, вони в одній колонці/рядку
    expect(r.length, 2);
    final l = r.toList();
    expect((l[0].$1 - l[1].$1).abs() + (l[0].$2 - l[1].$2).abs(), 2);
    expect(l[0].$1 == l[1].$1 || l[0].$2 == l[1].$2, isTrue);
    expect(l[0].$1 == 0 && l[1].$1 == 2 || l[0].$1 == 2 && l[1].$1 == 0, isFalse);
  });

  test('стара група з кількох вуликів ділиться на окремі, історія копіюється вуликам', () async {
    final gid = await repo.addGroup(
        apiaryId, {'0,0': 'hive', '2,0': 'hive', '1,0': 'obstacle:trees'}, 0, 0, groupLabel: 'Л 1');
    final p = await repo.addParameter('Вага');
    await repo.setAttachedParameters([p], EntityRef.group(gid));
    await repo.addParameterRecord(p, '12', EntityRef.group(gid));
    await repo.splitMultiObjectGroups();
    final els = await repo.listElements(apiaryId);
    final hives = els.where((e) => e.isHive).toList()..sort((a, b) => a.x.compareTo(b.x));
    final tree = els.firstWhere((e) => !e.isHive);
    expect({hives[0].groupId, hives[1].groupId, tree.groupId}.length, 3);
    expect(hives.map((e) => e.label), ['Л 1 · 1', 'Л 1 · 2']);
    for (final h in hives) {
      expect((await repo.latestParameterValues(h.entity))[p], '12');
      expect(await repo.attachedParameterIds(h.entity), contains(p));
    }
    expect(await repo.latestParameterValues(tree.entity), isEmpty);
    // окрема історія: запис одному вулику не видно в іншого
    await repo.addParameterRecord(p, '20', hives[1].entity);
    expect((await repo.latestParameterValues(hives[0].entity))[p], '12');
    // повторний запуск нічого не змінює
    await repo.splitMultiObjectGroups();
    expect((await repo.listElements(apiaryId)).map((e) => e.groupId).toSet().length, 3);
  });

  group('перенесення історії параметра', () {
    test('записи копіюються з конвертацією, прив\'язки й шаблони переходять', () async {
      final old = await repo.addParameter('Рамки'); // текст
      final el = await repo.addElement(apiaryId, 1, 1);
      final e = EntityRef.element(el);
      await repo.setAttachedParameters([old], e);
      for (final v in ['10', '12,5', 'багато', '', '7']) {
        await repo.addParameterRecord(old, v, e);
      }
      final tpl = await repo.addTemplate('Т', 1, 1, {
        '0,0': {'type': 'hive', 'parameters': [old]}
      });
      final neu = await repo.addParameter('Рамки', dataType: DataTypes.int_);

      final pv = await repo.previewHistoryPort(old, neu);
      expect((pv.movable, pv.skipped), (3, 2)); // "12,5" і "багато" не цілі

      final r = await repo.portParameterHistory(old, neu);
      expect((r.moved, r.skipped), (3, 2));
      final hist = await repo.db.rawQuery(
          'SELECT value FROM parameter_records WHERE parameter_id = ? ORDER BY created_at, rowid', [neu]);
      expect(hist.map((h) => h['value']), ['10', '', '7']);
      expect((await repo.latestParameterValues(e))[neu], '7');
      expect(await repo.attachedParameterIds(e), containsAll([old, neu]));
      final cells = (await repo.getTemplate(tpl))!.cells;
      expect((cells['0,0'] as Map)['parameters'], [neu]);

      // повторне перенесення не дублює; з видаленням старого
      final again = await repo.portParameterHistory(old, neu, deleteSource: true);
      expect(again.moved, 0);
      expect((await repo.getParameter(old))!.deleted, isTrue);
      expect(await repo.attachedParameterIds(e), isNot(contains(old)));
      expect(await repo.attachedParameterIds(e), contains(neu));
    });

    test('конвертація значень між типами', () {
      expect(convertValue('12', DataTypes.float_), '12.0');
      expect(convertValue('12,50', DataTypes.float_), '12.5');
      expect(convertValue('12.0', DataTypes.int_), '12');
      expect(convertValue('12.5', DataTypes.int_), isNull);
      expect(convertValue('1.2.2026', DataTypes.date), '01.02.2026');
      expect(convertValue('31.02.2026', DataTypes.date), isNull);
      expect(convertValue('жовтий', DataTypes.color), 'Жовтий');
      expect(convertValue('фіолетовий', DataTypes.color), isNull);
      expect(convertValue('будь-що', DataTypes.text), 'будь-що');
      expect(convertValue('', DataTypes.int_), '');
    });
  });

  test('зайві старі «базові» без ключа стають звичайними параметрами', () async {
    await repo.db.insert('parameters', {
      'id': 'dup',
      'name': 'Мітка матки (стара)',
      'data_type': 'color',
      'is_base': 1,
      'base_type': 'hive',
      'updated_at': 1,
      'synced': 0,
    });
    await repo.init();
    final p = (await repo.getParameter('dup'))!;
    expect(p.isBase, isFalse);
    expect((await repo.listParameters()).where((p) => p.isBase).length, 3);
    // тепер її можна прив'язати/видалити як звичайну
    await repo.deleteParameter('dup');
  });

  group('генерація QR-кодів застосунку', () {
    test('кожен вулик - свій код і номер; повторна генерація вимикає старі', () async {
      final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0,
          groupLabel: 'Лежак 1');
      final single = await repo.addElement(apiaryId, 5, 5);
      final els = [...await repo.getGroupElements(gid), (await repo.getElement(single))!];

      final first = await repo.generateQrForElements(els);
      expect(first.length, 3);
      expect(first.map((c) => c.number).toSet().length, 3);
      for (final c in first) {
        expect(c.code, startsWith(Repository.appQrPrefix));
        expect(Repository.appQrNumber(c.code), c.number);
        expect((await repo.findByQr(c.code))!.element.id, c.elementId);
        // номер з наліпки, введений вручну, теж знаходить вулик
        expect((await repo.findByQr('№ ${c.number.toString().padLeft(4, '0')}'))!.element.id,
            c.elementId);
      }
      expect(await repo.elementIdsWithQr(apiaryId), {for (final e in els) e.id});

      final again = await repo.generateQrForElements(els);
      final maxOld = first.map((c) => c.number!).reduce((a, b) => a > b ? a : b);
      for (var i = 0; i < els.length; i++) {
        expect(again[i].elementId, first[i].elementId);
        expect(again[i].code, isNot(first[i].code));
        expect(again[i].number! > maxOld, isTrue); // номери не повторюються
        // старий код і старий номер більше нічого не відкривають
        expect(await repo.findByQr(first[i].code), isNull);
        expect(await repo.findByQr('${first[i].number}'), isNull);
        expect((await repo.findByQr(again[i].code))!.element.id, els[i].id);
        expect(await repo.qrForElement(els[i]), again[i].code);
      }
      expect(await repo.elementIdsWithQr(apiaryId), {for (final e in els) e.id});
    });

    test('ручний ввід номера прив\'язує справжній код наліпки', () async {
      final a = await repo.addElement(apiaryId, 1, 1);
      final b = await repo.addElement(apiaryId, 3, 1);
      final code = (await repo.generateQrForElements([(await repo.getElement(a))!])).single;
      // номер з наліпки -> повний код
      expect(await repo.resolveTypedQr('№ ${code.number.toString().padLeft(4, '0')}'), code.code);
      expect(await repo.resolveTypedQr(' ${code.number} '), code.code);
      // чужий текст і невідомий номер — як є
      expect(await repo.resolveTypedQr('https://x.y/1'), 'https://x.y/1');
      expect(await repo.resolveTypedQr('987654'), '987654');
      // перенесли наліпку введенням номера: справжній код тепер у b і сканується
      await repo.linkQr(await repo.resolveTypedQr('${code.number}'), EntityRef.element(b));
      expect((await repo.findByQr(code.code))!.element.id, b);
      expect(await repo.qrFor(EntityRef.element(b)), code.code);
    });

    test('перегенерація вимикає й старий код усієї групи', () async {
      final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '0,1': 'obstacle:trees'}, 0, 0);
      await repo.linkQr('стара-групова', EntityRef.group(gid));
      // групою відкривається вулик, а не перешкода
      expect((await repo.findByQr('стара-групова'))!.element.isHive, isTrue);
      final hive = (await repo.getGroupElements(gid)).firstWhere((e) => e.isHive);
      await repo.generateQrForObjects([
        [hive]
      ]);
      expect(await repo.findByQr('стара-групова'), isNull);
    });

    test('видалення пасіки вимикає коди її вуликів', () async {
      final a = await repo.addElement(apiaryId, 1, 1);
      final gid = await repo.addGroup(apiaryId, {'0,0': 'hive'}, 5, 5);
      final code = (await repo.generateQrForElements([(await repo.getElement(a))!])).single;
      await repo.linkQr('групова', EntityRef.group(gid));
      await repo.deleteApiary(apiaryId);
      final active = await repo.db.rawQuery('SELECT * FROM qr_codes WHERE deleted = 0');
      expect(active, isEmpty);
      expect(await repo.findByQr(code.code), isNull);
    });

    test('номер наліпки не повторюється навіть після очистки', () async {
      final a = await repo.addElement(apiaryId, 1, 1);
      final el = (await repo.getElement(a))!;
      final first = (await repo.generateQrForElements([el])).single;
      await repo.unlinkQr(EntityRef.element(a));
      await repo.db.rawUpdate('UPDATE qr_codes SET synced = 1');
      await repo.purgeDeleted(grace: Duration.zero);
      final second = (await repo.generateQrForElements([el])).single;
      expect(second.number! > first.number!, isTrue);
    });

    test('злитий вулик: один код на весь об\'єкт, старі коди клітинок вимикаються', () async {
      final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0);
      final cells = (await repo.getGroupElements(gid))..sort((a, b) => a.x.compareTo(b.x));
      final old = await repo.generateQrForElements(cells); // старі коди по клітинках
      final res = await repo.generateQrForObjects([cells]);
      expect(res.single.elementId, cells.first.id);
      for (final c in old) {
        expect(await repo.findByQr(c.code), isNull);
      }
      expect(await repo.qrForObject(cells), res.single.code);
      expect(await repo.qrForObject(cells.reversed.toList()), res.single.code);
      expect(await repo.qrFor(EntityRef.element(cells.last.id)), isNull);
      expect((await repo.findByQr(res.single.code))!.element.id, cells.first.id);
    });

    test('код групи підсвічує всі вулики групи; перенесений код зберігає номер', () async {
      final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '1,0': 'hive'}, 0, 0);
      await repo.linkQr('чужа-наліпка', EntityRef.group(gid));
      final ids = {for (final e in await repo.getGroupElements(gid)) e.id};
      expect(await repo.elementIdsWithQr(apiaryId), ids);

      final a = await repo.addElement(apiaryId, 4, 4);
      final b = await repo.addElement(apiaryId, 6, 4);
      final code = (await repo.generateQrForElements([(await repo.getElement(a))!])).single;
      await repo.linkQr(code.code, EntityRef.element(b)); // наліпку переклеїли
      expect(await repo.qrFor(EntityRef.element(b)), code.code);
      expect(await repo.qrFor(EntityRef.element(a)), isNull);
      // номер наліпки переїхав разом із кодом
      expect((await repo.findByQr('${code.number}'))!.element.id, b);
    });

    test('розбір номерів', () {
      expect(Repository.appQrNumber('MYAPIARY:H:17:abcd1234'), 17);
      expect(Repository.appQrNumber('https://x/17'), isNull);
      expect(Repository.typedQrNumber('№ 0017'), 17);
      expect(Repository.typedQrNumber('#5'), 5);
      expect(Repository.typedQrNumber('5a'), isNull);
    });
  });

  test('типові шаблони «Вулик» і «Лежак» додаються один раз', () async {
    final before = (await repo.listTemplates()).length;
    await repo.seedDefaultTemplates();
    final list = await repo.listTemplates();
    expect(list.length, before + 2);
    final hive = list.firstWhere((t) => t.name == 'Вулик');
    expect((hive.width, hive.height), (1, 1));
    final lying = list.firstWhere((t) => t.name == 'Лежак' && t.width == 2 && t.height == 1);
    // повторний запуск не дублює, а видалений шаблон не повертається
    await repo.deleteTemplate(hive.id);
    await repo.seedDefaultTemplates();
    final after = await repo.listTemplates();
    expect(after.where((t) => t.name == 'Вулик'), isEmpty);
    expect(after.where((t) => t.id == lying.id).length, 1);
  });

  test('швидке створення пасіки: «Пасіка N» з наступним номером', () async {
    final a = await repo.getApiary(await repo.addApiaryQuick());
    final b = await repo.getApiary(await repo.addApiaryQuick());
    expect(b!.name, 'Пасіка ${int.parse(a!.name.split(' ').last) + 1}');
  });

  test('«Почати»: остання відкрита пасіка, інакше єдина', () async {
    final all = await repo.listApiaries();
    expect((await repo.startApiary())?.id, all.length == 1 ? all.first.id : null);
    final id = await repo.addApiary('Друга');
    await repo.setMeta('last_apiary', id);
    expect((await repo.startApiary())!.name, 'Друга');
    await repo.deleteApiary(id);
    expect((await repo.startApiary())?.id, all.length == 1 ? all.first.id : null);
  });

  test('періодичність обходу пасіки діє на вулики без власної', () async {
    final aid = await repo.addApiary('Пасіка з періодом');
    final gid = await repo.addGroup(aid, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 9');
    Future<VisitTarget> t() async => (await repo.visitTargets()).firstWhere((x) => x.key == 'g:$gid');
    expect((await t()).periodDays, isNull);
    await repo.updateApiary(aid, visitPeriod: (7,));
    expect((await t()).periodDays, 7);
    expect((await t()).periodSetAt, isNotNull); // точка відліку без дати обходу
    // своя періодичність вулика перекриває пасіку
    final periodId = (await repo.baseParameterId('hive', 'visit_period'))!;
    await repo.addParameterRecord(periodId, '3', EntityRef.group(gid));
    expect((await t()).periodDays, 3);
    // прибрали в пасіки — у вулика лишилась своя
    await repo.updateApiary(aid, visitPeriod: (null,));
    expect((await t()).periodDays, 3);
    expect((await repo.getApiary(aid))!.visitPeriod, isNull);
  });
}
