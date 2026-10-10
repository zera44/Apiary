import 'package:flutter/foundation.dart' show debugPrint;

import '../services/backups.dart';
import 'repository.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

/// Що зробити з даними, коли вони є і на телефоні, і на сервері.
enum FirstLoginChoice {
  /// Дані телефона стають даними акаунта; те, чого на телефоні немає, на
  /// сервері позначається видаленим.
  keepPhone,

  /// Дані телефона замінюються даними з сервера (перед тим - копія на
  /// телефоні).
  keepServer,

  /// Злити: усе з обох боків лишається (однакові типові записи зливаються,
  /// при збігу - пізніша зміна).
  merge,
}

/// Що з'ясувалося під час першого входу на цьому телефоні.
enum FirstLoginState {
  /// Вибір не потрібен: синхронізуємось як звичайно (на телефоні порожньо -
  /// просто отримаємо все; на сервері порожньо - просто відправимо).
  ready,

  /// Дані є і тут, і там - спитати людину.
  ask,

  /// На телефоні - дані ІНШОГО акаунта Google (увійшли іншим): спитати,
  /// чи замінити їх даними цього акаунта.
  otherAccount,
}

/// Перший вхід на сервер з цього телефона (або вхід іншим акаунтом).
class FirstLogin {
  final Repository repo;
  final SyncApi api;
  FirstLogin(this.repo, this.api);

  Future<String?> _meta(String k) => repo.getMeta(k);

  /// Чи є на телефоні «справжні» дані (не лише типові записи).
  static Future<bool> localHasData(Repository repo) async {
    for (final t in kOwnDataTables) {
      final own = t == 'parameter_records' || t == 'hive_notes'
          ? 'apiary_id IS NULL OR apiary_id IN (SELECT id FROM apiaries WHERE owner_id IS NULL)'
          : 'owner_id IS NULL';
      final del = t == 'parameter_records' ? '' : ' AND deleted = 0';
      final r = await repo.db.rawQuery('SELECT 1 FROM $t WHERE ($own)$del LIMIT 1');
      if (r.isNotEmpty) return true;
    }
    return false;
  }

  /// З'ясувати, чи потрібен вибір. Якщо ні - одразу все готово до
  /// синхронізації. Якщо так - синхронізація чекатиме ([SyncNeedsChoice]),
  /// доки не буде викликано [apply].
  Future<FirstLoginState> prepare() async {
    final was = await _meta(SyncEngine.userKey);
    if (was == api.userId && await _meta(SyncEngine.pendingChoiceKey) != '1') return FirstLoginState.ready;
    // поки не з'ясовано - не синхронізуватись (і фоновому завданню теж)
    await repo.setMeta(SyncEngine.pendingChoiceKey, '1');
    if (was != null && was.isNotEmpty && was != api.userId) {
      return await localHasData(repo) ? FirstLoginState.otherAccount : await _accept();
    }
    if (!await localHasData(repo) || !await api.hasOwnData()) return _accept();
    return FirstLoginState.ask;
  }

  Future<FirstLoginState> _accept() async {
    await repo.setMeta(SyncEngine.userKey, api.userId);
    await repo.setMeta(SyncEngine.pendingChoiceKey, '');
    return FirstLoginState.ready;
  }

  /// Виконати вибір. Далі - звичайна синхронізація.
  Future<void> apply(FirstLoginChoice choice, {Future<BackupService> Function(Repository)? backups}) async {
    switch (choice) {
      case FirstLoginChoice.merge:
        break;
      case FirstLoginChoice.keepServer:
        await _replaceWithServer(backups ?? BackupService.of);
      case FirstLoginChoice.keepPhone:
        await _phoneWins();
    }
    await _accept();
  }

  static const _localOnlyTables = ['apiary_members', 'invitations', 'sync_deletions', 'sync_photos'];

  /// Копія на телефоні, потім - усе прибрати: наступна синхронізація
  /// отримає дані акаунта з сервера.
  Future<void> _replaceWithServer(Future<BackupService> Function(Repository) backups) async {
    try {
      await (await backups(repo)).create(BackupKind.beforeRestore);
    } catch (e) {
      debugPrint('Перший вхід: копія перед заміною - $e');
      rethrow; // без копії не стираємо
    }
    await repo.db.transaction((txn) async {
      for (final t in [...kSyncTables, ..._localOnlyTables]) {
        await txn.delete(t);
      }
      await txn.delete('app_meta', where: "key LIKE 'sync_cursor:%' OR key IN (?, ?, ?)",
          whereArgs: [SyncEngine.accessKey, SyncEngine.lastPullKey, SyncEngine.userKey]);
    });
    // базові характеристики й категорії - одразу (навіть без мережі застосунок
    // працює); з однаковими із сервера вони зіллються за сталим ключем
    await repo.init();
    repo.notifyAllChanged();
  }

  /// Дані телефона - головні: свої рядки сервера, яких на телефоні немає, -
  /// позначити видаленими; свої рядки телефона - як свіжі зміни (новіші за
  /// все на сервері), і забрати все заново.
  Future<void> _phoneWins() async {
    final now = Repository.now();
    for (final t in kSyncTables) {
      final local = {
        for (final r in await repo.db.query(t, columns: ['id'])) r['id']! as String,
      };
      final extra = <String>[];
      String? cursor;
      for (;;) {
        final page = await api.pull(t, cursor);
        for (final r in page.rows) {
          final id = r['id']! as String;
          if (r['owner_id'] == api.userId && r['deleted'] != 1 && !local.contains(id)) extra.add(id);
        }
        cursor = page.next;
        if (!page.more || page.rows.isEmpty) break;
      }
      for (var i = 0; i < extra.length; i += SyncEngine.deletionBatch) {
        await api.markDeleted(t, extra.sublist(i, (i + SyncEngine.deletionBatch).clamp(0, extra.length)), now);
      }
    }
    await repo.db.transaction((txn) async {
      for (final t in kSyncTables) {
        final cols = {for (final r in await txn.rawQuery('PRAGMA table_info($t)')) r['name']! as String};
        final mine = cols.contains('owner_id') ? 'owner_id IS NULL' : '1 = 1';
        await txn.rawUpdate(
            cols.contains('updated_at')
                ? 'UPDATE $t SET synced = 0, updated_at = ? WHERE $mine'
                : 'UPDATE $t SET synced = 0 WHERE $mine',
            [if (cols.contains('updated_at')) now]);
      }
      await txn.delete('app_meta', where: "key LIKE 'sync_cursor:%'");
    });
  }
}
