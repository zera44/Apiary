import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, kReleaseMode;
import 'package:http/http.dart' as http;

import 'repository.dart';

/// Фонова синхронізація: періодично перевіряє інтернет і вивантажує
/// накопичені (synced = 0) зміни на сервер.
///
/// Адреса сервера задається під час збірки:
///   flutter run --dart-define=APIARY_API_URL=https://api.example.com
/// Поки її не задано — це заглушка: записи просто позначаються як
/// синхронізовані (як і в старій версії), щоб офлайн-частину можна було
/// тестувати без бекенду. Кожен рядок відправляється POST-запитом на
/// `{API_URL}/{таблиця}`.
/// Стан синхронізації для рядка на головному екрані.
class SyncInfo {
  /// Коли востаннє все вивантажено (null - ще не було).
  final DateTime? lastOk;

  /// Скільки записів ще чекає відправки.
  final int pending;

  /// Немає зв'язку із сервером.
  final bool offline;
  const SyncInfo({this.lastOk, this.pending = 0, this.offline = false});
}

class SyncService {
  /// Поточна служба (її можна смикнути одразу після входу).
  static SyncService? current;
  static final ValueNotifier<SyncInfo> info = ValueNotifier(const SyncInfo());

  /// Синхронізувати зараз (наприклад, одразу після входу).
  static Future<void> now() async {
    await current?.syncOnce();
  }

  static const apiUrl = String.fromEnvironment('APIARY_API_URL');
  static const interval = Duration(seconds: 20);

  final Repository repo;
  Timer? _timer;
  bool _running = false;
  http.Client? _client;

  SyncService(this.repo);

  void start() {
    current = this;
    if (_timer == null) {
      _timer = Timer.periodic(interval, (_) => syncOnce());
      unawaited(syncOnce()); // одразу після запуску, не чекаючи 20 с
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _client?.close();
    _client = null;
  }

  /// Адреса сервера придатна лише з HTTPS (дані — зокрема координати пасік —
  /// не повинні йти відкритим текстом). Виняток — локальний сервер розробки.
  static Uri? serverBase(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty) return null;
    // http — лише для локального сервера розробки й лише не в release-збірці
    final local = u.host == 'localhost' || u.host == '127.0.0.1' || u.host == '10.0.2.2';
    if (u.scheme != 'https' && !(u.scheme == 'http' && local && !kReleaseMode)) return null;
    if (u.userInfo.isNotEmpty) return null; // жодних паролів в адресі
    final path = u.path.endsWith('/') ? u.path.substring(0, u.path.length - 1) : u.path;
    // лише схема, хост, порт і шлях (без ?параметрів і #фрагмента)
    return Uri(scheme: u.scheme, host: u.host, port: u.port, path: path);
  }

  static final Uri? _base = apiUrl.isEmpty ? null : serverBase(apiUrl);

  /// Швидка перевірка інтернету. (ВИПРАВЛЕНО: сокет тепер закривається, а
  /// таймаут не змінюється глобально для всього застосунку.)
  /// Перевіряємо зв'язок із ВЛАСНИМ сервером (раніше — з публічними DNS
  /// 8.8.8.8 / 1.1.1.1, що зайве повідомляло стороннім про роботу
  /// застосунку й не працювало там, де їх заблоковано).
  static Future<bool> hasInternet(String host, int port,
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _push(String table, Map<String, Object?> row) async {
    if (apiUrl.isEmpty) return true;
    final base = _base;
    if (base == null) return false; // небезпечна адреса — нічого не відправляємо
    try {
      _client ??= http.Client();
      final resp = await _client!
          .post(base.replace(pathSegments: [...base.pathSegments, table]),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(row))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Одна спроба. Повертає (успішно відправлено, всього в черзі).
  /// ВИПРАВЛЕНО: синхронізуються ВСІ таблиці, включно з параметрами,
  /// прив'язками та історією значень (раніше — лише карта й шаблони).
  Future<(int, int)> syncOnce() async {
    if (_running) return (0, 0);
    _running = true;
    try {
      // Без адреси сервера (заглушка) інтернет не потрібен: перевірка
      // сокетом кожні 20 с лише даремно будила мережу й радіомодуль.
      if (apiUrl.isNotEmpty) {
        final base = _base;
        if (base == null) return (0, 0); // не https — не синхронізуємо
        if (!await hasInternet(base.host, base.port)) {
          info.value = SyncInfo(lastOk: info.value.lastOk, pending: info.value.pending, offline: true);
          return (0, 0);
        }
      }
      var ok = 0, total = 0;
      for (final table in kSyncTables) {
        final rows = await repo.unsynced(table);
        if (rows.isEmpty) continue;
        total += rows.length;
        if (apiUrl.isEmpty) {
          // заглушка: усе позначається разом, однією транзакцією
          await repo.markSyncedBatch(table, rows);
          ok += rows.length;
          continue;
        }
        for (final row in rows) {
          if (await _push(table, row)) {
            await repo.markSynced(table, row);
            ok++;
          }
        }
      }
      if (ok > 0) await repo.purgeDeleted();
      info.value = SyncInfo(
          lastOk: ok == total ? DateTime.now() : info.value.lastOk, pending: total - ok);
      return (ok, total);
    } catch (_) {
      return (0, 0);
    } finally {
      _running = false;
    }
  }
}
