import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../logic/visit_reminders.dart';

/// Пуш-сповіщення "Ти давно не заглядав у вулик …".
///
/// * Android / iOS — система сама показує сповіщення у призначений час,
///   навіть коли застосунок закритий: наперед плануються найближчі
///   нагадування кожного вулика (повторюються щоперіоду), при кожній зміні
///   даних план перебудовується.
/// * Windows — відкладених сповіщень система не вміє, тож застосунок сам
///   перевіряє час (щохвилини й при запуску) і показує сповіщення, поки
///   він запущений (можна згорнути).
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  static bool get _windows => !kIsWeb && Platform.isWindows;

  /// Чи працюють сповіщення на цій платформі.
  static bool get supported => _mobile || _windows;

  static const _channelId = 'visit_reminders';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Нагадування про обхід',
      channelDescription: 'Нагадує оглянути вулики за заданою періодичністю',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  Repository? _repo;
  bool _ready = false;
  bool _askedPermission = false;
  Future<void> _tail = Future.value();
  Timer? _debounce;
  Timer? _windowsTimer;
  List<VisitTarget> _targets = const [];
  Map<String, int> _shown = {}; // Windows: ключ → мс часу показаного нагадування
  File? _stateFile;

  /// Запуск: перше планування + автооновлення при зміні карти. Безпечно
  /// викликати на будь-якій платформі й багаторазово.
  Future<void> start(Repository repo) async {
    if (!supported || _repo != null) return;
    _repo = repo;
    repo.mapChanges.addListener(_scheduleSoon);
    await reschedule();
    if (_windows) {
      _windowsTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDueWindows());
    }
  }

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), reschedule);
  }

  /// Перебудувати нагадування за поточними даними (викликати після кожної
  /// зміни періодичності / дати обходу). Виклики виконуються по черзі.
  Future<void> reschedule() {
    final repo = _repo;
    if (repo == null || !supported) return Future.value();
    _tail = _tail.then((_) => _run(repo)).catchError((Object e, StackTrace s) {
      debugPrint('Нагадування: $e');
    });
    return _tail;
  }

  Future<bool> _init() async {
    if (_ready) return true;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'Моя пасіка',
        appUserModelId: 'com.zera44.apiary',
        guid: '6f1c1f4e-3b0e-4b7a-9d55-2f8f0b6a1c11',
      ),
    );
    _ready = await _plugin.initialize(settings: settings) ?? false;
    return _ready;
  }

  Future<void> _requestPermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }

  Future<void> _run(Repository repo) async {
    if (!await _init()) return;
    final targets = await repo.visitTargets();
    _targets = targets;
    if (_windows) {
      await _checkDueWindows();
      return;
    }
    final now = DateTime.now();
    // iOS дозволяє лише 64 відкладені сповіщення
    final plans = planReminders(targets, now: now, limit: Platform.isIOS ? 60 : 300);
    await _plugin.cancelAll();
    if (plans.isEmpty) return;
    await _requestPermission();
    var id = 1;
    for (final p in plans) {
      final u = p.when.toUtc();
      await _plugin.zonedSchedule(
        id: id++,
        title: p.title,
        body: p.body,
        // абсолютний момент часу (UTC), тож база часових поясів не потрібна
        scheduledDate: tz.TZDateTime.utc(u.year, u.month, u.day, u.hour, u.minute),
        notificationDetails: _details,
        // неточний режим: не вимагає окремого дозволу на точні будильники
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  // ------------------------------- Windows -------------------------------

  Future<File?> _state() async {
    if (_stateFile != null) return _stateFile;
    try {
      final dir = await getApplicationSupportDirectory();
      _stateFile = File('${dir.path}${Platform.pathSeparator}reminders_state.json');
      if (await _stateFile!.exists()) {
        final m = jsonDecode(await _stateFile!.readAsString());
        if (m is Map) {
          _shown = {for (final e in m.entries) e.key as String: (e.value as num).toInt()};
        }
      }
    } catch (_) {}
    return _stateFile;
  }

  bool _checking = false;

  Future<void> _checkDueWindows() async {
    if (_checking || !_ready) return;
    _checking = true;
    try {
      final file = await _state();
      final now = DateTime.now();
      var changed = false;
      for (final t in _targets) {
        final d = dueReminder(t, now: now);
        if (d == null) continue;
        final ms = d.when.millisecondsSinceEpoch;
        if ((_shown[t.key] ?? 0) >= ms) continue;
        await _plugin.show(
          id: t.key.hashCode & 0x7fffffff,
          title: d.title,
          body: d.body,
          notificationDetails: _details,
        );
        _shown[t.key] = ms;
        changed = true;
      }
      if (changed && file != null) {
        await file.writeAsString(jsonEncode(_shown));
      }
    } catch (e) {
      debugPrint('Нагадування (Windows): $e');
    } finally {
      _checking = false;
    }
  }
}
