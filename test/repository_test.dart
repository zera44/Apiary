import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_service.dart';
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
    expect(names, ['Періодичність обходу', 'Дата початку обходу', 'Мітка матки']);
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
