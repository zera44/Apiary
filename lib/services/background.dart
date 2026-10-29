import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:workmanager/workmanager.dart';

import '../assistant/assistant_model.dart';
import '../assistant/assistant_persona.dart';
import '../assistant/assistant_queue.dart';
import '../assistant/assistant_store.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../data/sync_api.dart';
import '../data/sync_service.dart';
import '../l10n/l10n.dart';
import 'app_config.dart';
import 'backups.dart';
import 'feedback_chat.dart';
import 'reminders.dart';
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

  /// Відповіді розробника на відгук: раз на ~15 хв питає сервер (лише якщо
  /// людина вже писала) і показує сповіщення.
  static const feedback = 'apiary.feedback';

  /// Помічник «Пасічник»: дослати чергу повідомлень, коли з'явиться
  /// інтернет (навіть якщо застосунок закрили). Разове; невдача - система
  /// повторює з паузою.
  static const assistant = 'apiary.assistant';

  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  /// Записати завдання в систему (один раз на запуск; наявні не дублюються).
  static Future<void> register() async {
    if (!Platform.isAndroid) return;
    final wm = Workmanager();
    await _init();
    await wm.registerPeriodicTask(
      backup,
      backup,
      frequency: BackupService.interval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired, requiresStorageNotLow: true),
    );
    await registerSync(mobile: true, replace: false);
  }

  /// Люди, що вже писали розробнику, отримують відповіді й коли застосунок
  /// закрито.
  static Future<void> registerFeedback() async {
    if (!Platform.isAndroid) return;
    await _init();
    await Workmanager().registerPeriodicTask(
      feedback,
      feedback,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// Черга помічника не порожня: дослати у фоні, щойно буде мережа.
  static Future<void> scheduleAssistant() async {
    if (!Platform.isAndroid) return;
    await _init();
    await Workmanager().registerOneOffTask(
      assistant,
      assistant,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
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
    Future<SyncApi?> Function()? syncApi,
    AssistantModel Function()? assistantModel}) async {
  try {
    final repo = await (openRepo ?? () async => Repository(await AppDatabase.openDefault()))();
    await L10n.load(repo); // сповіщення - мовою, обраною в застосунку
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
      case BackgroundTasks.feedback:
        final fresh = await FeedbackChat(repo).poll();
        if (fresh.isNotEmpty) await ReminderService.notifyFeedbackReply(fresh.last.body);
        return true;
      case BackgroundTasks.assistant:
        final store = AssistantStore(repo.db);
        final model = assistantModel?.call() ??
            AssistantModel.fromConfig(options: () => AssistantPrefs.requestOptions(repo));
        await AssistantQueue(repo, store, model,
                isOnline: () async => true)
            .process();
        // лишилося (пауза після збою, зв'язок зник) - система повторить
        return !await store.hasQueued();
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
