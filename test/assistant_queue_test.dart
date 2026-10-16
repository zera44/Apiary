import 'dart:convert';

import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/services/background.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ModelTurn say(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

ModelTurn use(String id, String name, Map<String, dynamic> input) => ModelTurn([
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input}
    ], 'tool_use');

/// Фейкова модель: відповіді за сценарієм, перед ними - можливі збої.
class FakeModel implements AssistantModel {
  final List<Object> script; // ModelTurn або AssistantFailure
  FakeModel(this.script);
  final sent = <List<Map<String, dynamic>>>[];
  @override
  bool get isRemote => true;
  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    sent.add(jsonDecode(jsonEncode(messages)).cast<Map<String, dynamic>>());
    final next = script.removeAt(0);
    if (next is AssistantFailure) throw AssistantException(next);
    return next as ModelTurn;
  }
}

void main() {
  late Repository repo;
  late AssistantStore store;
  late DateTime clock;
  late bool online;
  late int backgroundScheduled;

  AssistantQueue queue(AssistantModel m) => AssistantQueue(repo, store, m,
      isOnline: () async => online,
      onlineChanges: const Stream.empty(),
      now: () => clock,
      scheduleBackground: () async => backgroundScheduled++);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    await repo.init();
    store = AssistantStore(repo.db);
    clock = DateTime(2026, 5, 10, 12);
    online = true;
    backgroundScheduled = 0;
  });
  tearDown(() async => repo.db.close());

  Future<List<String>> statuses() async =>
      [for (final i in await store.items()) '${i.role}:${i.status}:${i.text}'];

  test('є зв\'язок - відповідь одразу, розмова збережена для наступного питання', () async {
    final m = FakeModel([say('Привіт!'), say('У вас 2 пасіки.')]);
    final q = queue(m);
    expect(await q.submit('Привіт'), isTrue);
    expect(await statuses(), ['user:sent:Привіт', 'assistant::Привіт!']);
    await q.submit('Скільки пасік?');
    // друге питання йде з усією попередньою розмовою
    expect(m.sent.last.length, 3);
    expect((await store.history()).length, 4);
  });

  test('без зв\'язку - «чекає на інтернет», з\'явився - надіслано по порядку', () async {
    final m = FakeModel([say('Перша'), say('Друга')]);
    final q = queue(m);
    online = false;
    expect(await q.submit('Раз'), isFalse);
    expect(await q.submit('Два'), isFalse);
    expect(m.sent, isEmpty);
    expect(await statuses(), ['user:queued:Раз', 'user:queued:Два']);
    expect(backgroundScheduled, greaterThan(0)); // і фонове завдання

    online = true;
    await q.process();
    expect(await statuses(),
        ['user:sent:Раз', 'user:sent:Два', 'assistant::Перша', 'assistant::Друга']);
    // питання йшли по черзі: друге - вже з відповіддю на перше
    expect(m.sent[0].last['content'], startsWith('Раз'));
    expect(m.sent[1].last['content'], startsWith('Два'));
    expect(m.sent[1].length, 3);
  });

  test('перезапуск застосунку з непорожньою чергою - черга не губиться', () async {
    online = false;
    await queue(FakeModel([])).submit('Запиши огляд');
    // «закрили» посеред відправки
    final id = (await store.items()).single.id;
    await store.claim(id);
    // новий запуск: інша черга, та сама база
    online = true;
    final m = FakeModel([say('Готово')]);
    final q = queue(m);
    await q.start();
    await q.process();
    q.stop();
    expect(await statuses(), ['user:sent:Запиши огляд', 'assistant::Готово']);
  });

  test('збій сервера - повтор після паузи; після 5 невдач - «не надіслано», «Повторити»', () async {
    final m = FakeModel([
      AssistantFailure.busy,
      AssistantFailure.busy,
      AssistantFailure.busy,
      AssistantFailure.busy,
      AssistantFailure.busy,
      say('Нарешті'),
    ]);
    final q = queue(m);
    await q.submit('Питання');
    var it = (await store.items()).single;
    expect(it.status, ChatStatus.queued);
    expect(it.attempts, 1);
    // до кінця паузи - не повторює
    await q.process();
    expect(m.sent.length, 1);
    for (var i = 0; i < 4; i++) {
      clock = clock.add(const Duration(hours: 1));
      await q.process();
    }
    it = (await store.items()).single;
    expect(it.status, ChatStatus.failed);
    expect(m.sent.length, AssistantQueue.maxAttempts);
    await q.retry(it.id);
    expect(await statuses(), ['user:sent:Питання', 'assistant::Нарешті']);
  });

  test('неправильний тестовий код - одразу «не надіслано» (без повторів)', () async {
    final m = FakeModel([AssistantFailure.unauthorized]);
    await queue(m).submit('x');
    final it = (await store.items()).single;
    expect(it.status, ChatStatus.failed);
    expect(it.error, 'unauthorized');
    expect(m.sent.length, 1);
  });

  test('видалити з черги до відправки - і нічого не піде', () async {
    online = false;
    final q = queue(FakeModel([]));
    await q.submit('Не треба');
    final id = (await store.items()).single.id;
    expect(await q.remove(id), isTrue);
    online = true;
    await q.process();
    expect(await store.items(), isEmpty);
  });

  test('зв\'язок зник посеред відправки - повідомлення лишається в черзі, решта чекає', () async {
    final m = FakeModel([AssistantFailure.offline, say('Перша'), say('Друга')]);
    final q = queue(m);
    await q.submit('Раз');
    await q.submit('Два'); // поки Раз чекає паузу - Два не йде вперед
    expect(m.sent.length, 1);
    expect([for (final i in await store.items()) i.status], [ChatStatus.queued, ChatStatus.queued]);
    clock = clock.add(const Duration(minutes: 1));
    await q.process();
    expect([for (final i in await store.items()) if (i.isUser) i.status], [ChatStatus.sent, ChatStatus.sent]);
    expect(m.sent[1].last['content'], startsWith('Раз'));
  });

  group('відповідь на повідомлення з черги', () {
    test('екран не відкривається сам - кнопка «Відкрити»', () async {
      final opened = <NavTarget>[];
      final m = FakeModel([use('t1', 'open_screen', {'screen': 'stock'}), say('Ось склад.')]);
      final q = queue(m)
        ..presenter = ((_) async => null)
        ..navigator = ((t) async {
          opened.add(t);
          return true;
        });
      online = false;
      await q.submit('Відкрий склад');
      online = true;
      await q.process();
      expect(opened, isEmpty);
      final reply = (await store.items()).last;
      expect(reply.text, 'Ось склад.');
      expect(reply.offeredNav.single.screen, 'stock');
    });

    test('той самий запит одразу у відкритому чаті - відкриває', () async {
      final opened = <NavTarget>[];
      final m = FakeModel([use('t1', 'open_screen', {'screen': 'stock'}), say('Відкрив.')]);
      final q = queue(m)
        ..presenter = ((_) async => null)
        ..navigator = ((t) async {
          opened.add(t);
          return true;
        });
      await q.submit('Відкрий склад');
      expect(opened.single.screen, 'stock');
    });

    test('запис - картка чекає в чаті; «Так» - записано на свіжих даних, «Ні» - нічого', () async {
      final sugar = await repo.addStockItem('Цукор', 'кг');
      final m = FakeModel([
        use('t1', 'stock_receive', {'item': 'Цукор', 'amount': 10, 'total': 400}),
        say('Підготував прихід - підтвердіть картку.'),
        use('t2', 'stock_receive', {'item': 'Цукор', 'amount': 5, 'total': 200}),
        say('Ще одна картка.'),
      ]);
      final q = queue(m);
      online = false;
      await q.submit('Прийми 10 кг цукру');
      await q.submit('І ще 5');
      online = true;
      await q.process(); // чат закрито (фон)
      // модель дізналась, що запис чекає людину
      final result = (m.sent[1].last['content'] as List).single as Map;
      expect(jsonDecode(result['content'] as String)['status'], 'очікує підтвердження');
      expect((await repo.getStockItem(sugar))!.quantity ?? 0, 0);

      final items = await store.items();
      expect([for (final i in items) i.role], [
        ChatRole.user, ChatRole.user, ChatRole.assistant, ChatRole.card, ChatRole.assistant, ChatRole.card,
      ]);
      // нові відповіді й картки - значок на поштоматі
      expect(q.unread.value, 4);
      final cards = [for (final i in items) if (i.isCard) i];
      expect(cards.first.card!.fields.first.label, 'Кількість (кг)');

      final out = await q.answerCard(cards.first.id, {'amount': '12', 'total': '480'});
      expect(out!.isError, isFalse);
      expect((await repo.getStockItem(sugar))!.quantity, 12);
      expect(await q.answerCard(cards.last.id, null), isNull);
      expect((await repo.getStockItem(sugar))!.quantity, 12);
      expect((await store.item(cards.last.id))!.status, ChatStatus.rejected);
      // повторна відповідь на ту саму картку нічого не робить
      expect(await q.answerCard(cards.first.id, {'amount': '12', 'total': '480'}), isNull);
      expect((await repo.getStockItem(sugar))!.quantity, 12);
      await q.markAllRead();
      expect(q.unread.value, 0);
    });

    test('читання - на даних у момент відповіді, а не відправлення', () async {
      final m = FakeModel([use('t1', 'stock_list', {}), say('Є цукор.')]);
      final q = queue(m);
      online = false;
      await q.submit('Що на складі?');
      await repo.addStockItem('Цукор', 'кг'); // додали, поки не було зв'язку
      online = true;
      await q.process();
      final result = (m.sent[1].last['content'] as List).single as Map;
      expect(result['content'], contains('Цукор'));
    });
  });

  test('«Нова розмова» - чисто, але черга лишається', () async {
    final q = queue(FakeModel([say('Так')]));
    await q.submit('Раз');
    online = false;
    await q.submit('Два');
    await store.newConversation();
    expect(await statuses(), ['user:queued:Два']);
    expect(await store.history(), isEmpty);
  });

  test('фонове завдання дошле чергу (застосунок закрито)', () async {
    online = false;
    await queue(FakeModel([])).submit('З фону');
    final ok = await runBackgroundTask(BackgroundTasks.assistant,
        openRepo: () async => repo, assistantModel: () => FakeModel([say('Отримав')]));
    expect(ok, isTrue);
    expect(await statuses(), ['user:sent:З фону', 'assistant::Отримав']);
  });
}
