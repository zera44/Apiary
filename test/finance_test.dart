import 'package:apiary/data/database.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/logic/receipt_parser.dart';
import 'package:apiary/screens/fin_add_screen.dart';
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
Цукор білий 1кг
2.000 х 45.50  91.00 А
Сироп 1л  3 x 80.00
СУМА 331.00
ГОТІВКА 400.00
''';

void main() {
  late Repository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
  });

  tearDown(() async => repo.db.close());

  DateTime from() => DateTime(2000);
  DateTime to() => DateTime(2100);

  Future<FinCategory> cat(String name) async =>
      (await repo.listFinCategories()).firstWhere((c) => c.name == name);

  test('початкові категорії створюються один раз, «Корми» йдуть на склад', () async {
    await repo.init();
    final all = await repo.listFinCategories();
    expect(all.where((c) => c.name == 'Корми').length, 1);
    expect((await cat('Корми')).toStock, isTrue);
    expect((await cat('Дорога')).toStock, isFalse);
    expect(all.any((c) => c.kind == kFinIncome), isTrue);
  });

  test('витрата з рядками «на склад»: прихід на складі й зв\'язок', () async {
    final known = await repo.addStockItem('Вощина', 'шт');
    await repo.receiveStock(known, 10, total: 100);
    final korm = await cat('Корми');
    await repo.addFinOp(
      kind: kFinExpense,
      categoryId: korm.id,
      amount: 1200,
      date: DateTime(2026, 10, 8),
      lines: const [
        FinLineInput(name: 'Цукор', qty: 50, unit: 'кг', price: 24, toStock: true),
        FinLineInput(name: 'вощина', qty: 5, unit: 'шт', price: 0, toStock: true),
        FinLineInput(name: 'Дорога', qty: 1, unit: 'шт', price: 100),
      ],
    );
    final items = {for (final i in await repo.listStockItems()) i.name: i};
    expect(items['Цукор']!.quantity, 50);
    expect(items['Вощина']!.quantity, 15); // наявна поповнена, а не продубльована
    expect(items.containsKey('вощина'), isFalse);
    expect(items.containsKey('Дорога'), isFalse); // не на склад - лише гроші

    final entries = await repo.listFinEntries(from: from(), to: to());
    final e = entries.singleWhere((x) => !x.fromStock);
    expect(e.amount, 1200); // сума введена вручну (знижка), а не сума таблиці
    expect(e.lineCount, 3);
    expect(e.categoryId, korm.id);
    final s = FinSummary.of(entries);
    expect(s.expense, 1200);
    expect(s.balance, -1200);
    // той самий прихід не задвоюється як «внесено на складі»
    expect(entries.where((x) => x.fromStock).length, 1); // лише ручний прихід Вощини (100 ₴)
    expect(entries.singleWhere((x) => x.fromStock).amount, 100);
  });

  test('скасування витрати у фінансах скасовує прихід на складі', () async {
    final korm = await cat('Корми');
    await repo.addFinOp(
      kind: kFinExpense,
      categoryId: korm.id,
      amount: 100,
      date: DateTime.now(),
      lines: const [FinLineInput(name: 'Цукор', qty: 4, unit: 'кг', price: 25, toStock: true)],
    );
    var e = (await repo.listFinEntries(from: from(), to: to())).single;
    await repo.cancelFinEntry(e);
    e = (await repo.listFinEntries(from: from(), to: to())).single;
    expect(e.cancelled, isTrue);
    expect(FinSummary.of([e]).expense, 0);
    expect((await repo.listStockItems()).single.quantity, 0);
    expect(() => repo.cancelFinEntry(e), throwsStateError);
  });

  test('якщо частину вже списано - витрату скасувати не можна, нічого не змінюється', () async {
    final korm = await cat('Корми');
    await repo.addFinOp(
      kind: kFinExpense,
      categoryId: korm.id,
      amount: 100,
      date: DateTime.now(),
      lines: const [
        FinLineInput(name: 'Цукор', qty: 4, unit: 'кг', price: 25, toStock: true),
        FinLineInput(name: 'Сироп', qty: 2, unit: 'л', price: 10, toStock: true),
      ],
    );
    final sugar = (await repo.listStockItems()).firstWhere((i) => i.name == 'Цукор');
    await repo.writeOffStock(sugar.id, 3);
    final e = (await repo.listFinEntries(from: from(), to: to())).single;
    await expectLater(repo.cancelFinEntry(e), throwsStateError);
    expect((await repo.listFinEntries(from: from(), to: to())).single.cancelled, isFalse);
    final items = {for (final i in await repo.listStockItems()) i.name: i.quantity};
    expect(items['Сироп'], 2); // другий рядок теж не скасовано
    expect(items['Цукор'], 1);
  });

  test('прихід, внесений на складі, видно у фінансах; скасування працює в обидва боки', () async {
    final id = await repo.addStockItem('Рамка', 'шт');
    await repo.receiveStock(id, 20, total: 400);
    var entries = await repo.listFinEntries(from: from(), to: to());
    expect(entries.length, 1);
    expect(entries.first.fromStock, isTrue);
    expect(entries.first.amount, 400);
    expect(entries.first.title, 'Рамка');
    await repo.cancelFinEntry(entries.first);
    expect((await repo.getStockItem(id))!.quantity, 0);
    expect((await repo.listFinEntries(from: from(), to: to())).first.cancelled, isTrue);

    // і навпаки: скасували у фінансах-операції приход на складі -> операція скасована
    final korm = await cat('Корми');
    await repo.addFinOp(
      kind: kFinExpense,
      categoryId: korm.id,
      amount: 50,
      date: DateTime.now(),
      lines: const [FinLineInput(name: 'Цукор', qty: 2, unit: 'кг', price: 25, toStock: true)],
    );
    final sugar = (await repo.listStockItems()).firstWhere((i) => i.name == 'Цукор');
    final moves = await repo.stockMoves(sugar.id);
    await repo.cancelStockMove(moves.single['id'] as String);
    entries = await repo.listFinEntries(from: from(), to: to());
    expect(entries.where((e) => !e.fromStock).single.cancelled, isTrue);
  });

  test('дохід - лише гроші, на склад не потрапляє; період фільтрується', () async {
    final inc = await cat('Продаж меду');
    await repo.addFinOp(
      kind: kFinIncome,
      categoryId: inc.id,
      amount: 3000,
      date: DateTime(2026, 7, 10),
      lines: const [FinLineInput(name: 'Мед', qty: 10, unit: 'кг', price: 300, toStock: true)],
    );
    expect(await repo.listStockItems(), isEmpty);
    expect(await repo.listFinEntries(from: DateTime(2026, 8), to: DateTime(2026, 9)), isEmpty);
    final july = await repo.listFinEntries(from: DateTime(2026, 7), to: DateTime(2026, 8));
    expect(FinSummary.of(july).income, 3000);
  });

  test('нова категорія й видалення (старі записи зберігають назву)', () async {
    final id = await repo.addFinCategory('Бочки', kFinExpense, toStock: true, icon: 'jar');
    expect((await repo.listFinCategories(kind: kFinExpense)).any((c) => c.id == id), isTrue);
    await repo.deleteFinCategory(id);
    expect((await repo.listFinCategories()).any((c) => c.id == id), isFalse);
    expect((await repo.finCategoryMap())[id]!.name, 'Бочки');
    expect(() => repo.addFinCategory('  ', kFinExpense), throwsArgumentError);
  });

  test('невалідний рядок не пише нічого', () async {
    final korm = await cat('Корми');
    expect(
      () => repo.addFinOp(
        kind: kFinExpense,
        categoryId: korm.id,
        amount: 10,
        date: DateTime.now(),
        lines: const [FinLineInput(name: 'Цукор', qty: 0, unit: 'кг', price: 5, toStock: true)],
      ),
      throwsArgumentError,
    );
    expect(await repo.listFinEntries(from: from(), to: to()), isEmpty);
  });

  test('сума, надрукована на чеку', () {
    expect(receiptDeclaredTotal(_receipt), 331);
    expect(receiptDeclaredTotal('Мед\nРАЗОМ\n1 250,00 грн'), 1250);
    expect(receiptDeclaredTotal('Мед 1 шт'), isNull);
  });

  group('екран нової витрати', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> open(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(ctx).push(MaterialPageRoute<String>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('чек заповнює таблицю, сума з таблиці, запис іде на склад', (tester) async {
      await open(tester, FinAddScreen(repo: repo, imagePath: '/x.jpg', ocr: _FakeOcr(_receipt)));
      expect(find.textContaining('сума збігається'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Цукор білий 1кг'), findsOneWidget);
      expect(find.widgetWithText(TextField, '331'), findsOneWidget); // сума з таблиці

      await tester.tap(find.text('Корми'));
      await tester.pump();
      await tester.tap(find.text('Додати'));
      await settle(tester);
      await settle(tester);

      final items = (await tester.runAsync(() => repo.listStockItems()))!;
      final byName = {for (final i in items) i.name: i.quantity};
      expect(byName['Цукор білий 1кг'], 2);
      expect(byName['Сироп 1л'], 3);
      final entries =
          (await tester.runAsync(() => repo.listFinEntries(from: from(), to: to())))!;
      expect(entries.where((e) => !e.fromStock).single.amount, 331);
      expect(tester.takeException(), isNull);
    });

    testWidgets('без категорії не записується', (tester) async {
      await open(tester, FinAddScreen(repo: repo, imagePath: '/x.jpg', ocr: _FakeOcr(_receipt)));
      await tester.tap(find.text('Додати'));
      await settle(tester);
      expect(find.textContaining('Оберіть категорію'), findsOneWidget);
      expect((await tester.runAsync(() => repo.listStockItems()))!, isEmpty);
    });

    testWidgets('вручну: сума вводиться без таблиці, категорія не складська', (tester) async {
      await open(tester, FinAddScreen(repo: repo));
      await tester.tap(find.text('Дорога'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '0').first, '250');
      await tester.pump();
      await tester.tap(find.text('Додати'));
      await settle(tester);
      await settle(tester);
      final entries =
          (await tester.runAsync(() => repo.listFinEntries(from: from(), to: to())))!;
      expect(entries.single.amount, 250);
      expect(entries.single.lineCount, 0);
      expect((await tester.runAsync(() => repo.listStockItems()))!, isEmpty);
    });
  });
}
