import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:workmanager/workmanager.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../data/sync_api.dart';
import '../data/sync_service.dart';
import 'app_config.dart';
import 'backups.dart';
import 'supabase_api.dart';

/// Фонові завдання (Android, WorkManager). Точного часу Android не гарантує
/// (може відкласти), тому кожне завдання ще й перевіряється, коли
/// застосунок відкривають (див. [ForegroundJobs]).
///
/// Фонове завдання запускається в окремому потоці Dart: тут немає екранів,
/// і базу воно відкриває саме. Базу НЕ закриває: на Android з'єднання з нею
/// одне на весь застосунок, і якщо він саме відкритий, закриття зламало б
/// йому роботу.
class BackgroundTasks {
  BackgroundTasks._();

  /// Резервна копія бази (кожні [BackupService.interval]).
  static const backup = 'apiary.backup';

  /// Синхронізація: кожні 15 хв перевірка розкладу (щогодини у свою
  /// хвилину, понад добу без зв'язку - одразу, нічна копія). Лише коли є
  /// мережа (Android сам відкладає до її появи); без мобільного інтернету -
  /// лише Wi-Fi.
  static const sync = 'apiary.sync';
  static const syncEvery = Duration(minutes: 15);

  /// Записати завдання в систему (один раз на запуск; наявні не дублюються).
  static Future<void> register() async {
    if (!Platform.isAndroid) return;
    final wm = Workmanager();
    await wm.initialize(callbackDispatcher);
    await wm.registerPeriodicTask(
      backup,
      backup,
      frequency: BackupService.interval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired, requiresStorageNotLow: true),
    );
    await registerSync(mobile: true, replace: false);
  }

  /// Записати (чи переписати - змінився перемикач мобільного інтернету)
  /// завдання синхронізації. Без сервера в збірці - не потрібне.
  static Future<void> registerSync({required bool mobile, bool replace = true}) async {
    if (!Platform.isAndroid || !AppConfig.current.syncConfigured) return;
    await Workmanager().registerPeriodicTask(
      sync,
      sync,
      frequency: syncEvery,
      existingWorkPolicy: replace ? ExistingPeriodicWorkPolicy.update : ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: mobile ? NetworkType.connected : NetworkType.unmetered),
    );
  }
}

/// Точка входу фонових завдань (Android викликає її сам).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) => runBackgroundTask(task));
}

/// Виконати фонове завдання [task]. [openRepo] - тести підставляють свою базу.
Future<bool> runBackgroundTask(String task,
    {Future<Repository> Function()? openRepo,
    Future<BackupService> Function(Repository)? backups,
    Future<SyncApi?> Function()? syncApi}) async {
  try {
    final repo = await (openRepo ?? () async => Repository(await AppDatabase.openDefault()))();
    switch (task) {
      case BackgroundTasks.backup:
        final service = await (backups ?? BackupService.forApp)(repo);
        await service.maybeBackup();
        return true;
      case BackgroundTasks.sync:
        final api = await (syncApi ?? _restoreApi)();
        if (api == null) return true; // не увійшли - нічого робити
        await SyncService(repo, api: api).tick();
        return true;
    }
    return true; // невідоме (застаріле) завдання - не повторювати
  } catch (e) {
    debugPrint('Фонове завдання $task: $e');
    return false; // система повторить пізніше
  }
}

Future<SyncApi?> _restoreApi() async =>
    SupabaseApi.restore(AppConfig.current, await SessionStore.forApp());

/// Ті самі завдання, поки застосунок відкритий: одразу після запуску й
/// далі щогодини перевіряють, чи не пора (фон Android може запізнюватись).
class ForegroundJobs {
  final BackupService backups;
  Timer? _timer;
  ForegroundJobs(this.backups);

  static const checkEvery = Duration(hours: 1);

  void start() {
    unawaited(tick());
    _timer ??= Timer.periodic(checkEvery, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    try {
      await backups.maybeBackup();
    } catch (e) {
      debugPrint('Резервна копія: $e');
    }
  }
}
