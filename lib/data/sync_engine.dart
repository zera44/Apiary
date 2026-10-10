import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../services/stock_photos.dart';
import 'repository.dart';
import 'sync_api.dart';
import 'sync_payload.dart';
import 'sync_repo.dart';

/// Чим закінчився один обмін із сервером.
class SyncReport {
  int sent = 0;
  int received = 0;

  /// Рядки, які сервер відхилив (правила доступу): позначені synced = 2,
  /// повторяться, коли їх змінять (або вночі).
  int rejected = 0;
  int photosUp = 0;
  int photosDown = 0;

  @override
  String toString() => 'надіслано $sent, отримано $received, відхилено $rejected, '
      'фото ↑$photosUp ↓$photosDown';
}

/// Один обмін із сервером: спершу відправити свої зміни (пакетами), потім
/// забрати чужі.
///
/// Правила (ті самі, що на сервері, supabase/migrations):
///  * «перемагає пізніший» за часом сервера: що записано на сервер пізніше,
///    те й лишається;
///  * видалення, зроблене пізніше за зміну, перемагає (сервер не дає давній
///    зміні скасувати його і розсилає позначку заново);
///  * рухи складу й історія значень лише дописуються; залишок складу -
///    сума рухів (див. [RepositorySync.recomputeStock]);
///  * рядок, змінений на телефоні після відправки (synced = 0), отримане
///    із сервера не затирає - зміна піде наступним обміном. Виняток - новіше
///    видалення.
class SyncEngine {
  final Repository repo;
  final SyncApi api;
  SyncEngine(this.repo, this.api);

  static const batchSize = 200;

  /// Що забираємо: спершу доступ (помічники), далі - дані.
  static const pullTables = ['apiary_members', 'invitations', ...kSyncTables];

  static String cursorKey(String table) => 'sync_cursor:$table';
  static const accessKey = 'sync_access';

  final Map<String, Set<String>> _cols = {};

  Future<Set<String>> _columns(String table) async => _cols[table] ??= {
        for (final r in await repo.db.rawQuery('PRAGMA table_info($table)')) r['name']! as String,
      };

  static const userKey = 'sync_user';

  /// Перший вхід: людина ще не вибрала, що робити з даними (див. FirstLogin).
  static const pendingChoiceKey = 'sync_first_pending';
  static const lastPullKey = 'sync_last_pull';

  /// Сервер стирає позначки «видалено», старші за 180 днів. Телефон, що
  /// не забирав змін довше за це (з запасом), забирає все заново й прибирає
  /// те, чого на сервері вже немає (інакше видалене ожило б).
  static const fullResyncAfter = Duration(days: 150);

  Future<SyncReport> run() async {
    await _checkUser();
    final r = SyncReport();
    final full = await _fullResyncDue();
    if (full) {
      for (final t in pullTables) {
        await repo.setMeta(cursorKey(t), '');
      }
    }
    await repo.adoptForeignRefs();
    await _pushDeletions(r);
    // спершу файли фото, потім рядки, що на них посилаються
    await _pushPhotos(r);
    for (final t in kSyncTables) {
      await _push(t, r);
    }
    final seen = full ? <String, Set<String>>{} : null;
    await _pullAll(r, seen: seen);
    if (seen != null) await _dropUnseen(seen);
    await repo.setMeta(lastPullKey, '${Repository.now()}');
    // злиття однакових типових записів (другий телефон, перевстановлення)
    // і переведення записів помічника дали нові зміни - одразу їх і відправити
    if (await repo.countUnsynced() > 0) {
      await repo.adoptForeignRefs();
      for (final t in kSyncTables) {
        await _push(t, r);
      }
    }
    return r;
  }

  /// Дані на телефоні - іншого акаунта (увійшли іншим Google): не змішувати.
  Future<void> _checkUser() async {
    if (await repo.getMeta(pendingChoiceKey) == '1') throw const SyncNeedsChoice();
    final was = await repo.getMeta(userKey);
    if (was == null || was.isEmpty) {
      await repo.setMeta(userKey, api.userId);
    } else if (was != api.userId) {
      throw const SyncOtherAccount();
    }
  }

  Future<bool> _fullResyncDue() async {
    final last = double.tryParse(await repo.getMeta(lastPullKey) ?? '');
    return last != null && Repository.now() - last > fullResyncAfter.inSeconds;
  }

  /// Після повного забирання: рядки, які сервер колись мав (synced = 1), а
  /// тепер не повернув, - стерто на сервері; прибрати й тут.
  Future<void> _dropUnseen(Map<String, Set<String>> seen) async {
    await repo.db.transaction((txn) async {
      for (final t in pullTables) {
        final have = seen[t] ?? const <String>{};
        final local = await txn.query(t, columns: ['id'], where: 'synced = 1');
        for (final row in local) {
          final id = row['id']! as String;
          if (!have.contains(id)) await txn.delete(t, where: 'id = ?', whereArgs: [id]);
        }
      }
    });
    repo.notifyAllChanged();
  }

  // ── відправка ──────────────────────────────────────────────────────────

  Map<String, Object?> _toServer(String table, Map<String, Object?> row) {
    final out = toServerRow(table, row);
    // NULL - «мій»: сервер і так підставив би мене, але явно - надійніше
    if (out.containsKey('owner_id') && out['owner_id'] == null) out['owner_id'] = api.userId;
    return out;
  }

  Future<void> _push(String table, SyncReport r) async {
    final rows = await repo.unsynced(table);
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(i, (i + batchSize).clamp(0, rows.length));
      await _send(table, batch, r);
    }
  }

  Future<void> _send(String table, List<Map<String, Object?>> batch, SyncReport r) async {
    try {
      await api.upsert(table, [for (final row in batch) _toServer(table, row)]);
      await repo.markSyncedBatch(table, batch);
      r.sent += batch.length;
    } on SyncRejected catch (e) {
      if (batch.length > 1) {
        // хто саме - по одному (решта пакета не має чекати через один рядок)
        for (final row in batch) {
          await _send(table, [row], r);
        }
        return;
      }
      debugPrint('Синхронізація: $table ${batch.single['id']} - $e');
      final row = batch.single;
      final stamp = row['updated_at'];
      await repo.db.rawUpdate(
          'UPDATE $table SET synced = 2 WHERE id = ?${stamp == null ? '' : ' AND updated_at = ?'}',
          [row['id'], ?stamp]);
      r.rejected++;
    }
  }

  /// Малими пакетами: id ідуть в адресі запиту.
  static const deletionBatch = 50;

  Future<void> _pushDeletions(SyncReport r) async {
    final rows = await repo.db.query('sync_deletions', orderBy: 'tbl, id');
    final byTable = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      byTable.putIfAbsent(row['tbl']! as String, () => []).add(row);
    }
    for (final e in byTable.entries) {
      for (var i = 0; i < e.value.length; i += deletionBatch) {
        await _sendDeletions(e.key, e.value.sublist(i, (i + deletionBatch).clamp(0, e.value.length)), r);
      }
    }
  }

  Future<void> _sendDeletions(String table, List<Map<String, Object?>> part, SyncReport r) async {
    final at = part.map((x) => (x['at'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    try {
      await api.markDeleted(table, [for (final x in part) x['id']! as String], at);
    } on SyncRejected catch (e) {
      if (part.length > 1) {
        for (final x in part) {
          await _sendDeletions(table, [x], r);
        }
        return;
      }
      // сервер не дає (чужий запис, доступ забрали) - більше не пробуємо
      debugPrint('Синхронізація: видалення $table ${part.single['id']} - $e');
      r.rejected++;
    }
    await repo.db.transaction((txn) async {
      for (final x in part) {
        await txn.delete('sync_deletions', where: 'tbl = ? AND id = ?', whereArgs: [table, x['id']]);
      }
    });
    r.sent += part.length;
  }

  Future<void> _pushPhotos(SyncReport r) async {
    if (StockPhotos.dir == null) return;
    final rows = await repo.db.rawQuery(
        "SELECT photo, owner_id FROM stock_items WHERE deleted = 0 AND photo IS NOT NULL AND photo != '' "
        'AND photo NOT IN (SELECT name FROM sync_photos)');
    for (final row in rows) {
      final name = row['photo']! as String;
      if (StockPhotos.isLegacy(name)) continue; // ще не перетиснуте - пізніше
      final full = File(StockPhotos.fullPath(name)!);
      if (!await full.exists()) continue;
      final owner = (row['owner_id'] as String?) ?? api.userId;
      try {
        await api.putPhoto(owner, name, await full.readAsBytes());
        final thumb = File(StockPhotos.thumbPath(name)!);
        if (await thumb.exists()) {
          await api.putPhoto(owner, StockPhotos.thumbName(name), await thumb.readAsBytes());
        }
      } on SyncRejected catch (e) {
        debugPrint('Фото $name: $e');
        continue;
      }
      await repo.db.insert('sync_photos', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
      r.photosUp++;
    }
  }

  // ── забирання ──────────────────────────────────────────────────────────

  Future<void> _pullAll(SyncReport r, {Map<String, Set<String>>? seen}) async {
    for (final t in pullTables) {
      await _pull(t, r, seen);
      if (t == 'apiary_members') {
        final before = await repo.getMeta(accessKey);
        final now = await repo.applyAccess(api.userId);
        if (now != before) {
          await repo.setMeta(accessKey, now);
          // новий доступ: давні рядки власника лежать «до» курсора - заново
          // все (свого це не зачепить: отримане співпаде з наявним)
          if (seen == null && _gained(before ?? '', now)) {
            for (final x in pullTables.skip(1)) {
              await repo.setMeta(cursorKey(x), '');
            }
          }
        }
      }
    }
    await repo.mergeSeedDuplicates();
    await _pullPhotos(r);
    if (r.received > 0) repo.notifyAllChanged();
  }

  static bool _gained(String before, String now) {
    final b = before.split(',').toSet();
    return now.split(',').any((x) => x.isNotEmpty && !b.contains(x));
  }

  Future<void> _pull(String table, SyncReport r, Map<String, Set<String>>? seen) async {
    final cols = await _columns(table);
    var cursor = await repo.getMeta(cursorKey(table));
    for (;;) {
      final page = await api.pull(table, (cursor == null || cursor.isEmpty) ? null : cursor);
      final stockItems = <String>{};
      await repo.db.transaction((txn) async {
        for (final row in page.rows) {
          if (await _apply(txn, table, row, cols)) r.received++;
          seen?.putIfAbsent(table, () => {}).add(row['id']! as String);
          if (table == 'stock_moves') stockItems.add(row['item_id']! as String);
          if (table == 'stock_items') stockItems.add(row['id']! as String);
        }
        if (page.next != null) {
          await txn.insert('app_meta', {'key': cursorKey(table), 'value': page.next},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      // залишок - одразу (обірвалась синхронізація після цієї сторінки - він
      // уже правильний)
      if (stockItems.isNotEmpty) await repo.recomputeStock(stockItems);
      cursor = page.next;
      if (!page.more || page.rows.isEmpty) break;
    }
  }

  /// Записати рядок сервера. false - пропущено (на телефоні новіша зміна).
  Future<bool> _apply(Transaction txn, String table, Map<String, Object?> s, Set<String> cols) async {
    final id = s['id']! as String;
    if (table == 'parameter_records' && s['deleted'] == 1) {
      await txn.delete(table, where: 'id = ?', whereArgs: [id]);
      await txn.delete('sync_deletions', where: 'tbl = ? AND id = ?', whereArgs: [table, id]);
      return true;
    }
    final row = fromServerRow(s, cols);
    for (final e in row.entries.toList()) {
      final v = e.value;
      if (v is List || v is Map) row[e.key] = jsonEncode(v);
      if (v is bool) row[e.key] = v ? 1 : 0;
    }
    if (cols.contains('owner_id')) {
      final o = s['owner_id'];
      row['owner_id'] = (o == null || o == api.userId) ? null : o;
    }
    final local = await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isNotEmpty && local.first['synced'] == 0) {
      final lu = (local.first['updated_at'] as num?)?.toDouble();
      final su = (s['updated_at'] as num?)?.toDouble();
      final newerDelete = s['deleted'] == 1 && lu != null && su != null && su >= lu;
      if (!newerDelete) return false;
    }
    await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// Фото складу, яких на телефоні ще немає (зокрема ті, що раніше не
  /// вдалось отримати: файл ще не дійшов на сервер, обірвався зв'язок), -
  /// щоразу, доки не з'являться.
  Future<void> _pullPhotos(SyncReport r) async {
    if (StockPhotos.dir == null) return;
    final rows = await repo.db.rawQuery(
        "SELECT photo, owner_id FROM stock_items WHERE deleted = 0 AND photo IS NOT NULL AND photo != ''");
    for (final row in rows) {
      final name = row['photo']! as String;
      if (StockPhotos.isLegacy(name) || await File(StockPhotos.fullPath(name)!).exists()) continue;
      final owner = (row['owner_id'] as String?) ?? api.userId;
      try {
        final bytes = await api.getPhoto(owner, name);
        if (bytes == null) continue; // ще не вивантажене - наступного разу
        await StockPhotos.writeDownloaded(name, bytes);
        final thumb = await api.getPhoto(owner, StockPhotos.thumbName(name));
        if (thumb != null) await StockPhotos.writeDownloaded(StockPhotos.thumbName(name), thumb);
        await repo.db.insert('sync_photos', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
        r.photosDown++;
      } on SyncRejected catch (e) {
        debugPrint('Фото $name: $e');
      }
    }
    if (r.photosDown > 0) repo.stockChanges.value++;
  }

  /// Рядки, які сервер колись відхилив, - спробувати ще раз (раз на ніч:
  /// доступ міг з'явитися).
  Future<int> retryRejected() async {
    var n = 0;
    for (final t in kSyncTables) {
      n += await repo.db.rawUpdate('UPDATE $t SET synced = 0 WHERE synced = 2');
    }
    return n;
  }
}

/// Рядки таблиці синхронізації, які сервер відхилив.
Future<int> countRejected(Repository repo) async {
  var n = 0;
  for (final t in kSyncTables) {
    final r = await repo.db.rawQuery('SELECT COUNT(*) AS n FROM $t WHERE synced = 2');
    n += (r.first['n'] as int?) ?? 0;
  }
  return n;
}
