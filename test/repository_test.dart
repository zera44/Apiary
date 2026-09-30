import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_service.dart';
import 'package:apiary/logic/value_convert.dart';
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
    expect(ids.length, 3);
    final names = [for (final id in ids) (await repo.getParameter(id))!.name];
    expect(names, ['Періодичність обходу', 'Дата останнього обходу', 'Мітка матки']);
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
    expect(all.length, 3);
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
    expect(all.length, 3); // не 4
    final ids = await repo.baseParameterIds('hive');
    expect(ids.length, 3);
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

  test('прив\'язка параметрів: порядок, базові не зберігаються окремо', () async {
    final id = await repo.addElement(apiaryId, 0, 0);
    final e = EntityRef.element(id);
    final p1 = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.float_);
    final p2 = await repo.addParameter('Порода');
    final base = await repo.baseParameterIds('hive');
    await repo.setAttachedParameters([p2, base.first, p1], e);
    final stored = await repo.db.rawQuery(
        'SELECT parameter_id FROM element_parameters WHERE deleted = 0 ORDER BY sort_order');
    expect([for (final r in stored) r['parameter_id']], [p2, p1]);
    final shown = await repo.attachedParameterIds(e, elType: 'hive');
    expect(shown, [...base, p2, p1]);
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

    test('один код — один вулик; один вулик — один код', () async {
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
    test('кожен вулик — свій код і номер; повторна генерація вимикає старі', () async {
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
}
