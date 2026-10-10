import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:apiary/data/sync_api.dart';
import 'package:crypto/crypto.dart';

/// Фейковий сервер синхронізації: ті самі правила, що задають
/// supabase/migrations (власник, доступ помічника, «видалення новіше
/// перемагає», «лише дописуються», номер зміни). Кілька «телефонів»
/// працюють з ним через [as].
class FakeSyncServer {
  /// таблиця -> id -> рядок (як на сервері: з owner_id і server_seq)
  final tables = <String, Map<String, Map<String, Object?>>>{};
  final photos = <String, Uint8List>{};
  final backups = <String, ServerBackup>{};
  final backupFiles = <String, Uint8List>{};
  int _seq = 0;

  /// Зв'язку немає - кожен запит падає.
  bool offline = false;

  /// Зв'язок обривається на забиранні цих таблиць.
  final offlineTables = <String>{};

  /// Сервер не дає позначати видаленими ці id.
  final rejectDeletes = <String>{};

  /// Скільки запитів upsert прийшло (перевірка пакетів).
  int upserts = 0;

  static const _apiaryTables = {'element_parameters', 'parameter_records', 'qr_codes', 'hive_notes'};
  static const _stock = {'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines'};
  static const _frozen = {
    'stock_moves': ['item_id', 'kind', 'amount', 'quantity_after', 'created_at', 'ref_id'],
    'parameter_records': ['group_id', 'element_id', 'value', 'created_at'],
  };

  Map<String, Map<String, Object?>> t(String name) => tables.putIfAbsent(name, () => {});

  SyncApi as(String uid) => _Client(this, uid);

  /// Помічник [user] у власника [owner] (пасіка [apiary] або всі).
  String addMember(String owner, String user, {String? apiary, bool stock = false}) {
    final id = 'm-${_seq + 1}';
    _stamp('apiary_members', {
      'id': id,
      'owner_id': owner,
      'apiary_id': apiary,
      'user_id': user,
      'email': '$user@gmail.com',
      'role': 'helper',
      'stock_access': stock ? 1 : 0,
      'created_at': 1.0,
      'deleted': 0,
      'updated_at': 1.0,
    });
    return id;
  }

  void removeMember(String id) {
    final m = t('apiary_members')[id]!;
    _stamp('apiary_members', {...m, 'deleted': 1, 'stock_access': 0});
  }

  void _stamp(String table, Map<String, Object?> row) {
    t(table)[row['id']! as String] = {...row, 'server_seq': ++_seq};
  }

  Iterable<Map<String, Object?>> _members(String uid) =>
      t('apiary_members').values.where((m) => m['user_id'] == uid && m['deleted'] == 0);

  bool _isMember(String uid, String owner, [String? apiary]) => _members(uid).any((m) =>
      m['owner_id'] == owner && (apiary == null || m['apiary_id'] == null || m['apiary_id'] == apiary));

  bool _stockOk(String uid, String owner) =>
      owner == uid || _members(uid).any((m) => m['owner_id'] == owner && m['stock_access'] == 1);

  String? _apiaryOwner(String? apiary) => apiary == null ? null : t('apiaries')[apiary]?['owner_id'] as String?;

  bool canRead(String uid, String table, Map<String, Object?> r) {
    final owner = r['owner_id'] as String?;
    if (table == 'apiary_members') return owner == uid || r['user_id'] == uid;
    if (owner == uid) return true;
    if (owner == null) return false;
    if (table == 'apiaries') return _isMember(uid, owner, r['id'] as String);
    if (table == 'elements' || _apiaryTables.contains(table)) {
      final a = r['apiary_id'] as String?;
      return a != null && _isMember(uid, owner, a);
    }
    if (_stock.contains(table)) return _stockOk(uid, owner);
    return _isMember(uid, owner);
  }

  bool _canWrite(String uid, String table, Map<String, Object?> r) {
    final owner = r['owner_id'] as String;
    if (owner == uid) return true;
    if (table == 'apiaries' || table == 'templates' || table == 'param_groups') return false;
    return canRead(uid, table, r);
  }

  void _net() {
    if (offline) throw const SyncOffline();
  }

  /// Рядок так, як його записала б база сервера (або виняток).
  Map<String, Object?>? _prepare(String uid, String table, Map<String, Object?> input) {
    final id = input['id']! as String;
    final old = t(table)[id];
    final row = {...?old, ...input};
    if (table == 'elements' || _apiaryTables.contains(table)) {
      if (table != 'elements') {
        final el = t('elements').values.where((e) =>
            (row['element_id'] != null && e['id'] == row['element_id']) ||
            (row['group_id'] != null && e['group_id'] == row['group_id']));
        if (el.isNotEmpty) row['apiary_id'] = el.first['apiary_id'];
      }
      final o = _apiaryOwner(row['apiary_id'] as String?);
      row['owner_id'] = o ?? (old?['owner_id'] ?? uid);
      if (old != null && o != null && o != old['owner_id']) throw const SyncRejected(403, 'чужа пасіка');
    } else {
      row['owner_id'] = old?['owner_id'] ?? input['owner_id'] ?? uid;
    }
    if (old != null && !_canWrite(uid, table, old)) throw SyncRejected(403, '$table $id: немає доступу');
    if (!_canWrite(uid, table, row)) throw SyncRejected(403, '$table $id: немає доступу');
    if (old != null) {
      for (final c in _frozen[table] ?? const <String>[]) {
        if (input.containsKey(c) && '${input[c]}' != '${old[c]}') {
          throw SyncRejected(403, '$table лише дописуються ($c)');
        }
      }
      if (old['deleted'] == 1 &&
          row['deleted'] == 0 &&
          ((row['updated_at'] as num?) ?? 0) <= ((old['updated_at'] as num?) ?? 0)) {
        return old; // новіше видалення лишається (з новим номером)
      }
    }
    return row;
  }
}

class _Client implements SyncApi {
  final FakeSyncServer s;
  @override
  final String userId;
  _Client(this.s, this.userId);

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    s._net();
    s.upserts++;
    // увесь пакет - одна транзакція: хоч один рядок відхилено - нічого
    final ready = [for (final r in rows) s._prepare(userId, table, r)!];
    for (final r in ready) {
      s._stamp(table, r);
    }
  }

  @override
  Future<void> markDeleted(String table, List<String> ids, double at) async {
    s._net();
    if (ids.any(s.rejectDeletes.contains)) throw const SyncRejected(403, 'не можна');
    for (final id in ids) {
      final old = s.t(table)[id];
      if (old == null || !s._canWrite(userId, table, old)) continue;
      s._stamp(table, {...old, 'deleted': 1, 'updated_at': at});
    }
  }

  @override
  Future<PullPage> pull(String table, String? after, {int limit = 500}) async {
    s._net();
    if (s.offlineTables.contains(table)) throw const SyncOffline();
    final from = after == null ? 0 : int.parse(after);
    final rows = [
      for (final r in s.t(table).values)
        if ((r['server_seq']! as int) > from && s.canRead(userId, table, r)) r
    ]..sort((a, b) => (a['server_seq']! as int).compareTo(b['server_seq']! as int));
    final page = rows.take(limit).map((r) => {...r}).toList();
    return PullPage(page, page.isEmpty ? after : '${page.last['server_seq']}', more: page.length == limit);
  }

  @override
  Future<void> putPhoto(String ownerId, String name, Uint8List bytes) async {
    s._net();
    if (!s._stockOk(userId, ownerId)) throw const SyncRejected(403, 'фото: немає доступу');
    s.photos['$ownerId/$name'] = bytes;
  }

  @override
  Future<Uint8List?> getPhoto(String ownerId, String name) async {
    s._net();
    if (!s._stockOk(userId, ownerId)) throw const SyncRejected(403, 'фото: немає доступу');
    return s.photos['$ownerId/$name'];
  }

  @override
  Future<void> announceBackup(ServerBackup b) async {
    s._net();
    if (!b.path.startsWith('$userId/')) throw const SyncRejected(403, 'чужа тека');
    s.backups[b.id] = ServerBackup(
        id: b.id, path: b.path, size: b.size, sha256: b.sha256, schemaV: b.schemaV,
        device: b.device, createdAt: DateTime.now());
  }

  @override
  Future<void> putBackup(String path, Uint8List gz) async {
    s._net();
    if (!path.startsWith('$userId/') || s.backupFiles.containsKey(path)) {
      throw const SyncRejected(403, 'не можна');
    }
    s.backupFiles[path] = gz;
  }

  @override
  Future<String> commitBackup(String id) async {
    s._net();
    final b = s.backups[id]!;
    final f = s.backupFiles[b.path];
    if (f == null) throw const SyncRejected(409, 'файлу ще немає');
    final ok = f.length == b.size && sha256.convert(f).toString() == b.sha256 && _isSqliteGz(f);
    if (!ok) {
      s.backups.remove(id);
      s.backupFiles.remove(b.path);
      return 'bad';
    }
    s.backups[id] = ServerBackup(
        id: b.id, path: b.path, size: b.size, sha256: b.sha256, schemaV: b.schemaV,
        device: b.device, createdAt: b.createdAt, status: 'ok');
    // нову перевірено - лишаються 2 найновіші цілі
    final mine = s.backups.values.where((x) => x.path.startsWith('$userId/') && x.status == 'ok').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final old in mine.skip(2)) {
      s.backups.remove(old.id);
      s.backupFiles.remove(old.path);
    }
    return 'ok';
  }

  static bool _isSqliteGz(Uint8List gz) {
    try {
      final raw = gzip.decode(gz);
      return utf8.decode(raw.sublist(0, 15), allowMalformed: true) == 'SQLite format 3';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ServerBackup>> listBackups() async {
    s._net();
    return s.backups.values.where((x) => x.path.startsWith('$userId/') && x.status == 'ok').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Uint8List> getBackup(String path) async {
    s._net();
    if (!path.startsWith('$userId/')) throw const SyncRejected(403, 'чужа копія');
    return s.backupFiles[path]!;
  }
}
