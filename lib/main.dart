import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/repository.dart';
import 'data/sync_service.dart';
import 'icons/app_icons.dart';
import 'screens/splash_screen.dart';
import 'services/reminders.dart';
import 'ui/theme.dart';

/// "Моя пасіка" — план пасіки. Працює повністю офлайн: усі дані одразу
/// пишуться в локальну SQLite, а фонова синхронізація вивантажує зміни,
/// щойно з'являється інтернет.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppIcons.load(); // SVG-іконки з assets/icons
  final db = await AppDatabase.openDefault();
  final repo = Repository(db);
  await repo.init();
  final sync = SyncService(repo)..start();
  // нагадування про обхід; збій не повинен заважати запуску
  unawaited(ReminderService.instance.start(repo).catchError((Object _) {}));
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
      title: 'Моя пасіка',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: SplashScreen(repo: widget.repo),
    );
  }
}
