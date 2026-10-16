// Зведені сценарії помічника «Пасічник» від початку до кінця: застосунок
// (черга, інструменти, база) -> «сервер» -> фейкова модель із заготовленими
// викликами інструментів. «Сервер» тут - підставний HTTP (MockClient), що
// відповідає так само, як supabase/functions/assistant (коди 200 / 401 /
// 422 / 503); сам сервер перевіряють тести на Node
// (supabase/tests/assistant*.test.ts).
//
// Окремі частини докладніше - у test/assistant_*_test.dart; карта
// сценаріїв -> тестів - у supabase/functions/assistant/README.md.
import 'dart:convert';

import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_session.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const goodCode = 'test-code-0123456789';

/// Підставний сервер: перевіряє тестовий код, рахує кроки (як index.ts) і
/// віддає заготовлені відповіді моделі.
class FakeServer {
  final List<Object> script; // Map (відповідь моделі) або int (код помилки)
  FakeServer(this.script);
  final requests = <List<dynamic>>[];
  bool down = false;

  http.Client get client => MockClient((req) async {
        if (down) throw http.ClientException('no network');
        if (req.headers[RemoteAssistantModel.tokenHeader] != goodCode) {
          return http.Response('{"error":"unauthorized"}', 401);
        }
        final messages = (jsonDecode(req.body) as Map)['messages'] as List;
        requests.add(messages);
        // кроки з інструментами після останнього повідомлення людини
        var steps = 0;
        for (final m in messages.reversed) {
          final c = m['content'];
          if (m['role'] == 'user' && (c is String || (c as List).any((b) => b['type'] != 'tool_result'))) {
            break;
          }
          if (m['role'] == 'assistant' && c is List && c.any((b) => b['type'] == 'tool_use')) steps++;
        }
        if (steps >= 6) return http.Response('{"error":"step_limit"}', 422);
        final next = script.removeAt(0);
        if (next is int) return http.Response('{"error":"busy","retry":true}', next);
        return http.Response.bytes(utf8.encode(jsonEncode(next)), 200);
      });
}

Map<String, dynamic> text(String t) => {
      'content': [
        {'type': 'text', 'text': t}
      ],
      'stop_reason': 'end_turn',
    };

Map<String, dynamic> tool(String name, Map<String, dynamic> input) => {
      'content': [
        {'type': 'tool_use', 'id': 'tu-$name-${input.hashCode}', 'name': name, 'input': input}
      ],
      'stop_reason': 'tool_use',
    };

void main() {
  late Repository repo;
  late AssistantStore store;
  late FakeServer server;
  late bool online;
  late DateTime clock;
  late List<NavTarget> opened;
  late Map<String, String>? Function(PendingWrite) human;
  late String hive5;

  AssistantQueue queue({String code = goodCode, bool chatOpen = true}) {
    final q = AssistantQueue(
      repo,
      store,
      RemoteAssistantModel(Uri.parse('https://x.supabase.co/functions/v1/assistant'), code,
          client: server.client),
      isOnline: () async => online,
      onlineChanges: const Stream.empty(),
      now: () => clock,
    );
    if (chatOpen) {
      q.presenter = (w) async => human(w);
      q.navigator = (t) async {
        opened.add(t);
        return true;
      };
    }
    return q;
  }

  Future<List<ChatItem>> chat() => store.items();
  Future<String> lastReply() async => (await chat()).lastWhere((i) => i.role == ChatRole.assistant).text;
  Map<String, dynamic> lastToolResult() {
    final m = server.requests.last.last as Map;
    return jsonDecode(((m['content'] as List).single as Map)['content'] as String) as Map<String, dynamic>;
  }

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    await repo.init();
    store = AssistantStore(repo.db);
    online = true;
    clock = DateTime(2026, 5, 10, 12);
    opened = [];
    human = (w) => {for (final f in w.fields) f.key: f.value}; // «Так»
    final a = await repo.addApiary('Біля хати');
    hive5 = await repo.addElement(a, 0, 0, label: 'Вулик 5');
    final force = await repo.addParameter('Сила', unit: 'вуличок', dataType: DataTypes.int_);
    await repo.setAttachedParameters([force], EntityRef.element(hive5));
  });
  tearDown(() async => repo.db.close());

  test('навігація: «відкрий склад» - екран відкрито', () async {
    server = FakeServer([tool('open_screen', {'screen': 'stock'}), text('Відкрив склад.')]);
    await queue().submit('Відкрий склад');
    expect(opened.single.screen, 'stock');
    expect(await lastReply(), 'Відкрив склад.');
  });

  test('пошук: «які вулики пора оглянути» - модель отримує короткий список', () async {
    final period = (await repo.baseParameterId('hive', 'visit_period'))!;
    await repo.addParameterRecord(period, '7', EntityRef.element(hive5));
    await repo.markVisited(EntityRef.element(hive5), when: DateTime(2026, 4, 1));
    server = FakeServer([tool('find_hives', {'due': 'overdue'}), text('Пора оглянути вулик 5.')]);
    await queue().submit('Які вулики пора оглянути?');
    final r = lastToolResult();
    expect(r['count'], 1);
    expect(r['hives'][0]['name'], 'Вулик 5');
    expect(await lastReply(), 'Пора оглянути вулик 5.');
  });

  test('запис із «Так» - записано, модель знає «підтверджено»; «Скасувати» - як було', () async {
    final undo = <UndoEntry>[];
    server = FakeServer([
      tool('record_inspection', {'hive_id': '5', 'values': {'Сила': '9'}}),
      text('Записав.'),
    ]);
    final q = queue()..onUndoable = undo.add;
    await q.submit('Запиши силу 9 у п\'ятий');
    expect(lastToolResult()['status'], 'підтверджено');
    final force = (await repo.listParameters()).firstWhere((p) => p.name == 'Сила').id;
    expect((await repo.latestParameterValues(EntityRef.element(hive5)))[force], '9');
    await undo.single.undo();
    expect((await repo.latestParameterValues(EntityRef.element(hive5)))[force], isNull);
  });

  test('запис із «Ні» - нічого не змінилось, модель знає «відхилено»', () async {
    human = (_) => null;
    server = FakeServer([
      tool('add_finance_entry', {'kind': 'expense', 'amount': 500}),
      text('Добре, не записую.'),
    ]);
    await queue().submit('Запиши витрату 500');
    expect(lastToolResult()['status'], 'відхилено');
    expect(await repo.db.query('fin_ops'), isEmpty);
  });

  test('черга: офлайн -> онлайн, по порядку', () async {
    server = FakeServer([text('Перша'), text('Друга')]);
    final q = queue();
    online = false;
    expect(await q.submit('Раз'), isFalse);
    expect(await q.submit('Два'), isFalse);
    expect(server.requests, isEmpty);
    online = true;
    await q.process();
    expect([for (final i in await chat()) i.text], ['Раз', 'Два', 'Перша', 'Друга']);
  });

  test('черга: перезапуск застосунку з непорожньою чергою', () async {
    server = FakeServer([text('Отримав після перезапуску')]);
    online = false;
    await queue().submit('Не загубись');
    // «перезапуск»: нова черга на тій самій базі
    online = true;
    final q = queue();
    await q.start();
    await q.process();
    q.stop();
    expect(await lastReply(), 'Отримав після перезапуску');
  });

  test('черга: повтор після збою сервера', () async {
    server = FakeServer([503, text('Вдалося з другого разу')]);
    final q = queue();
    await q.submit('Питання');
    expect((await chat()).single.status, ChatStatus.queued);
    clock = clock.add(const Duration(minutes: 1));
    await q.process();
    expect(await lastReply(), 'Вдалося з другого разу');
  });

  test('черга: видалення до відправки', () async {
    server = FakeServer([]);
    final q = queue();
    online = false;
    await q.submit('Передумав');
    expect(await q.remove((await chat()).single.id), isTrue);
    online = true;
    await q.process();
    expect(await chat(), isEmpty);
    expect(server.requests, isEmpty);
  });

  test('відповідь із черги не відкриває екран сама - кнопка «Відкрити»', () async {
    server = FakeServer([tool('open_screen', {'screen': 'finance'}), text('Ось фінанси.')]);
    final q = queue();
    online = false;
    await q.submit('Відкрий фінанси');
    online = true;
    await q.process();
    expect(opened, isEmpty);
    expect((await chat()).last.offeredNav.single.screen, 'finance');
  });

  test('зупинка після 6 кроків', () async {
    server = FakeServer([for (var i = 0; i < 10; i++) tool('stock_list', {'query': '$i'})]);
    await queue().submit('Шукай без кінця');
    expect(server.requests.length, AssistantSession.maxSteps);
    expect(await lastReply(), AssistantSession.limitText);
  });

  test('неправильний тестовий код - сервер відмовляє, «не надіслано» без повторів', () async {
    server = FakeServer([text('не має дійти')]);
    await queue(code: 'wrong').submit('Привіт');
    final it = (await chat()).single;
    expect(it.status, ChatStatus.failed);
    expect(it.error, 'unauthorized');
    expect(server.requests, isEmpty);
  });
}
