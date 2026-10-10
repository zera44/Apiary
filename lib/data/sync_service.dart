import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:sqflite/sqflite.dart';

import '../services/app_config.dart';
import '../services/backups.dart';
import '../services/server_backups.dart';
import 'repository.dart';
import 'sync_api.dart';
import 'sync_engine.dart';
import 'sync_schedule.dart';

/// Стан синхронізації для рядка стану (головний екран, Налаштування → «Головне»).
class SyncInfo {
  /// Коли востаннє все вивантажено (null - ще не було).
  final DateTime? lastOk;

  /// Скільки змін ще чекає відправки.
  final int pending;

  /// Немає зв'язку із сервером.
  final bool offline;

  /// Синхронізацію не налаштовано (немає адреси й ключа сервера) або не
  /// виконано вхід.
  final bool disabled;

  /// Текст останньої помилки (null - помилки не було).
  final String? error;

  /// Скільки змін сервер відхилив (правила доступу).
  final int rejected;

  /// Чекає Wi-Fi (мобільний інтернет для синхронізації вимкнено).
  final bool waitingWifi;

  /// Саме синхронізується.
  final bool running;

  /// Сервер налаштовано, але вхід не виконано.
  final bool needsSignIn;

  const SyncInfo({
    this.lastOk,
    this.pending = 0,
    this.offline = false,
    this.disabled = false,
    this.error,
    this.rejected = 0,
    this.waitingWifi = false,
    this.running = false,
    this.needsSignIn = false,
  });
}

/// Синхронізація із сервером (Supabase), див. [SyncEngine] і [SyncSchedule].
///
/// Поки адресу й ключ не задано під час збірки (див. [AppConfig]) або не
/// виконано вхід ([api] null), синхронізація вимкнена й НІЧОГО не робить із
/// даними: записи лишаються в черзі (synced = 0), позначки «видалено» не
/// стираються - їх отримає сервер, коли синхронізацію буде увімкнено.
///
/// Застосунок і фонове завдання (окремий потік) можуть почати синхронізацію
/// одночасно - тоді другий просто пропускає хід (позначка-замок у базі).
class SyncService {
  /// Поточна служба (її можна смикнути одразу після входу).
  static SyncService? current;
  static final ValueNotifier<SyncInfo> info = ValueNotifier(const SyncInfo(disabled: true));

  /// Синхронізувати зараз (наприклад, одразу після входу).
  static Future<void> now() async {
    await current?.syncNow();
  }

  static const lastOkKey = 'sync_last_ok';
  static const lastTryKey = 'sync_last_try';
  static const errorKey = 'sync_error';
  static const offlineKey = 'sync_offline';
  static const minuteKey = 'sync_minute';
  static const mobileKey = 'sync_mobile';
  static const mobileWarnedKey = 'sync_mobile_warned';
  static const lockKey = 'sync_lock';
  static const nightlyKey = 'sync_nightly_last';
  static const nightlyTryKey = 'sync_nightly_try';

  /// Нічна копія не вдалась - наступна спроба не раніше.
  static const nightlyRetry = Duration(minutes: 30);

  /// Замок довше за це - покинутий (потік, що його взяв, загинув).
  static const lockFor = Duration(minutes: 10);

  final Repository repo;
  final AppConfig _config;

  /// Сервер (null - не увійшли).
  SyncApi? api;

  /// Чи телефон зараз лише на мобільному інтернеті (тести підставляють своє).
  final Future<bool> Function() _mobileOnly;

  /// Вхід на сервер закінчився (відкликали, довго не відкривали) - увійти
  /// знову (тихо через Google). Задає [Server].
  Future<void> Function()? onSignedOut;

  /// Сервер налаштовано, а вхід ще не вдався (не було мережі) - спробувати
  /// знову. Задає [Server].
  Future<void> Function()? reconnect;
  DateTime? _reconnectAt;

  /// Синхронізація чекає вибору першого входу, а питання ще не поставлено
  /// (перевірка не вдалась без мережі) - перевірити знову. Задає [Server].
  Future<void> Function()? onNeedsChoice;

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _net;
  Future<SyncReport?>? _running;

  SyncService(this.repo, {AppConfig? config, this.api, Future<bool> Function()? mobileOnly})
      : _config = config ?? AppConfig.current,
        _mobileOnly = mobileOnly ?? _mobileOnlyNow;

  /// Чи налаштовано сервер.
  bool get configured => _config.syncConfigured;

  /// Синхронізація можлива: сервер налаштовано й вхід виконано.
  bool get enabled => configured && api != null;

  /// Поки застосунок відкритий: щохвилини перевірка розкладу (дешева), і
  /// одразу - коли з'явився інтернет (якщо зв'язку не було понад добу).
  void start() {
    current = this;
    unawaited(refreshInfo());
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(tick()));
    try {
      _net ??= Connectivity().onConnectivityChanged.listen((r) {
        if (!r.contains(ConnectivityResult.none)) unawaited(maybeSync());
      });
    } catch (_) {
      // без плагіна (тести) - лише за розкладом
    }
    unawaited(maybeSync());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_net?.cancel());
    _net = null;
    if (identical(current, this)) current = null;
  }

  static Future<bool> _mobileOnlyNow() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.mobile) &&
          !r.contains(ConnectivityResult.wifi) &&
          !r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  /// Своя хвилина щогодинної синхронізації (випадкова, назавжди).
  Future<int> minute() async {
    final v = int.tryParse(await repo.getMeta(minuteKey) ?? '');
    if (v != null && v >= 0 && v < 60) return v;
    final m = Random().nextInt(60);
    await repo.setMeta(minuteKey, '$m');
    return m;
  }

  /// Синхронізувати через мобільний інтернет (за замовчуванням - так).
  Future<bool> mobileAllowed() async => (await repo.getMeta(mobileKey)) != '0';
  Future<void> setMobileAllowed(bool on) => repo.setMeta(mobileKey, on ? '1' : '0');

  Future<DateTime?> _time(String key) async {
    final v = double.tryParse(await repo.getMeta(key) ?? '');
    return v == null ? null : DateTime.fromMicrosecondsSinceEpoch((v * 1e6).round());
  }

  Future<void> _setTime(String key, DateTime t) =>
      repo.setMeta(key, '${t.microsecondsSinceEpoch / 1e6}');

  /// Синхронізуватись, якщо пора за розкладом.
  Future<SyncReport?> maybeSync() async {
    if (!enabled) return null;
    final due = SyncSchedule.due(
        lastOk: await _time(lastOkKey), lastTry: await _time(lastTryKey), now: clock.now(), minute: await minute());
    return due ? syncNow() : null;
  }

  /// Нічна повна копія на сервер, якщо пора (00:00-06:00, раз за ніч).
  /// Заразом - ще одна спроба для змін, які сервер колись відхилив.
  /// Повертає 'ok' / 'bad' або null (не пора / не вийшло).
  Future<String?> maybeNightly({Future<BackupService> Function(Repository)? backups}) async {
    if (!enabled) return null;
    // повна копія - лише коли дані телефона точно цього акаунта
    if ((await repo.getMeta(SyncEngine.pendingChoiceKey) ?? '').isNotEmpty ||
        await repo.getMeta(SyncEngine.userKey) != api!.userId) {
      return null;
    }
    final now = clock.now();
    if (!SyncSchedule.nightlyDue(await _time(nightlyKey), now)) return null;
    final lastTry = await _time(nightlyTryKey);
    if (lastTry != null && now.difference(lastTry) < nightlyRetry && !lastTry.isAfter(now)) return null;
    if (!await mobileAllowed() && await _mobileOnly()) return null;
    if (!await _lock()) return null;
    try {
      await _setTime(nightlyTryKey, now);
      await SyncEngine(repo, api!).retryRejected();
      final local = await (backups ?? BackupService.of)(repo);
      final status = await ServerBackups(repo, api!, local).upload();
      if (status == 'ok') await _setTime(nightlyKey, now);
      debugPrint('Нічна копія на сервер: $status');
      return status;
    } catch (e) {
      debugPrint('Нічна копія на сервер: $e');
      return null;
    } finally {
      await _unlock();
    }
  }

  /// Один хід розкладу (фонове завдання, таймер застосунку): зміни, якщо
  /// пора, і нічна копія, якщо пора.
  Future<void> tick() async {
    final f = reconnect;
    if (!enabled && configured && f != null) {
      final now = clock.now();
      final at = _reconnectAt;
      if (at == null || now.difference(at) > const Duration(minutes: 5) || at.isAfter(now)) {
        _reconnectAt = now;
        try {
          await f();
        } catch (_) {}
      }
    }
    await maybeSync();
    await maybeNightly();
  }

  /// Сумісність зі старими викликами: (надіслано, усього було в черзі).
  Future<(int, int)> syncOnce() async {
    final before = enabled ? await repo.countUnsynced() : 0;
    final r = await syncNow();
    return (r?.sent ?? 0, r == null ? 0 : before);
  }

  /// Синхронізуватись зараз. null - не вийшло або не можна (див. [info]).
  Future<SyncReport?> syncNow() {
    if (!enabled) {
      unawaited(refreshInfo());
      return Future.value(null);
    }
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<SyncReport?> _run() async {
    final api = this.api!;
    if (!await mobileAllowed() && await _mobileOnly()) {
      await refreshInfo(waitingWifi: true);
      return null;
    }
    if (!await _lock()) return null; // уже синхронізує фонове завдання
    info.value = SyncInfo(
        lastOk: info.value.lastOk, pending: info.value.pending, rejected: info.value.rejected, running: true);
    SyncReport? report;
    try {
      report = await SyncEngine(repo, api).run();
      await _setTime(lastOkKey, clock.now());
      await repo.setMeta(errorKey, '');
      await repo.setMeta(offlineKey, '');
      debugPrint('Синхронізація: $report');
    } on SyncOffline catch (e) {
      await repo.setMeta(offlineKey, '1');
      debugPrint('Синхронізація: $e');
    } on SyncNeedsChoice catch (e) {
      await repo.setMeta(offlineKey, '');
      await repo.setMeta(errorKey, '$e');
      final f = onNeedsChoice;
      if (f != null) unawaited(f().catchError((Object _) {}));
    } on SyncSignedOut catch (e) {
      await repo.setMeta(offlineKey, '');
      await repo.setMeta(errorKey, '$e');
      this.api = null;
      final f = onSignedOut;
      if (f != null) unawaited(f().catchError((Object _) {}));
    } catch (e) {
      await repo.setMeta(offlineKey, '');
      await repo.setMeta(errorKey, '$e');
      debugPrint('Синхронізація: $e');
    } finally {
      await _setTime(lastTryKey, clock.now());
      await _unlock();
      await refreshInfo();
    }
    return report;
  }

  Future<bool> _lock() async {
    final now = clock.now();
    return repo.db.transaction((txn) async {
      final r = await txn.query('app_meta', where: 'key = ?', whereArgs: [lockKey], limit: 1);
      final until = r.isEmpty ? null : double.tryParse('${r.first['value']}');
      if (until != null && until * 1e6 > now.microsecondsSinceEpoch) return false;
      await txn.insert(
          'app_meta', {'key': lockKey, 'value': '${now.add(lockFor).microsecondsSinceEpoch / 1e6}'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<void> _unlock() => repo.setMeta(lockKey, '');

  /// Для видалення акаунта: дочекатися поточної синхронізації (і фонової -
  /// до [wait]) і взяти замок, щоб нова не почалась. false - не вийшло.
  Future<bool> holdLock({Duration wait = const Duration(seconds: 30)}) async {
    await _running?.catchError((Object _) => null);
    final until = clock.now().add(wait);
    while (!await _lock()) {
      if (clock.now().isAfter(until)) return false;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return true;
  }

  Future<void> releaseLock() => _unlock();

  /// Оновити рядок стану з бази.
  Future<SyncInfo> refreshInfo({bool waitingWifi = false}) async {
    if (!enabled) return info.value = SyncInfo(disabled: true, needsSignIn: configured);
    final err = await repo.getMeta(errorKey);
    return info.value = SyncInfo(
      lastOk: await _time(lastOkKey),
      pending: await repo.countUnsynced(),
      offline: (await repo.getMeta(offlineKey)) == '1',
      error: (err == null || err.isEmpty) ? null : err,
      rejected: await countRejected(repo),
      waitingWifi: waitingWifi,
    );
  }
}
