import 'dart:convert';

import 'package:apiary/assistant/assistant_chat_screen.dart';
import 'package:apiary/assistant/assistant_context.dart';
import 'package:apiary/assistant/assistant_host.dart';
import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/finance_screen.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ModelTurn say(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

/// Модель, що запам'ятовує, що їй надіслали.
class RecModel implements AssistantModel {
  final sent = <List<Map<String, dynamic>>>[];
  @override
  bool get isRemote => true;
  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    sent.add(jsonDecode(jsonEncode(messages)).cast<Map<String, dynamic>>());
    return say('Гаразд');
  }

  String get lastUserText => sent.last.lastWhere((m) => m['role'] == 'user')['content'] as String;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Repository repo;
  late RecModel model;
  late AssistantQueue q;
  late List<NavTarget> opened;
  var ready = false;

  setUpAll(sqfliteFfiInit);

  Future<void> setup(WidgetTester tester) async {
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
    });
    model = RecModel();
    ready = true;
    opened = [];
    q = AssistantQueue(repo, AssistantStore(repo.db), model,
        isOnline: () async => true, onlineChanges: const Stream.empty());
  }

  tearDown(() async {
    if (!ready) return;
    ready = false;
    AssistantContext.current.value = null;
    AssistantContext.chatOnTop.value = false;
    AssistantHost.dockOpen.value = false;
    q.stop();
    try {
      await repo.db.close();
    } catch (_) {}
  });

  Future<void> pumpChat(WidgetTester tester) async {
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
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  test('рядок для моделі й зберігання контексту; підказки за вкладкою', () {
    const c = ScreenContext('map', 'Карта: Біля хати', apiaryId: 'a1', elementId: 'e1');
    expect(c.promptLine, '[Екран: map (Карта: Біля хати), пасіка: a1, вулик: e1]');
    expect(const ScreenContext('finance', 'Фінанси').promptLine, '[Екран: finance (Фінанси)]');
    expect(ScreenContext.fromJson(c.toJson()), c);
    expect(ScreenContext.fromJson(null), isNull);
    expect(ScreenContext.fromTarget(const NavTarget('stock', 'stock')).label, 'Склад');
    // перше - завжди «Що ти вмієш?»; усього три
    for (final s in [null, 'finance', 'stock', 'map', 'history', 'settings']) {
      final l = assistantSuggestions(s == null ? null : ScreenContext(s, s));
      expect(l.length, 3, reason: '$s');
      expect(l.first, 'Що ти вмієш?');
    }
    expect(assistantSuggestions(const ScreenContext('stock', 'Склад'))[1], contains('складі'));
  });

  testWidgets('плашка вкладки: видно, іде в модель; хрестик - про весь застосунок; назад - знову',
      (tester) async {
    await setup(tester);
    AssistantContext.current.value = const ScreenContext('finance', 'Фінанси');
    await pumpChat(tester);
    expect(find.byKey(const ValueKey('assistant-context')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('assistant-context')), matching: find.text('Фінанси')),
        findsOneWidget);

    await send(tester, 'Скільки витратив?');
    expect(model.lastUserText, contains('Скільки витратив?'));
    expect(model.lastUserText, contains('[Екран: finance (Фінанси)]'));

    // хрестик: плашки немає, у модель контекст не йде, є кнопка «Говорити про…»
    await tester.tap(find.byKey(const ValueKey('assistant-context-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-context')), findsNothing);
    expect(find.text(tr.assistantContextPin('Фінанси')), findsOneWidget);
    await send(tester, 'А взагалі?');
    expect(model.lastUserText, isNot(contains('[Екран:')));

    // знову прив'язати
    await tester.tap(find.byKey(const ValueKey('assistant-context-repin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-context')), findsOneWidget);
    await send(tester, 'І ще');
    expect(model.lastUserText, contains('[Екран: finance (Фінанси)]'));
  });

  testWidgets('без знайомої вкладки (головний) - без плашки й без рядка для моделі', (tester) async {
    await setup(tester);
    await pumpChat(tester);
    expect(find.byKey(const ValueKey('assistant-context')), findsNothing);
    await send(tester, 'Привіт');
    expect(model.lastUserText, isNot(contains('[Екран:')));
  });

  testWidgets('«відкрий Склад»: плашка стає «Склад»', (tester) async {
    await setup(tester);
    AssistantContext.current.value = const ScreenContext('finance', 'Фінанси');
    await pumpChat(tester);
    await tester.runAsync(() => q.store.addAssistant('Готово', nav: [const NavTarget('stock', 'stock')]));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr.assistantOpenTarget('stock')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(opened.single.screen, 'stock');
    expect(find.descendant(of: find.byKey(const ValueKey('assistant-context')), matching: find.text('Склад')),
        findsOneWidget);
    await send(tester, 'Додай прихід');
    expect(model.lastUserText, contains('[Екран: stock (Склад)]'));
  });

  testWidgets('часті питання: у порожній розмові, торкнувся - надіслано; потім зникають', (tester) async {
    await setup(tester);
    AssistantContext.current.value = const ScreenContext('stock', 'Склад');
    await pumpChat(tester);
    expect(find.byKey(const ValueKey('assistant-faq-0')), findsOneWidget);
    expect(find.text('Що ти вмієш?'), findsOneWidget);
    expect(find.text('Чого мало на складі?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-faq-0')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(model.lastUserText, contains('Що ти вмієш?'));
    expect(model.lastUserText, contains('[Екран: stock (Склад)]'));
    expect(find.byKey(const ValueKey('assistant-faq-1')), findsNothing); // розмова вже є
  });

  testWidgets('плашка виклику на вкладці: показує, веде в чат із плашкою; у чаті її немає',
      (tester) async {
    await setup(tester);
    await tester.runAsync(() => q.start());
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [AssistantContext.observer],
      builder: (context, child) =>
          AssistantHost(repo: repo, navigator: nav, child: child ?? const SizedBox()),
      home: const Scaffold(body: Center(child: Text('головний'))),
    ));
    await settle(tester);
    // головний екран - плашки немає
    expect(find.byKey(const ValueKey('assistant-fab')), findsNothing);

    unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => StockScreen(repo: repo))));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(AssistantContext.current.value?.screen, 'stock');
    expect(find.byKey(const ValueKey('assistant-fab')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assistant-fab')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantChatScreen), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('assistant-context')), matching: find.text('Склад')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-fab')), findsNothing); // у чаті плашки немає

    // торкнулися плашки вкладки - повернулись у неї
    await tester.tap(find.byKey(const ValueKey('assistant-context-open')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantChatScreen), findsNothing);
    expect(find.byType(StockScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-fab')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('планшет: чат збоку від вкладки; говорить про ту вкладку, що на екрані', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setup(tester);
    await tester.runAsync(() => q.start());
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [AssistantContext.observer],
      builder: (context, child) =>
          AssistantHost(repo: repo, navigator: nav, child: child ?? const SizedBox()),
      home: const Scaffold(body: Center(child: Text('головний'))),
    ));
    await settle(tester);
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => StockScreen(repo: repo))));
    await settle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('assistant-fab')));
    await settle(tester);
    await tester.pumpAndSettle();
    // збоку: чат, а склад лишається видно
    expect(find.byKey(const ValueKey('assistant-dock')), findsOneWidget);
    expect(find.byType(AssistantChatScreen), findsOneWidget);
    expect(find.byType(StockScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-fab')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('assistant-dock'))).width, AssistantHost.dockWidth);
    expect(find.descendant(of: find.byKey(const ValueKey('assistant-context')), matching: find.text('Склад')),
        findsOneWidget);

    // «перейди на фінанси»: вкладка відкривається в основній частині, плашка за нею
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => FinanceScreen(repo: repo))));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantChatScreen), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('assistant-context')), matching: find.text('Фінанси')),
        findsOneWidget);
    await send(tester, 'Скільки витрат?');
    expect(model.lastUserText, contains('[Екран: finance (Фінанси)]'));

    // хрестик на плашці - про весь застосунок
    await tester.tap(find.byKey(const ValueKey('assistant-context-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-context')), findsNothing);

    // закрити панель - плашка виклику повернулась
    await tester.tap(find.byKey(const ValueKey('assistant-dock-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-dock')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-fab')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

void unawaited(Future<void> f) {}
