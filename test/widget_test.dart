import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/logic/hive_objects.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/main.dart';
import 'package:apiary/screens/apiary_list_screen.dart';
import 'package:apiary/screens/feedback_screen.dart';
import 'package:apiary/screens/home_screen.dart';
import 'package:apiary/services/auth.dart';
import 'package:apiary/services/reminders.dart';
import 'package:apiary/screens/history_hub_screen.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:apiary/services/feedback.dart';
import 'package:apiary/screens/history_screen.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/parameters_screen.dart';
import 'package:apiary/screens/qr_generate_screen.dart';
import 'package:apiary/services/qr_labels.dart';
import 'package:apiary/screens/template_editor_screen.dart';
import 'package:apiary/screens/templates_screen.dart';
import 'package:apiary/screens/tutorial_screen.dart';
import 'package:apiary/ui/app_drawer.dart';
import 'package:apiary/ui/fill_values_dialog.dart';
import 'package:apiary/ui/first_hints.dart';
import 'package:apiary/screens/whats_new_screen.dart';
import 'package:apiary/ui/characteristics_panel.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/grid_view.dart';
import 'package:apiary/ui/theme.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Димові тести: кожен екран будується без винятків розкладки.
void main() {
  late Repository repo;
  late String apiaryId;
  late String groupId;
  late String templateId;
  late String paramId;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    await AppIcons.load(); // SVG-іконки з assets/icons
    // підказки першого запуску й «Що нового» мають свої тести (вмикаються там)
    Hints.enabled = false;
    WhatsNewScreen.enabled = false;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Увесь застосунок у вікні як у телефона (головний екран з усіма
  /// кнопками вміщується без прокрутки).
  Future<void> pumpApp(WidgetTester tester, Widget app) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app);
  }

  /// З карти пасіки — до списку пасік через меню ☰ → «Мої пасіки».
  Future<void> listViaMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Мої пасіки'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  /// Меню ☰ уже відкрите: «QR-код» → [action] (Сканувати / Генерувати / Прив'язати підряд).
  Future<void> qrMenu(WidgetTester tester, String action) async {
    await tester.ensureVisible(find.text('QR-код'));
    await tester.tap(find.text('QR-код'));
    await settle(tester);
    await tester.ensureVisible(find.text(action));
    await settle(tester);
    await tester.tap(find.text(action));
    await settle(tester);
  }

  /// Екран входу «Увійти через Google» → головний екран «Почати» → «Мої пасіки».
  Future<void> toApiaries(WidgetTester tester) async {
    await tester.tap(find.text('Увійти через Google'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1)); // перехід між екранами завершився
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // «Почати» відкриває останню/єдину пасіку — список через меню ☰
    if (find.byType(MapScreen).evaluate().isNotEmpty) await listViaMenu(tester);
  }

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
    apiaryId = await repo.addApiary('Тестова пасіка');
    groupId = await repo.addGroup(
        apiaryId, {'0,0': 'hive', '1,0': 'hive', '0,1': 'obstacle:trees'}, 0, 0,
        groupLabel: 'Лежак 1');
    templateId = await repo.addTemplate('Лежак', 2, 2, {'0,0': 'hive', '1,0': 'hive', '0,1': 'obstacle:trees'});
    paramId = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.float_);
    await repo.addParameterRecord(paramId, '12', EntityRef.group(groupId));
  });

  tearDown(() async => repo.db.close());

  Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  testWidgets('склад: додати номенклатуру, прихід і списання', (tester) async {
    await tester.pumpWidget(wrap(StockScreen(repo: repo)));
    await settle(tester);
    expect(find.text('Прихід номенклатури'), findsOneWidget);
    expect(find.text('Ще немає жодної номенклатури'), findsOneWidget);

    await tester.tap(find.text('Додати номенклатуру'));
    await settle(tester);
    // без назви не зберігається
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('Вкажіть назву'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Цукор');
    await tester.tap(find.text('кг'));
    await settle(tester);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('Цукор'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);

    // вибуття: поки приходу не було — нічого списувати
    await tester.tap(find.text('Вибуття'));
    await settle(tester);
    expect(find.text('Вибуття номенклатури'), findsOneWidget);
    expect(find.textContaining('Немає що списувати'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, 'Прихід'));
    await settle(tester);

    // прихід: жодного «перезаписати» — лише кількість
    await tester.tap(find.widgetWithText(PillButton, 'Прихід').last);
    await settle(tester);
    expect(find.text('Прихід: Цукор'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.enterText(find.byType(TextField).at(1), '150');
    await tester.pump();
    expect(find.text('Ціна за одиницю: 30 грн/кг'), findsOneWidget);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('5 кг'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, 'Прихід').last);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '2,5');
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('Вкажіть загальну вартість приходу'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '75');
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('7,5 кг'), findsOneWidget);

    // списання: не більше залишку; поля — дата, кількість, коментар
    await tester.tap(find.text('Вибуття'));
    await settle(tester);
    await tester.tap(find.widgetWithText(PillButton, 'Списати'));
    await settle(tester);
    expect(find.text('Списання: Цукор'), findsOneWidget);
    expect(find.text('Кількість'), findsOneWidget);
    expect(find.textContaining('Загальна вартість'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.tap(find.widgetWithText(PillButton, 'Списати').last);
    await settle(tester);
    expect(find.text('Можна списати не більше 7,5 кг'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.tap(find.widgetWithText(PillButton, 'Списати').last);
    await settle(tester);
    expect(find.text('5,5 кг'), findsOneWidget);

    // переоблік: фактично 5 → нестача 0,5
    await tester.tap(find.widgetWithText(PillButton, 'Переоблік'));
    await settle(tester);
    await tester.tap(find.widgetWithText(PillButton, 'Перерахувати'));
    await settle(tester);
    expect(find.text('За обліком: 5,5 кг'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('5 кг'), findsOneWidget);
    final moves = await repo.stockMoves((await repo.listStockItems()).single.id);
    expect(moves.last['kind'], 'inv');
    expect(moves.last['amount'], -0.5);
  });

  testWidgets('історія: вкладки «Характеристики» і «Склад», записи складу', (tester) async {
    final id = await repo.addStockItem('Цукор', 'кг');
    await repo.receiveStock(id, 5, total: 150);
    await repo.receiveStock(id, 2, total: 60);
    await repo.writeOffStock(id, 3, comment: 'підгодівля');
    final params = await repo.listParameters();
    await tester.pumpWidget(wrap(HistoryHubScreen(repo: repo)));
    await settle(tester);
    expect(find.text(params.first.nameWithUnit), findsOneWidget);

    await tester.tap(find.text('Склад'));
    await settle(tester);
    expect(find.text('Залишок: 4 кг'), findsOneWidget);
    await tester.tap(find.text('Цукор'));
    await settle(tester);
    expect(find.text('Історія: Цукор'), findsOneWidget);
    expect(find.text('Прихід'), findsNWidgets(2));
    expect(find.text('+2 кг'), findsOneWidget);
    expect(find.text('Списано'), findsOneWidget);
    expect(find.text('−3 кг'), findsOneWidget);
    expect(find.text('стало: 4 кг'), findsOneWidget);
    expect(find.textContaining('60 грн · 30 грн/кг'), findsOneWidget);

    // скасувати помилкове списання (найновіший запис — перший)
    await tester.tap(find.byTooltip('Скасувати запис').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(PillButton, 'Скасувати запис'));
    await settle(tester);
    expect(find.text('Скасування запису'), findsOneWidget);
    expect(find.text('стало: 7 кг'), findsNWidgets(2)); // скасування і другий прихід
    expect(find.textContaining('скасовано'), findsOneWidget);
    expect((await repo.getStockItem(id))!.quantity, 7);
  });

  testWidgets('вхід → головний екран → мої пасіки; «назад» - на головний; «Вийти»', (tester) async {
    final auth = FakeAuth();
    await pumpApp(tester, ApiaryApp(repo: repo, auth: auth));
    await settle(tester);
    // вхід обов'язковий: на заставці лише «Увійти через Google»
    expect(find.text('Почати'), findsNothing);
    await tester.tap(find.text('Увійти через Google'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.user, isNotNull);
    // головний екран
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byTooltip('Сканувати QR-код'), findsOneWidget); // значок угорі праворуч
    expect(find.text('Склад'), findsOneWidget);
    expect(find.text('Відгук'), findsOneWidget);
    expect(find.text('Навчання'), findsOneWidget);
    expect(find.text('Що нового'), findsOneWidget);
    expect(find.text('pasichnyk@example.com'), findsOneWidget);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // єдина пасіка — одразу її карта; «назад» — на головний екран (не до списку)
    expect(find.byType(MapScreen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ApiaryListScreen), findsNothing);
    // список пасік — через меню ☰ на карті
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await listViaMenu(tester);
    expect(find.text('Мої пасіки'), findsOneWidget);
    // «назад» із моїх пасік — на головний екран
    await tester.tap(find
        .descendant(of: find.byType(ApiaryListScreen), matching: find.byType(CircleIconButton))
        .first);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget);
    // «Склад» — склад на вкладці «Прихід»
    await tester.tap(find.text('Склад'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StockScreen), findsOneWidget);
    await tester.tap(find
        .descendant(of: find.byType(StockScreen), matching: find.byType(CircleIconButton))
        .first);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // «Вийти» — з підтвердженням, назад на екран входу
    await tester.tap(find.text('Вийти'));
    await settle(tester);
    await tester.tap(find.widgetWithText(PillButton, 'Вийти'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.user, isNull);
    expect(find.text('Увійти через Google'), findsOneWidget);
  });

  testWidgets('вхід не налаштовано в збірці - одразу головний екран', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(configured: false)));
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Увійти через Google'), findsNothing);
    expect(find.text('Вийти'), findsNothing);
  });

  testWidgets('вже увійшов - одразу головний екран, без заставки', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Увійти через Google'), findsNothing);
  });

  testWidgets('вхід скасовано - лишаємось на заставці без помилки; збій - пояснення', (tester) async {
    final auth = FakeAuth(fail: const SignInCancelled());
    await pumpApp(tester, ApiaryApp(repo: repo, auth: auth));
    await settle(tester);
    await tester.tap(find.text('Увійти через Google'));
    await settle(tester);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.textContaining('Не вдалося'), findsNothing);
    auth.fail = const SocketException('offline');
    await tester.tap(find.text('Увійти через Google'));
    await settle(tester);
    expect(find.textContaining('Не вдалося увійти'), findsOneWidget);
  });

  testWidgets('натискання на нагадування відкриває вулик одразу з формою', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!
        .firstWhere((e) => e.isHive);
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    await settle(tester);
    ReminderService.instance.openHiveRequest.value = hive.id;
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(ReminderService.instance.openHiveRequest.value, isNull);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('Заповнити параметри'), findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await settle(tester);
    expect(find.text('Лежак 1'), findsWidgets); // панель цього вулика
    expect(tester.takeException(), isNull);
  });

  testWidgets('нагадування без входу - нічого не відкриває', (tester) async {
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!
        .firstWhere((e) => e.isHive);
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    ReminderService.instance.openHiveRequest.value = hive.id;
    await settle(tester);
    expect(find.byType(MapScreen), findsNothing);
    expect(find.text('Увійти через Google'), findsOneWidget);
  });

  testWidgets('без входу: гість працює, а пізніше входить для синхронізації', (tester) async {
    final auth = FakeAuth();
    await pumpApp(tester, ApiaryApp(repo: repo, auth: auth));
    await settle(tester);
    await tester.tap(find.text('Продовжити без входу'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.guest, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Дані лише на цьому пристрої'), findsOneWidget);
    // пасіки доступні й без входу
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MapScreen), findsOneWidget);
    await listViaMenu(tester);
    expect(find.text('Тестова пасіка'), findsOneWidget);
    // сканування — на головному екрані, у списку пасік його немає
    expect(find.descendant(of: find.byType(ApiaryListScreen), matching: find.text('Сканувати QR-код')),
        findsNothing);
    await tester.tap(find
        .descendant(of: find.byType(ApiaryListScreen), matching: find.byType(CircleIconButton))
        .first);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // пізніше — вхід через Google; дані лишаються
    await tester.tap(find.text('Увійти через Google для синхронізації'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.user, isNotNull);
    expect(auth.guest, isFalse);
    expect(find.text('pasichnyk@example.com'), findsOneWidget);
    expect((await tester.runAsync(() => repo.listApiaries()))!.length, 1);
  });

  testWidgets('гість після перезапуску - одразу головний екран', (tester) async {
    final auth = FakeAuth()..fail = null;
    await auth.continueAsGuest();
    await pumpApp(tester, ApiaryApp(repo: repo, auth: auth));
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Продовжити без входу'), findsNothing);
  });

  testWidgets('карта: довгий дотик до вулика - одразу редагування й перетягування', (tester) async {
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    expect(find.byTooltip('Готово'), findsNothing);
    // вулик (0,0): камера по центру (1,0), клітинка 34
    final g = await tester.startGesture(tester.getCenter(find.byType(InfiniteGrid)) + const Offset(-17, -17));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byTooltip('Готово'), findsOneWidget); // режим редагування
    expect(find.text('Оберіть шаблон'), findsNothing); // без вибору шаблону
    await g.moveBy(const Offset(0, 120));
    await tester.pump();
    await g.up();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель: «Оглянуто, змін немає» - дата огляду сьогодні', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!.firstWhere((e) => e.isHive);
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a, focusElementId: hive.id)));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    await tester.tap(find.text('Змін немає'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    final visitId = (await tester.runAsync(() => repo.baseParameterId('hive', 'visit_start')))!;
    final latest = (await tester.runAsync(() => repo.latestParameterValues(EntityRef.group(groupId))))!;
    expect(latest[visitId], Repository.formatVisitDate(DateTime.now()));
  });

  testWidgets('форма: «Зберегти й далі» з карти - наступний вулик одразу з формою', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // другий вулик нижче лежака — наступний за порядком (зверху вниз)
    await tester.runAsync(() => repo.addGroup(apiaryId, {'0,0': 'hive'}, 0, -4, groupLabel: 'Вулик 2'));
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!
        .firstWhere((e) => e.isHive && e.groupId == groupId);
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a, focusElementId: hive.id, openFill: true)));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.text('Заповнити параметри'), findsOneWidget);
    await tester.tap(find.text('Зберегти й далі →'));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
    // та сама форма — вже з даними наступного вулика (вікно не закривалось)
    expect(find.text('Заповнити параметри'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Вулик 2')),
        findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await settle(tester);
    expect(find.text('Вулик 2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('головний: «Сьогодні оглянути: N» веде до простроченого вулика з формою', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      final period = (await repo.baseParameterId('hive', 'visit_period'))!;
      final start = (await repo.baseParameterId('hive', 'visit_start'))!;
      await repo.addParameterRecord(period, '7', EntityRef.group(groupId));
      await repo.addParameterRecord(start, '01.01.2020', EntityRef.group(groupId));
    });
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Сьогодні оглянути: 1'), findsOneWidget);
    await tester.tap(find.text('Сьогодні оглянути: 1'));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('Заповнити параметри'), findsOneWidget);
    expect(find.text('Зберегти й далі →'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('меню: «Прив\'язати наліпки підряд» - вулики без коду по черзі', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await qrMenu(tester, 'Прив\'язати підряд');
    // у тестах камери немає — код вводиться вручну
    await tester.enterText(find.byType(TextField), 'https://pasika.example/h/1');
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.textContaining('Прив\'язано наліпок: 1'), findsOneWidget);
    final found = await tester.runAsync(() => repo.findByQr('https://pasika.example/h/1'));
    expect(found?.element.groupId, groupId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('форма вулика: підгодівля списується зі складу', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sugar = (await tester.runAsync(() async {
      final id = await repo.addStockItem('Цукор', 'кг');
      await repo.receiveStock(id, 5, total: 150);
      return id;
    }))!;
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!.firstWhere((e) => e.isHive);
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a, focusElementId: hive.id, openFill: true)));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.text('Підгодівля зі складу'), findsOneWidget);
    await tester.tap(find.text('Не списувати'));
    await settle(tester);
    await tester.tap(find.text('Цукор (є 5 кг)').last);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '2'); // рядок «Скільки, кг»
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    final item = (await tester.runAsync(() => repo.getStockItem(sugar)))!;
    expect(item.quantity, 3);
    final moves = (await tester.runAsync(() => repo.stockMoves(sugar)))!;
    expect(moves.last['reason'], 'Підгодівля');
    expect(tester.takeException(), isNull);
  });

  testWidgets('головний: «Час докупити» - номенклатура на мінімальному залишку', (tester) async {
    await tester.runAsync(() async {
      final id = await repo.addStockItem('Рамки', 'шт');
      await repo.receiveStock(id, 3, total: 90);
      await repo.updateStockItem(id, minQuantity: (5,));
    });
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Час докупити: Рамки'), findsOneWidget);
    await tester.tap(find.text('Час докупити: Рамки'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StockScreen), findsOneWidget);
    expect(find.text('Час докупити'), findsOneWidget); // позначка на плитці
  });

  testWidgets('вибір параметрів вулика: обрані вгорі з ручкою перетягування', (tester) async {
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!.firstWhere((e) => e.isHive);
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: hive)));
    await settle(tester);
    final chosen = (await tester.runAsync(() => repo.attachedParameterIds(hive.entity, elType: 'hive')))!;
    // ручка — у кожного обраного (базові теж), у необраних — немає
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(chosen.length));
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('переоблік списком: записуються лише розбіжності', (tester) async {
    final (sugar, frames) = (await tester.runAsync(() async {
      final a = await repo.addStockItem('Цукор', 'кг');
      await repo.receiveStock(a, 5, total: 150);
      final b = await repo.addStockItem('Рамки', 'шт');
      await repo.receiveStock(b, 10, total: 300);
      return (a, b);
    }))!;
    await tester.pumpWidget(wrap(StockScreen(repo: repo, initialTab: StockOp.inventory)));
    await settle(tester);
    await tester.tap(find.text('Списком'));
    await settle(tester);
    expect(find.text('За обліком: 5 кг'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '5'), '4');
    await tester.tap(find.text('Зберегти переоблік'));
    await settle(tester);
    await settle(tester);
    expect((await tester.runAsync(() => repo.getStockItem(sugar)))!.quantity, 4);
    expect((await tester.runAsync(() => repo.getStockItem(frames)))!.quantity, 10);
    final moves = (await tester.runAsync(() => repo.stockMoves(frames)))!;
    expect(moves.where((m) => m['kind'] == 'inv'), isEmpty); // збіглось — без запису
  });

  testWidgets('нова номенклатура одразу з приходом', (tester) async {
    await tester.pumpWidget(wrap(StockScreen(repo: repo)));
    await settle(tester);
    await tester.tap(find.text('Додати номенклатуру'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Назва'), 'Вощина');
    await tester.tap(find.text('кг'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Кількість'), '3');
    await tester.enterText(find.widgetWithText(TextField, 'Вартість'), '900');
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    await settle(tester);
    final item = (await tester.runAsync(() => repo.listStockItems()))!.firstWhere((i) => i.name == 'Вощина');
    expect(item.quantity, 3);
  });

  testWidgets('параметри: «Для всіх вуликів пасіки» - однаковий набір усім', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final other = (await tester.runAsync(
        () => repo.addGroup(apiaryId, {'0,0': 'hive'}, 6, 6, groupLabel: 'Вулик 7')))!;
    final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!
        .firstWhere((e) => e.isHive && e.groupId == groupId);
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: hive)));
    await settle(tester);
    await tester.tap(find.descendant(
        of: find.widgetWithText(ListCard, 'Вага'), matching: find.byType(CheckToggle)));
    await settle(tester);
    await tester.tap(find.text('Для всіх вуликів пасіки (такий самий набір і порядок)'));
    await settle(tester);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    final a = (await tester.runAsync(() => repo.attachedParameterIds(EntityRef.group(groupId), elType: 'hive')))!;
    final b = (await tester.runAsync(() => repo.attachedParameterIds(EntityRef.group(other), elType: 'hive')))!;
    expect(a, contains(paramId));
    expect(b, a);
  });

  test('id_token Google → користувач', () {
    String part(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final token = '${part({'alg': 'RS256'})}.${part({'sub': '42', 'email': 'a@b.c', 'name': 'Бджоляр'})}.sig';
    final u = GoogleAuthService.userFromIdToken(token)!;
    expect(u.id, '42');
    expect(u.email, 'a@b.c');
    expect(u.name, 'Бджоляр');
    expect(GoogleAuthService.userFromIdToken('bad'), isNull);
  });

  testWidgets('головний екран: «Навчання» відкриває режим навчання', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    await settle(tester);
    await tester.tap(find.text('Навчання'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.descendant(of: find.byType(TutorialScreen), matching: find.text('Навчання')),
        findsOneWidget);
    expect(find.text('Базові поняття'), findsOneWidget);
    await tester.tap(find
        .descendant(of: find.byType(TutorialScreen), matching: find.byType(CircleIconButton))
        .first); // «назад»
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('навчання: «Базові поняття» - порожні «Мої пасіки» з підказкою пасічника',
      (tester) async {
    await tester.pumpWidget(wrap(TutorialScreen(openSandbox: () async {
      final r = Repository(await AppDatabase.openSandbox(databaseFactoryFfiNoIsolate));
      await r.prepareLikeFreshInstall();
      return r;
    })));
    await settle(tester);
    await tester.tap(find.text('Базові поняття'));
    await settle(tester);
    await settle(tester);
    expect(find.text('Мої пасіки'), findsOneWidget);
    // пісочниця: справжніх пасік не видно, замість порожнього тексту — підказка
    expect(find.text('Тестова пасіка'), findsNothing);
    expect(find.textContaining('Колего, пропоную тобі вибір'), findsOneWidget);
    expect(find.textContaining('«Створити карту»'), findsOneWidget);
    expect(find.text('Ще немає жодної пасіки.\nСтвори її кнопкою нижче.'), findsNothing);
    // «назад» — до плиток уроків, а не на заставку
    await tester.tap(find
        .descendant(of: find.byType(ApiaryListScreen), matching: find.byType(CircleIconButton))
        .first);
    await settle(tester);
    expect(find.text('Базові поняття'), findsOneWidget);
  });

  testWidgets('навчання: карта - «Редагувати», шаблон, вулик, «Готово», свій вулик, «Оглянути»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(TutorialScreen(openSandbox: () async {
      final r = Repository(await AppDatabase.openSandbox(databaseFactoryFfiNoIsolate));
      await r.prepareLikeFreshInstall();
      return r;
    })));
    await settle(tester);
    await tester.tap(find.text('Базові поняття'));
    await settle(tester);
    await settle(tester);
    await tester.tap(find.text('+  Створити карту'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.textContaining('вуликів то нема'), findsOneWidget);
    expect(find.textContaining('«Редагування»'), findsOneWidget);
    // підказка не заважає натиснути саму кнопку
    await tester.tap(find.byTooltip('Редагування'));
    await settle(tester);
    expect(find.text('Оберіть шаблон'), findsOneWidget);
    // як після встановлення: готові шаблони вже є
    expect(find.byTooltip('Вулик (1×1)'), findsOneWidget);
    // пасічник називає готові шаблони
    expect(find.textContaining('потурбувався'), findsOneWidget);
    expect(find.textContaining('«Вулик» і «Лежак»'), findsOneWidget);
    expect(find.textContaining('Обери «Вулик»'), findsOneWidget);

    // обрали шаблон — «Натисни на карту»
    await tester.tap(find.byTooltip('Вулик (1×1)'));
    await settle(tester);
    expect(find.textContaining('Натисни на карту'), findsOneWidget);
    final spot = tester.getCenter(find.byType(InfiniteGrid)) - const Offset(150, 150);
    await tester.tapAt(spot);
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    // «геть не туди» — перетягнути на підсвічену клітинку
    expect(find.textContaining('геть не туди'), findsOneWidget);
    // поки не перетягнули — «Готово» не натискається (завіса уроку)
    await tester.tap(find.byTooltip('Готово'), warnIfMissed: false);
    await settle(tester);
    expect(find.textContaining('геть не туди'), findsOneWidget);
    final target = tester.getCenter(find.byKey(const ValueKey('lesson-target')));
    await tester.timedDragFrom(spot, target - spot, const Duration(milliseconds: 400));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    // вулик стоїть — «Підтверди вибір», «Готово» в медовому ободку
    expect(find.textContaining('Підтверди вибір'), findsOneWidget);
    expect(find.ancestor(of: find.byTooltip('Готово'), matching: find.byType(HoneyRing)),
        findsOneWidget);
    await tester.tap(find.byTooltip('Готово'));
    await settle(tester);
    expect(find.textContaining('З легким стартом'), findsNothing);
    expect(find.textContaining('Не час відпочивати'), findsOneWidget);
    expect(find.textContaining('«Вулик 1»'), findsOneWidget);
    // натиснули на свій вулик — панель і завдання «Проведи огляд»
    await tester.tapAt(target);
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.textContaining('короткі замітки'), findsOneWidget);
    // друга хмарка - після дотику; кнопка «Оглянути» тоді в медовому ободку
    await tester.tap(find.textContaining('короткі замітки'));
    await settle(tester);
    expect(find.textContaining('проведи огляд вулика'), findsOneWidget);
    expect(find.text('Оглянути'), findsOneWidget);

    // з уроку не вийти системним «назад» і немає меню ☰ — лише «Назад» угорі
    expect(find.byTooltip('Меню'), findsNothing);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(MapScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MapScreen), findsNothing);
    expect(find.byType(ApiaryListScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(ApiaryListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('навчання: огляд з ведмежам і «Я сам собі маг пасіки» - пасіка стає справжньою',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(TutorialScreen(
      realRepo: repo,
      openSandbox: () async {
        final r = Repository(await AppDatabase.openSandbox(databaseFactoryFfiNoIsolate));
        await r.prepareLikeFreshInstall();
        return r;
      },
    )));
    await settle(tester);
    await tester.tap(find.text('Базові поняття'));
    await settle(tester);
    await settle(tester);
    await tester.tap(find.text('+  Створити карту'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    await tester.tap(find.byTooltip('Редагування'));
    await settle(tester);
    await tester.tap(find.byTooltip('Вулик (1×1)'));
    await settle(tester);
    final spot = tester.getCenter(find.byType(InfiniteGrid)) - const Offset(150, 150);
    await tester.tapAt(spot);
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    final target = tester.getCenter(find.byKey(const ValueKey('lesson-target')));
    await tester.timedDragFrom(spot, target - spot, const Duration(milliseconds: 400));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    await tester.tap(find.byTooltip('Готово'));
    await settle(tester);
    await tester.tapAt(target);
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    await tester.tap(find.textContaining('короткі замітки'));
    await settle(tester);
    await tester.tap(find.text('Оглянути'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    // у формі: пояснення, ведмежа, комірки по черзі
    expect(find.textContaining('Це параметри вулика'), findsOneWidget);
    await tester.tap(find.textContaining('Це параметри вулика'));
    await settle(tester);
    expect(find.textContaining('Мій помічник'), findsNothing);
    expect(find.textContaining('Грр...'), findsOneWidget);
    await tester.tap(find.textContaining('Грр...'));
    await settle(tester);
    expect(find.textContaining('В тебе матка'), findsOneWidget);
    await tester.tap(find.byTooltip('Білий'));
    await settle(tester);
    expect(find.textContaining('Заглянеш сам через'), findsOneWidget);
    await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '3');
    await settle(tester);
    expect(find.textContaining('Збережи, бо я більше'), findsOneWidget);
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.textContaining('Синя пігулка'), findsOneWidget);
    await tester.tap(find.text('Синя'));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
    await tester.pump(const Duration(seconds: 1));
    // справжня база: нова пасіка з вуликом і записами огляду
    final apiaries = (await tester.runAsync(() => repo.listApiaries()))!;
    expect(apiaries.length, 2);
    final moved = apiaries.firstWhere((a) => a.id != apiaryId);
    final els = (await tester.runAsync(() => repo.listElements(moved.id)))!;
    expect(els.where((e) => e.isHive), isNotEmpty);
    final period = (await tester.runAsync(() => repo.baseParameterId('hive', 'visit_period')))!;
    final hive = els.firstWhere((e) => e.isHive);
    final latest = (await tester.runAsync(() => repo.latestParameterValues(hive.entity)))!;
    expect(latest[period], '3');
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byTooltip('Меню'), findsOneWidget); // уже справжня карта, не урок
    // пасічник востаннє просить відкрити меню навігації
    expect(find.textContaining('Наостанок покажу меню'), findsOneWidget);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    expect(find.textContaining('Наостанок покажу меню'), findsNothing);
    // у меню - одна репліка пасічника про навчання
    expect(find.textContaining('керувати своєю пасікою'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('навчання: пасічник проходить по пунктах меню навігації', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(AppDrawer(repo: repo, currentApiary: a, tour: true)));
    await settle(tester);
    expect(find.textContaining('усі твої пасіки в одному місці'), findsOneWidget);
    for (final t in ['рамки, корми, ліки', 'зміни показників', 'час на вітер',
        'тут є все: шаблони', 'спеціалізоване навчання', 'поділитись ідеєю']) {
      await tester.tap(find.text('Далі'));
      await settle(tester);
      expect(find.textContaining(t), findsOneWidget);
    }
    expect(find.text('Зрозуміло'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('перший «Почати»: пасічник пропонує вибір, синя - без навчання', (tester) async {
    // окрема порожня база (setUp уже створив пасіку в основній)
    final fresh = (await tester.runAsync(() async {
      final r = Repository(await AppDatabase.openSandbox(databaseFactoryFfiNoIsolate));
      await r.init();
      return r;
    }))!;
    addTearDown(() async => fresh.db.close());
    await pumpApp(tester, ApiaryApp(repo: fresh, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    expect(find.textContaining('Колего, пропоную тобі вибір'), findsOneWidget);
    expect(find.text('Червона'), findsOneWidget);
    await tester.tap(find.text('Синя'));
    await settle(tester);
    expect(find.textContaining('Колего, пропоную'), findsNothing);
    expect(await tester.runAsync(() => fresh.getMeta('intro_done')), '1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('заставка -> список пасік -> карта', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    expect(find.text('Vulyk'), findsOneWidget);

    await toApiaries(tester);
    expect(find.text('Тестова пасіка'), findsOneWidget);

    await tester.tap(find.byTooltip('Відкрити'));
    await settle(tester);
    expect(find.text('Тестова пасіка'), findsWidgets); // назва в шапці карти
    expect(tester.takeException(), isNull);
  });

  testWidgets('шаблони', (tester) async {
    await tester.pumpWidget(wrap(TemplatesScreen(repo: repo)));
    await settle(tester);
    expect(find.text('Лежак'), findsOneWidget);
    // плитка — мініатюра шматка карти з шаблоном
    expect(find.byType(SceneThumbnail), findsOneWidget);
    expect(find.text('2×2'), findsOneWidget);
    expect(find.text('Створити шаблон'), findsOneWidget);
    final t = (await tester.runAsync(() => repo.getTemplate(templateId)))!;
    expect(templateSceneCells(t).length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('редактор шаблону', (tester) async {
    await tester.pumpWidget(wrap(TemplateEditorScreen(repo: repo, templateId: templateId)));
    await settle(tester);
    expect(find.text('Лежак'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('список параметрів', (tester) async {
    final el = (await tester.runAsync(() => repo.getGroupElements(groupId)))!.first;
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: el)));
    await settle(tester);
    expect(find.text('Вага'), findsOneWidget);
    expect(find.text('Мітка матки'), findsOneWidget);
    // обов'язкові (базові) — вгорі, з замочком і без кнопки редагування
    expect(tester.getTopLeft(find.text('Мітка матки')).dy,
        lessThan(tester.getTopLeft(find.text('Вага')).dy));
    expect(find.byType(LockMark), findsWidgets);
    // у списку конкретного вулика параметри не редагуються й не видаляються
    // (лише в меню → «Характеристики»)
    expect(find.byTooltip('Редагувати'), findsNothing);
    expect(find.byTooltip('Видалити'), findsNothing);
    await tester.tap(find.byTooltip('Новий параметр'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Сила сім\'ї');
    await tester.tap(find.text('Зберегти').last);
    await settle(tester);
    expect(tester.getTopLeft(find.text('Мітка матки')).dy,
        lessThan(tester.getTopLeft(find.text('Сила сім\'ї')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('історія', (tester) async {
    final p = (await tester.runAsync(() => repo.getParameter(paramId)))!;
    await tester.pumpWidget(wrap(HistoryScreen(repo: repo, parameter: p)));
    await settle(tester);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('довга назва пасіки не переповнює верхню панель карти', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final id = (await tester.runAsync(() => repo.addApiary('Дуже-дуже довга назва пасіки '
        'на схилі біля річки, де багато липи та гречки')))!;
    final a = (await tester.runAsync(() => repo.getApiary(id)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('меню: Характеристики - каталог без вибору й без «Зберегти»', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    await tester.tap(find.byTooltip('Відкрити')); // меню є лише на карті пасіки
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Налаштування')); // характеристики й шаблони — тут
    await settle(tester);
    await tester.ensureVisible(find.text('Характеристики'));
    await settle(tester);
    await tester.tap(find.text('Характеристики'));
    await settle(tester);
    await settle(tester);
    expect(find.text('Вага'), findsOneWidget);
    expect(find.text('Зберегти'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('нова пасіка «Пасіка 1»: створення -> карта -> назад на головний -> «Почати» -> плитка в списку', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    await tester.tap(find.text('+  Створити карту'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    // одразу карта нової пасіки з типовою назвою
    expect(find.text('Пасіка 1'), findsWidgets); // шапка відкритої карти
    // «Головної» в меню немає — головний екран кнопкою «назад»
    for (var i = 0; i < 3 && find.byType(HomeScreen).evaluate().isEmpty; i++) {
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget); // «Головна» — головний екран
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    // «Почати» — остання відкрита пасіка; список — через меню ☰
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('Пасіка 1'), findsWidgets); // шапка карти
    await listViaMenu(tester);
    expect(find.text('Пасіка 1'), findsOneWidget); // плитка у списку
    expect(find.text('Тестова пасіка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('редактор шаблону: порожній шаблон не зберігається', (tester) async {
    await tester.pumpWidget(wrap(TemplateEditorScreen(repo: repo)));
    await settle(tester);
    await tester.tap(find.byTooltip('Зберегти'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Додайте хоча б одну клітинку'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // таймер попередження
    final list = (await tester.runAsync(() => repo.listTemplates()))!;
    expect(list.length, 1); // лише шаблон із setUp
  });

  testWidgets('список пасік: видалення без підтвердження, з «Відмінити»', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    expect(find.text('Тестова пасіка'), findsOneWidget);

    // видалили — зникла одразу; «Відмінити» — повернулась
    await tester.tap(find.byTooltip('Видалити'));
    await settle(tester);
    expect(find.text('Тестова пасіка'), findsNothing);
    expect(find.text('Пасіку «Тестова пасіка» видалено'), findsOneWidget);
    await tester.tap(find.text('Відмінити'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Тестова пасіка'), findsOneWidget);
    expect((await tester.runAsync(() => repo.listApiaries()))!.length, 1);

    // видалили й не відмінили — повідомлення зникло, пасіку видалено з бази
    await tester.tap(find.byTooltip('Видалити'));
    await settle(tester);
    // таймер повідомлення стартує після його появи — час іде кроками
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect((await tester.runAsync(() => repo.listApiaries()))!, isEmpty);
    expect(find.textContaining('Ще немає жодної пасіки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Оглянути»: спорожнене поле й «Очистити» дату записують порожнє значення',
      (tester) async {
    const text = Parameter(id: 't', name: 'Нотатка');
    const date = Parameter(id: 'd', name: 'Дата огляду', dataType: DataTypes.date);
    const untouched = Parameter(id: 'u', name: 'Вага', dataType: DataTypes.text);
    FillResult? result;
    await tester.pumpWidget(wrap(Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async => result = await showFillValuesDialog(
            ctx,
            params: const [text, date, untouched],
            latest: const {'t': 'привіт', 'd': '01.02.2026', 'u': '5'},
          ),
          child: const Text('відкрити'),
        ),
      ),
    )));
    await tester.tap(find.text('відкрити'));
    await settle(tester);

    // спорожнюємо текстове поле
    await tester.enterText(find.byType(TextField).first, '');
    // очищаємо дату через календар
    await tester.tap(find.text('01.02.2026')); // клітинка дати відкриває календар
    await settle(tester);
    await tester.tap(find.byTooltip('Очистити'));
    await settle(tester);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(result?.values, {'t': '', 'd': ''}); // "Вага" не змінювалась — її немає
  });

  testWidgets('вибір іконки: вулику - лише вулики, перешкоді - лише перешкоди, різне - дві плитки',
      (tester) async {
    Future<void> open(String? type) async {
      await tester.pumpWidget(wrap(Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
              onPressed: () => pickIcon(ctx, elType: type), child: const Text('іконка')),
        ),
      )));
      await tester.tap(find.text('іконка'));
      await settle(tester);
    }

    await open('hive');
    expect(find.byTooltip('Вулик'), findsOneWidget);
    expect(find.byTooltip('Гора'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await open('obstacle');
    expect(find.byTooltip('Гора'), findsOneWidget);
    expect(find.byTooltip('Вулик'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    await open(null);
    expect(find.text('Вулики'), findsOneWidget);
    expect(find.text('Перешкоди'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Оглянути»: «Так / Ні» кнопками, «Список» - випадаючим списком', (tester) async {
    const yn = Parameter(id: 'b', name: 'Є розплід', dataType: DataTypes.bool_);
    const ch = Parameter(
        id: 'c', name: 'Сила сім\'ї', dataType: DataTypes.choice, options: ['Слабка', 'Сильна']);
    FillResult? result;
    await tester.pumpWidget(wrap(Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async => result =
              await showFillValuesDialog(ctx, params: const [yn, ch], latest: const {}),
          child: const Text('відкрити'),
        ),
      ),
    )));
    await tester.tap(find.text('відкрити'));
    await settle(tester);
    await tester.tap(find.text('Так'));
    await settle(tester);
    await tester.tap(find.text('Обрати'));
    await settle(tester);
    await tester.tap(find.text('Сильна').last);
    await settle(tester);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(result?.values, {'b': 'Так', 'c': 'Сильна'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('новий параметр «Список»: варіанти задаються в самій формі', (tester) async {
    await tester.pumpWidget(wrap(ParametersScreen.catalog(repo: repo)));
    await settle(tester);
    await tester.tap(find.byTooltip('Новий параметр'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Сила сім\'ї');
    await tester.tap(find.text('Список'));
    await settle(tester);
    expect(find.text('Варіанти списку'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Слабка');
    await tester.tap(find.byTooltip('Додати варіант'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Сильна'); // недописаний — теж збережеться
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    final p = (await tester.runAsync(() => repo.listParameters()))!
        .firstWhere((p) => p.name == 'Сила сім\'ї');
    expect(p.dataType, DataTypes.choice);
    expect(p.options, ['Слабка', 'Сильна']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Оглянути»: старе значення не того типу не блокує збереження інших полів',
      (tester) async {
    const n = Parameter(id: 'n', name: 'Рамки', dataType: DataTypes.int_);
    const note = Parameter(id: 't', name: 'Нотатка');
    FillResult? result;
    await tester.pumpWidget(wrap(Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () async => result = await showFillValuesDialog(
            ctx,
            params: const [n, note],
            latest: const {'n': 'багато', 't': ''},
          ),
          child: const Text('відкрити'),
        ),
      ),
    )));
    await tester.tap(find.text('відкрити'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'огляд');
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(result?.values, {'t': 'огляд'});
    expect(result?.next, isFalse);
  });

  test('числові поля: зайве не «з\'їдає» введене', () {
    final f = WholeValueFormatter(RegExp(r'^-?\d*$'));
    TextEditingValue v(String t) => TextEditingValue(text: t);
    expect(f.formatEditUpdate(v('1'), v('1.')).text, '1'); // крапку не приймає
    expect(f.formatEditUpdate(v('1'), v('15')).text, '15');
    expect(f.formatEditUpdate(v(''), v(' 25')).text, '25'); // вставка з пробілом
    expect(f.formatEditUpdate(v('2'), v('2-5')).text, '2');
    final g = WholeValueFormatter(RegExp(r'^-?\d*[.,]?\d*$'));
    expect(g.formatEditUpdate(v('12'), v('12,5')).text, '12,5');
    expect(g.formatEditUpdate(v('12,5'), v('12,5,')).text, '12,5');
  });

  testWidgets('список параметрів перешкоди: без обов\'язкових характеристик вулика', (tester) async {
    final obstacle = (await tester.runAsync(() => repo.getGroupElements(groupId)))!
        .firstWhere((e) => !e.isHive);
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: obstacle)));
    await settle(tester);
    expect(find.text('Вага'), findsOneWidget);
    expect(find.text('Мітка матки'), findsNothing);
    expect(find.byType(LockMark), findsNothing);
  });

  testWidgets('меню: сканер QR відкриває вулик на карті з панеллю', (tester) async {
    // у тестах камери немає — код вводиться вручну (як на комп'ютері);
    // високе вікно, щоб уся панель (разом із рядком QR) була на екрані
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => repo.linkQr('https://pasika.example/h/7', EntityRef.group(groupId)));
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    await tester.tap(find.byTooltip('Відкрити')); // меню є лише на карті пасіки
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await qrMenu(tester, 'Сканувати');
    await tester.enterText(find.byType(TextField), 'https://pasika.example/h/7');
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    // після сканування одразу форма «Оглянути» (людина біля вулика)
    expect(find.text('Заповнити параметри'), findsOneWidget);
    await tester.tap(find.text('Скасувати'));
    await settle(tester);
    expect(find.text('Тестова пасіка'), findsWidgets); // карта пасіки
    expect(find.text('Лежак 1'), findsWidgets); // панель вулика
    expect(find.text('https://pasika.example/h/7'), findsOneWidget); // код на панелі
    expect(tester.takeException(), isNull);
  });

  testWidgets('меню: невідомий QR-код - пояснення, як прив\'язати', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    await tester.tap(find.byTooltip('Відкрити')); // меню є лише на карті пасіки
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await qrMenu(tester, 'Сканувати');
    await tester.enterText(find.byType(TextField), 'невідомий');
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Вулик не знайдено'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('генератор QR: вулики без коду обрані одразу -> «Згенерувати» -> наліпки', (tester) async {
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(QrGenerateScreen(repo: repo, apiary: a)));
    await settle(tester);
    // дві сусідні клітинки-вулики групи злиті в ОДИН вулик: один код
    expect(find.textContaining('0 з 1'), findsOneWidget);
    // вулики без коду обрані одразу
    expect(find.text('Згенерувати (1)'), findsOneWidget);
    await tester.tap(find.text('Згенерувати (1)'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Наліпки (1)'), findsOneWidget);
    final ids = (await tester.runAsync(() => repo.elementIdsWithQr(apiaryId)))!;
    expect(ids.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('наліпка малюється в PNG, а PDF збирається', (tester) async {
    final res = await tester.runAsync(() async {
      final png = await renderLabelPng(
          const QrLabel(code: 'MYAPIARY:H:1:abcdef12', name: 'Лежак 1 · 2', number: 1));
      final pdf = await buildLabelsPdf(List.filled(13, png)); // 2 сторінки
      return (png, pdf);
    });
    final (png, pdf) = res!;
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });

  test('PDF наліпок: сітка вміщається на A4 повністю (12 на аркуш)', () {
    final (cols, rows) = labelsGridA4();
    expect((cols, rows), (3, 4));
    // жоден ряд/стовпець не виходить за поля
    expect(cols * kPdfLabelWmm + (cols - 1) * kPdfGapMm, lessThanOrEqualTo(210 - 2 * kPdfMarginMm));
    expect(rows * pdfLabelHmm + (rows - 1) * kPdfGapMm, lessThanOrEqualTo(297 - 2 * kPdfMarginMm));
  });

  test('назва вулика на наліпці: номер вулика-об\'єкта в групі', () {
    // три окремі вулики групи (не сусіди) і перешкода
    const g1 = MapElement(id: 'a', x: 0, y: 2, label: 'Лежак 1', groupId: 'g');
    const g2 = MapElement(id: 'b', x: 2, y: 2, label: 'Лежак 1', groupId: 'g');
    const g3 = MapElement(id: 'c', x: 0, y: 0, label: 'Лежак 1', groupId: 'g');
    const o = MapElement(id: 'o', x: 1, y: 0, type: 'obstacle', label: 'Лежак 1', groupId: 'g');
    const solo = MapElement(id: 's', x: 5, y: 5);
    final all = [g3, o, g2, g1, solo];
    expect(hiveLabelName(g1, all), 'Лежак 1 · 1');
    expect(hiveLabelName(g2, all), 'Лежак 1 · 2');
    expect(hiveLabelName(g3, all), 'Лежак 1 · 3');
    expect(hiveLabelName(solo, all), 'Вулик');
    // сусідні клітинки — один вулик, без номера
    const m1 = MapElement(id: 'm1', x: 0, y: 0, label: 'Довгий', groupId: 'h');
    const m2 = MapElement(id: 'm2', x: 1, y: 0, label: 'Довгий', groupId: 'h');
    expect(hiveLabelName(m2, [m1, m2]), 'Довгий');
    expect(hiveObjects([m2, m1, solo]).map((o) => [for (final e in o) e.id]).toList(), [
      ['s'],
      ['m1', 'm2'],
    ]);
  });

  testWidgets('генератор QR з меню карти відкриває цю ж пасіку без питання', (tester) async {
    await tester.runAsync(() => repo.addApiary('Друга пасіка')); // пасік кілька
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await qrMenu(tester, 'Генерувати');
    await settle(tester);
    expect(find.text('Для якої пасіки?'), findsNothing);
    expect(find.text('QR-коди: Тестова пасіка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('генератор QR: перегенерація питає підтвердження й вимикає старі коди',
      (tester) async {
    final els = (await tester.runAsync(() => repo.getGroupElements(groupId)))!;
    final hives = els.where((e) => e.isHive).toList()..sort((a, b) => a.x.compareTo(b.x));
    final old = (await tester.runAsync(() => repo.generateQrForElements(hives)))!;
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(QrGenerateScreen(repo: repo, apiary: a)));
    await settle(tester);
    expect(find.textContaining('1 з 1'), findsOneWidget); // один злитий вулик

    // вулики (0,0) і (1,0), перешкода (0,-1): камера центрована на (1, 0),
    // клітинка 34 px -> центри вуликів на (-17,-17) і (+17,-17) від центру
    final c = tester.getCenter(find.byType(InfiniteGrid));
    await tester.tapAt(c + const Offset(17, -17)); // будь-яка клітинка — весь вулик
    await tester.pump();
    await tester.tapAt(c + const Offset(-17, 17)); // перешкода — не обирається
    await tester.pump();
    expect(find.text('Згенерувати (1)'), findsOneWidget);

    await tester.tap(find.text('Згенерувати (1)'));
    await settle(tester);
    expect(find.text('Перегенерувати коди?'), findsOneWidget);
    await tester.tap(find.text('Скасувати')); // скасували — старі коди живі
    await settle(tester);
    expect((await tester.runAsync(() => repo.findByQr(old.first.code))), isNotNull);

    await tester.tap(find.text('Згенерувати (1)'));
    await settle(tester);
    await tester.tap(find.text('Перегенерувати'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Наліпки (1)'), findsOneWidget);
    // старі коди обох клітинок вимкнено, новий — один на весь вулик
    for (var i = 0; i < hives.length; i++) {
      expect((await tester.runAsync(() => repo.findByQr(old[i].code))), isNull);
    }
    final now = (await tester.runAsync(() => repo.qrForObject(hives)))!;
    expect(old.map((c) => c.code), isNot(contains(now)));
    expect((await tester.runAsync(() => repo.qrForElement(hives[1]))), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('у списку пасік меню немає - лише на карті', (tester) async {
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth()));
    await settle(tester);
    await toApiaries(tester);
    expect(find.byTooltip('Меню'), findsNothing);
    await tester.tap(find.byTooltip('Відкрити'));
    await settle(tester);
    expect(find.byTooltip('Меню'), findsOneWidget);
  });

  testWidgets('редагування карти: без «Перейменувати»; немає шаблонів - «Створити шаблон» відкриває новий шаблон',
      (tester) async {
    await tester.runAsync(() => repo.deleteTemplate(templateId)); // шаблонів немає
    final id = (await tester.runAsync(() => repo.addApiary('Пасіка')))!;
    final a = (await tester.runAsync(() => repo.getApiary(id)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    // «Редагувати» одразу пропонує шаблони
    await tester.tap(find.byTooltip('Редагування'));
    await settle(tester);
    expect(find.text('Ще немає жодного шаблону.'), findsOneWidget);
    await tester.tap(find.text('Створити шаблон'));
    await settle(tester);
    expect(find.text('Новий шаблон'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('розміщення шаблону: щойно поставлений об\'єкт можна одразу перетягнути', (tester) async {
    final id = (await tester.runAsync(() => repo.addApiary('Пасіка')))!;
    final a = (await tester.runAsync(() => repo.getApiary(id)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.byTooltip('Редагування')); // одразу вибір шаблону
    await settle(tester);
    await tester.tap(find.byTooltip('Лежак (2×2)'));
    await settle(tester);
    final center = tester.getCenter(find.byType(InfiniteGrid));
    await tester.tapAt(center);
    await settle(tester);
    final before = (await tester.runAsync(() => repo.listElements(id)))!;
    expect(before.length, 3);
    // режим розміщення ще активний, але дотик по об'єкту — перетягування
    await tester.dragFrom(center, const Offset(0, 260));
    await settle(tester);
    final after = (await tester.runAsync(() => repo.listElements(id)))!;
    expect(after.length, 3, reason: 'перетягування не повинне ставити новий об\'єкт');
    final moved = {for (final e in after) e.id: (e.x, e.y)};
    expect(before.any((e) => moved[e.id] != (e.x, e.y)), isTrue);
    // одне «Готово» завершує і розміщення, і редагування
    await tester.tap(find.byTooltip('Готово'));
    await settle(tester);
    expect(find.byTooltip('Готово'), findsNothing);
    expect(find.byTooltip('Редагування'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('редактор шаблону: тап - інформація, режим переміщення - тягнути й кнопки',
      (tester) async {
    await tester.pumpWidget(wrap(TemplateEditorScreen(repo: repo, templateId: templateId)));
    await settle(tester);
    // вулики шаблону — клітинки (0,1),(1,1), камера по центру (1,1), клітинка 32
    final hive = tester.getCenter(find.byType(InfiniteGrid)) + const Offset(-16, -16);
    await tester.tapAt(hive);
    await settle(tester);
    expect(find.byType(CharacteristicsPanel), findsOneWidget);
    expect(find.byTooltip('Повернути'), findsNothing);
    // у режимі інформації перетягування не рухає вулик — лише зсуває поле
    await tester.dragFrom(hive, const Offset(0, -96));
    await settle(tester);
    final undo = find.byWidgetPredicate((w) => w is CircleIconButton && w.tooltip == 'Скасувати');
    expect(tester.widget<CircleIconButton>(undo).onPressed, isNull); // змін немає
    final moved = hive + const Offset(0, -96); // поле зсунулось разом із пальцем

    await tester.tap(find.byTooltip('Переміщення'));
    await settle(tester);
    expect(find.byType(CharacteristicsPanel), findsNothing);
    await tester.tapAt(moved);
    await settle(tester);
    expect(find.byTooltip('Повернути'), findsOneWidget); // над обраним
    expect(find.byType(CharacteristicsPanel), findsNothing);
    await tester.dragFrom(moved, const Offset(0, -96));
    await settle(tester);
    await tester.tap(find.byTooltip('Зберегти'));
    await settle(tester);
    final t = (await tester.runAsync(() => repo.getTemplate(templateId)))!;
    expect(t.height, 5); // вулики піднялись на 3 клітинки над деревами
    expect(tester.takeException(), isNull);
  });

  testWidgets('редагування карти: над обраним об\'єктом - «Повернути» й «Видалити»', (tester) async {
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.byTooltip('Редагування'));
    await settle(tester);
    await tester.tapAt(const Offset(12, 300)); // закрити вибір шаблону — лишаємось у редагуванні
    await settle(tester);
    expect(find.byTooltip('Повернути'), findsNothing); // унизу «Повернути» немає
    // вулик (0,0): камера по центру (1,0), клітинка 34
    await tester.tapAt(tester.getCenter(find.byType(InfiniteGrid)) + const Offset(-17, -17));
    await settle(tester);
    expect(find.byTooltip('Повернути'), findsOneWidget); // лише над обраним об'єктом
    expect(find.byTooltip('Видалити'), findsNWidgets(2));
    expect(find.byType(CharacteristicsPanel), findsNothing); // інформація не відкривається
    expect(tester.takeException(), isNull);
  });

  testWidgets('збій відкриття бази: пояснення й «Спробувати ще раз» замість порожнього екрана',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(StartupErrorApp(
      error: 'database is locked',
      onRetry: () async => retried++,
    ));
    expect(find.text('Не вдалося відкрити дані пасіки'), findsOneWidget);
    expect(find.text('database is locked'), findsOneWidget);
    await tester.tap(find.text('Спробувати ще раз'));
    await tester.pump();
    expect(retried, 1);
  });

  group("зворотний зв'язок", () {
    Widget host(Future<FeedbackResult> Function(String) send) => MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx)
                      .push(MaterialPageRoute(builder: (_) => FeedbackScreen(send: send))),
                  child: const Text('відкрити'),
                ),
              ),
            ),
          ),
        );

    testWidgets('напис, порожній текст і успішна відправка', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(host((m) async {
        sent.add(m);
        return FeedbackResult.sent;
      }));
      await tester.tap(find.text('відкрити'));
      await tester.pumpAndSettle();
      expect(find.text(FeedbackScreen.intro), findsOneWidget);

      await tester.tap(find.text('Надіслати'));
      await tester.pump();
      expect(find.text('Напишіть хоча б кілька слів'), findsOneWidget);
      expect(sent, isEmpty);

      await tester.enterText(find.byType(TextField), 'Додайте темну тему');
      await tester.tap(find.text('Надіслати'));
      await tester.pumpAndSettle();
      expect(sent, ['Додайте темну тему']);
      // повідомлення внизу, без вікна «Гаразд»; екран закрився сам
      expect(find.text('Дякуємо! Ваше повідомлення надіслано.'), findsOneWidget);
      expect(find.text('Гаразд'), findsNothing);
      expect(find.byType(FeedbackScreen), findsNothing);
    });

    testWidgets('не вдалося - текст лишається, можна скопіювати', (tester) async {
      await tester.pumpWidget(host((_) async => FeedbackResult.failed));
      await tester.tap(find.text('відкрити'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Не працює сканер');
      await tester.tap(find.text('Надіслати'));
      await tester.pumpAndSettle();
      expect(find.text('Не надіслано'), findsOneWidget);
      expect(find.textContaining(FeedbackService.email), findsOneWidget);
      await tester.tap(find.text('Гаразд'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsOneWidget);
      expect(find.text('Не працює сканер'), findsOneWidget);
    });
  });

  testWidgets('карта: «Редагувати» одразу пропонує шаблони; «Шаблони» - лише в меню', (tester) async {
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    expect(find.text('Шаблони'), findsNothing);
    expect(find.text('Додати'), findsNothing);
    await tester.tap(find.byTooltip('Редагування'));
    await settle(tester);
    expect(find.text('Оберіть шаблон'), findsOneWidget);
    expect(find.byTooltip('Лежак (2×2)'), findsOneWidget);
    // закрили вибір, нічого не обравши — лишаємось у редагуванні
    await tester.tapAt(const Offset(12, 300));
    await settle(tester);
    expect(find.text('Оберіть шаблон'), findsNothing);
    expect(find.byTooltip('Готово'), findsOneWidget);
    // «Готово» — назад до перегляду; знову «Редагувати» й обрали шаблон — розміщення
    await tester.tap(find.byTooltip('Готово'));
    await settle(tester);
    await tester.tap(find.byTooltip('Редагування'));
    await settle(tester);
    await tester.tap(find.byTooltip('Лежак (2×2)'));
    await settle(tester);
    expect(find.byTooltip('Завершити розміщення'), findsNothing); // окремого виходу з розміщення немає
    expect(find.byTooltip('Готово'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P19: підказка першого запуску - один раз, «Зрозуміло»', (tester) async {
    Hints.enabled = true;
    Hints.resetSession();
    addTearDown(() => Hints.enabled = false);
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500)); // поява завершилась
    // на головному екрані підказки немає
    expect(find.text('Зрозуміло'), findsNothing);
    // склад — своя підказка; «Пропустити всі» вимикає решту
    await tester.tap(find.text('Склад'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Пропустити'), findsOneWidget);
    await tester.tap(find.text('Пропустити'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(await tester.runAsync(() => repo.getMeta('hints_off')), '1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Що нового»: після оновлення один раз, на новому встановленні - ні', (tester) async {
    WhatsNewScreen.enabled = true;
    addTearDown(() => WhatsNewScreen.enabled = false);
    // у setUp уже є пасіка — це оновлення, а не нове встановлення
    await pumpApp(tester, ApiaryApp(repo: repo, auth: FakeAuth(signedIn: true)));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WhatsNewScreen), findsOneWidget);
    expect(find.textContaining('Що нового ·'), findsOneWidget);
    expect(find.textContaining('Ще: ', skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('До роботи'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(WhatsNewScreen), findsNothing);
    expect(await tester.runAsync(() => repo.getMeta('whats_new_seen_n')), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P14: «Звіт по пасіці» у меню карти й у налаштуваннях пасіки', (tester) async {
    final a = (await tester.runAsync(() => repo.listApiaries()))!.first;
    await pumpApp(tester, wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Історія')); // звіт — усередині «Історії»
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Звіт по пасіці (Excel)'));
    await settle(tester);
    expect(find.text('Поділитися'), findsOneWidget);
    expect(find.text('Зберегти у файл'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Вхід без Google (для тестів).
class FakeAuth implements AuthService {
  Object? fail;
  AppUser? _user;
  @override
  final bool configured;
  FakeAuth({bool signedIn = false, this.fail, this.configured = true}) {
    if (signedIn) _user = _pasichnyk;
  }
  static const _pasichnyk = AppUser(id: '1', email: 'pasichnyk@example.com', name: 'Пасічник');

  @override
  AppUser? get user => _user;

  @override
  Future<AppUser> signIn() async {
    final f = fail;
    if (f != null) throw f;
    return _user = _pasichnyk;
  }

  bool _guest = false;
  @override
  bool get guest => _user == null && _guest;

  @override
  Future<void> continueAsGuest() async => _guest = true;

  @override
  Future<void> signOut() async {
    _user = null;
    _guest = false;
  }
}
