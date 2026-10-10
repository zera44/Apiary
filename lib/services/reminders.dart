import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../logic/visit_reminders.dart';

/// Пуш-сповіщення "Ти давно не заглядав у вулик …".
///
/// Android / iOS: система сама показує сповіщення у призначений час, навіть
/// коли застосунок закритий: наперед плануються найближчі нагадування
/// кожного вулика (повторюються щоперіоду), при кожній зміні даних план
/// перебудовується.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Чи працюють сповіщення на цій платформі.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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
  );

  Repository? _repo;
  bool _ready = false;
  bool _askedPermission = false;

  /// Натиснули на нагадування: id вулика, який треба відкрити з формою
  /// «Оглянути». Застосунок слухає це значення (див. main.dart) і, щойно
  /// головний екран готовий, відкриває вулик і скидає значення в null.
  /// Якщо застосунок запустили натисканням на сповіщення, значення
  /// з'являється під час першого [start].
  final ValueNotifier<String?> openHiveRequest = ValueNotifier<String?>(null);

  void _onTapped(NotificationResponse r) {
    final id = r.payload;
    if (id != null && id.isNotEmpty) openHiveRequest.value = id;
  }
  Future<void> _tail = Future.value();
  Timer? _debounce;

  /// Запуск: перше планування + автооновлення при зміні карти. Безпечно
  /// викликати на будь-якій платформі й багаторазово.
  Future<void> start(Repository repo) async {
    if (!supported || _repo != null) return;
    _repo = repo;
    repo.mapChanges.addListener(_scheduleSoon);
    repo.remindersChanged.addListener(_scheduleSoon);
    await reschedule();
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
    );
    _ready = await _plugin.initialize(
          settings: settings,
          onDidReceiveNotificationResponse: _onTapped,
        ) ??
        false;
    if (_ready) {
      // застосунок запустили натисканням на нагадування
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final resp = launch?.notificationResponse;
        if (launch?.didNotificationLaunchApp == true && resp != null) _onTapped(resp);
      } catch (e) {
        debugPrint('Нагадування (запуск): $e');
      }
    }
    return _ready;
  }

  /// Застосунок підставляє сюди пояснення перед системним запитом про
  /// сповіщення: true — питати, false — не питати зараз.
  Future<bool> Function()? beforeAskPermission;

  Future<void> _requestPermission() async {
    if (_askedPermission) return;
    final explain = beforeAskPermission;
    if (explain != null) {
      var go = true;
      try {
        go = await explain();
      } catch (_) {}
      if (!go) return; // не зараз — запитаємо наступного разу
    }
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
          payload: p.elementId, // натискання відкриває цей вулик
          // неточний режим: не вимагає окремого дозволу на точні будильники
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e) {
        // одне невдале нагадування не повинне скасовувати решту
        debugPrint('Нагадування (${p.title}): $e');
      }
    }
  }
}
