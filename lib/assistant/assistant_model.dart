import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/sync_api.dart' show SyncOffline, SyncSignedOut;
import '../services/app_config.dart';
import '../services/server.dart';
import '../services/supabase_api.dart';
import '../l10n/l10n.dart';

/// Помічник «Пасічник»: обмін із посередником (supabase/functions/assistant).
///
/// Один виклик [AssistantModel.send] = один крок моделі. Розмова -
/// у форматі Anthropic Messages (role + content-блоки) і лише дописується:
/// відповіді моделі зберігаються без змін (разом із блоками thinking).

/// Відповідь моделі на один крок.
class ModelTurn {
  final List<Map<String, dynamic>> content;
  final String stopReason;

  /// Хто відповідав (haiku / sonnet) - за ним персонаж у чаті.
  final String? model;

  /// Кого обрала людина, якщо сервер передав просте прохання іншому
  /// (Пасічник -> Ведмедик); null - відповідав обраний.
  final String? routedFrom;

  /// Хто не впорався, якщо сервер підняв питання на рівень вище
  /// (Ведмедик -> Пасічник -> Робопасічник); [model] - хто відповів.
  final String? escalatedFrom;
  const ModelTurn(this.content, this.stopReason,
      {this.model, this.routedFrom, this.escalatedFrom});

  /// Текст відповіді (усі текстові блоки).
  String get text => [
        for (final b in content)
          if (b['type'] == 'text') b['text'] as String
      ].join('\n').trim();

  /// Запити інструментів.
  List<Map<String, dynamic>> get toolUses =>
      [for (final b in content) if (b['type'] == 'tool_use') b];
}

enum AssistantFailure {
  /// немає інтернету чи сервер не відповів - можна в чергу й повторити
  offline,

  /// з'єднання є, але сервер не встиг відповісти (довга відповідь):
  /// повторюємо з паузою й лічимо спроби - не «немає інтернету»
  timeout,

  /// сервер чи модель перевантажені - повторити згодом
  busy,

  /// сервер не пустив: немає входу Google чи вхід відкликано
  unauthorized,

  /// денний ліміт запитів на людину вичерпано (до завтра)
  limit,

  /// забагато кроків на одне повідомлення
  stepLimit,

  /// сервер не налаштовано (немає ключа) або інша помилка
  server,
}

class AssistantException implements Exception {
  final AssistantFailure kind;
  const AssistantException(this.kind);

  /// Чи варто повторити пізніше (черга).
  bool get retryable => kind == AssistantFailure.offline ||
      kind == AssistantFailure.busy ||
      kind == AssistantFailure.timeout;

  @override
  String toString() => 'AssistantException($kind)';
}

/// Пошук у книгах з бджільництва (інструмент search_books): уміє справжня
/// модель через посередника; demo й тестові моделі - ні (інструмент
/// скаже, що книг немає).
abstract interface class BookSearch {
  /// {books: чи є книги в базі, results: [{book, author, year, chapter, page, text}]}.
  Future<Map<String, dynamic>> searchBooks(String query, {int limit = 5});
}

abstract class AssistantModel {
  /// Чи це справжня модель (а не demo).
  bool get isRemote;

  Future<ModelTurn> send(List<Map<String, dynamic>> messages);

  /// Модель за налаштуваннями збірки: є адреса - посередник; немає - demo.
  static AssistantModel fromConfig({
    String url = assistantUrl,
    http.Client? client,
    Future<Map<String, String>> Function()? options,
    AssistantTokenSource? tokenSource,
  }) {
    final base = url.trim().isEmpty ? null : AppConfig.secureBase(url);
    if (base == null) return DemoAssistantModel();
    return RemoteAssistantModel(base, tokenSource ?? serverTokenSource(),
        client: client, options: options);
  }

  /// --dart-define=APIARY_ASSISTANT_URL=https://<проєкт>.supabase.co/functions/v1/assistant
  static const assistantUrl = String.fromEnvironment('APIARY_ASSISTANT_URL');

  /// Токен входу на сервер для помічника: живий вхід застосунку, а коли його
  /// ще немає (запуск, фонове завдання) - збережений на телефоні. Без
  /// інтернету дійсний токен береться з телефона, мережа не потрібна.
  static AssistantTokenSource serverTokenSource() {
    SupabaseApi? restored;
    return ({bool force = false}) async {
      final api = Server.api ??
          (restored ??= await SupabaseApi.restore(AppConfig.current, await Server.sessionStore()));
      return api?.accessToken(force: force);
    };
  }
}

/// Дає токен входу (null - не увійшли). [force] - оновити, навіть якщо ще
/// дійсний (сервер відмовив).
typedef AssistantTokenSource = Future<String?> Function({bool force});

/// Справжня модель через посередника.
class RemoteAssistantModel implements AssistantModel, BookSearch {
  final Uri url;
  final AssistantTokenSource tokenSource;
  final http.Client? client;
  final Duration timeout;

  /// Вибір людини (модель, глибина) - додається до кожного запиту.
  final Future<Map<String, String>> Function()? options;
  RemoteAssistantModel(this.url, this.tokenSource,
      {this.client, this.timeout = const Duration(seconds: 150), this.options});

  /// Токен входу. Не вийшло дістати: без зв'язку - [AssistantFailure.offline]
  /// (повідомлення чекає в черзі), вхід відкликано чи його немає -
  /// [AssistantFailure.unauthorized].
  Future<String> _token({bool force = false}) async {
    final String? t;
    try {
      t = await tokenSource(force: force);
    } on SyncOffline {
      throw const AssistantException(AssistantFailure.offline);
    } on SyncSignedOut {
      throw const AssistantException(AssistantFailure.unauthorized);
    } on AssistantException {
      rethrow;
    } catch (_) {
      throw const AssistantException(AssistantFailure.server);
    }
    if (t == null || t.isEmpty) throw const AssistantException(AssistantFailure.unauthorized);
    return t;
  }

  /// POST до посередника з токеном входу. Відмова 401 - токен міг
  /// прострочитись: один раз беремо свіжий і повторюємо.
  Future<http.Response> _post(Object body, Duration limit) async {
    final c = client ?? http.Client();
    try {
      for (var attempt = 0;; attempt++) {
        final token = await _token(force: attempt > 0);
        final r = await c
            .post(url,
                headers: {
                  'Content-Type': 'application/json; charset=utf-8',
                  'Authorization': 'Bearer $token',
                },
                body: jsonEncode(body))
            .timeout(limit);
        if (r.statusCode == 401 && attempt == 0) continue;
        return r;
      }
    } on SocketException {
      throw const AssistantException(AssistantFailure.offline);
    } on http.ClientException {
      throw const AssistantException(AssistantFailure.offline);
    } on TimeoutException {
      throw const AssistantException(AssistantFailure.timeout);
    } finally {
      if (client == null) c.close();
    }
  }

  @override
  bool get isRemote => true;

  @override
  Future<Map<String, dynamic>> searchBooks(String query, {int limit = 5}) async {
    final r = await _post({'action': 'search_books', 'query': query, 'limit': limit},
        const Duration(seconds: 20));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
    throw AssistantException(_failureFor(r.statusCode));
  }

  /// Що означає відповідь сервера з помилкою.
  static AssistantFailure _failureFor(int status) => switch (status) {
        401 || 403 => AssistantFailure.unauthorized,
        422 => AssistantFailure.stepLimit,
        // 429 від посередника - лише денний ліміт (ліміт Anthropic він
        // віддає як 503)
        429 => AssistantFailure.limit,
        503 => AssistantFailure.busy,
        _ => AssistantFailure.server,
      };

  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    final extra = await options?.call() ?? const <String, String>{};
    final r = await _post({'messages': messages, ...extra}, timeout);
    if (r.statusCode != 200) throw AssistantException(_failureFor(r.statusCode));
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return ModelTurn(
      [
        for (final b in (j['content'] as List? ?? const []))
          Map<String, dynamic>.from(b as Map)
      ],
      j['stop_reason'] as String? ?? 'end_turn',
      model: j['model'] as String?,
      routedFrom: j['routed_from'] as String?,
      escalatedFrom: j['escalated_from'] as String?,
    );
  }
}

/// Demo-модель: без сервера (немає APIARY_ASSISTANT_URL) і в тестах.
/// Без сценарію - коротка відповідь-пояснення; зі сценарієм - заготовлені
/// кроки по черзі (зокрема виклики інструментів).
class DemoAssistantModel implements AssistantModel {
  final List<ModelTurn> _script;
  DemoAssistantModel([List<ModelTurn> script = const []]) : _script = [...script];

  /// Що надсилалося (для тестів).
  final List<List<Map<String, dynamic>>> sent = [];

  static String get demoReply => tr.assistantDemoReply;

  @override
  bool get isRemote => false;

  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    sent.add([for (final m in messages) Map<String, dynamic>.from(m)]);
    if (_script.isNotEmpty) return _script.removeAt(0);
    return ModelTurn([
      {'type': 'text', 'text': demoReply}
    ], 'end_turn');
  }
}
