import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/logic/hive_objects.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/main.dart';
import 'package:apiary/screens/history_screen.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/parameters_screen.dart';
import 'package:apiary/screens/qr_generate_screen.dart';
import 'package:apiary/services/qr_labels.dart';
import 'package:apiary/screens/template_editor_screen.dart';
import 'package:apiary/screens/templates_screen.dart';
import 'package:apiary/ui/fill_values_dialog.dart';
import 'package:apiary/ui/characteristics_panel.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/grid_view.dart';
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    await AppIcons.load(); // SVG-іконки з assets/icons
  });

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

  testWidgets('меню: Характеристики — каталог без вибору й без «Зберегти»', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.tap(find.byTooltip('Відкрити')); // меню є лише на карті пасіки
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

  testWidgets('«Заповнити»: старе значення не того типу не блокує збереження інших полів',
      (tester) async {
    const n = Parameter(id: 'n', name: 'Рамки', dataType: DataTypes.int_);
    const note = Parameter(id: 't', name: 'Нотатка');
    Map<String, String>? result;
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
    expect(result, {'t': 'огляд'});
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
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    await tester.tap(find.byTooltip('Відкрити')); // меню є лише на карті пасіки
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
    await tester.tap(find.byTooltip('Відкрити')); // меню є лише на карті пасіки
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

  testWidgets('генератор QR: «Усі без коду» -> «Згенерувати» -> наліпки', (tester) async {
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(QrGenerateScreen(repo: repo, apiary: a)));
    await settle(tester);
    // дві сусідні клітинки-вулики групи злиті в ОДИН вулик: один код
    expect(find.textContaining('0 з 1'), findsOneWidget);
    await tester.tap(find.text('Усі без коду'));
    await tester.pump();
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
    await tester.tap(find.text('Генерувати QR-коди'));
    await settle(tester);
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

  testWidgets('у списку пасік меню немає — лише на карті', (tester) async {
    await tester.pumpWidget(ApiaryApp(repo: repo));
    await settle(tester);
    await tester.tap(find.text('Почати'));
    await settle(tester);
    expect(find.byTooltip('Меню'), findsNothing);
    await tester.tap(find.byTooltip('Відкрити'));
    await settle(tester);
    expect(find.byTooltip('Меню'), findsOneWidget);
  });

  testWidgets('редагування карти: без «Перейменувати»; немає шаблонів — «Створити шаблон» відкриває новий шаблон',
      (tester) async {
    await tester.runAsync(() => repo.deleteTemplate(templateId)); // шаблонів немає
    final id = (await tester.runAsync(() => repo.addApiary('Пасіка')))!;
    final a = (await tester.runAsync(() => repo.getApiary(id)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.text('+').last); // кнопка меню (перша «+» — зум)
    await settle(tester);
    await tester.tap(find.text('Редагувати'));
    await settle(tester);
    expect(find.byTooltip('Перейменувати'), findsNothing);
    await tester.tap(find.byTooltip("Додати об'єкт"));
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
    await tester.tap(find.text('+').last);
    await settle(tester);
    await tester.tap(find.text('Редагувати'));
    await settle(tester);
    await tester.tap(find.byTooltip("Додати об'єкт"));
    await settle(tester);
    await tester.tap(find.text('Лежак (2×2)'));
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
    expect(find.byTooltip('Завершити розміщення'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('редактор шаблону: тап — інформація, режим переміщення — тягнути й кнопки',
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

  testWidgets('редагування карти: над обраним об\'єктом — «Повернути» й «Видалити»', (tester) async {
    final a = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
    await tester.pumpWidget(wrap(MapScreen(repo: repo, apiary: a)));
    await settle(tester);
    await tester.tap(find.text('+').last);
    await settle(tester);
    await tester.tap(find.text('Редагувати'));
    await settle(tester);
    expect(find.byTooltip('Повернути'), findsOneWidget); // лише внизу
    // вулик (0,0): камера по центру (1,0), клітинка 34
    await tester.tapAt(tester.getCenter(find.byType(InfiniteGrid)) + const Offset(-17, -17));
    await settle(tester);
    expect(find.byTooltip('Повернути'), findsNWidgets(2)); // внизу + над об'єктом
    expect(find.byTooltip('Видалити'), findsNWidgets(2));
    expect(find.byType(CharacteristicsPanel), findsNothing); // інформація не відкривається
    expect(tester.takeException(), isNull);
  });
}
