import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/logic/receipt_parser.dart';
import 'package:apiary/screens/receipt_screen.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:apiary/services/receipt_ocr.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOcr implements ReceiptOcr {
  final String text;
  _FakeOcr(this.text);
  @override
  bool get supported => true;
  @override
  Future<String> read(String imagePath) async => text;
}

const _receipt = '''
ТОВ "МЕДОВИЙ ДІМ"
м. Київ, вул. Садова 5
Чек № 4521  Дата 08.10.2026
Цукор білий 1кг
2.000 х 45.50  91.00 А
Вощина пасічна
5 шт x 120,00 = 600.00 Б
Мед липовий 0.5кг 150.00 А
Сироп 1л  3 x 80.00
СУМА 841.00
ГОТІВКА 1000.00
РЕШТА 159.00
ПДВ А 20% 15.17
''';

void main() {
  group('розбір чека', () {
    test('назва в одному рядку, «кількість x ціна» - у наступному', () {
      final rows = parseReceipt(_receipt);
      expect(rows.map((r) => r.name), ['Цукор білий 1кг', 'Вощина пасічна', 'Мед липовий 0.5кг', 'Сироп 1л']);
      expect(rows[0].qty, 2);
      expect(rows[0].price, 45.5);
      expect(rows[0].unit, 'шт');
      expect(rows[1].qty, 5);
      expect(rows[1].price, 120);
      // «Мед … 150.00» - одна позиція за ціною
      expect(rows[2].qty, 1);
      expect(rows[2].price, 150);
      expect(rows[3].qty, 3);
      expect(rows[3].price, 80);
    });

    test('службові рядки й усе після «СУМА» не стають товарами', () {
      final names = parseReceipt(_receipt).map((r) => r.name.toLowerCase()).join('|');
      for (final w in ['сума', 'готівка', 'решта', 'пдв', 'чек', 'київ']) {
        expect(names.contains(w), isFalse, reason: w);
      }
    });

    test('«кількість x ціна» і назва в одному рядку; вага; кома; літера О замість нуля', () {
      final rows = parseReceipt('Огірки 1.2О0 кг x 55,5О 66.60\nХліб 2 * 18.00');
      expect(rows.length, 2);
      expect(rows[0].name, 'Огірки');
      expect(rows[0].qty, 1.2);
      expect(rows[0].unit, 'кг');
      expect(rows[0].price, 55.5);
      expect(rows[1].qty, 2);
      expect(rows[1].price, 18);
    });

    test('нумерація позицій і сміття не потрапляють у назву', () {
      final rows = parseReceipt('1. Цукор | рафінад\n2 x 30.00');
      expect(rows.single.name, 'Цукор рафінад');
    });

    test('порожній чи нечитабельний текст - порожній результат', () {
      expect(parseReceipt(''), isEmpty);
      expect(parseReceipt('###\n12:30\n0.00'), isEmpty);
    });
  });

  group('екран чека', () {
    late Repository repo;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      await AppIcons.load();
    });

    setUp(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
      await repo.init();
    });

    tearDown(() async => repo.db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    testWidgets('таблиця «Товар / Кількість / Ціна» і запис у склад (нове й поповнення)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final known = (await tester.runAsync(() async {
        final id = await repo.addStockItem('Вощина пасічна', 'шт');
        await repo.receiveStock(id, 10, total: 100);
        return id;
      }))!;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ReceiptScreen(repo: repo, imagePath: '/x.jpg', ocr: _FakeOcr(_receipt)),
      ));
      await settle(tester);
      expect(find.text('Товар'), findsOneWidget);
      expect(find.text('Кількість'), findsOneWidget);
      expect(find.text('Ціна'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Цукор білий 1кг'), findsOneWidget);
      expect(find.textContaining('Разом: '), findsOneWidget);

      // зайву позицію знімаємо
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.tap(find.text('Додати на склад'));
      await settle(tester);
      await settle(tester);

      expect(find.byType(StockScreen), findsOneWidget);
      final items = (await tester.runAsync(() => repo.listStockItems()))!;
      final byName = {for (final i in items) i.name: i};
      expect(byName['Цукор білий 1кг']!.quantity, 2);
      expect(byName['Мед липовий 0.5кг']!.quantity, 1);
      expect(byName.containsKey('Сироп 1л'), isFalse); // знята галочка
      // наявну номенклатуру поповнено, а не продубльовано
      expect(items.where((i) => i.name == 'Вощина пасічна').length, 1);
      expect((await tester.runAsync(() => repo.getStockItem(known)))!.quantity, 15);
      expect(tester.takeException(), isNull);
    });

    testWidgets('невалідний рядок не записується, пояснення людською мовою', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ReceiptScreen(repo: repo, ocr: _FakeOcr('')),
      ));
      await settle(tester);
      await tester.tap(find.text('+ Додати рядок'));
      await tester.pump();
      await tester.tap(find.text('Додати на склад'));
      await settle(tester);
      expect(find.textContaining('не вистачає назви'), findsOneWidget);
      expect(await tester.runAsync(() => repo.listStockItems()), isEmpty);
    });

    testWidgets('там, де розпізнавання недоступне, - порожня таблиця й пояснення', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ReceiptScreen(repo: repo, imagePath: '/x.jpg', ocr: _NoOcr()),
      ));
      await settle(tester);
      expect(find.textContaining('працює на телефоні'), findsOneWidget);
      expect(find.text('+ Додати рядок'), findsOneWidget);
    });
  });
}

class _NoOcr implements ReceiptOcr {
  @override
  bool get supported => false;
  @override
  Future<String> read(String imagePath) async => throw StateError('no');
}
