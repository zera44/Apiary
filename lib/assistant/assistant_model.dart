import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/app_config.dart';

/// Помічник «Пасічник»: обмін із посередником (supabase/functions/assistant).
///
/// Один виклик [AssistantModel.send] = один крок моделі. Розмова -
/// у форматі Anthropic Messages (role + content-блоки) і лише дописується:
/// відповіді моделі зберігаються без змін (разом із блоками thinking).

/// Відповідь моделі на один крок.
class ModelTurn {
  final List<Map<String, dynamic>> content;
  final String stopReason;
  const ModelTurn(this.content, this.stopReason);

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

  /// сервер чи модель перевантажені - повторити згодом
  busy,

  /// сервер не пустив (неправильний тестовий код)
  unauthorized,

  /// забагато кроків на одне повідомлення
  stepLimit,

  /// сервер не налаштовано (немає ключа) або інша помилка
  server,
}

class AssistantException implements Exception {
  final AssistantFailure kind;
  const AssistantException(this.kind);

  /// Чи варто повторити пізніше (черга).
  bool get retryable => kind == AssistantFailure.offline || kind == AssistantFailure.busy;

  @override
  String toString() => 'AssistantException($kind)';
}

abstract class AssistantModel {
  /// Чи це справжня модель (а не demo).
  bool get isRemote;

  Future<ModelTurn> send(List<Map<String, dynamic>> messages);

  /// Модель за налаштуваннями збірки: є адреса - посередник; немає - demo.
  static AssistantModel fromConfig({String url = assistantUrl, http.Client? client}) {
    final base = url.trim().isEmpty ? null : AppConfig.secureBase(url);
    if (base == null) return DemoAssistantModel();
    return RemoteAssistantModel(base, assistantTestToken, client: client);
  }

  /// --dart-define=APIARY_ASSISTANT_URL=https://<проєкт>.supabase.co/functions/v1/assistant
  static const assistantUrl = String.fromEnvironment('APIARY_ASSISTANT_URL');

  /// Тестовий код доступу (поки немає входу).
  static const assistantTestToken = String.fromEnvironment('APIARY_ASSISTANT_TEST_TOKEN');
}

/// Справжня модель через посередника.
class RemoteAssistantModel implements AssistantModel {
  final Uri url;
  final String token;
  final http.Client? client;
  final Duration timeout;
  RemoteAssistantModel(this.url, this.token,
      {this.client, this.timeout = const Duration(seconds: 60)});

  static const tokenHeader = 'x-apiary-assistant-token';

  @override
  bool get isRemote => true;

  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    final c = client ?? http.Client();
    http.Response r;
    try {
      r = await c
          .post(url,
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                tokenHeader: token,
              },
              body: jsonEncode({'messages': messages}))
          .timeout(timeout);
    } on SocketException {
      throw const AssistantException(AssistantFailure.offline);
    } on http.ClientException {
      throw const AssistantException(AssistantFailure.offline);
    } on TimeoutException {
      throw const AssistantException(AssistantFailure.offline);
    } finally {
      if (client == null) c.close();
    }
    switch (r.statusCode) {
      case 200:
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        return ModelTurn(
          [
            for (final b in (j['content'] as List? ?? const []))
              Map<String, dynamic>.from(b as Map)
          ],
          j['stop_reason'] as String? ?? 'end_turn',
        );
      case 401:
      case 403:
        throw const AssistantException(AssistantFailure.unauthorized);
      case 422:
        throw const AssistantException(AssistantFailure.stepLimit);
      case 429:
      case 503:
        throw const AssistantException(AssistantFailure.busy);
      default:
        throw const AssistantException(AssistantFailure.server);
    }
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

  static const demoReply = 'Я - Пасічник, поки в демо-режимі: сервер помічника не підключено.';

  @override
  bool get isRemote => false;

  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    sent.add([for (final m in messages) Map<String, dynamic>.from(m)]);
    if (_script.isNotEmpty) return _script.removeAt(0);
    return const ModelTurn([
      {'type': 'text', 'text': demoReply}
    ], 'end_turn');
  }
}
