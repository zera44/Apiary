import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/backups_screen.dart';
import 'package:apiary/screens/settings_screen.dart';
import 'package:apiary/services/background.dart';
import 'package:apiary/services/backups.dart';
import 'package:apiary/services/stock_photos.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/theme.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late Repository repo;
  late BackupService backups;
  final factory = databaseFactoryFfiNoIsolate;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('apiary_backups_');
    repo = Repository(await AppDatabase.open(factory, p.join(dir.path, 'apiary.db')));
    await repo.init();
    backups = BackupService(repo, dir: p.join(dir.path, 'backups'), factory: factory);
  });
  tearDown(() async {
    await repo.db.close();
    BackupService.of = BackupService.forApp;
    dir.deleteSync(recursive: true);
  });

  Future<String?> apiaryName(String id) async => (await repo.getApiary(id))?.name;

  Future<Map<String, Object?>> apiaryRow(String id) async =>
      (await repo.db.query('apiaries', where: 'id = ?', whereArgs: [id])).single;

  group('розклад', () {
    final t = DateTime(2026, 10, 10, 12);
    test('кожні 6 годин; копій ще немає - одразу', () {
      expect(BackupService.isDue(null, t), isTrue);
      expect(BackupService.isDue(t.subtract(const Duration(hours: 5, minutes: 59)), t), isFalse);
      expect(BackupService.isDue(t.subtract(const Duration(hours: 6)), t), isTrue);
      expect(BackupService.isDue(t.subtract(const Duration(days: 3)), t), isTrue);
    });

    test('годинник перевели назад - теж пора (остання «з майбутнього»)', () {
      expect(BackupService.isDue(t.add(const Duration(hours: 2)), t), isTrue);
    });

    test('maybeBackup робить копію лише коли пора', () async {
      final b = await withClock(Clock.fixed(t), backups.maybeBackup);
      expect(b, isNotNull);
      expect(await withClock(Clock.fixed(t.add(const Duration(hours: 1))), backups.maybeBackup),
          isNull);
      expect(await withClock(Clock.fixed(t.add(const Duration(hours: 6))), backups.maybeBackup),
          isNotNull);
      expect((await backups.list()).length, 2);
    });
  });

  group('створення', () {
    Future<void> checkCopy(LocalBackup b, String apiary) async {
      expect(await backups.verify(b.path), isTrue);
      final c = await factory.openDatabase(b.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final r = await c.query('apiaries', where: 'id = ?', whereArgs: [apiary]);
      expect(r.single['name'], 'Пасіка в копії');
      await c.close();
    }

    test('узгоджений знімок (VACUUM INTO): дані на місці, копія перевірена', () async {
      final a = await repo.addApiary('Пасіка в копії');
      final b = await backups.create();
      expect(b.kind, BackupKind.manual);
      expect(b.size, greaterThan(0));
      await checkCopy(b, a);
      expect((await backups.latest())!.path, b.path);
    });

    test('Android 7-10 (без VACUUM INTO): копія файлу в транзакції - так само ціла', () async {
      backups.forceFileCopy = true;
      final a = await repo.addApiary('Пасіка в копії');
      await checkCopy(await backups.create(BackupKind.auto), a);
    });

    test('Android 9 (режим WAL, без VACUUM INTO): свіжі зміни з -wal у копії, '
        'сторонніх файлів немає', () async {
      expect((await repo.db.rawQuery('PRAGMA journal_mode=WAL')).first.values.first, 'wal');
      backups.forceFileCopy = true;
      final a = await repo.addApiary('Пасіка в копії');
      expect(File('${repo.db.path}-wal').existsSync(), isTrue);
      final b = await backups.create(BackupKind.auto);
      await checkCopy(b, a);
      expect(Directory(backups.dir).listSync().map((e) => p.basename(e.path)),
          [p.basename(b.path)]);
    });

    test('копія «з майбутнього» (годинник перевели назад): не рахується; '
        'з\'явилась звичайна - прибрана', () async {
      final t = DateTime(2026, 10, 10, 12);
      final future = await withClock(
          Clock.fixed(t.add(const Duration(days: 1))), () => backups.create(BackupKind.auto));
      // лише «майбутня» - вона найсвіжіший стан, але копію все одно робимо
      final fresh = await withClock(Clock.fixed(t), backups.maybeBackup);
      expect(fresh, isNotNull);
      final left = await backups.list();
      expect(left.map((b) => b.path), [fresh!.path]);
      expect(left.map((b) => b.path), isNot(contains(future.path)));
      expect((await withClock(Clock.fixed(t), backups.latest))!.path, fresh.path);
    });

    test('пошкоджену копію не зберігаємо', () async {
      backups.debugAfterSnapshot = (path) async {
        final f = File(path);
        final bytes = await f.readAsBytes();
        bytes.fillRange(100, bytes.length, 0x5A); // зіпсувати все після заголовка
        await f.writeAsBytes(bytes);
      };
      await expectLater(backups.create(), throwsA(isA<BackupException>()));
      expect(await backups.list(), isEmpty);
      expect(Directory(backups.dir).listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('копії за 2 дні; старіші видаляються, але найновіша - завжди', () async {
      final t0 = DateTime(2026, 10, 1, 0, 30);
      for (var h = 0; h <= 72; h += 6) {
        await withClock(Clock.fixed(t0.add(Duration(hours: h))), () => backups.create(BackupKind.auto));
      }
      final now = t0.add(const Duration(hours: 72));
      final left = await backups.list();
      expect(left.length, 9); // 0..48 год тому
      expect(left.every((b) => now.difference(b.time) <= BackupService.keepFor), isTrue);
      expect(left.first.time, now.subtract(Duration(microseconds: now.microsecond)));

      // тиждень без застосунку - остання копія лишається
      await withClock(Clock.fixed(now.add(const Duration(days: 7))), backups.prune);
      expect((await backups.list()).length, 1);
    });
  });

  group('відновлення', () {
    test('дані з копії; нове - позначкою «видалено»; налаштування телефона не чіпаються; '
        'можна скасувати', () async {
      final a = await repo.addApiary('Стара назва');
      await repo.addGroup(a, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      await repo.setParamGroups([ParamGroup(id: 'g', name: 'Обходи', ids: [])]);
      await repo.setMeta('last_apiary', a);
      final copy = await backups.create();

      // після копії: перейменували, додали пасіку, змінили групи
      await repo.updateApiary(a, name: 'Нова назва');
      final c = await repo.addApiary('Додана після копії');
      await repo.setParamGroups([ParamGroup(id: 'g2', name: 'Інша', ids: [])]);
      await repo.setMeta('last_apiary', c);
      var changed = 0;
      void bump() => changed++;
      repo.mapChanges.addListener(bump);
      repo.stockChanges.addListener(bump);

      final before = await backups.restore(copy);

      expect(await apiaryName(a), 'Стара назва');
      expect((await repo.listApiaries()).map((x) => x.id), isNot(contains(c))); // у списках немає...
      final cRow = await apiaryRow(c);
      expect(cRow['deleted'], 1); // ...але сервер дізнається, що її видалено
      expect(cRow['synced'], 0);
      expect((await repo.paramGroups()).single.name, 'Обходи');
      expect(await repo.getMeta('last_apiary'), c); // позначка саме цього телефона
      expect(changed, greaterThanOrEqualTo(2)); // екрани перечитають дані
      // усе відновлене - у черзі на відправку
      for (final t in kSyncTables) {
        expect((await repo.db.rawQuery('SELECT COUNT(*) AS n FROM $t WHERE synced != 0'))
            .first['n'], 0, reason: t);
      }
      // стан перед відновленням - окремою копією
      expect(before.kind, BackupKind.beforeRestore);
      expect((await backups.list()).map((b) => b.path), contains(before.path));

      // «Скасувати» - назад як було
      await backups.restoreFrom(before.path);
      expect(await apiaryName(a), 'Нова назва');
      expect(await apiaryName(c), 'Додана після копії');
      expect((await repo.paramGroups()).single.name, 'Інша');
      // база й далі працює (копія від'єднана)
      expect((await repo.db.rawQuery('PRAGMA database_list')).map((r) => r['name']),
          isNot(contains('bk')));
    });

    test('найстаріша копія після 48+ год: прибирання її не видаляє, відновлення вдається',
        () async {
      final t0 = DateTime(2026, 10, 1, 9);
      final a = await withClock(Clock.fixed(t0), () => repo.addApiary('Давня назва'));
      final oldest = await withClock(Clock.fixed(t0), () => backups.create(BackupKind.auto));
      await withClock(Clock.fixed(t0.add(const Duration(hours: 6))),
          () => backups.create(BackupKind.auto));
      await repo.updateApiary(a, name: 'Нова назва');
      final later = t0.add(const Duration(hours: 49));
      final copy = (await withClock(Clock.fixed(later), backups.list))
          .firstWhere((b) => b.path == oldest.path);
      final before = await withClock(Clock.fixed(later), () => backups.restore(copy));
      expect(await apiaryName(a), 'Давня назва');
      expect(before.kind, BackupKind.beforeRestore);
      // наступне прибирання - вже звичайне
      await withClock(Clock.fixed(later), backups.prune);
      expect((await backups.list()).map((b) => b.path), isNot(contains(oldest.path)));
    });

    test('копії, з якої відновлюють, уже немає - зрозуміла помилка, дані як були', () async {
      final a = await repo.addApiary('Як було');
      final b = await backups.create();
      await File(b.path).delete();
      await expectLater(backups.restore(b), throwsA(isA<BackupException>()));
      expect(await apiaryName(a), 'Як було');
    });

    test('копія старішої версії: кроки міграції, фото під новими назвами', () async {
      // копія до етапу 0: версія 1, усе позначено «відправленим», фото - повний шлях
      final oldPath = p.join(dir.path, 'old.db');
      final old = Repository(await AppDatabase.open(factory, oldPath, version: 1, steps: const {}));
      await old.init();
      final a = await old.addApiary('Пасіка з давньої копії');
      final item = await old.addStockItem('Цукор', 'кг');
      await old.updateStockItem(item, photo: ('/old/stock_photos/photo_1.jpg',));
      for (final t in kSyncTables) {
        await old.markSyncedBatch(t, await old.unsynced(t));
      }
      await old.db.close();
      await repo.setMeta(StockPhotos.upgradeMapKey, '{"/old/stock_photos/photo_1.jpg":"new.webp"}');

      await backups.restoreFrom(oldPath);
      expect(await apiaryName(a), 'Пасіка з давньої копії');
      expect((await apiaryRow(a))['synced'], 0);
      final row = (await repo.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single;
      expect(row['photo'], 'new.webp');
    });

    test('копію новішої версії не відновлюємо, дані як були', () async {
      final a = await repo.addApiary('Як було');
      final newerPath = p.join(dir.path, 'newer.db');
      final newer = await AppDatabase.open(factory, newerPath,
          version: AppDatabase.schemaVersion + 1, steps: const {});
      await newer.close();
      await expectLater(backups.restoreFrom(newerPath), throwsA(isA<DatabaseTooNewException>()));
      expect(await apiaryName(a), 'Як було');
    });

    test('збій посеред відновлення - нічого не змінено, база працює', () async {
      final a = await repo.addApiary('Як було');
      // «копія», де в пасіки немає назви (у справжній базі - обов'язкова)
      final badPath = p.join(dir.path, 'bad.db');
      final bad = await factory.openDatabase(badPath);
      await bad.execute('CREATE TABLE apiaries (id TEXT PRIMARY KEY, name TEXT)');
      await bad.execute('CREATE TABLE elements (id TEXT PRIMARY KEY)');
      await bad.insert('apiaries', {'id': 'x', 'name': null});
      await bad.close();
      await expectLater(backups.restoreFrom(badPath), throwsA(isA<DatabaseException>()));
      expect(await apiaryName(a), 'Як було');
      expect((await apiaryRow(a))['deleted'], 0);
      expect((await repo.db.rawQuery('PRAGMA database_list')).map((r) => r['name']),
          isNot(contains('bk')));
      expect(await repo.addApiary('Ще одна'), isNotEmpty);
    });

    test('пошкоджену копію не відновлюємо', () async {
      final a = await repo.addApiary('Як було');
      final f = File(p.join(backups.dir, 'apiary-20261010-120000-auto.db'));
      await f.parent.create(recursive: true);
      await f.writeAsString('не база');
      final b = (await backups.list()).single;
      await expectLater(backups.restore(b), throwsA(isA<BackupException>()));
      expect(await apiaryName(a), 'Як було');
    });
  });

  test('фото, на які посилаються копії, не прибираються з теки', () async {
    final id = await repo.addStockItem('Цукор', 'кг');
    await repo.updateStockItem(id, photo: ('в-копії.webp',));
    await backups.create();
    await repo.updateStockItem(id, photo: (null,));
    expect(await backups.photoRefs(), {'в-копії.webp'});
  });

  group('фонове завдання', () {
    test('робить копію, якщо пора; невідоме - не повторюється', () async {
      expect(
          await runBackgroundTask(BackgroundTasks.backup,
              openRepo: () async => repo, backups: (_) async => backups),
          isTrue);
      expect((await backups.list()).single.kind, BackupKind.auto);
      expect(await runBackgroundTask('застаріле', openRepo: () async => repo), isTrue);
    });

    test('збій - система повторить пізніше', () async {
      expect(await runBackgroundTask(BackgroundTasks.backup, openRepo: () => throw StateError('x')),
          isFalse);
    });
  });

  testWidgets('Налаштування → «Головне» → «Резервні копії»: копія зараз і відновлення',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BackupService.of = (_) async => backups;
    final a = (await tester.runAsync(() => repo.addApiary('Стара назва')))!;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: SettingsScreen(repo: repo)));
    await settle();
    expect(find.text(tr.backupsSection), findsNWidgets(2)); // заголовок і кнопка
    expect(find.text(tr.backupsNone), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, tr.backupsSection));
    await settle();
    expect(find.byType(BackupsScreen), findsOneWidget);
    await tester.tap(find.text(tr.backupNow));
    await settle();
    // список перечитується з диска - чекаємо, поки з'явиться
    for (var k = 0; k < 20 && find.textContaining(tr.backupKindManual).evaluate().isEmpty; k++) {
      await settle();
    }
    expect(find.textContaining(tr.backupKindManual), findsOneWidget); // «зроблена вручну · 20 КБ»

    await tester.runAsync(() => repo.updateApiary(a, name: 'Нова назва'));
    await tester.tap(find.widgetWithText(PillButton, tr.backupRestore).first);
    await settle();
    expect(find.text(tr.backupRestoreTitle), findsOneWidget);
    await tester.tap(find.text(tr.backupRestore).last); // кнопка у вікні підтвердження
    for (var k = 0; k < 20 && find.byType(BackupsScreen).evaluate().isNotEmpty; k++) {
      await settle();
    }
    expect(await tester.runAsync(() => apiaryName(a)), 'Стара назва');
    // на перший екран, з «Скасувати»
    expect(find.byType(BackupsScreen), findsNothing);
    expect(find.text(tr.backupRestored), findsOneWidget);

    // «Скасувати» - як було перед відновленням, з повідомленням
    await tester.tap(find.text(tr.undo));
    for (var k = 0; k < 20 && find.text(tr.backupUndone).evaluate().isEmpty; k++) {
      await settle();
    }
    expect(find.text(tr.backupUndone), findsOneWidget);
    expect(await tester.runAsync(() => apiaryName(a)), 'Нова назва');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Скасувати» не вдалося - повідомлення, а не тиша', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BackupService.of = (_) async => backups;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.runAsync(() async {
      await repo.addApiary('Пасіка');
      await backups.create();
    });
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: BackupsScreen(repo: repo)));
    for (var k = 0; k < 20 && find.text(tr.backupRestore).evaluate().isEmpty; k++) {
      await settle();
    }
    await tester.tap(find.widgetWithText(PillButton, tr.backupRestore).first);
    await settle();
    await tester.tap(find.text(tr.backupRestore).last);
    for (var k = 0; k < 20 && find.text(tr.backupRestored).evaluate().isEmpty; k++) {
      await settle();
    }
    // копію «до відновлення» встигли прибрати
    await tester.runAsync(() async {
      for (final b in await backups.list()) {
        if (b.kind == BackupKind.beforeRestore) await File(b.path).delete();
      }
    });
    await tester.tap(find.text(tr.undo));
    for (var k = 0; k < 20 && find.textContaining(tr.backupRestoreFailed('')).evaluate().isEmpty;
        k++) {
      await settle();
    }
    expect(find.textContaining(tr.backupRestoreFailed('')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('теку копій не прочитати - порожній список і пояснення, без вічного завантаження',
      (tester) async {
    BackupService.of = (_) async => throw const FileSystemException('немає доступу');
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: BackupsScreen(repo: repo)));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(tr.backupsNone), findsOneWidget);
    expect(find.textContaining('немає доступу'), findsOneWidget);
  });
}
