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
  http.Client get client => MockClient((r) async {
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        bodies.add(b);
        final asked = b['model'] as String?;
        final routed = routeSimple && asked == 'sonnet';
        final model = routed ? 'haiku' : (asked == 'sonnet' || asked == 'opus' ? asked : 'haiku');
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Відповідає $model'}
              ],
              'stop_reason': 'end_turn',
              'model': model,
              if (routed) 'routed_from': 'sonnet',
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

  testWidgets('Робопасічник: третій у списку, іде в запит як opus, з роботом', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-chooser')));
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantRobo), findsOneWidget);
    expect(find.text(tr.assistantRoboHint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('persona-opus')));
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => repo.getMeta(AssistantPrefs.modelKey)), 'opus');
    await send(tester, 'Привіт');
    expect(server.bodies.last['model'], 'opus');
    expect(find.text('Відповідає opus'), findsOneWidget);
    expect(hasImage(AssistantPersona.robo.image), isTrue);
    expect(find.textContaining('Opus'), findsNothing); // людині - без назв моделей
    expect(AssistantPersona.of('opus'), AssistantPersona.robo);
    expect(AssistantPersona.robo.name, 'Робопасічник');
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
    expect(find.text(tr.assistantRouted(tr.assistantBeekeeper)), findsOneWidget);
    expect(hasImage(AssistantPersona.bear.image), isTrue); // обличчя того, хто відповів
    // звичайна відповідь (без передачі) - без підпису
    server.routeSimple = false;
    await send(tester, 'Поясни докладніше');
    expect(find.text(tr.assistantRouted(tr.assistantBeekeeper)), findsOneWidget);
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
    expect(await AssistantPrefs.requestOptions(repo), {'model': 'haiku', 'effort': 'medium'});
    await AssistantPrefs.setPersona(repo, AssistantPersona.beekeeper);
    await AssistantPrefs.setEffort(repo, 'high');
    expect(await AssistantPrefs.requestOptions(repo), {'model': 'sonnet', 'effort': 'high'});
    expect(AssistantPersona.of(null), AssistantPersona.bear);
    // колишня «дуже висока» - тепер середня
    await repo.setMeta(AssistantPrefs.effortKey, 'xhigh');
    expect((await AssistantPrefs.requestOptions(repo))['effort'], 'medium');
    expect(kAssistantEfforts, ['low', 'medium', 'high']);
    // голоси різні
    expect(AssistantPersona.bear.pitch, greaterThan(AssistantPersona.beekeeper.pitch));
  });
}
