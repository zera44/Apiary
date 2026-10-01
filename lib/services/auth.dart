import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
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

/// Вхід у застосунок (обов'язковий). Після першого входу користувач
/// запам'ятовується на пристрої, тож далі застосунок працює й офлайн.
abstract class AuthService {
  AppUser? get user;

  /// Чи можна в цій збірці увійти (задано ідентифікатори Google). Якщо ні —
  /// застосунок працює без входу (тестові збірки до налаштування Google).
  bool get configured;

  /// Інтерактивний вхід. Кидає [SignInCancelled], якщо користувач
  /// передумав, або інший виняток, якщо вхід не вдався.
  Future<AppUser> signIn();

  Future<void> signOut();
}

/// Вхід через Google.
///
/// * Android — пакет google_sign_in (системне вікно вибору акаунта).
/// * Windows — google_sign_in там не працює, тож стандартний для
///   настільних програм спосіб Google: браузер + повернення на
///   http://127.0.0.1:порт (OAuth 2.0 з PKCE).
///
/// Ідентифікатори клієнтів OAuth задаються під час збірки (див. README,
/// розділ «Вхід через Google»):
///   APIARY_GOOGLE_SERVER_CLIENT_ID     — Web client ID (для Android)
///   APIARY_GOOGLE_DESKTOP_CLIENT_ID    — Desktop client ID (для Windows)
///   APIARY_GOOGLE_DESKTOP_CLIENT_SECRET — його «secret» (для настільних
///     програм Google не вважає його таємницею)
class GoogleAuthService implements AuthService {
  static const serverClientId = String.fromEnvironment('APIARY_GOOGLE_SERVER_CLIENT_ID');
  static const desktopClientId = String.fromEnvironment('APIARY_GOOGLE_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('APIARY_GOOGLE_DESKTOP_CLIENT_SECRET');

  final File _store;
  AppUser? _user;
  bool _googleReady = false;

  GoogleAuthService._(this._store);

  @override
  AppUser? get user => _user;

  @override
  bool get configured => Platform.isWindows || Platform.isLinux || Platform.isMacOS
      ? desktopClientId.isNotEmpty
      : serverClientId.isNotEmpty;

  /// Відкрити сервіс і відновити збереженого користувача.
  static Future<GoogleAuthService> open() async {
    final dir = await getApplicationSupportDirectory();
    final s = GoogleAuthService._(File(p.join(dir.path, 'account.json')));
    try {
      if (s._store.existsSync()) s._user = AppUser.fromJson(jsonDecode(s._store.readAsStringSync()));
    } catch (_) {
      s._user = null; // пошкоджений файл — просто увійти ще раз
    }
    return s;
  }

  @override
  Future<AppUser> signIn() async {
    final u = Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? await _desktopSignIn()
        : await _mobileSignIn();
    _user = u;
    final tmp = File('${_store.path}.tmp');
    await tmp.writeAsString(jsonEncode(u.toJson()), flush: true);
    await tmp.rename(_store.path);
    return u;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    try {
      if (_store.existsSync()) await _store.delete();
    } catch (_) {}
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
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
      return AppUser(id: acc.id, email: acc.email, name: acc.displayName ?? acc.email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInCancelled();
      rethrow;
    }
  }

  // -------------------------------------------------------------------
  // Windows: OAuth 2.0 для настільних програм (браузер + loopback + PKCE)
  // -------------------------------------------------------------------

  Future<AppUser> _desktopSignIn() async {
    if (desktopClientId.isEmpty) {
      throw StateError('Вхід через Google не налаштовано в цій збірці');
    }
    final verifier = _randomString(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomString(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': desktopClientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      });
      await _openBrowser(url);

      final code = await _awaitCode(server, state).timeout(const Duration(minutes: 5),
          onTimeout: () => throw const SignInCancelled());

      final resp = await http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': code,
        'client_id': desktopClientId,
        if (desktopClientSecret.isNotEmpty) 'client_secret': desktopClientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw HttpException('Google відповів ${resp.statusCode}');
      }
      final idToken = (jsonDecode(resp.body) as Map)['id_token'];
      if (idToken is! String) throw const FormatException('немає id_token');
      final u = userFromIdToken(idToken);
      if (u == null) throw const FormatException('некоректний id_token');
      return u;
    } finally {
      await server.close(force: true);
    }
  }

  /// Чекати повернення з браузера: ?code=…&state=… (або ?error=…).
  static Future<String> _awaitCode(HttpServer server, String state) async {
    await for (final req in server) {
      final q = req.uri.queryParameters;
      if (!q.containsKey('code') && !q.containsKey('error')) {
        req.response.statusCode = 404; // favicon тощо
        await req.response.close();
        continue;
      }
      final ok = q['state'] == state && q['code'] != null;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;'
          'text-align:center;padding-top:15vh">'
          '${ok ? 'Вхід виконано. Можна повернутися до Vulyk.' : 'Вхід скасовано.'}</body>');
      await req.response.close();
      if (!ok) throw const SignInCancelled();
      return q['code']!;
    }
    throw const SignInCancelled();
  }

  static Future<void> _openBrowser(Uri url) async {
    final s = url.toString();
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', s]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [s]);
    } else {
      await Process.run('xdg-open', [s]);
    }
  }

  static String _randomString(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return String.fromCharCodes(List.generate(n, (_) => chars.codeUnitAt(r.nextInt(chars.length))));
  }

  /// Дані користувача з id_token (JWT, отриманого напряму від Google по
  /// HTTPS, тож підпис окремо не перевіряємо).
  static AppUser? userFromIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is! Map) return null;
      return AppUser.fromJson({
        'id': payload['sub'],
        'email': payload['email'] ?? '',
        'name': payload['name'],
      });
    } catch (_) {
      return null;
    }
  }
}
