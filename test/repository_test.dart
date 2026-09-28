import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/services/excel_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Repository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
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

  test('старі базові записи без base_key підхоплюються за назвою', () async {
    // імітуємо стару базу: ключі стерто
    await repo.db.rawUpdate('UPDATE parameters SET base_key = NULL');
    await repo.init();
    final all = (await repo.listParameters()).where((p) => p.isBase).toList();
    expect(all.length, 3);
  });

  test('ВИПРАВЛЕНО: "крок назад" відновлює видалений об\'єкт навіть після очистки', () async {
    final id = await repo.addElement(1, 1);
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
    final id = await repo.addElement(2, 2);
    await repo.deleteElement(id);
    await repo.db.rawUpdate('UPDATE elements SET synced = 1');
    await repo.purgeDeleted();
    expect(await repo.getElement(id), isNotNull);
  });

  test('розміщення шаблону: група, автонумерація назви, координати', () async {
    final cells = {
      '0,0': 'hive',
      '1,0': {'type': 'obstacle', 'variant': 'trees', 'icon': null, 'color': '#F2B705', 'parameters': <String>[]},
    };
    final l1 = await repo.nextGroupLabel('Лежак');
    expect(l1, 'Лежак 1');
    final gid = await repo.addGroup(cells, 10, 20, groupLabel: l1);
    expect(await repo.nextGroupLabel('Лежак'), 'Лежак 2');
    final els = await repo.getGroupElements(gid);
    expect(els.length, 2);
    final obstacle = els.firstWhere((e) => e.type == 'obstacle');
    expect((obstacle.x, obstacle.y), (11, 20));
    expect(obstacle.variant, 'trees');
    expect(obstacle.color, '#F2B705');
  });

  test('поворот групи зберігає сусідство клітинок', () async {
    final gid = await repo.addGroup({'0,0': 'hive', '1,0': 'hive'}, 0, 0);
    await repo.rotateGroup(gid);
    final els = await repo.getGroupElements(gid);
    expect(els[0].x, els[1].x);
    expect((els[0].y - els[1].y).abs(), 1);
  });

  test('прив\'язка параметрів: порядок, базові не зберігаються окремо', () async {
    final id = await repo.addElement(0, 0);
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

  test('значення: історія, останні значення, дата оновлення', () async {
    final gid = await repo.addGroup({'0,0': 'hive'}, 0, 0, groupLabel: 'Лежак 1');
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
    final id = await repo.addElement(0, 0);
    final p = await repo.addParameter('Вага');
    await repo.setAttachedParameters([p], EntityRef.element(id));
    await repo.addParameterRecord(p, '5', EntityRef.element(id));
    await repo.addTemplate('Лежак', 2, 1, {'0,0': 'hive', '1,0': 'hive'});
    for (final t in kSyncTables) {
      expect(await repo.unsynced(t), isNotEmpty, reason: t);
    }
  });

  test('markSynced не губить зміну, зроблену під час відправки', () async {
    final id = await repo.addElement(0, 0);
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
}
