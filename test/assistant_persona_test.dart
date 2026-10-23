import 'dart:convert';

import 'package:apiary/assistant/assistant_chat_screen.dart';
import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_persona.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Підставний сервер: запам'ятовує, що надіслано, і відповідає від імені
/// обраної моделі (як справжній посередник - поле model).
class EchoServer {
  final bodies = <Map<String, dynamic>>[];

  /// Сервер передає просте прохання Пасічника Ведмедику (поле routed_from).
  bool routeSimple = false;

  /// Сервер підняв питання на рівень вище (поле escalated_from).
  bool escalate = false;
  http.Client get client => MockClient((r) async {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        bodies.add(b);
        final asked = b['model'] as String?;
        final routed = routeSimple && asked == 'sonnet';
        final up = escalate && asked == 'haiku';
        final model = up
            ? 'sonnet'
            : routed ? 'haiku' : (asked == 'sonnet' || asked == 'opus' ? asked : 'haiku');
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Відповідає $model'}
              ],
              'stop_reason': 'end_turn',
              'model': model,
              if (routed) 'routed_from': 'sonnet',
              if (up) 'escalated_from': 'haiku',
            })),
            200);
      });
}

bool hasImage(String asset) => find
    .byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset)
    .evaluate()
    .isNotEmpty;

void main() {
  late Repository repo;
  late EchoServer server;
  late AssistantQueue q;

  setUpAll(sqfliteFfiInit);

  Future<void> open(WidgetTester tester, {EchoServer? srv}) async {
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
      await AssistantPrefs.load(repo);
    });
    server = srv ?? EchoServer();
    q = AssistantQueue(
      repo,
      AssistantStore(repo.db),
      RemoteAssistantModel(Uri.parse('https://x/functions/v1/assistant'), 'code',
          client: server.client, options: () => AssistantPrefs.requestOptions(repo)),
      isOnline: () async => true,
      onlineChanges: const Stream.empty(),
    );
    await tester.pumpWidget(MaterialApp(home: AssistantChatScreen(repo: repo, queue: q, navigate: (_) async => true)));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    try {
      await repo.db.close();
    } catch (_) {}
  });

  testWidgets('типово - Ведмедик (Haiku), середня глибина; так і йде в запит', (tester) async {
    await open(tester);
    expect(find.text(tr.assistantBear), findsWidgets); // заголовок і плашка
    expect(hasImage(AssistantPersona.bear.image), isTrue);
    await send(tester, 'Привіт');
    expect(server.bodies.last['model'], 'haiku');
    expect(server.bodies.last['effort'], 'medium');
    expect(find.text('Відповідає haiku'), findsOneWidget);
  });

  testWidgets('плашка під полем: обрати Пасічника й «Високу» - зберігається, іде в запит',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-chooser')));
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantWhoHelps), findsOneWidget);
    expect(find.text(tr.assistantBeekeeperHint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('persona-sonnet')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('effort-high')));
    await settle(tester);
    await tester.tapAt(const Offset(10, 10)); // закрити
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => repo.getMeta(AssistantPrefs.modelKey)), 'sonnet');
    expect(await tester.runAsync(() => repo.getMeta(AssistantPrefs.effortKey)), 'high');
    expect(find.text(tr.assistantBeekeeper), findsWidgets);
    await send(tester, 'Привіт');
    expect(server.bodies.last['model'], 'sonnet');
    expect(server.bodies.last['effort'], 'high');
    // людині - без назв моделей; лише три рівні
    expect(find.textContaining('Haiku'), findsNothing);
    expect(find.textContaining('Sonnet'), findsNothing);
  });

  testWidgets('Робопасічник: у списку під замочком, обрати його не можна', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-chooser')));
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantRobo), findsOneWidget);
    expect(find.text(tr.assistantRoboLocked), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('persona-opus')));
    await settle(tester);
    expect(AssistantPrefs.persona.value, AssistantPersona.bear);
    expect(AssistantPrefs.active.value, AssistantPersona.bear);
    expect(await tester.runAsync(() => repo.getMeta(AssistantPrefs.modelKey)), isNot('opus'));
    expect(AssistantPersona.robo.locked, isTrue);
    expect(AssistantPersona.of('opus'), AssistantPersona.robo);
    expect(AssistantPersona.robo.name, 'Робопасічник');
    expect(AssistantPersona.robo.nameAcc, 'Робопасічника');
  });

  testWidgets('система перейшла на Робопасічника - аватар і заголовок змінилися, у запит іде active',
      (tester) async {
    await open(tester);
    await tester.runAsync(() => AssistantPrefs.setActive(repo, AssistantPersona.robo));
    await tester.pumpAndSettle();
    expect(hasImage(AssistantPersona.robo.image), isTrue);
    await send(tester, 'Привіт');
    expect(server.bodies.last['model'], 'haiku'); // обране людиною лишилось
    expect(server.bodies.last['active'], 'opus');
  });

  testWidgets('перемикання помітне: відповів Ведмедик, підпис «Пасічник передав просте…»',
      (tester) async {
    await open(tester, srv: EchoServer()..routeSimple = true);
    await tester.runAsync(() => AssistantPrefs.setPersona(repo, AssistantPersona.beekeeper));
    await send(tester, 'Відкрий склад');
    final items = (await tester.runAsync(q.store.items))!;
    final reply = items.firstWhere((i) => i.role == ChatRole.assistant);
    expect(reply.data['model'], 'haiku');
    expect(reply.data['routed_from'], 'sonnet');
    expect(find.text(tr.assistantRouted(tr.assistantBearAcc)), findsOneWidget);
    expect(hasImage(AssistantPersona.bear.image), isTrue); // обличчя того, хто відповів
    // звичайна відповідь (без передачі) - без підпису
    server.routeSimple = false;
    await send(tester, 'Поясни докладніше');
    expect(find.text(tr.assistantRouted(tr.assistantBearAcc)), findsOneWidget);
  });

  testWidgets('ескалація помітна: Ведмедик не впорався - відповів Пасічник', (tester) async {
    await open(tester, srv: EchoServer()..escalate = true);
    await send(tester, 'Складне питання');
    final items = (await tester.runAsync(q.store.items))!;
    final reply = items.firstWhere((i) => i.role == ChatRole.assistant);
    expect(reply.data['model'], 'sonnet');
    expect(reply.data['escalated_from'], 'haiku');
    expect(find.text(tr.assistantEscalated(tr.assistantBear, tr.assistantBeekeeperAcc)), findsOneWidget);
    expect(hasImage(AssistantPersona.beekeeper.image), isTrue);
  });

  testWidgets('кожна відповідь - з обличчям того, хто відповідав', (tester) async {
    await open(tester);
    await send(tester, 'Раз'); // Ведмедик
    await tester.runAsync(() => AssistantPrefs.setPersona(repo, AssistantPersona.beekeeper));
    await send(tester, 'Два'); // Пасічник
    final items = (await tester.runAsync(q.store.items))!;
    expect([for (final i in items) if (i.role == ChatRole.assistant) i.data['model']], ['haiku', 'sonnet']);
    expect(hasImage(AssistantPersona.bear.image), isTrue);
    expect(hasImage(AssistantPersona.beekeeper.image), isTrue);
  });

  test('вибір читається з бази (і для фонового завдання); дивне значення - типове', () async {
    sqfliteFfiInit();
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false));
    await repo.init();
    await repo.setMeta(AssistantPrefs.effortKey, 'turbo');
    expect(await AssistantPrefs.requestOptions(repo), {'model': 'haiku', 'active': 'haiku', 'effort': 'medium'});
    await AssistantPrefs.setPersona(repo, AssistantPersona.beekeeper);
    await AssistantPrefs.setEffort(repo, 'high');
    expect(await AssistantPrefs.requestOptions(repo), {'model': 'sonnet', 'active': 'sonnet', 'effort': 'high'});
    expect(AssistantPersona.of(null), AssistantPersona.bear);
    // колишня «дуже висока» - тепер середня
    await repo.setMeta(AssistantPrefs.effortKey, 'xhigh');
    expect((await AssistantPrefs.requestOptions(repo))['effort'], 'medium');
    expect(kAssistantEfforts, ['low', 'medium', 'high']);
    // голоси різні
    expect(AssistantPersona.bear.pitch, greaterThan(AssistantPersona.beekeeper.pitch));
  });
}
