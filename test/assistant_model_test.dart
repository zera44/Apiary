import 'dart:convert';

import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ModelTurn text(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

ModelTurn tool(String id, String name, [Map<String, dynamic> input = const {}]) => ModelTurn([
      {'type': 'thinking', 'thinking': '', 'signature': 'sig-$id'},
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
    ], 'tool_use');

void main() {
  group('вибір моделі', () {
    test('без адреси - demo', () {
      expect(AssistantModel.fromConfig(url: ''), isA<DemoAssistantModel>());
      expect(AssistantModel.fromConfig(url: '').isRemote, isFalse);
    });

    test('незахищена адреса - теж demo (лише https)', () {
      expect(AssistantModel.fromConfig(url: 'http://example.com/functions/v1/assistant'),
          isA<DemoAssistantModel>());
    });

    test('https-адреса - посередник', () {
      final m = AssistantModel.fromConfig(url: 'https://x.supabase.co/functions/v1/assistant');
      expect(m, isA<RemoteAssistantModel>());
      expect((m as RemoteAssistantModel).url.toString(),
          'https://x.supabase.co/functions/v1/assistant');
    });
  });

  group('посередник', () {
    final url = Uri.parse('https://x.supabase.co/functions/v1/assistant');

    test('надсилає розмову й тестовий код; розбирає відповідь', () async {
      late http.Request seen;
      final m = RemoteAssistantModel(url, 'code-123', client: MockClient((r) async {
        seen = r;
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Добрий день!'}
              ],
              'stop_reason': 'end_turn',
            })),
            200);
      }));
      final t = await m.send([
        {'role': 'user', 'content': 'Привіт'}
      ]);
      expect(t.text, 'Добрий день!');
      expect(t.stopReason, 'end_turn');
      expect(seen.headers[RemoteAssistantModel.tokenHeader], 'code-123');
      expect(jsonDecode(seen.body), {
        'messages': [
          {'role': 'user', 'content': 'Привіт'}
        ]
      });
    });

    Future<AssistantFailure> failure(Future<http.Response> Function(http.Request) h) async {
      final m = RemoteAssistantModel(url, 'c', client: MockClient(h));
      try {
        await m.send([
          {'role': 'user', 'content': 'x'}
        ]);
      } on AssistantException catch (e) {
        return e.kind;
      }
      fail('мала бути помилка');
    }

    test('відповіді сервера -> зрозумілі помилки', () async {
      expect(await failure((_) async => http.Response('', 401)), AssistantFailure.unauthorized);
      expect(await failure((_) async => http.Response('', 422)), AssistantFailure.stepLimit);
      expect(await failure((_) async => http.Response('', 503)), AssistantFailure.busy);
      expect(await failure((_) async => http.Response('', 500)), AssistantFailure.server);
      expect(await failure((_) async => throw http.ClientException('no net')),
          AssistantFailure.offline);
    });

    test('повторювати можна лише зв\'язок і перевантаження', () {
      expect(const AssistantException(AssistantFailure.offline).retryable, isTrue);
      expect(const AssistantException(AssistantFailure.busy).retryable, isTrue);
      expect(const AssistantException(AssistantFailure.unauthorized).retryable, isFalse);
    });
  });

  group('цикл інструментів', () {
    test('demo без сценарію відповідає поясненням', () async {
      final s = AssistantSession(DemoAssistantModel());
      final r = await s.ask('Привіт');
      expect(r.text, DemoAssistantModel.demoReply);
      expect(s.messages.length, 2);
    });

    test('інструмент виконується, результат - назад моделі, далі відповідь', () async {
      final model = DemoAssistantModel([tool('t1', 'apiaries_list'), text('У вас 2 пасіки.')]);
      final s = AssistantSession(model);
      final calls = <String>[];
      final r = await s.ask('Скільки пасік?', tools: (name, input) async {
        calls.add(name);
        return const ToolOutcome('[{"name":"Пасіка 1"},{"name":"Пасіка 2"}]');
      });
      expect(r.text, 'У вас 2 пасіки.');
      expect(calls, ['apiaries_list']);
      // другий запит: людина, відповідь моделі без змін (з thinking), результат
      final second = model.sent[1];
      expect(second.length, 3);
      expect((second[1]['content'] as List).first['signature'], 'sig-t1');
      final result = (second[2]['content'] as List).single as Map;
      expect(result['type'], 'tool_result');
      expect(result['tool_use_id'], 't1');
      expect(result.containsKey('is_error'), isFalse);
    });

    test('кілька інструментів за крок - усі результати одним повідомленням', () async {
      final both = ModelTurn([
        {'type': 'tool_use', 'id': 'a', 'name': 'stock_list', 'input': {}},
        {'type': 'tool_use', 'id': 'b', 'name': 'apiaries_list', 'input': {}},
      ], 'tool_use');
      final model = DemoAssistantModel([both, text('Готово')]);
      final s = AssistantSession(model);
      await s.ask('Що є?', tools: (n, _) async => ToolOutcome(n));
      final results = model.sent[1].last['content'] as List;
      expect([for (final r in results) r['tool_use_id']], ['a', 'b']);
    });

    test('помилка інструмента не ламає розмову - модель отримує is_error', () async {
      final model = DemoAssistantModel([tool('t1', 'find_hives'), text('Не знайшов.')]);
      final s = AssistantSession(model);
      final r = await s.ask('Знайди', tools: (_, _) async => throw StateError('db'));
      expect(r.text, 'Не знайшов.');
      final result = (model.sent[1].last['content'] as List).single as Map;
      expect(result['is_error'], isTrue);
    });

    test('не більше 6 кроків на повідомлення', () async {
      final model = DemoAssistantModel([for (var i = 0; i < 10; i++) tool('t$i', 'find_hives')]);
      final s = AssistantSession(model);
      var runs = 0;
      final r = await s.ask('Шукай без кінця', tools: (_, _) async {
        runs++;
        return const ToolOutcome('[]');
      });
      expect(r.stoppedAtLimit, isTrue);
      expect(runs, AssistantSession.maxSteps);
      expect(model.sent.length, AssistantSession.maxSteps);
      // розмову можна продовжувати: останнє - відповідь помічника
      expect(s.messages.last['role'], 'assistant');
    });

    test('відмова сервера за лімітом кроків - теж спокійна відповідь', () async {
      final s = AssistantSession(_Failing(AssistantFailure.stepLimit));
      final r = await s.ask('x');
      expect(r.stoppedAtLimit, isTrue);
    });

    test('немає зв\'язку - помилка, історія без недоставленого повідомлення', () async {
      final s = AssistantSession(DemoAssistantModel(), history: [
        {'role': 'user', 'content': 'Було'},
        {'role': 'assistant', 'content': 'Так'},
      ]);
      final offline = AssistantSession(_Failing(AssistantFailure.offline), history: s.messages);
      await expectLater(offline.ask('Нове'), throwsA(isA<AssistantException>()));
      expect(offline.messages.length, 2);
    });
  });
}

class _Failing implements AssistantModel {
  final AssistantFailure kind;
  _Failing(this.kind);
  @override
  bool get isRemote => true;
  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async =>
      throw AssistantException(kind);
}
