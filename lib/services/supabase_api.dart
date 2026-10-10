import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/sharing.dart';
import '../data/sync_api.dart';
import 'app_config.dart';
import 'sharing.dart';

/// Вхід на сервер Supabase: токен доступу (живе ~годину), токен оновлення,
/// хто увійшов.
class SupabaseSession {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String email;

  const SupabaseSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  bool get expiringSoon => clock.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
        'user': {'id': userId, 'email': email},
      };

  /// З відповіді сервера входу або збереженого файлу.
  static SupabaseSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final user = j['user'];
    final at = j['access_token'], rt = j['refresh_token'];
    if (at is! String || rt is! String || user is! Map || user['id'] is! String) return null;
    final exp = j['expires_at'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['expires_at'] as num).toInt() * 1000)
        : clock.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
    return SupabaseSession(
      accessToken: at,
      refreshToken: rt,
      expiresAt: exp,
      userId: user['id'] as String,
      email: normalizeEmail((user['email'] as String?) ?? ''),
    );
  }
}

/// Де зберігається вхід (файл поруч із базою; у тестах - у пам'яті).
abstract class SessionStore {
  Future<SupabaseSession?> read();
  Future<void> write(SupabaseSession? s);

  /// Файл у теці застосунку (його бачить і фонове завдання).
  static Future<SessionStore> forApp() async =>
      FileSessionStore(File(p.join((await getApplicationSupportDirectory()).path, 'supabase_session.json')));
}

class FileSessionStore implements SessionStore {
  final File file;
  FileSessionStore(this.file);

  @override
  Future<SupabaseSession?> read() async {
    try {
      if (!await file.exists()) return null;
      return SupabaseSession.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SupabaseSession? s) async {
    if (s == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(s.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

class MemorySessionStore implements SessionStore {
  SupabaseSession? value;
  MemorySessionStore([this.value]);
  @override
  Future<SupabaseSession?> read() async => value;
  @override
  Future<void> write(SupabaseSession? s) async => value = s;
}

/// Запити до Supabase: синхронізація ([SyncApi]) і спільний доступ
/// ([SharingApi]). Правила - на сервері (supabase/migrations).
class SupabaseApi implements SyncApi, SharingApi {
  final Uri base;
  final String anonKey;
  final SessionStore store;
  final http.Client _http;
  SupabaseSession _session;

  static const timeout = Duration(seconds: 30);
  static const bigTimeout = Duration(minutes: 5);

  SupabaseApi._(this.base, this.anonKey, this.store, this._session, this._http);

  SupabaseSession get session => _session;

  @override
  String get userId => _session.userId;
  @override
  String get myUserId => _session.userId;
  @override
  String get myEmail => _session.email;

  /// Відновити збережений вхід (null - не входили або сервер не налаштовано).
  static Future<SupabaseApi?> restore(AppConfig config, SessionStore store, {http.Client? client}) async {
    final base = config.supabaseBase;
    if (base == null || !config.syncConfigured) return null;
    final s = await store.read();
    if (s == null) return null;
    return SupabaseApi._(base, config.supabaseAnonKey.trim(), store, s, client ?? http.Client());
  }

  /// Увійти на сервер ID-токеном Google (після входу Google на телефоні).
  static Future<SupabaseApi> signInWithGoogle(AppConfig config, SessionStore store, String idToken,
      {http.Client? client}) async {
    final base = config.supabaseBase;
    if (base == null || !config.syncConfigured) throw StateError('Сервер не налаштовано в цій збірці');
    final c = client ?? http.Client();
    final key = config.supabaseAnonKey.trim();
    final r = await _guard(() => c
        .post(_join(base, '/auth/v1/token', {'grant_type': 'id_token'}),
            headers: {'apikey': key, 'Content-Type': 'application/json'},
            body: jsonEncode({'provider': 'google', 'id_token': idToken}))
        .timeout(timeout));
    _check(r);
    final s = SupabaseSession.fromJson(jsonDecode(r.body));
    if (s == null) throw const SyncRejected(500, 'сервер входу повернув незрозумілу відповідь');
    await store.write(s);
    return SupabaseApi._(base, key, store, s, c);
  }

  /// Вийти: забути вхід на цьому телефоні.
  Future<void> signOut() async {
    try {
      await _http
          // лише цей телефон (інакше вийшли б і всі інші пристрої акаунта)
          .post(_join(base, '/auth/v1/logout', {'scope': 'local'}), headers: await _headers())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // без зв'язку - просто забуваємо локально
    }
    await store.write(null);
  }

  static Uri _join(Uri base, String path, [Map<String, String>? query]) =>
      base.replace(path: '${base.path}$path', queryParameters: query);

  Uri _u(String path, [Map<String, String>? query]) => _join(base, path, query);

  Future<Map<String, String>> _headers([Map<String, String> extra = const {}]) async {
    await _fresh();
    return {'apikey': anonKey, 'Authorization': 'Bearer ${_session.accessToken}', ...extra};
  }

  /// Оновити вхід, якщо скоро закінчиться. Спершу - перечитати збережений:
  /// його могло вже оновити фонове завдання (той самий токен оновлення двічі
  /// сервер не приймає).
  Future<void> _fresh({bool force = false}) async {
    if (!force && !_session.expiringSoon) return;
    final saved = await store.read();
    if (saved != null && saved.refreshToken != _session.refreshToken) {
      _session = saved;
      if (!force && !_session.expiringSoon) return;
    }
    final r = await _guard(() => _http
        .post(_u('/auth/v1/token', {'grant_type': 'refresh_token'}),
            headers: {'apikey': anonKey, 'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _session.refreshToken}))
        .timeout(timeout));
    if (r.statusCode == 400 || r.statusCode == 401 || r.statusCode == 403) throw const SyncSignedOut();
    _check(r);
    final s = SupabaseSession.fromJson(jsonDecode(r.body));
    if (s == null) throw const SyncSignedOut();
    _session = s;
    await store.write(s);
  }

  /// Запит із повтором після оновлення входу (раптом токен відкликали).
  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> h) f,
      {Map<String, String> headers = const {}}) async {
    var r = await _guard(() async => f(await _headers(headers)));
    if (r.statusCode == 401) {
      await _fresh(force: true);
      r = await _guard(() async => f(await _headers(headers)));
      if (r.statusCode == 401) throw const SyncSignedOut();
    }
    _check(r);
    return r;
  }

  static Future<http.Response> _guard(Future<http.Response> Function() f) async {
    try {
      return await f();
    } on SocketException catch (e) {
      throw SyncOffline('немає зв\'язку із сервером (${e.message})');
    } on TimeoutException {
      throw const SyncOffline('сервер не відповідає');
    } on HandshakeException {
      throw const SyncOffline('не вдалося встановити захищене з\'єднання');
    } on http.ClientException catch (e) {
      throw SyncOffline('немає зв\'язку із сервером (${e.message})');
    }
  }

  static void _check(http.Response r) {
    final s = r.statusCode;
    if (s >= 200 && s < 300) return;
    final msg = _message(r.body);
    if (s >= 500 || s == 408 || s == 429) throw SyncOffline('сервер тимчасово недоступний ($s)');
    throw SyncRejected(s, msg);
  }

  static final _notFound = RegExp(r'not.?found|404', caseSensitive: false);

  static String _message(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        return '${j['message'] ?? j['msg'] ?? j['error_description'] ?? j['error'] ?? body}';
      }
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  Future<Object?> _rpc(String fn, Map<String, Object?> args) async {
    final r = await _send((h) => _http
        .post(_u('/rest/v1/rpc/$fn'), headers: h, body: jsonEncode(args))
        .timeout(timeout), headers: {'Content-Type': 'application/json'});
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<List<Map<String, Object?>>> _select(String table, Map<String, String> query) async {
    final r = await _send((h) => _http.get(_u('/rest/v1/$table', query), headers: h).timeout(timeout));
    return [for (final x in jsonDecode(r.body) as List) (x as Map).cast<String, Object?>()];
  }

  // ── синхронізація ──────────────────────────────────────────────────────

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    await _send(
        (h) => _http
            .post(_u('/rest/v1/$table', {'on_conflict': 'id'}), headers: h, body: jsonEncode(rows))
            .timeout(timeout),
        headers: {
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        });
  }

  @override
  Future<void> markDeleted(String table, List<String> ids, double at) async {
    if (ids.isEmpty) return;
    final list = ids.map((x) => '"$x"').join(',');
    await _send(
        (h) => _http
            .patch(_u('/rest/v1/$table', {'id': 'in.($list)'}),
                headers: h, body: jsonEncode({'deleted': 1, 'updated_at': at}))
            .timeout(timeout),
        headers: {'Content-Type': 'application/json', 'Prefer': 'return=minimal'});
  }

  @override
  Future<PullPage> pull(String table, String? after, {int limit = 500}) async {
    final j = await _rpc('sync_pull', {'p_table': table, 'p_after': after, 'p_limit': limit}) as Map;
    return PullPage(
      [for (final x in j['rows'] as List) (x as Map).cast<String, Object?>()],
      j['next'] as String?,
      more: j['more'] == true,
    );
  }

  @override
  Future<void> putPhoto(String ownerId, String name, Uint8List bytes) async {
    await _send(
        (h) => _http
            .post(_u('/storage/v1/object/stock-photos/$ownerId/$name'), headers: h, body: bytes)
            .timeout(timeout),
        headers: {
          'Content-Type': name.endsWith('.webp') ? 'image/webp' : 'image/jpeg',
          'x-upsert': 'true',
        });
  }

  @override
  Future<Uint8List?> getPhoto(String ownerId, String name) async {
    try {
      final r = await _send((h) => _http
          .get(_u('/storage/v1/object/authenticated/stock-photos/$ownerId/$name'), headers: h)
          .timeout(timeout));
      return r.bodyBytes;
    } on SyncRejected catch (e) {
      // Storage на «немає такого файлу» відповідає 400 або 404 з not_found
      if (e.status == 404 || (e.status == 400 && _notFound.hasMatch(e.message))) return null;
      rethrow;
    }
  }

  @override
  Future<void> announceBackup(ServerBackup b) async {
    await _send(
        (h) => _http.post(_u('/rest/v1/device_backups'), headers: h, body: jsonEncode(b.toJson())).timeout(timeout),
        headers: {'Content-Type': 'application/json', 'Prefer': 'return=minimal'});
  }

  @override
  Future<void> putBackup(String path, Uint8List gz) async {
    await _send(
        (h) => _http.post(_u('/storage/v1/object/backups/$path'), headers: h, body: gz).timeout(bigTimeout),
        headers: {'Content-Type': 'application/gzip'});
  }

  @override
  Future<String> commitBackup(String id) async {
    try {
      final r = await _send(
          (h) => _http
              .post(_u('/functions/v1/backup-commit'), headers: h, body: jsonEncode({'id': id}))
              .timeout(bigTimeout),
          headers: {'Content-Type': 'application/json'});
      return '${(jsonDecode(r.body) as Map)['status']}';
    } on SyncRejected catch (e) {
      if (e.status == 422) return 'bad';
      rethrow;
    }
  }

  @override
  Future<List<ServerBackup>> listBackups() async => [
        for (final r in await _select('device_backups',
            {'select': '*', 'status': 'eq.ok', 'order': 'created_at.desc'}))
          ServerBackup.fromJson(r),
      ];

  @override
  Future<Uint8List> getBackup(String path) async {
    final r = await _send(
        (h) => _http.get(_u('/storage/v1/object/authenticated/backups/$path'), headers: h).timeout(bigTimeout));
    return r.bodyBytes;
  }

  // ── спільний доступ ────────────────────────────────────────────────────

  /// Рядок сервера - як рядок на телефоні (списки - JSON-рядком).
  static Map<String, Object?> _local(Map<String, Object?> r) => {
        for (final e in r.entries) e.key: e.value is List ? jsonEncode(e.value) : e.value,
      };

  @override
  Future<String?> findUser(String email) async => await _rpc('find_user', {'p_email': email}) as String?;

  @override
  Future<void> createInvitation(Invitation inv) async {
    await _send(
        (h) => _http
            .post(_u('/rest/v1/invitations'),
                headers: h,
                body: jsonEncode({
                  'id': inv.id,
                  'to_email': inv.toEmail,
                  'from_name': inv.fromName,
                  'apiary_ids': inv.apiaryIds,
                  'apiary_names': inv.apiaryNames,
                  'stock_access': inv.stockAccess ? 1 : 0,
                  'created_at': inv.createdAt,
                }))
            .timeout(timeout),
        headers: {'Content-Type': 'application/json', 'Prefer': 'return=minimal'});
  }

  @override
  Future<List<Invitation>> incoming() async => [
        for (final r in await _select('invitations', {'select': '*', 'to_email': 'eq.$myEmail'}))
          Invitation.fromRow(_local(r)),
      ];

  @override
  Future<List<Invitation>> outgoing() async => [
        for (final r in await _select('invitations', {'select': '*', 'from_user_id': 'eq.$userId'}))
          Invitation.fromRow(_local(r)),
      ];

  @override
  Future<void> respond(String invitationId, {required bool accept}) =>
      _rpc('respond_invitation', {'p_id': invitationId, 'p_accept': accept});

  @override
  Future<void> cancel(String invitationId) => _rpc('cancel_invitation', {'p_id': invitationId});

  @override
  Future<List<Member>> members() async => [
        for (final r in await _select(
            'apiary_members', {'select': '*', 'owner_id': 'eq.$userId', 'deleted': 'eq.0'}))
          Member.fromRow(r),
      ];

  @override
  Future<void> removeMember(String memberId) => _rpc('remove_member', {'p_id': memberId});

  @override
  Future<void> setStockAccess(String memberId, {required bool on}) =>
      _rpc('set_member_stock_access', {'p_id': memberId, 'p_on': on});
}
