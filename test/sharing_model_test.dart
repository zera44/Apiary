import 'dart:convert';
import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/notes.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_payload.dart';
import 'package:apiary/services/backups.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Етап 3: модель даних спільного доступу.
void main() {
  late Directory dir;
  late Repository repo;
  final factory = databaseFactoryFfiNoIsolate;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('apiary_share_');
    repo = Repository(await AppDatabase.open(factory, p.join(dir.path, 'apiary.db')));
    await repo.prepareLikeFreshInstall();
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  Future<int> count(String table, [String where = '1 = 1', List<Object?> args = const []]) async =>
      (await repo.db.rawQuery('SELECT COUNT(*) AS n FROM $table WHERE $where', args)).first['n']!
          as int;

  Future<Map<String, Object?>> rowOf(String table, String id) async =>
      (await repo.db.query(table, where: 'id = ?', whereArgs: [id])).single;

  /// Пасіка з вуликом-групою, прив'язкою, записом, QR-кодом і нотаткою.
  Future<({String apiary, String group, String param})> hive(String name) async {
    final a = await repo.addApiary(name);
    final g = await repo.addGroup(a, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
    final pid = await repo.addParameter('Сила');
    final e = EntityRef.group(g);
    await repo.setAttachedParameters([pid], e);
    await repo.addParameterRecord(pid, '7', e);
    await repo.linkQr('https://v/h/$name', e);
    await repo.addHiveNote(e, 'нотатка');
    return (apiary: a, group: g, param: pid);
  }

  group('пасіка в кожному записі', () {
    test('нові прив\'язки, записи, QR-коди й нотатки отримують пасіку самі', () async {
      final h = await hive('Перша');
      for (final t in AppDatabase.apiaryLinkedTables) {
        expect(await count(t, 'apiary_id IS NULL'), 0, reason: t);
        expect(await count(t, 'apiary_id = ?', [h.apiary]), greaterThan(0), reason: t);
      }
    });

    test('міграція до версії 3: старі записи (зокрема видалені) - без втрат', () async {
      final h = await hive('Стара');
      final gone = await repo.addGroup(h.apiary, {'0,0': 'hive'}, 3, 3, groupLabel: 'Вулик 2');
      await repo.addHiveNote(EntityRef.group(gone), 'про видалений вулик');
      await repo.deleteGroup(gone);
      await repo.db.insert('app_meta', {
        'key': 'param_groups',
        'value': jsonEncode([
          {'id': 'g1', 'name': 'Обходи', 'ids': [h.param]},
          {'id': 'g2', 'name': 'Сила', 'ids': <String>[]},
        ]),
      });
      // як у базі версії 2: ні пасіки в записах, ні тригерів, ні ключів, ні таблиці груп
      final db = repo.db;
      for (final t in AppDatabase.apiaryLinkedTables) {
        await db.execute('DROP TRIGGER IF EXISTS trg_${t}_apiary_ins');
        await db.execute('DROP TRIGGER IF EXISTS trg_${t}_apiary_upd');
        await db.execute('UPDATE $t SET apiary_id = NULL');
      }
      for (final t in AppDatabase.seededTables) {
        await db.execute('UPDATE $t SET seed_key = NULL');
      }
      await db.execute('DELETE FROM param_groups');
      final before = {for (final t in kSyncTables) t: await count(t)};
      await db.execute('PRAGMA user_version = 2');
      await db.close();

      repo = Repository(await AppDatabase.open(factory, p.join(dir.path, 'apiary.db')));
      expect((await repo.db.rawQuery('PRAGMA user_version')).first.values.first, 3);
      for (final t in AppDatabase.apiaryLinkedTables) {
        expect(await count(t, 'apiary_id IS NULL'), 0, reason: t);
      }
      // нотатка видаленого вулика теж знає свою пасіку (сервер дізнається про видалення)
      expect(await count('hive_notes', 'group_id = ? AND apiary_id = ?', [gone, h.apiary]), 1);
      // групи «Конструктора» - у таблиці, у службових позначках їх більше немає
      expect([for (final g in await repo.paramGroups()) g.name], ['Обходи', 'Сила']);
      expect((await repo.paramGroups()).first.ids, [h.param]);
      expect(await repo.getMeta('param_groups'), isNull);
      // типові записи отримали сталі ключі
      expect(await count('parameters', "seed_key LIKE 'base:%'"), greaterThan(0));
      expect(await count('templates', "seed_key = 'tpl:hive'"), 1);
      expect(await count('fin_categories', "seed_key LIKE 'fin:%'"), kFinSeedNames.length);
      // нічого не загубилось (груп стало 2 - з позначок)
      for (final t in kSyncTables) {
        expect(await count(t), t == 'param_groups' ? 2 : before[t], reason: t);
      }
    });
  });

  group('групи «Конструктора» - таблицею', () {
    test('порядок, перейменування; прибрані - позначкою; незмінені не відправляються', () async {
      await repo.setParamGroups([ParamGroup(id: 'a', name: 'А'), ParamGroup(id: 'b', name: 'Б')]);
      await repo.db.update('param_groups', {'synced': 1});
      await repo.setParamGroups([ParamGroup(id: 'b', name: 'Б'), ParamGroup(id: 'c', name: 'В')]);
      expect([for (final g in await repo.paramGroups()) g.id], ['b', 'c']);
      expect((await rowOf('param_groups', 'a'))['deleted'], 1);
      expect((await rowOf('param_groups', 'a'))['synced'], 0);
      expect((await rowOf('param_groups', 'c'))['synced'], 0);
      // «Б» змінила місце (0 замість 1) - теж у черзі
      expect((await rowOf('param_groups', 'b'))['synced'], 0);
      await repo.db.update('param_groups', {'synced': 1});
      await repo.setParamGroups([ParamGroup(id: 'b', name: 'Б'), ParamGroup(id: 'c', name: 'В')]);
      expect(await count('param_groups', 'synced = 0'), 0);
    });
  });

  group('однакові типові записи з двох телефонів', () {
    test('злиття: лишається один, посилання переписано, інший - позначкою «видалено»', () async {
      final a = await repo.addApiary('Пасіка');
      final g = await repo.addGroup(a, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      final e = EntityRef.group(g);
      // «з іншого телефона»: та сама базова характеристика під іншим id
      final mine = (await repo.db.query('parameters', where: "seed_key = 'base:hive:visit_start'"))
          .single;
      final other = mine['id'] == 'zzz' ? 'aaa' : 'zzz';
      await repo.db.insert('parameters', {...mine, 'id': other, 'synced': 1});
      await repo.setAttachedParameters([other], e);
      await repo.addParameterRecord(other, '01.10.2026', e);
      final tpl = await repo.addTemplate('Мій', 1, 1, {
        '0,0': {'type': 'hive', 'parameters': [other]},
      });
      await repo.setParamGroups([ParamGroup(id: 'g', name: 'Обходи', ids: [other])]);
      // і категорія фінансів, і мітка «Огляд»
      final cat = (await repo.db.query('fin_categories', where: "seed_key = 'fin:expense:Корми'"))
          .single;
      await repo.db.insert('fin_categories', {...cat, 'id': 'zzz-cat'});
      await repo.db.insert('fin_ops', {
        'id': 'op1', 'kind': 'expense', 'category_id': 'zzz-cat', 'amount': 10.0,
        'op_date': Repository.now(), 'created_at': Repository.now(), 'updated_at': Repository.now(),
      });
      final label = await repo.addNoteLabel(kInspectionNoteLabel);
      await Repository.assignSeedKeys(repo.db);
      final labelRow = await rowOf('note_labels', label);
      await repo.db.insert('note_labels', {...labelRow, 'id': 'zzz-label'});
      await repo.addHiveNote(e, 'огляд', labelId: 'zzz-label');

      expect(await repo.mergeSeedDuplicates(), 3);

      final keep = [mine['id']! as String, other]..sort();
      final kept = keep.first, dropped = keep.last;
      expect((await rowOf('parameters', dropped))['deleted'], 1);
      expect((await rowOf('parameters', dropped))['synced'], 0);
      expect((await rowOf('parameters', kept))['deleted'], 0);
      expect(await count('element_parameters', 'parameter_id = ? AND deleted = 0', [dropped]), 0);
      expect(await count('parameter_records', 'parameter_id = ?', [dropped]), 0);
      expect(await count('parameter_records', 'parameter_id = ?', [kept]), greaterThan(0));
      expect((await rowOf('templates', tpl))['cells'], contains(kept));
      expect((await rowOf('templates', tpl))['cells'], isNot(contains('"$dropped"')));
      expect((await repo.paramGroups()).single.ids, [kept]);
      expect((await rowOf('fin_ops', 'op1'))['category_id'], cat['id']);
      expect(await count('hive_notes', "label_id = 'zzz-label'"), 0);
      // у вулика одна прив'язка до злитої характеристики
      expect(await count('element_parameters', 'group_id = ? AND parameter_id = ? AND deleted = 0',
          [g, kept]), 1);
      // повторно - нічого
      expect(await repo.mergeSeedDuplicates(), 0);
    });

    test('свій однойменний шаблон користувача не зливається з типовим', () async {
      await repo.addTemplate('Вулик', 1, 1, {'0,0': 'hive'}); // свій, пізніше за типовий
      await Repository.assignSeedKeys(repo.db);
      expect(await count('templates', "name = 'Вулик' AND seed_key = 'tpl:hive'"), 1);
      expect(await repo.mergeSeedDuplicates(), 0);
      expect(await count('templates', "name = 'Вулик' AND deleted = 0"), 2);
    });
  });

  group('позначки «видалено»', () {
    test('стираються лише давні й лише ті, що сервер уже отримав', () async {
      final h = await hive('П');
      await repo.deleteGroup(h.group);
      final old = Repository.now() - const Duration(days: 40).inSeconds;
      await repo.db.update('elements', {'updated_at': old}, where: 'group_id = ?', whereArgs: [h.group]);
      // сервер ще не отримав - не чіпаємо
      await repo.purgeDeleted();
      expect(await count('elements', 'group_id = ?', [h.group]), 1);
      // отримав: стираємо, а несинхронізовану прив'язку - ні
      await repo.db.update('elements', {'synced': 1}, where: 'group_id = ?', whereArgs: [h.group]);
      await repo.purgeDeleted();
      expect(await count('elements', 'group_id = ?', [h.group]), 0);
      expect(await count('element_parameters', 'group_id = ?', [h.group]), 1);
      // свіже видалення (10 днів) не стирається
      final g2 = await repo.addGroup(h.apiary, {'0,0': 'hive'}, 5, 5);
      await repo.deleteGroup(g2);
      await repo.db.update('elements',
          {'synced': 1, 'updated_at': Repository.now() - const Duration(days: 10).inSeconds},
          where: 'group_id = ?', whereArgs: [g2]);
      await repo.purgeDeleted();
      expect(await count('elements', 'group_id = ?', [g2]), 1);
    });
  });

  test('чужу пасіку (доступ забрали) - прибрати з телефона без позначок «видалено»', () async {
    final mine = await hive('Моя');
    final theirs = await hive('Чужа');
    // «чужа» - від власника X: пасіка, довідник і склад X
    await repo.db.update('apiaries', {'owner_id': 'X'}, where: 'id = ?', whereArgs: [theirs.apiary]);
    await repo.db.update('parameters', {'owner_id': 'X'}, where: 'id = ?', whereArgs: [theirs.param]);
    final item = await repo.addStockItem('Цукор X', 'кг');
    await repo.db.update('stock_items', {'owner_id': 'X'}, where: 'id = ?', whereArgs: [item]);
    final deletedBefore = await count('elements', 'deleted = 1');

    await repo.evictApiary(theirs.apiary);
    expect(await repo.getApiary(theirs.apiary), isNull);
    for (final t in AppDatabase.apiaryLinkedTables) {
      expect(await count(t, 'apiary_id = ?', [theirs.apiary]), 0, reason: t);
    }
    expect(await count('elements', 'apiary_id = ?', [theirs.apiary]), 0);
    expect(await count('parameters', 'owner_id = ?', ['X']), 0);
    expect(await count('stock_items', 'owner_id = ?', ['X']), 0);
    expect(await count('elements', 'deleted = 1'), deletedBefore); // жодних позначок
    // своє - на місці
    expect(await repo.getApiary(mine.apiary), isNotNull);
    expect((await repo.getGroupElements(mine.group)).length, 1);
    // свою пасіку так не прибрати
    await repo.evictApiary(mine.apiary);
    expect(await count('parameters', 'id = ?', [mine.param]), 1);
  });

  test('рядок для сервера: версія схеми, без службових колонок; і назад', () {
    final out = toServerRow('apiaries', {'id': 'a', 'name': 'П', 'synced': 0, 'updated_at': 1.0});
    expect(out, {'id': 'a', 'name': 'П', 'updated_at': 1.0, 'schema_v': AppDatabase.schemaVersion});
    expect(() => toServerRow('app_meta', {'key': 'x'}), throwsArgumentError);
    final back = fromServerRow({'id': 'a', 'name': 'П', 'schema_v': 9, 'new_col': 1, 'synced': 0},
        {'id', 'name', 'updated_at'});
    expect(back, {'id': 'a', 'name': 'П', 'synced': 1});
  });

  test('відновлення копії версії 2: групи «Конструктора» переходять у таблицю', () async {
    // копія версії 2 з групами в службових позначках
    final oldPath = p.join(dir.path, 'v2.db');
    final old = Repository(await AppDatabase.open(factory, oldPath,
        version: 2, steps: {2: AppDatabase.migrations[2]!}));
    await old.init();
    await old.db.insert('app_meta', {
      'key': 'param_groups',
      'value': jsonEncode([
        {'id': 'old', 'name': 'З копії', 'ids': <String>[]},
      ]),
    });
    await old.db.close();
    await repo.setParamGroups([ParamGroup(id: 'now', name: 'Теперішня')]);
    final backups = BackupService(repo, dir: p.join(dir.path, 'backups'), factory: factory);
    await backups.restoreFrom(oldPath);
    expect([for (final g in await repo.paramGroups()) g.name], ['З копії']);
    expect(await repo.getMeta('param_groups'), isNull);
  });
}
