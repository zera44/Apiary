import 'package:apiary/assistant/assistant_chat_screen.dart';
import 'package:apiary/assistant/assistant_links.dart';
import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_persona.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

ModelTurn say(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

void main() {
  late Repository repo;
  late String apiary, hive;
  late List<NavTarget> opened;

  setUpAll(sqfliteFfiInit);

  test('розбір посилань: [текст](екран) і [текст](екран:id); чуже - звичайний текст', () {
    final parts = parseAssistantLinks(
        'Відкрийте [склад](stock) або [Вулик 100](hive:e:abc-1). [Ось](garage) і [x](https://a.b).');
    final links = [for (final p in parts) if (p is AssistantLink) p];
    expect([for (final l in links) '${l.text}|${l.screen}|${l.id}'],
        ['склад|stock|null', 'Вулик 100|hive|e:abc-1']);
    expect(plainAssistantText('Відкрийте [склад](stock) і [Вулик 100](hive:e:abc-1).'),
        'Відкрийте склад і Вулик 100.');
    expect(plainAssistantText('[Ось](garage)'), '[Ось](garage)'); // невідомий екран - як є
  });

  Future<AssistantQueue> open(WidgetTester tester, List<ModelTurn> script) async {
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
      apiary = await repo.addApiary('Пасіка 1');
      hive = await repo.addElement(apiary, 0, 0, label: 'Вулик 100');
      await AssistantPrefs.load(repo);
    });
    opened = [];
    final q = AssistantQueue(repo, AssistantStore(repo.db), DemoAssistantModel(script),
        isOnline: () async => true, onlineChanges: const Stream.empty());
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
    await settle(tester);
    return q;
  }

  tearDown(() async {
    try {
      await repo.db.close();
    } catch (_) {}
  });

  testWidgets('слово-посилання у відповіді: торкнувся - відкрився екран чи вулик', (tester) async {
    final queue = await open(tester, []);
    // id вулика - справжній (модель бере його з інструментів)
    await tester.runAsync(() => queue.store.addAssistant('Ось [Вулик 100](hive:e:$hive) і [налаштування](settings).'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('[', findRichText: true), findsNothing); // розмітку не видно

    // торкнутися слова в RichText: шукаємо його позицію
    Future<void> tapWord(String word) async {
      final rich = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains(word));
      final box = tester.renderObject<RenderParagraph>(rich.last);
      final text = box.text.toPlainText();
      final i = text.indexOf(word) + 1;
      final offset = box.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
      await tester.tapAt(box.localToGlobal(offset + const Offset(2, 8)));
      await settle(tester);
    }

    await tapWord('Вулик 100');
    expect(opened.last.screen, 'hive');
    expect(opened.last.elementId, hive);
    expect(opened.last.apiaryId, apiary);
    await tapWord('налаштування');
    expect(opened.last.screen, 'settings');
  });

  testWidgets('«Ведмедик думає…» - ім\'я обраного помічника', (tester) async {
    await open(tester, []);
    expect(tr.assistantThinking(AssistantPersona.bear.name), 'Ведмедик думає…');
    expect(tr.assistantThinking(AssistantPersona.beekeeper.name), 'Пасічник думає…');
  });

  testWidgets('картка: колір мітки матки - кольоровими кнопками', (tester) async {
    late String mark;
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
      apiary = await repo.addApiary('Пасіка 1');
      hive = await repo.addElement(apiary, 0, 0, label: 'Вулик 100');
      mark = (await repo.baseParameterId('hive', 'queen_mark'))!;
    });
    final q = AssistantQueue(
        repo,
        AssistantStore(repo.db),
        DemoAssistantModel([
          const ModelTurn([
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'record_inspection',
              'input': {
                'hive_id': '100',
                'values': {'Мітка матки': 'синя'},
                'mark_visited': false
              },
            }
          ], 'tool_use'),
          say('Записав.'),
        ]),
        isOnline: () async => true,
        onlineChanges: const Stream.empty());
    await tester.pumpWidget(MaterialApp(home: AssistantChatScreen(repo: repo, queue: q, navigate: (_) async => true)));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'синя матка у 100');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    final card = (await tester.runAsync(q.store.items))!.firstWhere((i) => i.isCard);
    // кнопки кольорів замість поля; обрано «Синій» - людина міняє на «Жовтий»
    final yellow = find.byKey(ValueKey('card-${card.id}-p:$mark-Жовтий'));
    await tester.ensureVisible(yellow);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(ValueKey('card-${card.id}-p:$mark-Синій'))).selected, isTrue);
    await tester.tap(yellow);
    await tester.pump();
    await tester.ensureVisible(find.byKey(ValueKey('card-yes-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('card-yes-${card.id}')));
    await settle(tester);
    final v = await tester.runAsync(() => repo.latestParameterValues(EntityRef.element(hive)));
    expect(v![mark], 'Жовтий');
    await tester.runAsync(() => repo.db.close());
  });
}
