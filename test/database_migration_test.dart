import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Міграції бази за номером версії: наявні дані не губляться, кожен крок
/// виконується рівно раз, новішу базу стара версія не відкриває.
void main() {
  late Directory dir;
  late String path;
  final factory = databaseFactoryFfiNoIsolate;

  setUpAll(sqfliteFfiInit);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('apiary_migr_');
    path = p.join(dir.path, 'apiary.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<int> userVersion(Database db) async =>
      (await db.rawQuery('PRAGMA user_version')).first.values.first! as int;

  /// База поточної версії з пасікою й вуликом.
  Future<(String, String)> seed() async {
    final db = await AppDatabase.open(factory, path);
    final repo = Repository(db);
    await repo.init();
    final a = await repo.addApiary('Стара пасіка');
    final g = await repo.addGroup(a, {'0,0': 'hive', '1,0': 'hive'}, 3, 4, groupLabel: 'Лежак 1');
    expect(await userVersion(db), AppDatabase.schemaVersion);
    await db.close();
    return (a, g);
  }

  test('нова база отримує поточну версію схеми', () async {
    final db = await AppDatabase.open(factory, path);
    expect(await userVersion(db), AppDatabase.schemaVersion);
    // усі таблиці на місці
    final tables = {
      for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        r['name']
    };
    for (final t in kSyncTables) {
      expect(tables, contains(t));
    }
    await db.close();
  });

  test('оновлення: кроки по черзі, рівно раз, дані цілі', () async {
    final (apiary, group) = await seed();
    final ran = <int>[];
    final steps = <int, Migration>{
      AppDatabase.schemaVersion + 1: (db) async {
        ran.add(AppDatabase.schemaVersion + 1);
        await db.execute('ALTER TABLE apiaries ADD COLUMN test_note TEXT');
        await db.update('apiaries', {'test_note': 'перенесено'});
      },
      AppDatabase.schemaVersion + 2: (db) async {
        ran.add(AppDatabase.schemaVersion + 2);
        // крок бачить результат попереднього
        final r = await db.query('apiaries', columns: ['test_note']);
        expect(r.every((x) => x['test_note'] == 'перенесено'), isTrue);
      },
    };
    final to = AppDatabase.schemaVersion + 2;
    var db = await AppDatabase.open(factory, path, version: to, steps: steps);
    expect(ran, [to - 1, to]);
    expect(await userVersion(db), to);
    final repo = Repository(db);
    expect((await repo.getApiary(apiary))?.name, 'Стара пасіка');
    expect((await repo.getGroupElements(group)).length, 2);
    await db.close();

    // повторне відкриття - кроки вдруге не виконуються
    db = await AppDatabase.open(factory, path, version: to, steps: steps);
    expect(ran, [to - 1, to]);
    await db.close();
  });

  test('збій посеред кроку - база лишається попередньої версії, дані цілі', () async {
    final (apiary, _) = await seed();
    final to = AppDatabase.schemaVersion + 1;
    await expectLater(
      AppDatabase.open(factory, path, version: to, steps: {
        to: (db) async {
          await db.delete('apiaries');
          throw StateError('збій');
        },
      }),
      throwsA(isA<StateError>()),
    );
    final db = await AppDatabase.open(factory, path);
    expect(await userVersion(db), AppDatabase.schemaVersion);
    expect((await Repository(db).getApiary(apiary))?.name, 'Стара пасіка');
    await db.close();
  });

  test('версія 2: усе, що стара заглушка позначила «відправленим», знову в черзі', () async {
    // база версії 1, як у людей до етапу 0: заглушка позначила все відправленим
    var db = await AppDatabase.open(factory, path, version: 1, steps: const {});
    var repo = Repository(db);
    await repo.init();
    final a = await repo.addApiary('Пасіка');
    await repo.addGroup(a, {'0,0': 'hive'}, 0, 0);
    for (final t in kSyncTables) {
      await repo.markSyncedBatch(t, await repo.unsynced(t));
    }
    expect(await repo.countUnsynced(), 0);
    var total = 0;
    for (final t in kSyncTables) {
      total += (await db.rawQuery('SELECT COUNT(*) AS n FROM $t')).first['n']! as int;
    }
    await db.close();

    db = await AppDatabase.open(factory, path);
    repo = Repository(db);
    expect(await userVersion(db), greaterThanOrEqualTo(2));
    expect(await repo.countUnsynced(), total); // сервер отримає все
    await db.close();
  });

  test('кроки міграції безпечні й для нової порожньої бази (і пісочниці)', () async {
    final ran = <int>[];
    final db = await AppDatabase.open(factory, inMemoryDatabasePath,
        singleInstance: false,
        steps: {
          for (final e in AppDatabase.migrations.entries)
            e.key: (d) async {
              ran.add(e.key);
              await e.value(d);
            },
        });
    expect(ran, AppDatabase.migrations.keys.toList()..sort());
    expect(await Repository(db).countUnsynced(), 0);
    await db.close();
    // і справжня пісочниця уроку відкривається
    final sandbox = await AppDatabase.openSandbox(factory);
    expect(await userVersion(sandbox), AppDatabase.schemaVersion);
    await sandbox.close();
  });

  test('базу новішої версії не відкриваємо (зрозуміла помилка)', () async {
    await seed();
    final newer = AppDatabase.schemaVersion + 1;
    var db = await AppDatabase.open(factory, path, version: newer, steps: const {});
    await db.close();
    Object? error;
    try {
      db = await AppDatabase.open(factory, path);
      await db.close();
    } catch (e) {
      error = e;
    }
    expect(error, isA<DatabaseTooNewException>());
    expect(error.toString(), contains('новішою версією'));
    expect((error! as DatabaseTooNewException).found, newer);
  });

  test('час змін - через clock (тести підставляють свій)', () async {
    final db = await AppDatabase.open(factory, path);
    final repo = Repository(db);
    await repo.init();
    final t = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final id = await withClock(Clock.fixed(t), () => repo.addApiary('Пасіка в часі'));
    final row = (await db.query('apiaries', where: 'id = ?', whereArgs: [id])).single;
    expect(row['updated_at'], t.microsecondsSinceEpoch / 1e6);
    expect(withClock(Clock.fixed(t), Repository.now), t.microsecondsSinceEpoch / 1e6);
    await db.close();
  });
}
