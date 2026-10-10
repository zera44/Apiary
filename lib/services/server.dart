import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../data/repository.dart';
import '../data/sync_api.dart';
import '../data/sync_service.dart';
import 'app_config.dart';
import 'auth.dart';
import 'sharing.dart';
import 'supabase_api.dart';

/// Вхід на сервер синхронізації (Supabase) і підключення до нього
/// синхронізації та спільного доступу.
///
/// Вхід у застосунок - Google на телефоні ([AuthService]); вхід на сервер -
/// тим самим акаунтом: ID-токен Google міняється на вхід Supabase, який
/// далі сам оновлюється (його бачить і фонове завдання).
abstract final class Server {
  static SupabaseApi? _api;

  /// Підключений сервер (null - не налаштовано або не увійшли).
  static SupabaseApi? get api => _api;

  /// Тести: інший сховок входу.
  static Future<SessionStore> Function() sessionStore = SessionStore.forApp;

  static void _attach(Repository repo, SupabaseApi? api) {
    _api = api;
    SyncService.current?.api = api;
    SharingService.current = SharingService(api, repo);
    unawaited(SyncService.current?.refreshInfo());
  }

  /// Під час запуску: збережений вхід на сервер. Якщо його немає, а в
  /// Google ми увійшли (оновились із версії без сервера), - тихо увійти.
  static Future<void> start(Repository repo, AuthService auth) async {
    final config = AppConfig.current;
    if (!config.syncConfigured || auth.user == null) {
      _attach(repo, null);
      return;
    }
    try {
      final restored = await SupabaseApi.restore(config, await sessionStore());
      if (restored != null && restored.session.email == auth.user!.email.toLowerCase()) {
        _attach(repo, restored);
        unawaited(SyncService.now());
        return;
      }
      await connect(repo, auth);
    } catch (e) {
      debugPrint('Сервер: $e');
      _attach(repo, null);
    }
  }

  /// Після входу Google: увійти на сервер і одразу синхронізуватись.
  /// Без токена чи без зв'язку - тихо (спробуємо при наступному запуску).
  static Future<bool> connect(Repository repo, AuthService auth) async {
    final config = AppConfig.current;
    if (!config.syncConfigured) return false;
    final token = await auth.idToken();
    if (token == null) return false;
    try {
      final api = await SupabaseApi.signInWithGoogle(config, await sessionStore(), token);
      _attach(repo, api);
      unawaited(SyncService.now());
      return true;
    } on SyncOffline catch (e) {
      debugPrint('Сервер: $e');
      return false;
    }
  }

  /// Вихід: забути вхід на сервер (дані на телефоні лишаються).
  static Future<void> signOut(Repository repo) async {
    final api = _api;
    _attach(repo, null);
    try {
      if (api != null) {
        await api.signOut();
      } else if (AppConfig.current.syncConfigured) {
        await (await sessionStore()).write(null);
      }
    } catch (e) {
      debugPrint('Сервер (вихід): $e'); // вихід із застосунку це не зупиняє
    }
  }
}
