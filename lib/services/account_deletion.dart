import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/repository.dart';
import 'backups.dart';
import 'stock_photos.dart';

/// «Видалити акаунт і всі дані» (Налаштування → «Головне»).
///
/// Спершу - сервер (акаунт, пасіки, склад, фінанси, фото, нічні копії; див.
/// supabase/functions/delete-account). Не вдалося - на телефоні нічого не
/// чіпаємо (людина спробує ще раз). Вдалося - телефон як після нової
/// інсталяції: дані, резервні копії, фото складу.
Future<void> deleteAccountAndData({
  required Repository repo,
  required Future<void> Function() deleteOnServer,
  Future<BackupService> Function(Repository)? backups,
}) async {
  await deleteOnServer();
  await wipeLocal(repo, backups: backups);
}

/// Стерти всі дані на телефоні (як після нової інсталяції).
Future<void> wipeLocal(Repository repo, {Future<BackupService> Function(Repository)? backups}) async {
  final tables = [
    for (final r in await repo.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'"))
      r['name']! as String,
  ];
  await repo.db.transaction((txn) async {
    for (final t in tables) {
      await txn.delete(t);
    }
  });
  await repo.prepareLikeFreshInstall();
  repo.notifyAllChanged();
  // резервні копії й фото - теж (у копіях - ті самі дані)
  try {
    final d = Directory((await (backups ?? BackupService.of)(repo)).dir);
    if (await d.exists()) await d.delete(recursive: true);
  } catch (e) {
    debugPrint('Видалення копій: $e');
  }
  final photos = StockPhotos.dir;
  if (photos != null) {
    try {
      final d = Directory(photos);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('Видалення фото: $e');
    }
  }
}
