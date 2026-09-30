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
      // на заблокованому екрані — за налаштуваннями приватності телефона
      visibility: NotificationVisibility.private,
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
  // Windows: ключ об'єкта → показане нагадування (час + підпис даних)
  final Map<String, _Shown> _shown = {};
  File? _stateFile;

  /// Запуск: перше планування + автооновлення при зміні карти. Безпечно
  /// викликати на будь-якій платформі й багаторазово.
  Future<void> start(Repository repo) async {
    if (!supported || _repo != null) return;
    _repo = repo;
    repo.mapChanges.addListener(_scheduleSoon);
    repo.remindersChanged.addListener(_scheduleSoon);
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
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'Vulyk',
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
    // iOS дозволяє лише 64 відкладені сповіщення
    final limit = Platform.isIOS ? 60 : 300;
    // лише заплановані: уже показані в шторці сповіщення лишаються
    await _plugin.cancelAllPendingNotifications();
    if (planReminders(targets, now: DateTime.now(), limit: limit).isEmpty) return;
    await _requestPermission();
    // план рахуємо ПІСЛЯ можливого діалогу дозволу (користувач міг відповісти
    // через кілька хвилин) і з запасом: момент у минулому система відхиляє
    final plans =
        planReminders(targets, now: DateTime.now().add(const Duration(minutes: 1)), limit: limit);
    var id = 1;
    for (final p in plans) {
      final u = p.when.toUtc();
      try {
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
      } catch (e) {
        // одне невдале нагадування не повинне скасовувати решту
        debugPrint('Нагадування (${p.title}): $e');
      }
    }
  }

  // ------------------------------- Windows -------------------------------

  Future<File?> _state() async {
    if (_stateFile != null) return _stateFile;
    final File file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}${Platform.pathSeparator}reminders_state.json');
    } catch (e) {
      debugPrint('Нагадування (стан): $e');
      return null; // спробуємо ще раз при наступній перевірці
    }
    try {
      if (await file.exists()) {
        final m = jsonDecode(await file.readAsString());
        if (m is Map) {
          for (final e in m.entries) {
            final v = _Shown.fromJson(e.value);
            // те, що вже показано в цьому запуску, має перевагу над файлом
            if (v != null) _shown.putIfAbsent(e.key as String, () => v);
          }
        }
      }
    } catch (e) {
      // пошкоджений файл (напр., вимкнули живлення під час запису): стан
      // починається з порожнього, і файл буде перезаписано справним —
      // інакше нагадування повторювались би при кожному запуску
      debugPrint('Нагадування (стан пошкоджено): $e');
    }
    _stateFile = file;
    return file;
  }

  /// Запис стану через тимчасовий файл: обрив посеред запису не псує стан.
  static Future<void> _writeState(File file, String json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
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
        final sig = '${t.lastVisit}|${t.periodDays}|${t.periodSetAt?.millisecondsSinceEpoch}';
        final prev = _shown[t.key];
        // те саме нагадування вже показано (дані не змінювались); якщо дату
        // обходу чи період змінили — рахуємо наново
        if (prev != null && prev.ms >= ms && (prev.sig == null || prev.sig == sig)) continue;
        await _plugin.show(
          id: t.key.hashCode & 0x7fffffff,
          title: d.title,
          body: d.body,
          notificationDetails: _details,
        );
        _shown[t.key] = _Shown(ms, sig);
        changed = true;
      }
      // прибрати записи вуликів, яких уже немає
      final alive = {for (final t in _targets) t.key};
      final before = _shown.length;
      _shown.removeWhere((k, _) => !alive.contains(k));
      if (_shown.length != before) changed = true;
      if (changed && file != null) {
        await _writeState(file, jsonEncode({for (final e in _shown.entries) e.key: e.value.toJson()}));
      }
    } catch (e) {
      debugPrint('Нагадування (Windows): $e');
    } finally {
      _checking = false;
    }
  }
}

/// Показане на Windows нагадування: час і "підпис" даних, з яких його
/// порахували (щоб зміна дати обходу/періоду не ховала наступне).
class _Shown {
  final int ms;
  final String? sig; // null — запис зі старого формату
  const _Shown(this.ms, this.sig);

  Map<String, Object?> toJson() => {'ms': ms, 'sig': sig};

  static _Shown? fromJson(Object? v) {
    if (v is num) return _Shown(v.toInt(), null);
    if (v is Map && v['ms'] is num) {
      return _Shown((v['ms'] as num).toInt(), v['sig'] as String?);
    }
    return null;
  }
}
