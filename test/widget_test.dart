import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/main.dart';
import 'package:apiary/screens/history_screen.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/parameters_screen.dart';
import 'package:apiary/screens/template_editor_screen.dart';
import 'package:apiary/screens/templates_screen.dart';
import 'package:apiary/ui/fill_values_dialog.dart';
import 'package:apiary/ui/theme.dart';
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

  setUpAll(sqfliteFfiInit);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
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

  testWidgets('заставка -> список пасік -> карта', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    expect(find.text('MyApiary'), findsOneWidget);

    await tester.tap(find.text('Почати'));
    await settle(tester);
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

  testWidgets('меню: Характеристики — каталог без вибору й без «Зберегти»', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Характеристики'));
    await settle(tester);
    await settle(tester);
    expect(find.text('Вага'), findsOneWidget);
    expect(find.text('Зберегти'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('нова пасіка: створення -> карта -> «Головна» -> плитка в списку', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.tap(find.text('+  Створити карту'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Нова пасіка');
    await tester.tap(find.text('OK'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.text('Нова пасіка'), findsWidgets); // шапка відкритої карти
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Головна'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Нова пасіка'), findsOneWidget); // плитка у списку
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

  testWidgets('список пасік: видалення пасіки з підтвердженням', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    expect(find.text('Тестова пасіка'), findsOneWidget);

    await tester.tap(find.byTooltip('Видалити'));
    await settle(tester);
    await tester.tap(find.text('Скасувати')); // скасували — пасіка на місці
    await settle(tester);
    expect(find.text('Тестова пасіка'), findsOneWidget);

    await tester.tap(find.byTooltip('Видалити'));
    await settle(tester);
    await tester.tap(find.text('Видалити'));
    await settle(tester);
    await settle(tester);
    expect(find.text('Тестова пасіка'), findsNothing);
    expect(find.textContaining('Ще немає жодної пасіки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Заповнити»: спорожнене поле й «Очистити» дату записують порожнє значення',
      (tester) async {
    const text = Parameter(id: 't', name: 'Нотатка');
    const date = Parameter(id: 'd', name: 'Дата огляду', dataType: DataTypes.date);
    const untouched = Parameter(id: 'u', name: 'Вага', dataType: DataTypes.text);
    Map<String, String>? result;
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
    await tester.tap(find.text('Обрати дату'));
    await settle(tester);
    await tester.tap(find.text('Очистити'));
    await settle(tester);
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(result, {'t': '', 'd': ''}); // "Вага" не змінювалась — її немає
  });

  testWidgets('меню: сканер QR відкриває вулик на карті з панеллю', (tester) async {
    // у тестах камери немає — код вводиться вручну (як на комп'ютері)
    await tester.runAsync(() => repo.linkQr('https://pasika.example/h/7', EntityRef.group(groupId)));
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Сканувати QR вулика'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'https://pasika.example/h/7');
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.text('Тестова пасіка'), findsWidgets); // карта пасіки
    expect(find.text('Лежак 1'), findsWidgets); // панель вулика
    expect(find.text('https://pasika.example/h/7'), findsOneWidget); // код на панелі
    expect(tester.takeException(), isNull);
  });

  testWidgets('меню: невідомий QR-код — пояснення, як прив\'язати', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.tap(find.byTooltip('Меню'));
    await settle(tester);
    await tester.tap(find.text('Сканувати QR вулика'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'невідомий');
    await tester.tap(find.text('Зберегти'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Вулик не знайдено'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
