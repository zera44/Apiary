import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../data/repository.dart';
import 'stock_photos.dart';

/// Звідки взялась копія.
enum BackupKind {
  /// Сама, кожні 6 годин.
  auto,

  /// «Зробити копію зараз».
  manual,

  /// Перед відновленням (щоб відновлення можна було скасувати).
  beforeRestore,
}

/// Резервна копія бази на цьому телефоні.
class LocalBackup {
  final String path;
  final DateTime time;
  final BackupKind kind;
  final int size;
  const LocalBackup(this.path, this.time, this.kind, this.size);

  String get fileName => p.basename(path);
}

/// Локальні резервні копії бази (лише дані; фото не дублюються - вони
/// лишаються у своїй теці й не стираються, поки на них посилається копія).
///
///  * копія - узгоджений знімок SQLite (`VACUUM INTO`; де його немає -
///    Android 7-10 - копія файлу всередині транзакції), після створення -
///    `PRAGMA integrity_check`; пошкоджену копію не зберігаємо;
///  * кожні [interval] (фоном і при відкритті застосунку);
///  * зберігаються копії за [keepFor] (~8 шт.), старіші видаляються, але
///    найновіша лишається завжди;
///  * відновлення - у відкриту базу, в одній транзакції; перед ним -
///    автоматична копія поточного стану.
class BackupService {
  static const interval = Duration(hours: 6);
  static const keepFor = Duration(days: 2);

  /// Більше копій не тримаємо, хоч би й свіжих (місце на телефоні).
  static const maxCount = 16;

  final Repository repo;

  /// Тека з копіями.
  final String dir;

  /// Чим відкривати копії для перевірки.
  final DatabaseFactory factory;

  /// Тести: завжди копіювати файл (як на Android 7-10, де немає VACUUM INTO).
  @visibleForTesting
  bool forceFileCopy = false;

  /// Тести: зіпсувати знімок одразу після створення.
  @visibleForTesting
  Future<void> Function(String path)? debugAfterSnapshot;

  BackupService(this.repo, {required this.dir, DatabaseFactory? factory})
      : factory = factory ?? AppDatabase.platformFactory;

  /// Як отримати службу для бази (тести підставляють свою теку).
  static Future<BackupService> Function(Repository repo) of = forApp;

  /// Служба для бази застосунку (тека `backups` поряд із базою).
  static Future<BackupService> forApp(Repository repo) async {
    final support = await getApplicationSupportDirectory();
    return BackupService(repo, dir: p.join(support.path, 'backups'));
  }

  /// Чи пора робити копію: копій ще немає, остання давніша за [interval]
  /// або годинник перевели назад (остання - «з майбутнього»).
  static bool isDue(DateTime? last, DateTime now) {
    if (last == null) return true;
    final d = now.difference(last);
    return d.isNegative || d >= interval;
  }

  static final _name = RegExp(r'^apiary-(\d{8})-(\d{6})-(auto|manual|before)\.db$');

  static String _fileName(DateTime t, BackupKind k) {
    String two(int n) => n.toString().padLeft(2, '0');
    final kind = switch (k) {
      BackupKind.auto => 'auto',
      BackupKind.manual => 'manual',
      BackupKind.beforeRestore => 'before',
    };
    return 'apiary-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-$kind.db';
  }

  /// Копії, від найновішої.
  Future<List<LocalBackup>> list() async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <LocalBackup>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final m = _name.firstMatch(p.basename(e.path));
      if (m == null) continue;
      final day = m.group(1)!, hms = m.group(2)!;
      final t = DateTime(
        int.parse(day.substring(0, 4)),
        int.parse(day.substring(4, 6)),
        int.parse(day.substring(6, 8)),
        int.parse(hms.substring(0, 2)),
        int.parse(hms.substring(2, 4)),
        int.parse(hms.substring(4, 6)),
      );
      final kind = switch (m.group(3)) {
        'manual' => BackupKind.manual,
        'before' => BackupKind.beforeRestore,
        _ => BackupKind.auto,
      };
      try {
        out.add(LocalBackup(e.path, t, kind, await e.length()));
      } on FileSystemException {
        continue; // копію саме прибрали (паралельно з фону)
      }
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// Копія «з майбутнього»: годинник перевели назад після неї.
  static bool _isFuture(LocalBackup b, DateTime now) =>
      b.time.isAfter(now.add(const Duration(minutes: 5)));

  /// Остання копія (null - ще немає). Копії «з майбутнього» (годинник
  /// перевели назад) не рахуються, поки є звичайні.
  Future<LocalBackup?> latest() async {
    final all = await list();
    final now = clock.now();
    for (final b in all) {
      if (!_isFuture(b, now)) return b;
    }
    return all.isEmpty ? null : all.first;
  }

  Future<void>? _running;

  /// Зробити копію, якщо пора ([isDue]). Повертає нову копію або null.
  Future<LocalBackup?> maybeBackup() async {
    final last = await latest();
    final now = clock.now();
    if (last != null && _isFuture(last, now)) return create(BackupKind.auto); // лише «майбутні»
    if (!isDue(last?.time, now)) return null;
    return create(BackupKind.auto);
  }

  /// Зробити копію зараз. Пошкоджену не зберігає - кидає [BackupException].
  /// [keep] - копії, яких прибирання цього разу не чіпає (ту, з якої
  /// саме відновлюють).
  Future<LocalBackup> create([BackupKind kind = BackupKind.manual, Set<String> keep = const {}]) async {
    // дві копії одночасно не робимо (фонова й «Зробити зараз»)
    while (_running != null) {
      await _running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      await Directory(dir).create(recursive: true);
      final now = clock.now();
      final target = p.join(dir, _fileName(now, kind));
      final tmp = '$target.tmp';
      await _delete(tmp);
      await _snapshot(tmp);
      await debugAfterSnapshot?.call(tmp);
      if (!await verify(tmp)) {
        await _delete(tmp);
        throw const BackupException('копія пошкоджена - не збережено');
      }
      await _delete(target);
      await File(tmp).rename(target);
      await prune(keep: keep);
      return LocalBackup(target, DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second),
          kind, await File(target).length());
    } finally {
      _running = null;
      done.complete();
    }
  }

  /// Узгоджений перевірений знімок бази у файл [target] (поза списком
  /// копій - для нічної копії на сервер).
  Future<void> snapshotTo(String target) async {
    await _delete(target);
    await _snapshot(target);
    if (!await verify(target)) {
      await _delete(target);
      throw const BackupException('знімок бази пошкоджений');
    }
  }

  Future<void> _snapshot(String target) async {
    final db = repo.db;
    if (!forceFileCopy) {
      try {
        await db.execute('VACUUM INTO ?', [target]);
        return;
      } on DatabaseException catch (e) {
        // старий SQLite (Android 7-10): VACUUM INTO немає - копіюємо файл
        debugPrint('VACUUM INTO недоступний: $e');
        await _delete(target);
      }
    }
    if (db.path == inMemoryDatabasePath) {
      throw const BackupException('база в пам\'яті - копіювати нічого');
    }
    // усе йде через одне з'єднання: поки триває ця транзакція, ніхто не
    // пише в базу. Якщо база в режимі WAL (Android 9 вмикає його сам),
    // свіжі зміни лежать у файлі -wal - копіюємо і його
    await db.transaction((txn) async {
      await File(db.path).copy(target);
      final wal = File('${db.path}-wal');
      if (await wal.exists()) await wal.copy('$target-wal');
    });
    // злити журнал у саму копію й перевести її у звичайний режим (без
    // супутніх файлів -wal/-shm)
    final c = await factory.openDatabase(target, options: OpenDatabaseOptions(singleInstance: false));
    try {
      await c.rawQuery('PRAGMA journal_mode=DELETE');
    } finally {
      await c.close();
    }
    await _deleteSidecars(target);
  }

  /// Чи ціла копія: відкривається, `integrity_check` - ok, є таблиці даних.
  Future<bool> verify(String path) async {
    Database? c;
    try {
      c = await factory.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final r = await c.rawQuery('PRAGMA integrity_check');
      if (r.length != 1 || r.first.values.first != 'ok') return false;
      final tables = {
        for (final t in await c.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          t['name']
      };
      return tables.contains('apiaries') && tables.contains('elements');
    } catch (_) {
      return false;
    } finally {
      await c?.close();
    }
  }

  /// Прибрати копії, давніші за [keepFor] (і понад [maxCount]); найновіша
  /// лишається завжди - навіть якщо застосунком тиждень не користувались.
  /// [keep] - копії, яких цього разу не чіпати. Копії «з майбутнього»
  /// (годинник перевели назад) прибираються, щойно є звичайна - до того
  /// вони можуть бути найсвіжішим станом.
  Future<void> prune({Set<String> keep = const {}}) async {
    final now = clock.now();
    final all = await list();
    final real = [for (final b in all) if (!_isFuture(b, now)) b];
    for (var i = 1; i < real.length; i++) {
      final b = real[i];
      if (keep.contains(b.path)) continue;
      if (i >= maxCount || now.difference(b.time) > keepFor) await _deleteBackup(b.path);
    }
    if (real.isNotEmpty) {
      for (final b in all) {
        if (_isFuture(b, now) && !keep.contains(b.path)) await _deleteBackup(b.path);
      }
    }
    // недороблені знімки (обірвався запис) і зайві супутні файли
    final d = Directory(dir);
    if (!await d.exists()) return;
    await for (final e in d.list()) {
      if (e is! File) continue;
      final path = e.path;
      final sidecar = path.endsWith('-wal') || path.endsWith('-shm');
      final base = sidecar ? path.substring(0, path.length - 4) : path;
      if (!path.endsWith('.tmp') && !base.endsWith('.tmp') && !(sidecar && !await File(base).exists())) {
        continue;
      }
      try {
        if (now.difference(await e.lastModified()) > const Duration(hours: 1)) await e.delete();
      } catch (_) {}
    }
  }

  static Future<void> _deleteBackup(String path) async {
    await _delete(path);
    await _deleteSidecars(path);
  }

  static Future<void> _deleteSidecars(String path) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      await _delete('$path$suffix');
    }
  }

  /// Фото, на які посилаються копії (їх не можна прибирати з теки фото).
  Future<Set<String>> photoRefs() async {
    final out = <String>{};
    for (final b in await list()) {
      Database? c;
      try {
        c = await factory.openDatabase(b.path,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
        for (final r in await c.rawQuery(
            "SELECT photo FROM stock_items WHERE photo IS NOT NULL AND photo != ''")) {
          out.add(r['photo']! as String);
        }
      } catch (_) {
        // копія без складу чи зіпсована - пропускаємо
      } finally {
        await c?.close();
      }
    }
    return out;
  }

  /// Позначки app_meta, що належать саме цьому телефону: відновлення копії
  /// їх не чіпає (уроки, підказки, «Що нового», остання пасіка, службові).
  static bool isDeviceLocalMeta(String key) =>
      key == 'intro_done' ||
      key == 'hints_off' ||
      key == 'last_apiary' ||
      key == StockPhotos.upgradedKey ||
      key == StockPhotos.upgradeMapKey ||
      key.startsWith('hint:') ||
      key.startsWith('whats_new_seen') ||
      key.startsWith('lesson_') ||
      key.startsWith('backup_') ||
      key.startsWith('sync_') ||
      key.startsWith('device_');

  /// Відновити дані з копії [b]. Спершу автоматична копія поточного стану
  /// (її теж видно в списку - так відновлення можна скасувати). Повертає її.
  /// Відновити з файлу бази [path] поза списком копій (копія із сервера):
  /// перевірка, копія поточного стану, потім дані з файлу. Повертає копію
  /// поточного стану (щоб можна було повернути).
  Future<LocalBackup> restoreFile(String path) async {
    if (!await verify(path)) throw const BackupException('копія пошкоджена');
    final before = await create(BackupKind.beforeRestore);
    await restoreFrom(path);
    return before;
  }

  Future<LocalBackup> restore(LocalBackup b) async {
    if (!await File(b.path).exists()) throw const BackupException('копії вже немає');
    if (!await verify(b.path)) throw const BackupException('копія пошкоджена');
    // прибирання старих копій не має зачепити ту, з якої відновлюємо
    final before = await create(BackupKind.beforeRestore, {b.path});
    await restoreFrom(b.path);
    return before;
  }

  /// Перенести дані з файлу копії в базу (в одній транзакції; збій - дані
  /// як були). Записи, яких у копії не було, стають позначками «видалено»
  /// (сервер дізнається про видалення, і вони не повернуться з іншого
  /// телефона) - у таблицях, де такі позначки є. Де їх немає (історія
  /// значень parameter_records - лише дописується), рядки прибираються.
  /// Усе відновлене стає в чергу на відправку - далі синхронізується
  /// звичайним шляхом.
  Future<void> restoreFrom(String path) async {
    final db = repo.db;
    final version = await _userVersion(path);
    if (version > AppDatabase.schemaVersion) {
      throw DatabaseTooNewException(version, AppDatabase.schemaVersion);
    }
    await db.execute('ATTACH DATABASE ? AS bk', [path]);
    try {
      await db.transaction((txn) async {
        final stamp = Repository.now();
        final bkApiaryCols = await _columns(txn, 'bk', 'apiaries');
        final mainApiaryCols = await _columns(txn, 'main', 'apiaries');
        for (final t in kSyncTables) {
          final mainCols = await _columns(txn, 'main', t);
          final bkCols = await _columns(txn, 'bk', t);
          final cols = [for (final c in mainCols) if (bkCols.contains(c)) c];
          final source = bkCols.isEmpty ? null : 'bk.$t';
          // відновлюємо лише своє: дані власника, якому я допомагаю, живуть
          // на сервері - копія не має ні видаляти їх, ні повертати старі
          final mine = _ownWhere('main', t, mainCols, mainApiaryCols);
          // чого в копії немає - видалено (позначкою, де вона є)
          final missing = source == null ? '' : ' AND id NOT IN (SELECT id FROM $source)';
          if (mainCols.contains('deleted')) {
            await txn.rawUpdate(
                'UPDATE main.$t SET deleted = 1, synced = 0, updated_at = ? '
                'WHERE deleted = 0 AND $mine$missing',
                [stamp]);
          } else {
            // історія значень позначок «видалено» не має: прибране
            // записуємо в журнал - сервер позначить і в себе (інакше
            // наступне забирання змін повернуло б ці рядки)
            await txn.rawInsert(
                'INSERT OR REPLACE INTO main.sync_deletions (tbl, id, at) '
                'SELECT ?, id, ? FROM main.$t WHERE $mine$missing',
                [t, stamp]);
            await txn.rawDelete('DELETE FROM main.$t WHERE $mine$missing');
          }
          if (source != null && cols.contains('id')) {
            final list = cols.join(', ');
            final bkMine = _ownWhere('bk', t, bkCols, bkApiaryCols);
            await txn.rawInsert('INSERT OR REPLACE INTO main.$t ($list) SELECT $list FROM $source '
                'WHERE $bkMine AND id NOT IN (SELECT id FROM main.$t WHERE NOT ($mine))');
          }
        }
        // налаштування з копії (групи «Конструктора» тощо) - крім позначок
        // саме цього телефона
        final metaCols = await _columns(txn, 'bk', 'app_meta');
        if (metaCols.contains('key')) {
          final current = await txn.rawQuery('SELECT key FROM main.app_meta');
          for (final r in current) {
            final k = r['key']! as String;
            if (!isDeviceLocalMeta(k)) await txn.delete('app_meta', where: 'key = ?', whereArgs: [k]);
          }
          for (final r in await txn.rawQuery('SELECT key, value FROM bk.app_meta')) {
            final k = r['key']! as String;
            if (isDeviceLocalMeta(k)) continue;
            await txn.insert('app_meta', {'key': k, 'value': r['value']},
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        // копія старішої версії - ті самі кроки міграції, що й для бази
        for (var v = version + 1; v <= AppDatabase.schemaVersion; v++) {
          await AppDatabase.migrations[v]?.call(txn);
        }
        // фото, перетиснуті після цієї копії, - під новими назвами
        final map = await txn.query('app_meta',
            where: 'key = ?', whereArgs: [StockPhotos.upgradeMapKey], limit: 1);
        if (map.isNotEmpty) {
          final m = (jsonDecode(map.first['value']! as String) as Map).cast<String, String>();
          for (final e in m.entries) {
            await txn.update('stock_items', {'photo': e.value}, where: 'photo = ?', whereArgs: [e.key]);
          }
        }
        // відновлене - у чергу на відправку
        for (final t in kSyncTables) {
          final cols = await _columns(txn, 'main', t);
          if (cols.contains('synced')) {
            await txn.rawUpdate('UPDATE main.$t SET synced = 0 '
                'WHERE synced != 0 AND ${_ownWhere('main', t, cols, mainApiaryCols)}');
          }
        }
        // давня копія: вулики без пасіки - у «Моя пасіка», як при запуску
        await repo.ensureLegacyApiary(txn);
      });
    } finally {
      await db.execute('DETACH DATABASE bk');
    }
    repo.notifyAllChanged();
  }

  Future<int> _userVersion(String path) async {
    final c = await factory.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      return (await c.rawQuery('PRAGMA user_version')).first.values.first! as int;
    } finally {
      await c.close();
    }
  }

  /// Умова «рядок мій» (а не власника, якому я допомагаю) для таблиці [t]
  /// у [schema]. [cols] - колонки таблиці; [apiaryCols] - колонки apiaries
  /// у цій же схемі (давня копія без owner_id - усе своє).
  static String _ownWhere(String schema, String t, List<String> cols, List<String> apiaryCols) {
    if (AppDatabase.ownerTables.contains(t) && cols.contains('owner_id')) return 'owner_id IS NULL';
    final viaApiary = t == 'elements' || AppDatabase.apiaryLinkedTables.contains(t);
    if (viaApiary && cols.contains('apiary_id') && apiaryCols.contains('owner_id')) {
      final foreign = 'SELECT id FROM $schema.apiaries WHERE owner_id IS NOT NULL';
      return '(apiary_id IS NULL OR (apiary_id NOT IN ($foreign) '
          'AND apiary_id NOT IN (SELECT id FROM main.apiaries WHERE owner_id IS NOT NULL)))';
    }
    return '1 = 1';
  }

  static Future<List<String>> _columns(DatabaseExecutor db, String schema, String table) async =>
      [for (final r in await db.rawQuery('PRAGMA $schema.table_info($table)')) r['name']! as String];

  static Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Резервну копію не вдалося зробити чи відновити.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}
