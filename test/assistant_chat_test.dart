import 'package:apiary/assistant/assistant_chat_screen.dart';
import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_nav.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:apiary/ui/voice_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ModelTurn say(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

ModelTurn use(String name, Map<String, dynamic> input) => ModelTurn([
      {'type': 'tool_use', 'id': 't-$name', 'name': name, 'input': input}
    ], 'tool_use');

/// Дати справжній базі й черзі доробити (вони поза «штучним» часом тесту).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Repository repo;
  late AssistantStore store;
  late bool online;
  late List<NavTarget> opened;

  setUpAll(sqfliteFfiInit);

  Future<AssistantQueue> setup(WidgetTester tester, List<ModelTurn> script) async {
    late AssistantQueue q;
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
      store = AssistantStore(repo.db);
    });
    online = true;
    opened = [];
    q = AssistantQueue(repo, store, DemoAssistantModel(script),
        isOnline: () async => online, onlineChanges: const Stream.empty());
    return q;
  }

  Future<void> pumpChat(WidgetTester tester, AssistantQueue q) async {
    await tester.pumpWidget(MaterialApp(
      home: AssistantChatScreen(
        repo: repo,
        queue: q,
        navigate: (t) async {
          opened.add(t);
          return true;
        },
      ),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  tearDown(() async => repo.db.close());

  testWidgets('копіювати питання й відповідь у буфер (без розмітки посилань)', (tester) async {
    final copied = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copied.add((c.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final q = await setup(tester, [say('Цукор - на [складі](stock).')]);
    await pumpChat(tester, q);
    await send(tester, 'Де цукор?');
    final items = (await tester.runAsync(() => store.items()))!;
    expect(items.length, 2);
    for (final it in items) {
      await tester.tap(find.byKey(ValueKey('assistant-copy-${it.id}')));
      await tester.pump();
    }
    expect(copied, ['Де цукор?', 'Цукор - на складі.']);
    expect(find.text(tr.assistantCopied), findsWidgets);
    // довге натискання - теж копіює
    await tester.longPress(find.text('Де цукор?'));
    await tester.pump();
    expect(copied.last, 'Де цукор?');
  });

  testWidgets('привітання, питання - відповідь хмаркою пасічника', (tester) async {
    final q = await setup(tester, [say('Добрий день! Чим допомогти?')]);
    await pumpChat(tester, q);
    expect(find.text(tr.assistantGreeting), findsOneWidget);
    expect(find.text(tr.assistantDemo), findsOneWidget); // demo-модель
    await send(tester, 'Привіт');
    expect(find.text('Привіт'), findsOneWidget);
    expect(find.text('Добрий день! Чим допомогти?'), findsOneWidget);
  });

  testWidgets('без зв\'язку - «Немає зв\'язку», «чекає на інтернет», можна видалити', (tester) async {
    final q = await setup(tester, []);
    await pumpChat(tester, q);
    online = false;
    await send(tester, 'Запиши огляд');
    expect(find.byKey(const ValueKey('assistant-offline')), findsOneWidget);
    expect(find.text(tr.assistantWaiting), findsOneWidget);
    await tester.tap(find.text(tr.assistantDelete));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Запиши огляд'), findsNothing);
  });

  testWidgets('жива картка: «Так» - записано, «Скасувати» - як було', (tester) async {
    final q = await setup(tester, [
      use('stock_receive', {'item': 'Цукор', 'amount': 10, 'total': 400}),
      say('Записав прихід.'),
    ]);
    late String sugar;
    await tester.runAsync(() async => sugar = await repo.addStockItem('Цукор', 'кг'));
    await pumpChat(tester, q);
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'Прийми 10 кг цукру');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    expect(find.text(tr.assistantCardTitle), findsOneWidget);
    expect(find.text('Прихід: Цукор'), findsOneWidget);
    // виправити кількість у картці
    final card = (await tester.runAsync(store.items))!.firstWhere((i) => i.isCard);
    await tester.enterText(find.byKey(ValueKey('card-${card.id}-amount')), '12');
    await tester.ensureVisible(find.byKey(ValueKey('card-yes-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('card-yes-${card.id}')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Записав прихід.'), findsOneWidget);
    expect(find.text(tr.assistantSaved), findsOneWidget);
    expect((await tester.runAsync(() => repo.getStockItem(sugar)))!.quantity, 12);

    await tester.ensureVisible(find.byKey(ValueKey('card-undo-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('card-undo-${card.id}')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantUndone), findsOneWidget);
    expect((await tester.runAsync(() => repo.getStockItem(sugar)))!.quantity, 0);
  });

  testWidgets('жива картка: «Ні» - нічого не записано', (tester) async {
    final q = await setup(tester, [
      use('add_finance_entry', {'kind': 'expense', 'amount': 300}),
      say('Добре, не записую.'),
    ]);
    await pumpChat(tester, q);
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'Витрата 300');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    final card = (await tester.runAsync(store.items))!.firstWhere((i) => i.isCard);
    await tester.ensureVisible(find.byKey(ValueKey('card-no-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('card-no-${card.id}')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantRejected), findsOneWidget);
    expect(await tester.runAsync(() => repo.db.query('fin_ops')), isEmpty);
  });

  test('поле чату - зі своїм мікрофоном (без загальної смужки «Голосовий ввід»)', () {
    final c = TextEditingController();
    VoiceInputHost.ownMicrophone(c);
    expect(VoiceInputHost.hasOwnMicrophone(c), isTrue);
    expect(VoiceInputHost.hasOwnMicrophone(TextEditingController()), isFalse);
  });

  testWidgets('«відкрий склад» у чаті - відкриває одразу', (tester) async {
    final q = await setup(tester, [use('open_screen', {'screen': 'stock'}), say('Відкрив склад.')]);
    await pumpChat(tester, q);
    await send(tester, 'Відкрий склад');
    expect(opened.single.screen, 'stock');
  });

  testWidgets('відповідь із черги - кнопка «Відкрити», а не перехід', (tester) async {
    final q = await setup(tester, [use('open_screen', {'screen': 'stock'}), say('Ось склад.')]);
    online = false;
    await tester.runAsync(() => q.submit('Відкрий склад'));
    online = true;
    await tester.runAsync(q.process); // відповідь прийшла, поки чат закрито
    expect(q.unread.value, 1);
    await pumpChat(tester, q);
    expect(opened, isEmpty);
    expect(find.text(tr.assistantOpenTarget('stock')), findsOneWidget);
    expect(q.unread.value, 0); // відкрили чат - прочитано
  });

  testWidgets('«Нова розмова» - стрічка чиста, стара лишається у списку «Розмови»', (tester) async {
    final q = await setup(tester, [say('Так'), say('Ага')]);
    await pumpChat(tester, q);
    await send(tester, 'Раз');
    await tester.tap(find.byKey(const ValueKey('assistant-new-chat')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(find.text('Раз'), findsNothing);
    expect(find.text(tr.assistantGreeting), findsOneWidget);

    // друга розмова
    await send(tester, 'Два');
    expect(find.text('Два'), findsOneWidget);

    // список: обидві; відкриваємо першу
    await tester.tap(find.byKey(const ValueKey('assistant-conversations')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(find.text('Раз'), findsOneWidget);
    expect(find.text('Два'), findsWidgets);
    await tester.tap(find.text('Раз'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(find.text('Раз'), findsOneWidget);
    expect(find.text('Так'), findsOneWidget);
    expect(find.text('Два'), findsNothing);
  });

  testWidgets('телефон 360 dp, найбільший шрифт: чат і картка без переповнень', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final q = await setup(tester, [
      use('record_inspection', {'hive_id': '5', 'values': {'Сила': '9'}, 'note': 'Спокійні, багато розплоду'}),
      say('Записав огляд вулика 5.'),
    ]);
    await tester.runAsync(() async {
      final a = await repo.addApiary('Біля хати');
      final h = await repo.addElement(a, 0, 0, label: 'Вулик 5');
      final p = await repo.addParameter('Сила', unit: 'вуличок', dataType: 'int');
      await repo.setAttachedParameters([p], EntityRef.element(h));
      await q.submit('Довге повідомлення людини, щоб перевірити перенесення рядків у бульбашці чату');
    });
    online = false;
    await tester.runAsync(() => q.submit('Ще одне, що чекає на інтернет'));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      home: AssistantChatScreen(repo: repo, queue: q, navigate: (_) async => true),
    ));
    await settle(tester);
    await tester.pumpAndSettle();
    // самий низ стрічки (довгі повідомлення на великому шрифті не вміщаються)
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(tr.assistantWaiting), findsOneWidget);
  });

  testWidgets('диспетчер екранів: кожен екран навігатора відкривається', (tester) async {
    await setup(tester, []);
    late String apiary, hive;
    await tester.runAsync(() async {
      apiary = await repo.addApiary('Біля хати');
      hive = await repo.addElement(apiary, 0, 0, label: 'Вулик 5');
    });
    for (final s in kAssistantScreens) {
      if (const {'home', 'scanner', 'whats_new'}.contains(s)) continue; // відкриваються по-своєму
      final w = await tester.runAsync(() => assistantScreen(
          repo, NavTarget(s, s, apiaryId: apiary, elementId: s == 'hive' ? hive : null)));
      expect(w, isNotNull, reason: s);
    }
    final map = await tester.runAsync(
        () => assistantScreen(repo, NavTarget('hive', 'Вулик 5', apiaryId: apiary, elementId: hive)));
    expect(map, isA<MapScreen>());
    expect((map as MapScreen).focusElementId, hive);
    expect(await tester.runAsync(() => assistantScreen(repo, const NavTarget('stock', 'stock'))),
        isA<StockScreen>());
  });
}
