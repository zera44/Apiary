import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/notes.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_api.dart';
import 'package:apiary/data/sync_engine.dart';
import 'package:apiary/services/stock_photos.dart';
import 'dart:typed_data';
import 'package:apiary/data/sync_repo.dart';
import 'package:apiary/services/backups.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_sync_server.dart';

/// Синхронізація: два «телефони» (дві бази) і фейковий сервер між ними.
void main() {
  late FakeSyncServer server;
  final opened = <Repository>[];

  setUpAll(sqfliteFfiInit);
  setUp(() => server = FakeSyncServer());
  tearDown(() async {
    for (final r in opened) {
      await r.db.close();
    }
    opened.clear();
  });

  Future<Repository> phone() async {
    final r = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false));
    await r.init();
    opened.add(r);
    return r;
  }

  Future<SyncReport> sync(Repository r, String uid) => SyncEngine(r, server.as(uid)).run();

  // час телефона - за годинником (Repository.now() іде через clock)
  var minute = 0;
  Future<T> later<T>(Future<T> Function() f) =>
      withClock(Clock.fixed(DateTime(2026, 10, 10, 12).add(Duration(minutes: ++minute))), f);

  Future<int> n(Repository r, String table, [String where = '1 = 1', List<Object?> args = const []]) async =>
      ((await r.db.rawQuery('SELECT COUNT(*) AS c FROM $table WHERE $where', args)).first['c'] as int?) ?? 0;

  group('один користувач, два телефони', () {
    test('зміни з одного телефона з\'являються на іншому; повтор нічого не шле', () async {
      final a = await phone(), b = await phone();
      final ap = await a.addApiary('Біля річки');
      final g = await a.addGroup(ap, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      final e = EntityRef.group(g);
      final pid = await a.addParameter('Сила');
      await a.setAttachedParameters([pid], e);
      await a.addParameterRecord(pid, '7', e);
      await a.addHiveNote(e, 'матка є');

      final ra = await sync(a, 'u1');
      expect(ra.sent, greaterThan(0));
      expect(await a.countUnsynced(), 0);
      await sync(b, 'u1');
      expect((await b.getApiary(ap))!.name, 'Біля річки');
      expect((await b.getApiary(ap))!.isMine, isTrue); // свій - owner_id NULL
      expect(await n(b, 'parameter_records', 'parameter_id = ?', [pid]), 1);
      expect(await n(b, 'hive_notes', "text = 'матка є'"), 1);
      expect(await b.countUnsynced(), 0, reason: 'отримане - не в черзі на відправку');

      // повторно - нічого нового в жоден бік
      final before = server.upserts;
      final again = await sync(b, 'u1');
      expect(again.sent, 0);
      expect(server.upserts, before);
    });

    test('конфлікт: перемагає той, хто записав на сервер пізніше', () async {
      final a = await phone(), b = await phone();
      final ap = await a.addApiary('Перша');
      await sync(a, 'u1');
      await sync(b, 'u1');
      await later(() => a.updateApiary(ap, name: 'Від А'));
      await later(() => b.updateApiary(ap, name: 'Від Б'));
      await sync(a, 'u1'); // А - першим
      await sync(b, 'u1'); // Б - пізніше: перемагає
      await sync(a, 'u1');
      expect((await a.getApiary(ap))!.name, 'Від Б');
      expect((await b.getApiary(ap))!.name, 'Від Б');
    });

    test('зміна, зроблена на телефоні після відправки, не затирається отриманим', () async {
      final a = await phone(), b = await phone();
      final ap = await a.addApiary('Перша');
      await sync(a, 'u1');
      await sync(b, 'u1');
      await later(() => b.updateApiary(ap, name: 'Б'));
      await sync(b, 'u1');
      await later(() => a.updateApiary(ap, name: 'А, ще не відправлено'));
      // забирання бачить «Б», але локальна зміна новіша й ще в черзі
      await SyncEngine(a, server.as('u1')).run();
      expect((await a.getApiary(ap))!.name, 'А, ще не відправлено');
      await sync(b, 'u1');
      expect((await b.getApiary(ap))!.name, 'А, ще не відправлено');
    });

    test('видалення пізніше за зміну перемагає; давня зміна не «воскрешає»', () async {
      final a = await phone(), b = await phone();
      final ap = await a.addApiary('Перша');
      await sync(a, 'u1');
      await sync(b, 'u1');
      await later(() => b.updateApiary(ap, name: 'Змінено'));
      await later(() => a.deleteApiary(ap));
      await sync(a, 'u1'); // видалення - на сервері
      await sync(b, 'u1'); // давніша зміна Б - не скасовує його
      expect(await n(b, 'apiaries', 'id = ? AND deleted = 0', [ap]), 0);
      expect(await n(a, 'apiaries', 'id = ? AND deleted = 0', [ap]), 0);
      // а зміна, зроблена ПІСЛЯ видалення, - так (свідоме відновлення)
      await later(() => b.db.update('apiaries', {'deleted': 0, 'synced': 0, 'updated_at': Repository.now()},
          where: 'id = ?', whereArgs: [ap]));
      await sync(b, 'u1');
      await sync(a, 'u1');
      expect(await n(a, 'apiaries', 'id = ? AND deleted = 0', [ap]), 1);
    });

    test('склад: прихід на двох телефонах одночасно - обидва рухи, залишок - сума', () async {
      final a = await phone(), b = await phone();
      final item = await a.addStockItem('Цукор', 'кг');
      await sync(a, 'u1');
      await sync(b, 'u1');
      await later(() => a.receiveStock(item, 10, total: 0));
      await later(() => b.receiveStock(item, 5, total: 0));
      await sync(a, 'u1');
      await sync(b, 'u1');
      await sync(a, 'u1');
      for (final r in [a, b]) {
        expect(await n(r, 'stock_moves', 'item_id = ?', [item]), 2);
        final q = (await r.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single['quantity'];
        expect(q, 15, reason: 'залишок - сума рухів');
      }
      // скасування руху теж доходить, залишок перераховано
      final m = (await a.db.query('stock_moves', where: "item_id = ? AND amount = 10", whereArgs: [item])).single;
      await later(() => a.cancelStockMove(m['id']! as String));
      await sync(a, 'u1');
      await sync(b, 'u1');
      final q = (await b.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single['quantity'];
      expect(q, 5);
    });

    test('без зв\'язку - дані лишаються в черзі; з\'явився - усе пішло', () async {
      final a = await phone();
      await a.addApiary('Перша');
      server.offline = true;
      await expectLater(sync(a, 'u1'), throwsA(anything));
      expect(await a.countUnsynced(), greaterThan(0));
      server.offline = false;
      await sync(a, 'u1');
      expect(await a.countUnsynced(), 0);
    });

    test('відновлена копія: прибране з історії значень сервер позначає видаленим на всіх', () async {
      final dir = Directory.systemTemp.createTempSync('apiary_sync_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, p.join(dir.path, 'a.db')));
      await a.init();
      opened.add(a);
      final b = await phone();
      final ap = await a.addApiary('Перша');
      final g = await a.addGroup(ap, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      final pid = await a.addParameter('Сила');
      final backups = BackupService(a, dir: p.join(dir.path, 'bk'), factory: databaseFactoryFfiNoIsolate);
      final copy = await backups.create();
      await a.addParameterRecord(pid, '9', EntityRef.group(g)); // після копії
      await sync(a, 'u1');
      await sync(b, 'u1');
      expect(await n(b, 'parameter_records'), 1);
      await backups.restoreFrom(copy.path);
      expect(await n(a, 'sync_deletions'), 1);
      await sync(a, 'u1');
      expect(await n(a, 'sync_deletions'), 0);
      await sync(b, 'u1');
      expect(await n(b, 'parameter_records'), 0);
    });
  });

  group('помічник', () {
    test('бачить лише пасіку, до якої запросили; огляди - власниці; доступ забрали - прибрано', () async {
      final olena = await phone(), petro = await phone();
      final river = await olena.addApiary('Річка');
      final forest = await olena.addApiary('Ліс');
      final g = await olena.addGroup(river, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      await olena.addGroup(forest, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      final item = await olena.addStockItem('Цукор', 'кг');
      await sync(olena, 'olena');
      final m = server.addMember('olena', 'petro', apiary: river);

      await sync(petro, 'petro');
      final list = await petro.listApiaries();
      expect([for (final x in list) x.name], containsAll(['Річка']));
      expect(list.where((x) => x.name == 'Ліс'), isEmpty);
      expect(list.firstWhere((x) => x.id == river).isMine, isFalse);
      expect(await n(petro, 'stock_items', 'id = ?', [item]), 0, reason: 'склад без дозволу');

      // Петро робить огляд своєю (типовою) характеристикою - у власниці вона своя
      final petroBase = await petro.addParameter('Медовий запас');
      await petro.addParameterRecord(petroBase, '12', EntityRef.group(g));
      final r = await sync(petro, 'petro');
      expect(r.rejected, 0);
      await sync(olena, 'olena');
      final rec = (await olena.db.query('parameter_records', where: "value = '12'")).single;
      final par = (await olena.db.query('parameters', where: 'id = ?', whereArgs: [rec['parameter_id']])).single;
      expect(par['name'], 'Медовий запас');
      expect(par['owner_id'], isNull, reason: 'у власниці характеристика - її');

      // доступ забрали - пасіка зникає з телефона Петра (без позначок «видалено»)
      server.removeMember(m);
      await sync(petro, 'petro');
      expect(await petro.getApiary(river), isNull);
      expect(await n(petro, 'elements', 'apiary_id = ?', [river]), 0);
      await sync(olena, 'olena');
      expect(await olena.getApiary(river), isNotNull, reason: 'у власниці все лишається');
    });

    test('запросили пізніше - давні дані власниці теж приходять; склад - за дозволом', () async {
      final olena = await phone(), petro = await phone();
      final river = await olena.addApiary('Річка');
      final item = await olena.addStockItem('Цукор', 'кг');
      await olena.receiveStock(item, 3, total: 0);
      await sync(olena, 'olena');
      await sync(petro, 'petro'); // курсор Петра вже пройшов ці рядки
      expect(await petro.getApiary(river), isNull);
      server.addMember('olena', 'petro', stock: true);
      await sync(petro, 'petro');
      expect(await petro.getApiary(river), isNotNull);
      expect(await n(petro, 'stock_moves', 'item_id = ?', [item]), 1);
      // помічник зі складом теж може списати
      await petro.writeOffStock(item, 1);
      final r = await sync(petro, 'petro');
      expect(r.rejected, 0);
      await sync(olena, 'olena');
      expect((await olena.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single['quantity'], 2);
    });

    test('відхилене сервером не блокує решту черги й не повторюється без змін', () async {
      final olena = await phone(), petro = await phone();
      final river = await olena.addApiary('Річка');
      await sync(olena, 'olena');
      server.addMember('olena', 'petro', apiary: river);
      await sync(petro, 'petro');
      // Петро перейменовує пасіку власниці (не можна) і створює свою (можна)
      await later(() => petro.updateApiary(river, name: 'Моя!'));
      final own = await petro.addApiary('Петрова');
      final r = await sync(petro, 'petro');
      expect(r.rejected, 1);
      expect(await countRejected(petro), 1);
      expect(await n(petro, 'apiaries', 'id = ? AND synced = 1', [own]), 1);
      final again = await sync(petro, 'petro');
      expect(again.rejected, 0);
      // уночі - ще спроба (раптом дозвіл з'явився)
      expect(await SyncEngine(petro, server.as('petro')).retryRejected(), 1);
    });
  });

  group('після перевірки', () {
    test('власниця забрала одну пасіку й дала іншу між синхронізаціями - нова лишається', () async {
      final olena = await phone(), petro = await phone();
      final river = await olena.addApiary('Річка');
      final forest = await olena.addApiary('Ліс');
      await sync(olena, 'olena');
      final m1 = server.addMember('olena', 'petro', apiary: river);
      await sync(petro, 'petro');
      server.removeMember(m1);
      server.addMember('olena', 'petro', apiary: forest);
      for (var i = 0; i < 3; i++) {
        await sync(petro, 'petro');
        expect(await petro.getApiary(river), isNull, reason: 'хід $i');
        expect(await petro.getApiary(forest), isNotNull, reason: 'хід $i');
      }
    });

    test('фото: ще не дійшло на сервер - отримаємо наступного разу', () async {
      final dir = Directory.systemTemp.createTempSync('apiary_photos_');
      addTearDown(() {
        StockPhotos.debugDir = null;
        dir.deleteSync(recursive: true);
      });
      StockPhotos.debugDir = dir.path;
      final a = await phone(), b = await phone();
      final item = await a.addStockItem('Цукор', 'кг');
      File(p.join(dir.path, 'ph.webp')).writeAsBytesSync([1, 2, 3]);
      await a.updateStockItem(item, photo: ('ph.webp',));
      await sync(a, 'u1');
      expect(server.photos.keys, contains('u1/ph.webp'));
      // на телефоні Б тієї ж теки немає - імітуємо: файл прибрано, на сервері ще нема
      final onServer = server.photos.remove('u1/ph.webp')!;
      File(p.join(dir.path, 'ph.webp')).deleteSync();
      final r1 = await sync(b, 'u1');
      expect(r1.photosDown, 0);
      server.photos['u1/ph.webp'] = onServer;
      final r2 = await sync(b, 'u1');
      expect(r2.photosDown, 1);
      expect(File(p.join(dir.path, 'ph.webp')).readAsBytesSync(), Uint8List.fromList([1, 2, 3]));
    });

    test('зв\'язок обірвався після складу - залишок усе одно правильний', () async {
      final a = await phone(), b = await phone();
      final item = await a.addStockItem('Цукор', 'кг');
      await sync(a, 'u1');
      await sync(b, 'u1');
      await later(() => a.receiveStock(item, 5, total: 0));
      await later(() => b.receiveStock(item, 3, total: 0));
      await sync(b, 'u1');
      server.offlineTables.add('fin_categories');
      await expectLater(sync(a, 'u1'), throwsA(isA<SyncOffline>()));
      expect((await a.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single['quantity'], 8);
    });

    test('сервер не дає позначити запис історії видаленим - решта синхронізації йде далі', () async {
      final a = await phone();
      await a.db.insert('sync_deletions', {'tbl': 'parameter_records', 'id': 'r-bad', 'at': 1.0});
      server.rejectDeletes.add('r-bad');
      await a.addApiary('Перша');
      final r = await sync(a, 'u1');
      expect(r.rejected, 1);
      expect(await n(a, 'sync_deletions'), 0);
      expect(await a.countUnsynced(), 0);
    });

    test('понад 150 днів без синхронізації - усе заново, стерте на сервері прибрано', () async {
      final a = await phone();
      final ap = await a.addApiary('Давно стерта');
      await sync(a, 'u1');
      server.t('apiaries').remove(ap); // сервер давно прибрав позначку
      await a.setMeta(SyncEngine.lastPullKey, '${Repository.now() - 200 * 86400}');
      await sync(a, 'u1');
      expect(await n(a, 'apiaries', 'id = ?', [ap]), 0);
    });

    test('інший акаунт Google на тому ж телефоні - не змішуємо дані', () async {
      final a = await phone();
      await a.addApiary('Пасіка першого');
      await sync(a, 'u1');
      await expectLater(sync(a, 'u2'), throwsA(isA<SyncOtherAccount>()));
      expect(server.t('apiaries').values.where((r) => r['owner_id'] == 'u2'), isEmpty);
    });

    test('відновили копію, синхронізували, «Скасувати» - нове після копії повертається', () async {
      final dir = Directory.systemTemp.createTempSync('apiary_undo_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, p.join(dir.path, 'a.db')));
      await a.init();
      opened.add(a);
      final b = await phone();
      final backups = BackupService(a, dir: p.join(dir.path, 'bk'), factory: databaseFactoryFfiNoIsolate);
      final copy = await later(() => backups.create());
      final fresh = await later(() => a.addApiary('Нова після копії'));
      await later(() => sync(a, 'u1'));
      final before = await later(() => backups.restore(copy));
      await later(() => sync(a, 'u1'));
      await later(() => sync(b, 'u1'));
      expect(await n(b, 'apiaries', 'id = ? AND deleted = 0', [fresh]), 0);
      await later(() => backups.restoreFrom(before.path)); // «Скасувати»
      await later(() => sync(a, 'u1'));
      await later(() => sync(b, 'u1'));
      expect(await n(a, 'apiaries', 'id = ? AND deleted = 0', [fresh]), 1);
      expect(await n(b, 'apiaries', 'id = ? AND deleted = 0', [fresh]), 1);
    });
  });

  test('перерахунок залишку з рухів: прихід, списання, переоблік, скасування, старий «set»', () async {
    final a = await phone();
    final item = await a.addStockItem('Мед', 'кг');
    await a.receiveStock(item, 10, total: 0);
    await a.writeOffStock(item, 3);
    await a.inventoryStock(item, 6);
    final m = (await a.db.query('stock_moves', where: "kind = 'out'")).single;
    await a.cancelStockMove(m['id']! as String);
    final real = (await a.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single['quantity'];
    await a.db.update('stock_items', {'quantity': 999}, where: 'id = ?', whereArgs: [item]);
    expect(await a.recomputeStock([item]), 1);
    expect((await a.db.query('stock_items', where: 'id = ?', whereArgs: [item])).single['quantity'], real);
  });
}
