import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'data/sync_service.dart';
import 'icons/app_icons.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart' show NextHive;
import 'screens/splash_screen.dart';
import 'services/auth.dart';
import 'services/autostart.dart';
import 'services/reminders.dart';
import 'ui/app_drawer.dart';
import 'ui/theme.dart';

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
  } catch (e) {
    runApp(StartupErrorApp(error: e, onRetry: _start));
    return;
  }
  final sync = SyncService(repo)..start();
  // нагадування про обхід; збій не повинен заважати запуску
  unawaited(ReminderService.instance.start(repo).catchError((Object _) {}));
  // Windows: після оновлення в нову теку автозапуск веде на поточний exe
  unawaited(Autostart.syncPath());
  runApp(ApiaryApp(repo: repo, auth: auth, sync: sync));
}

/// Чи можна одразу на головний екран: увійшли, обрали «без входу», або вхід
/// у цій збірці не налаштовано.
bool canUseApp(AuthService auth) => auth.user != null || auth.guest || !auth.configured;

class ApiaryApp extends StatefulWidget {
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

  @override
  void initState() {
    super.initState();
    _reminders.addListener(_openFromReminder);
    // застосунок могли запустити натисканням на нагадування
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromReminder());
  }

  @override
  void dispose() {
    _reminders.removeListener(_openFromReminder);
    widget.sync?.stop();
    super.dispose();
  }

  /// Натиснули на нагадування «Ти давно не заглядав у вулик N»: відкрити цей
  /// вулик на карті одразу з формою «Заповнити» (лише якщо вже увійшли).
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
                Text('Не вдалося відкрити дані пасіки',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  'Можливі причини: програму вже запущено в іншому вікні, закінчилось '
                  'місце на диску або файл даних пошкоджено. Закрийте інші копії '
                  'програми й спробуйте ще раз.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
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
                  child: Text(_busy ? 'Відкриваємо…' : 'Спробувати ще раз'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
