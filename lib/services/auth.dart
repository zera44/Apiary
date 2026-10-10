import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Користувач, що увійшов через Google.
class AppUser {
  final String id;
  final String email;
  final String name;
  const AppUser({required this.id, required this.email, required this.name});

  Map<String, Object?> toJson() => {'id': id, 'email': email, 'name': name};

  static AppUser? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], email = j['email'];
    if (id is! String || id.isEmpty || email is! String) return null;
    final name = j['name'];
    return AppUser(id: id, email: email, name: name is String && name.isNotEmpty ? name : email);
  }
}

/// Вхід скасовано користувачем (закрив вікно Google) — не помилка.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Вхід у застосунок. Обов'язковий вибір на першому екрані: увійти через
/// Google або «Продовжити без входу» (гість — дані лише на цьому пристрої;
/// увійти й синхронізуватись можна пізніше, дані при цьому лишаються).
/// Вибір запам'ятовується, тож далі застосунок працює й офлайн.
abstract class AuthService {
  AppUser? get user;

  /// Обрано «Продовжити без входу» (і ще не входили).
  bool get guest;

  /// Запам'ятати «Продовжити без входу».
  Future<void> continueAsGuest();

  /// Чи можна в цій збірці увійти (задано ідентифікатори Google). Якщо ні —
  /// застосунок працює без входу (тестові збірки до налаштування Google).
  bool get configured;

  /// Інтерактивний вхід. Кидає [SignInCancelled], якщо користувач
  /// передумав, або інший виняток, якщо вхід не вдався.
  Future<AppUser> signIn();

  Future<void> signOut();

  /// ID-токен Google для входу на сервер синхронізації: після [signIn] -
  /// той, що видав вхід; інакше - тихо, без вікон (null - не вийшло).
  Future<String?> idToken();
}

/// Вхід через Google: пакет google_sign_in (системне вікно вибору акаунта).
///
/// Ідентифікатор клієнта OAuth задається під час збірки (див. README,
/// розділ «Вхід через Google»):
///   APIARY_GOOGLE_SERVER_CLIENT_ID — Web client ID
class GoogleAuthService implements AuthService {
  static const serverClientId = String.fromEnvironment('APIARY_GOOGLE_SERVER_CLIENT_ID');

  final File _store;
  AppUser? _user;
  bool _guest = false;
  bool _googleReady = false;
  String? _idToken;

  GoogleAuthService._(this._store);

  @override
  AppUser? get user => _user;

  @override
  bool get guest => _user == null && _guest;

  @override
  Future<void> continueAsGuest() async {
    _guest = true;
    await _write({'guest': true});
  }

  Future<void> _write(Map<String, Object?> json) async {
    final tmp = File('${_store.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(_store.path);
  }

  @override
  bool get configured => serverClientId.isNotEmpty;

  /// Відкрити сервіс і відновити збереженого користувача.
  static Future<GoogleAuthService> open() async {
    final dir = await getApplicationSupportDirectory();
    final s = GoogleAuthService._(File(p.join(dir.path, 'account.json')));
    try {
      if (s._store.existsSync()) {
        final j = jsonDecode(s._store.readAsStringSync());
        s._user = AppUser.fromJson(j);
        s._guest = s._user == null && j is Map && j['guest'] == true;
      }
    } catch (_) {
      s._user = null; // пошкоджений файл — просто увійти ще раз
    }
    return s;
  }

  @override
  Future<AppUser> signIn() async {
    final u = await _mobileSignIn();
    _user = u;
    _guest = false;
    await _write(u.toJson());
    return u;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _guest = false;
    _idToken = null;
    try {
      if (_store.existsSync()) await _store.delete();
    } catch (_) {}
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  @override
  Future<String?> idToken() async {
    final t = _idToken;
    if (t != null) {
      _idToken = null; // токен Google живе годину - вдруге беремо свіжий
      return t;
    }
    if (_user == null || serverClientId.isEmpty) return null;
    try {
      final g = GoogleSignIn.instance;
      if (!_googleReady) {
        await g.initialize(serverClientId: serverClientId);
        _googleReady = true;
      }
      final acc = await g.attemptLightweightAuthentication();
      return acc?.authentication.idToken;
    } catch (_) {
      return null;
    }
  }

  Future<AppUser> _mobileSignIn() async {
    if (serverClientId.isEmpty) {
      throw StateError('Вхід через Google не налаштовано в цій збірці');
    }
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(serverClientId: serverClientId);
      _googleReady = true;
    }
    try {
      final acc = await g.authenticate();
      _idToken = acc.authentication.idToken;
      return AppUser(id: acc.id, email: acc.email, name: acc.displayName ?? acc.email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInCancelled();
      rethrow;
    }
  }
}
