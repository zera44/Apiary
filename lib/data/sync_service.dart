import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
class SyncService {
  static const apiUrl = String.fromEnvironment('APIARY_API_URL');
  static const interval = Duration(seconds: 20);

  final Repository repo;
  Timer? _timer;
  bool _running = false;
  http.Client? _client;

  SyncService(this.repo);

  void start() {
    _timer ??= Timer.periodic(interval, (_) => syncOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _client?.close();
    _client = null;
  }

  /// Швидка перевірка інтернету. (ВИПРАВЛЕНО: сокет тепер закривається, а
  /// таймаут не змінюється глобально для всього застосунку.)
  static Future<bool> hasInternet({Duration timeout = const Duration(seconds: 2)}) async {
    for (final host in const ['8.8.8.8', '1.1.1.1']) {
      try {
        final s = await Socket.connect(host, 53, timeout: timeout);
        s.destroy();
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<bool> _push(String table, Map<String, Object?> row) async {
    if (apiUrl.isEmpty) return true;
    try {
      _client ??= http.Client();
      final base = apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
      final resp = await _client!
          .post(Uri.parse('$base/$table'),
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
      if (!await hasInternet()) return (0, 0);
      var ok = 0, total = 0;
      for (final table in kSyncTables) {
        for (final row in await repo.unsynced(table)) {
          total++;
          if (await _push(table, row)) {
            await repo.markSynced(table, row);
            ok++;
          }
        }
      }
      if (ok > 0) await repo.purgeDeleted();
      return (ok, total);
    } catch (_) {
      return (0, 0);
    } finally {
      _running = false;
    }
  }
}
