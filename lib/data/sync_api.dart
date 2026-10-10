import 'dart:typed_data';

/// Що синхронізація потребує від сервера. Справжня реалізація - запити до
/// Supabase (services/supabase_api.dart); у тестах - фейковий сервер з тими
/// самими правилами, що й supabase/migrations.
abstract class SyncApi {
  /// Хто я на сервері (id користувача Supabase).
  String get userId;

  /// Записати рядки (нові - додати, наявні - оновити). Рядки - як їх шле
  /// телефон ([toServerRow]). Сервер сам вирішує власника, «перемагає
  /// пізніший», не дає скасувати новіше видалення тощо.
  Future<void> upsert(String table, List<Map<String, Object?>> rows);

  /// Позначити видаленими рядки [ids] таблиці без власних позначок на
  /// телефоні (історія значень).
  Future<void> markDeleted(String table, List<String> ids, double at);

  /// Зміни таблиці після курсора [after] (null - від початку).
  Future<PullPage> pull(String table, String? after, {int limit = 500});

  /// Фото складу власника [ownerId] з назвою [name].
  Future<void> putPhoto(String ownerId, String name, Uint8List bytes);
  Future<Uint8List?> getPhoto(String ownerId, String name);

  /// Нічна копія: заявити, завантажити файл, попросити сервер перевірити
  /// (повертає 'ok' або 'bad').
  Future<void> announceBackup(ServerBackup b);
  Future<void> putBackup(String path, Uint8List gz);
  Future<String> commitBackup(String id);

  /// Цілі копії на сервері (найновіші першими).
  Future<List<ServerBackup>> listBackups();
  Future<Uint8List> getBackup(String path);
}

/// Сторінка змін: рядки, курсор після них, чи є ще.
class PullPage {
  final List<Map<String, Object?>> rows;
  final String? next;
  final bool more;
  const PullPage(this.rows, this.next, {this.more = false});
}

/// Повна копія бази на сервері.
class ServerBackup {
  final String id;
  final String path;
  final int size;
  final String sha256;
  final int schemaV;
  final String? device;
  final DateTime createdAt;
  final String status;

  const ServerBackup({
    required this.id,
    required this.path,
    required this.size,
    required this.sha256,
    required this.schemaV,
    this.device,
    required this.createdAt,
    this.status = 'uploading',
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'size': size,
        'sha256': sha256,
        'schema_v': schemaV,
        'device': device,
      };

  factory ServerBackup.fromJson(Map<String, Object?> j) => ServerBackup(
        id: j['id']! as String,
        path: j['path']! as String,
        size: (j['size']! as num).toInt(),
        sha256: j['sha256']! as String,
        schemaV: (j['schema_v'] as num?)?.toInt() ?? 0,
        device: j['device'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime(2000),
        status: (j['status'] as String?) ?? 'uploading',
      );
}

/// Немає зв'язку із сервером (або він тимчасово не відповідає) - спробувати
/// пізніше; дані лишаються в черзі.
class SyncOffline implements Exception {
  final String message;
  const SyncOffline([this.message = 'немає зв\'язку із сервером']);
  @override
  String toString() => message;
}

/// Сервер відхилив дані (правила доступу, обмеження) - повтор не допоможе.
class SyncRejected implements Exception {
  final int status;
  final String message;
  const SyncRejected(this.status, this.message);
  @override
  String toString() => 'сервер відхилив ($status): $message';
}

/// Вхід на сервер закінчився (треба увійти знову).
class SyncSignedOut implements Exception {
  const SyncSignedOut();
  @override
  String toString() => 'потрібно знову увійти';
}
