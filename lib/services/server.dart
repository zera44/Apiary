import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;

import '../data/first_login.dart';

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

  /// Перший вхід: потрібен вибір людини (головний екран показує вікно).
  static final ValueNotifier<FirstLoginState?> choice = ValueNotifier(null);

  /// Підключений сервер (null - не налаштовано або не увійшли).
  static SupabaseApi? get api => _api;

  /// Тести: інший сховок входу.
  static Future<SessionStore> Function() sessionStore = SessionStore.forApp;

  static void _attach(Repository repo, SupabaseApi? api, [AuthService? auth]) {
    _api = api;
    final sync = SyncService.current;
    sync?.api = api;
    if (sync != null && auth != null) {
      // вхід на сервер відкликали - тихо увійти знову; не було мережі - знову
      // спробувати, коли застосунок перевірятиме розклад
      sync.onSignedOut = () async {
        await (await sessionStore()).write(null);
        _attach(repo, null, auth);
        await connect(repo, auth);
      };
      sync.reconnect = auth.user == null ? null : () => connect(repo, auth);
      sync.onNeedsChoice = () async {
        final a = _api;
        if (a != null && choice.value == null) await _firstLogin(repo, a);
      };
    }
    SharingService.current = SharingService(api, repo);
    unawaited(SyncService.current?.refreshInfo());
  }

  /// Під час запуску: збережений вхід на сервер. Якщо його немає, а в
  /// Google ми увійшли (оновились із версії без сервера), - тихо увійти.
  static Future<void> start(Repository repo, AuthService auth) async {
    final config = AppConfig.current;
    if (!config.syncConfigured || auth.user == null) {
      _attach(repo, null, auth);
      return;
    }
    try {
      final restored = await SupabaseApi.restore(config, await sessionStore());
      if (restored != null && restored.session.email == auth.user!.email.toLowerCase()) {
        _attach(repo, restored, auth);
        await _firstLogin(repo, restored);
        return;
      }
      await connect(repo, auth);
    } catch (e) {
      debugPrint('Сервер: $e');
      _attach(repo, null, auth);
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
      _attach(repo, api, auth);
      await _firstLogin(repo, api);
      return true;
    } on SyncOffline catch (e) {
      debugPrint('Сервер: $e');
      return false;
    }
  }

  /// Чи потрібен вибір (дані і тут, і на сервері; інший акаунт). Ні -
  /// синхронізуватись.
  static Future<void> _firstLogin(Repository repo, SupabaseApi api) async {
    final FirstLoginState state;
    try {
      state = await FirstLogin(repo, api).prepare();
    } on SyncOffline catch (e) {
      // без мережі - синхронізація чекатиме, а перевірку повторить розклад
      debugPrint('Перший вхід: $e');
      return;
    }
    choice.value = state == FirstLoginState.ready ? null : state;
    if (state == FirstLoginState.ready) unawaited(SyncService.now());
  }

  /// Людина вибрала - виконати й синхронізуватись.
  static Future<void> choose(Repository repo, FirstLoginChoice c) async {
    final api = _api;
    if (api == null) return;
    await FirstLogin(repo, api).apply(c);
    choice.value = null;
    await SyncService.current?.syncNow();
  }

  /// Вихід: забути вхід на сервер (дані на телефоні лишаються).
  static Future<void> signOut(Repository repo) async {
    final api = _api;
    _attach(repo, null);
    choice.value = null;
    // вийшли свідомо - не входити знову самим
    SyncService.current
      ?..reconnect = null
      ..onSignedOut = null;
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
