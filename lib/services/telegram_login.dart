import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'supabase_api.dart';

/// Технічна пошта акаунта, створеного входом через Telegram: не справжня,
/// на неї нічого не надсилається (див. supabase/README.md).
const telegramEmailDomain = 'tg.vulyk.invalid';

bool isTelegramEmail(String email) => email.toLowerCase().endsWith('@$telegramEmailDomain');

/// Помилка запиту до функції входу. [code] - що сталося: `wrong_pin`,
/// `locked` (див. [retryIn]), `bad_pin` / `new_pin_required` (див.
/// [message]), `too_many`, `used`, `offline`, `server`…
class TelegramApiError implements Exception {
  final String code;
  final int status;
  final int? retryIn;
  final String? message;
  const TelegramApiError(this.code, {this.status = 0, this.retryIn, this.message});

  bool get offline => code == 'offline';

  @override
  String toString() => 'TelegramApiError($code${message == null ? '' : ': $message'})';
}

/// Нова заявка на вхід: [match] - число, яке людина вибирає в боті;
/// [url] - посилання на бота з номером заявки.
class TelegramRequest {
  final String id;
  final int match;
  final Uri url;
  const TelegramRequest({required this.id, required this.match, required this.url});
}

/// Що робити після підтвердження в Telegram.
enum TelegramNext { pinSetup, pin, ready, locked }

/// Стан заявки (опитування): `new`, `opened`, `matched`, `approved`,
/// `done`, `cancelled`, `expired`, `unknown`.
class TelegramPoll {
  final String state;
  final TelegramNext? next;
  final int retryIn;
  final String device;

  /// Власник натиснув «Це я» під повідомленням про відновлення доступу.
  final bool recoveryOk;
  const TelegramPoll(this.state, {this.next, this.retryIn = 0, this.device = '', this.recoveryOk = false});

  bool get approved => state == 'approved';
  bool get dead => state == 'cancelled' || state == 'expired' || state == 'unknown';
}

/// Вхід виконано: сесія Supabase й назва акаунта.
class TelegramSignedIn {
  final SupabaseSession session;
  final String name;
  const TelegramSignedIn(this.session, this.name);
}

/// Стан PIN акаунта (налаштування).
class PinStatus {
  /// `none` (не встановлено), `on`, `off`, `locked`.
  final String state;
  final int retryIn;
  final DateTime? disableAt;
  final String? phone;
  final bool telegramOnly;
  const PinStatus(this.state, {this.retryIn = 0, this.disableAt, this.phone, this.telegramOnly = false});

  bool get on => state == 'on' || state == 'locked';
}

/// Секрет заявки: 32 випадкові байти. Знає лише цей телефон; на сервер іде
/// тільки відбиток ([loginSecretHash]).
String newLoginSecret([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String loginSecretHash(String secret) => sha256.convert(utf8.encode(secret)).toString();

/// Запити до функції `telegram-auth` (supabase/functions/telegram-auth).
class TelegramAuthApi {
  final Uri base;
  final String anonKey;
  final http.Client _http;

  static const timeout = Duration(seconds: 20);

  TelegramAuthApi(this.base, this.anonKey, {http.Client? client}) : _http = client ?? http.Client();

  /// null - сервер не налаштовано (тестові збірки без Supabase).
  static TelegramAuthApi? of(AppConfig config, {http.Client? client}) {
    final b = config.supabaseBase;
    if (b == null || !config.syncConfigured) return null;
    return TelegramAuthApi(b.replace(path: '${b.path}/functions/v1/telegram-auth'), config.supabaseAnonKey.trim(),
        client: client);
  }

  Future<Map<String, Object?>> _post(Map<String, Object?> body, {String? accessToken}) async {
    final http.Response r;
    try {
      r = await _http
          .post(base,
              headers: {
                'apikey': anonKey,
                'Content-Type': 'application/json',
                // без входу заголовка немає: функція ним розрізняє «увійти» й «прив'язати»
                'Authorization': ?(accessToken == null ? null : 'Bearer $accessToken'),
              },
              body: jsonEncode(body))
          .timeout(timeout);
    } on SocketException {
      throw const TelegramApiError('offline');
    } on TimeoutException {
      throw const TelegramApiError('offline');
    } on http.ClientException {
      throw const TelegramApiError('offline');
    }
    Map<String, Object?> j = const {};
    try {
      final d = jsonDecode(r.body);
      if (d is Map) j = d.cast<String, Object?>();
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300) return j;
    final code = j['error'] is String ? j['error']! as String : (r.statusCode >= 500 ? 'server' : 'http_${r.statusCode}');
    final retry = j['retry_in'];
    throw TelegramApiError(
      code,
      status: r.statusCode,
      retryIn: retry is num ? retry.toInt() : null,
      message: j['message'] is String ? j['message']! as String : null,
    );
  }

  /// Нова заявка. [accessToken] - прив'язати Telegram до акаунта, в якому
  /// вже увійшли (без нього - вхід через Telegram).
  Future<TelegramRequest> start({required String secret, required String device, String? accessToken}) async {
    final j = await _post({'action': 'start', 'secret_hash': loginSecretHash(secret), 'device': device},
        accessToken: accessToken);
    final id = j['id'], match = j['match'], url = j['url'];
    if (id is! String || match is! num || url is! String) throw const TelegramApiError('server');
    return TelegramRequest(id: id, match: match.toInt(), url: Uri.parse(url));
  }

  Future<TelegramPoll> poll(String id, String secret) async {
    try {
      final j = await _post({'action': 'poll', 'id': id, 'secret': secret});
      final next = switch (j['next']) {
        'pin_setup' => TelegramNext.pinSetup,
        'pin' => TelegramNext.pin,
        'ready' => TelegramNext.ready,
        'locked' => TelegramNext.locked,
        _ => null,
      };
      return TelegramPoll('${j['state']}',
          next: next,
          retryIn: (j['retry_in'] as num?)?.toInt() ?? 0,
          device: '${j['device'] ?? ''}',
          recoveryOk: j['recovery_ok'] == true);
    } on TelegramApiError catch (e) {
      if (e.status == 404) return const TelegramPoll('unknown');
      rethrow;
    }
  }

  /// Попросити код відновлення: бот надішле його власнику в Telegram разом із
  /// кнопкою «Це я». Код діє 5 хвилин. Повертає, скільки секунд він діє.
  Future<int> recoverySend(String id, String secret) async {
    final j = await _post({'action': 'recovery_send', 'id': id, 'secret': secret});
    return (j['expires_in'] as num?)?.toInt() ?? 300;
  }

  /// Завершити вхід. Новий акаунт - з [pin]; наявний із PIN - з [pin], з
  /// [recovery] (код із Telegram) або після кнопки «Це я» ([recoveryConfirmed]);
  /// у двох останніх випадках обов'язковий і [newPin].
  Future<TelegramSignedIn> finish(String id, String secret,
      {String? pin, String? recovery, String? newPin, bool recoveryConfirmed = false}) async {
    final j = await _post({
      'action': 'finish',
      'id': id,
      'secret': secret,
      'pin': ?pin,
      'recovery': ?recovery,
      'new_pin': ?newPin,
      if (recoveryConfirmed) 'recovery_confirmed': true,
    });
    final s = SupabaseSession.fromJson(j['session']);
    if (s == null) throw const TelegramApiError('server');
    String name = '';
    final user = (j['session'] as Map)['user'];
    if (user is Map && user['user_metadata'] is Map) {
      final n = (user['user_metadata'] as Map)['full_name'];
      if (n is String) name = n.trim();
    }
    return TelegramSignedIn(s, name);
  }

  Future<PinStatus> pinStatus(String accessToken) async {
    final j = await _post({'action': 'pin_status'}, accessToken: accessToken);
    final tg = j['telegram'];
    final at = j['disable_at'];
    return PinStatus(
      '${j['state']}',
      retryIn: (j['retry_in'] as num?)?.toInt() ?? 0,
      disableAt: at is String ? DateTime.tryParse(at) : null,
      phone: tg is Map && tg['phone'] is String ? tg['phone'] as String : null,
      telegramOnly: j['telegram_only'] == true,
    );
  }

  /// Встановити або змінити PIN.
  Future<void> pinSet(String accessToken, {String? current, required String newPin}) async {
    await _post({'action': 'pin_set', 'pin': ?current, 'new_pin': newPin}, accessToken: accessToken);
  }

  /// Перевірити PIN перед чутливою дією. Невірний - [TelegramApiError].
  Future<void> pinCheck(String accessToken, String pin) async {
    await _post({'action': 'pin_check', 'pin': pin}, accessToken: accessToken);
  }

  /// Вимкнути PIN. Акаунт лише з Telegram - з відстрочкою (повертає, коли
  /// вимкнеться); інакше null (вимкнено одразу).
  Future<DateTime?> pinDisable(String accessToken, String pin) async {
    final j = await _post({'action': 'pin_disable', 'pin': pin}, accessToken: accessToken);
    final at = j['disable_at'];
    return at is String ? DateTime.tryParse(at) : null;
  }

  Future<void> signOutEverywhere(String accessToken) async {
    await _post({'action': 'sign_out_everywhere'}, accessToken: accessToken);
  }
}
