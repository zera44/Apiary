import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'data/sync_service.dart';
import 'icons/app_icons.dart';
import 'screens/splash_screen.dart';
import 'services/autostart.dart';
import 'services/reminders.dart';
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
  try {
    final db = await AppDatabase.openDefault();
    repo = Repository(db);
    await repo.init();
  } catch (e) {
    runApp(StartupErrorApp(error: e, onRetry: _start));
    return;
  }
  final sync = SyncService(repo)..start();
  // нагадування про обхід; збій не повинен заважати запуску
  unawaited(ReminderService.instance.start(repo).catchError((Object _) {}));
  // Windows: після оновлення в нову теку автозапуск веде на поточний exe
  unawaited(Autostart.syncPath());
  runApp(ApiaryApp(repo: repo, sync: sync));
}

class ApiaryApp extends StatefulWidget {
  final Repository repo;
  final SyncService? sync;
  const ApiaryApp({super.key, required this.repo, this.sync});

  @override
  State<ApiaryApp> createState() => _ApiaryAppState();
}

class _ApiaryAppState extends State<ApiaryApp> {
  @override
  void dispose() {
    widget.sync?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vulyk',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: SplashScreen(repo: widget.repo),
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
