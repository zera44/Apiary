import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/repository.dart';
import '../data/sync_api.dart';
import 'backups.dart';

/// Повні копії бази на сервері: раз на ніч телефон відправляє стиснену
/// копію; сервер перевіряє її (функція backup-commit) і тримає 2 цілі.
/// «Завантажити з сервера» - замінити дані телефона однією з них.
class ServerBackups {
  final Repository repo;
  final SyncApi api;
  final BackupService local;
  ServerBackups(this.repo, this.api, this.local);

  /// Більше сервер не прийме (обмеження на файл безкоштовного тарифу).
  static const maxBytes = 50 * 1024 * 1024;

  /// Стиснена копія бази - на сервер. Повертає 'ok' (сервер перевірив і
  /// зберіг) або 'bad' (дійшла зіпсованою - старі копії не чіпано).
  Future<String> upload() async {
    final tmp = p.join(local.dir, 'server-upload.db.tmp');
    await Directory(local.dir).create(recursive: true);
    final Uint8List gz;
    try {
      await local.snapshotTo(tmp);
      gz = Uint8List.fromList(GZipCodec(level: 6).encode(await File(tmp).readAsBytes()));
    } finally {
      try {
        await File(tmp).delete();
      } catch (_) {}
    }
    if (gz.length > maxBytes) {
      throw BackupException('копія завелика для сервера (${gz.length ~/ (1024 * 1024)} МБ)');
    }
    final id = Repository.newId();
    final b = ServerBackup(
      id: id,
      path: '${api.userId}/$id.db.gz',
      size: gz.length,
      sha256: sha256.convert(gz).toString(),
      schemaV: AppDatabase.schemaVersion,
      device: Platform.operatingSystem,
      createdAt: clock.now(),
    );
    await api.announceBackup(b);
    await api.putBackup(b.path, gz);
    return api.commitBackup(id);
  }

  /// Цілі копії на сервері (найновіші першими).
  Future<List<ServerBackup>> list() => api.listBackups();

  /// Замінити дані телефона копією [b] із сервера. Перед цим - копія
  /// поточного стану на телефоні (її повертає: так можна передумати).
  Future<LocalBackup> restore(ServerBackup b) async {
    final gz = await api.getBackup(b.path);
    if (gz.length != b.size || sha256.convert(gz).toString() != b.sha256) {
      throw const BackupException('копія дійшла пошкодженою - спробуйте ще раз');
    }
    final tmp = p.join(local.dir, 'server-restore.db.tmp');
    await Directory(local.dir).create(recursive: true);
    try {
      await File(tmp).writeAsBytes(gzip.decode(gz), flush: true);
      return await local.restoreFile(tmp);
    } finally {
      try {
        await File(tmp).delete();
      } catch (_) {}
    }
  }
}
