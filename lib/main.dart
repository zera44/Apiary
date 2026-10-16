import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'data/sync_service.dart';
import 'icons/app_icons.dart';
import 'l10n/l10n.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart' show NextHive;
import 'screens/splash_screen.dart';
import 'services/auth.dart';
import 'services/background.dart';
import 'services/backups.dart';
import 'services/reminders.dart';
import 'services/server.dart';
import 'services/stock_photos.dart';
import 'ui/app_drawer.dart';
import 'ui/common.dart' show showConfirm;
import 'ui/theme.dart';
import 'ui/text_scale.dart';
import 'ui/orientation.dart';
import 'package:app_links/app_links.dart';
import 'services/invite_link.dart';
import 'ui/voice_input_bar.dart';

/// "Моя пасіка" — план пасіки. Працює повністю офлайн: усі дані одразу
/// пишуться в локальну SQLite, а фонова синхронізація вивантажує зміни,
/// щойно з'являється інтернет.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppIcons.load(); // SVG-іконки з assets/icons
  await _start();
}

/// Відкрити базу й показати застосунок. Якщо база не відкривається
/// (пошкоджений файл, зайнята, закінчилось місце), замість вічного екрана
/// запуску показується пояснення з кнопкою "Спробувати ще раз".
Future<void> _start() async {
  final Repository repo;
  final AuthService auth;
  try {
    final db = await AppDatabase.openDefault();
    repo = Repository(db);
    await repo.prepareLikeFreshInstall();
    auth = await GoogleAuthService.open();
    await StockPhotos.init();
    await AppTextScale.load(repo); // розмір шрифту з налаштувань
    await AppOrientation.load(repo); // орієнтація екрана з налаштувань
  } catch (e) {
    runApp(StartupErrorApp(error: e, onRetry: _start));
    return;
  }
  final sync = SyncService(repo)..start();
  // вхід на сервер (збережений або тихо через Google); без мережі - пізніше
  unawaited(Server.start(repo, auth).catchError((Object _) {}));
  // нагадування про обхід; збій не повинен заважати запуску
  unawaited(ReminderService.instance.start(repo).catchError((Object _) {}));
  runApp(ApiaryApp(repo: repo, auth: auth, sync: sync));
  unawaited(_startJobs(repo));
}

/// Після запуску, фоном (не заважаючи інтерфейсу): резервна копія, якщо
/// пора (і далі щогодини перевірка); фонові завдання Android; один раз після
/// оновлення - старі фото складу у новий формат і прибирання непотрібних
/// файлів (крім тих, на які посилаються резервні копії).
Future<void> _startJobs(Repository repo) async {
  try {
    final backups = await BackupService.of(repo);
    final jobs = ForegroundJobs(backups);
    await jobs.tick(); // копія - раніше за перетискання фото
    jobs.start();
    unawaited(BackgroundTasks.register().catchError((Object e) {
      debugPrint('Фонові завдання: $e');
    }));
    await StockPhotos.upgradeOld(repo);
    await StockPhotos.sweepOrphans(repo, alsoKeep: await backups.photoRefs());
  } catch (e) {
    debugPrint('Службові завдання: $e');
  }
}

/// Чи можна одразу на головний екран: увійшли, обрали «без входу», або вхід
/// у цій збірці не налаштовано.
bool canUseApp(AuthService auth) => auth.user != null || auth.guest || !auth.configured;

class ApiaryApp extends StatefulWidget {
  /// Слухати запрошувальні посилання (плагін системи; тести вимикають).
  static bool listenLinks = true;

  final Repository repo;
  final AuthService auth;
  final SyncService? sync;
  const ApiaryApp({super.key, required this.repo, required this.auth, this.sync});

  @override
  State<ApiaryApp> createState() => _ApiaryAppState();
}

class _ApiaryAppState extends State<ApiaryApp> {
  final _nav = GlobalKey<NavigatorState>();
  final _reminders = ReminderService.instance.openHiveRequest;
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    _reminders.addListener(_openFromReminder);
    ReminderService.instance.beforeAskPermission = _explainNotifications;
    // застосунок могли запустити натисканням на нагадування
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromReminder());
    _listenLinks();
  }

  /// Запрошувальні посилання (vulyk://join?t=...): і коли застосунок
  /// запустили ними, і коли він уже був відкритий. Без плагіна (тести,
  /// інші платформи) - тихо без посилань.
  void _listenLinks() {
    if (!ApiaryApp.listenLinks) return;
    try {
      final links = AppLinks();
      links.getInitialLink().then(_onLink).catchError((Object _) {});
      _links = links.uriLinkStream.listen(_onLink, onError: (Object _) {});
    } catch (e) {
      debugPrint('Посилання: $e');
    }
  }

  void _onLink(Uri? uri) {
    final t = uri == null ? null : InviteLink.tokenFrom(uri);
    if (t != null) InviteLink.pending.value = t;
  }

  @override
  void dispose() {
    _reminders.removeListener(_openFromReminder);
    unawaited(_links?.cancel());
    ReminderService.instance.beforeAskPermission = null;
    widget.sync?.stop();
    super.dispose();
  }

  /// Перед системним запитом: навіщо застосунку сповіщення.
  Future<bool> _explainNotifications() async {
    final ctx = _nav.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    return showConfirm(ctx,
        title: 'Нагадування про обхід',
        text: 'Дозвольте сповіщення, щоб застосунок нагадував оглянути вулик, коли '
            'настав час обходу. Без них нагадувань не буде.',
        confirmText: 'Далі',
        cancelText: 'Не зараз',
        danger: false);
  }

  /// Натиснули на нагадування «Ти давно не заглядав у вулик N»: відкрити цей
  /// вулик на карті одразу з формою «Оглянути» (лише якщо вже увійшли).
  Future<void> _openFromReminder() async {
    final id = _reminders.value;
    if (id == null) return;
    final nav = _nav.currentState;
    if (nav == null) return; // ще не побудовано — спрацює після першого кадру
    _reminders.value = null;
    if (!canUseApp(widget.auth)) return;
    final el = await widget.repo.getElement(id);
    final apiaryId = el?.apiaryId;
    if (el == null || el.deleted || apiaryId == null) return;
    final apiary = await widget.repo.getApiary(apiaryId);
    if (apiary == null || apiary.deleted || !nav.mounted) return;
    AppDrawer.openHive(nav, widget.repo, apiary, id, fill: true, next: NextHive.overdue);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      title: 'Vulyk',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // голосовий ввід (Vosk) над клавіатурою для всіх текстових полів
      // розмір шрифту з налаштувань - для всіх екранів
      builder: (context, child) => AppTextScale.apply(VoiceInputHost(child: child ?? const SizedBox())),
      // вхід обов'язковий: хто вже увійшов — одразу на головний екран
      // (поки вхід у збірці не налаштовано — одразу головний екран)
      home: !canUseApp(widget.auth)
          ? SplashScreen(repo: widget.repo, auth: widget.auth)
          : HomeScreen(repo: widget.repo, auth: widget.auth),
    );
  }
}

/// Екран "не вдалося відкрити дані" — замість порожнього вікна.
class StartupErrorApp extends StatefulWidget {
  final Object error;
  final Future<void> Function() onRetry;
  const StartupErrorApp({super.key, required this.error, required this.onRetry});

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // базу збережено новішою версією: повтор не допоможе - треба оновитись
    final tooNew = widget.error is DatabaseTooNewException;
    return MaterialApp(
      title: 'Vulyk',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr.startupErrorTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  tooNew ? '${widget.error}' : tr.startupErrorHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                if (!tooNew) ...[
                  const SizedBox(height: 12),
                  SelectableText('${widget.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await widget.onRetry();
                            if (mounted) setState(() => _busy = false);
                          },
                    child: Text(_busy ? tr.startupOpening : tr.retry),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
