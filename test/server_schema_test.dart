import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Таблиці сервера (supabase/migrations) мають приймати рядок телефона як
/// є: кожна колонка телефона (крім службових) є на сервері. Інакше
/// синхронізація впала б на першому ж рядку - ловимо це тут, щойно
/// змінюється схема телефона.
void main() {
  setUpAll(sqfliteFfiInit);

  Map<String, Set<String>> serverTables() {
    final out = <String, Set<String>>{};
    final table = RegExp(r'create table if not exists public\.(\w+) \(\n(.*?)\n\);', dotAll: true);
    final files = Directory('supabase/migrations').listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      for (final m in table.allMatches(f.readAsStringSync())) {
        final cols = <String>{};
        for (final line in m.group(2)!.split('\n')) {
          final c = RegExp(r'^  ([a-z_]+) ').firstMatch(line)?.group(1);
          if (c != null && !const {'primary', 'unique', 'check', 'constraint'}.contains(c)) cols.add(c);
        }
        out[m.group(1)!] = cols;
      }
      // колонки, додані пізнішими міграціями
      for (final m in RegExp(r'alter table public\.(\w+) add column if not exists ([a-z_]+)')
          .allMatches(f.readAsStringSync())) {
        out[m.group(1)!]?.add(m.group(2)!);
      }
    }
    return out;
  }

  test('кожна таблиця синхронізації є на сервері з усіма колонками телефона', () async {
    final repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false));
    await repo.init();
    final server = serverTables();
    for (final t in kSyncTables) {
      expect(server, contains(t), reason: 'на сервері немає таблиці $t');
      final local = {
        for (final c in await repo.db.rawQuery('PRAGMA table_info($t)')) c['name']! as String,
      }.difference(kLocalOnlyColumns);
      final missing = local.difference(server[t]!);
      expect(missing, isEmpty, reason: '$t: на сервері немає колонок $missing');
      // і службові колонки сервера
      expect(server[t], containsAll(['owner_id', 'schema_v', 'server_at', 'server_seq', 'deleted']),
          reason: t);
    }
    // спільний доступ - теж
    for (final t in ['apiary_members', 'invitations']) {
      final local = {
        for (final c in await repo.db.rawQuery('PRAGMA table_info($t)')) c['name']! as String,
      }.difference(kLocalOnlyColumns);
      expect(local.difference(server[t]!), isEmpty, reason: t);
    }
    await repo.db.close();
  });
}
