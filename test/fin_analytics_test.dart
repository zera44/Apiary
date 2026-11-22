import 'package:apiary/data/database.dart';
import 'package:apiary/data/fin_accounts.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/logic/fin_analytics.dart';
import 'package:apiary/screens/fin_category_trend_screen.dart';
import 'package:apiary/screens/fin_stats_screen.dart';
import 'package:apiary/ui/fin_style.dart' show uah;
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

FinEntry _e(String kind, double amount, DateTime d, {String? cat}) => FinEntry(
    id: '$d$amount$cat',
    kind: kind,
    categoryId: cat,
    amount: amount,
    date: d,
    title: '',
    lineCount: 0,
    cancelled: false,
    fromStock: false);

void main() {
  group('розподіл за правилом Парето', () {
    test('до шести категорій - усі своїм кольором, без «Інше»', () {
      final s = finParetoSlices({'a': 50, 'b': 20, 'c': 10, 'd': 10, 'e': 5, 'f': 5});
      expect(s.length, 6);
      expect(s.any((x) => x.isRest), isFalse);
      expect(s.first.key, 'a');
    });

    test('більше шести: категорії до 80% окремо, решта - в «Інше» останнім', () {
      final s = finParetoSlices({'a': 50, 'b': 20, 'c': 10, 'd': 5, 'e': 5, 'f': 4, 'g': 3, 'h': 3});
      expect(s.map((x) => x.key), ['a', 'b', 'c', null]);
      expect(s.last.isRest, isTrue);
      expect(s.last.amount, 20);
      expect(s.fold(0.0, (a, x) => a + x.amount), 100);
    });

    test('окремо не більше п\'яти кольорів, коли розподіл рівний', () {
      final s = finParetoSlices({for (var i = 0; i < 10; i++) 'k$i': 10});
      expect(s.where((x) => !x.isRest).length, 5);
      expect(s.last.isRest, isTrue);
      expect(s.last.amount, 50);
    });

    test('нулі пропускаються, порожнє дає порожнє', () {
      expect(finParetoSlices({'a': 0, 'b': 0}), isEmpty);
      expect(finParetoSlices({}), isEmpty);
    });
  });

  group('карта контролю', () {
    test('середнє, медіана, вибіркове відхилення й межі', () {
      final s = finControlStats([2, 4, 4, 4, 5, 5, 7, 9]);
      expect(s.mean, 5);
      expect(s.median, 4.5);
      expect(s.sd, closeTo(2.138, 0.001));
      expect(s.high, closeTo(5 + 2 * 2.138, 0.01));
      expect(s.low, closeTo(5 - 2 * 2.138, 0.01));
      expect(s.outside, isEmpty);
    });

    test('місяць поза межами нормальності знаходиться, нижня межа не нижча за нуль', () {
      final s = finControlStats([1, 1, 1, 1, 1, 1, 1, 1, 1, 10]);
      expect(s.low, 0);
      expect(s.outside, [9]);
    });

    test('одна точка й порожній ряд не ламають розрахунок', () {
      expect(finControlStats([5]).sd, 0);
      expect(finControlStats([5]).outside, isEmpty);
      expect(finControlStats([]).mean, 0);
    });

    test('сума категорії по місяцях: лише свій рік, вид і категорія', () {
      final v = finCategoryMonths([
        _e(kFinExpense, 100, DateTime(2026, 3, 5), cat: 'x'),
        _e(kFinExpense, 50, DateTime(2026, 3, 20), cat: 'x'),
        _e(kFinExpense, 70, DateTime(2026, 3, 20), cat: 'y'),
        _e(kFinIncome, 999, DateTime(2026, 3, 1), cat: 'x'),
        _e(kFinExpense, 5, DateTime(2025, 3, 1), cat: 'x'),
      ], 2026, 'x', kind: kFinExpense);
      expect(v[2], 150);
      expect(v.fold(0.0, (a, b) => a + b), 150);
    });

    test('скільки місяців року мають дані', () {
      final now = DateTime(2026, 11, 22);
      expect(finMonthsWithData(2026, now), 11);
      expect(finMonthsWithData(2025, now), 12);
      expect(finMonthsWithData(2027, now), 0);
    });
  });

  group('екрани', () {
    late Repository repo;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
      repo = Repository(db);
      await repo.init();
    });
    tearDown(() async => repo.db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    testWidgets('вкладка «Категорії»: витрати, вибір рядка й перехід до категорії', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final a = await repo.addFinCategory('Цукор', kFinExpense, icon: 'hair');
      final b = await repo.addFinCategory('Пальне', kFinExpense, icon: 'hair');
      final now = DateTime.now();
      await repo.addFinOp(kind: kFinExpense, categoryId: a, amount: 300, date: now);
      await repo.addFinOp(kind: kFinExpense, categoryId: b, amount: 100, date: now);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: FinStatsScreen(repo: repo)));
      await settle(tester);
      // відкривається на «Категорії» й «Результат»: збиток, рядки «Дохід» і «Витрати»
      expect(find.text('Збиток'), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-kind-expense')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stat-kind-expense')));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('cats-total'))).data, '−${uah(400)}');
      expect(find.text('75%'), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-picked')), findsNothing);
      // перший дотик - лінія лише про категорію
      await tester.tap(find.byKey(ValueKey('cats-row-$a')));
      await settle(tester);
      expect(find.byKey(const ValueKey('stat-picked')), findsOneWidget);
      expect(find.byType(FinCategoryTrendScreen), findsNothing);
      // другий - її динаміка за рік
      await tester.tap(find.byKey(ValueKey('cats-row-$a')));
      await settle(tester);
      expect(find.byType(FinCategoryTrendScreen), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('trend-total'))).data, '−${uah(300)}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('категорія за рік: точки, межі нормальності й порівняння двох місяців', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await repo.addFinCategory('Цукор', kFinExpense, icon: 'hair');
      final y = DateTime.now().year - 1;
      for (var m = 1; m <= 12; m++) {
        await repo.addFinOp(
            kind: kFinExpense, categoryId: c, amount: m == 10 ? 5000 : 100, date: DateTime(y, m, 5));
      }
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: FinCategoryTrendScreen(repo: repo, categoryId: c, kind: kFinExpense, year: y)));
      await settle(tester);
      expect(find.byKey(const ValueKey('fin-control-chart')), findsOneWidget);
      expect(find.text('Межі нормальності'), findsWidgets);
      expect(find.textContaining('Поза межами нормальності: жовтень'), findsOneWidget);
      expect(find.byKey(const ValueKey('trend-compare')), findsNothing);
      // торкаємося двох точок: вересня і жовтня
      final tl = tester.getTopLeft(find.byKey(const ValueKey('fin-control-chart')));
      final w = tester.getSize(find.byKey(const ValueKey('fin-control-chart'))).width;
      Offset at(int i) => Offset(tl.dx + 40 + (w - 48) * (i + 0.5) / 12, tl.dy + 120);
      await tester.tapAt(at(8));
      await tester.pump();
      await tester.tapAt(at(9));
      await tester.pump();
      expect(find.byKey(const ValueKey('trend-compare')), findsOneWidget);
      expect(find.textContaining(uah(4900)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('вкладка «Рахунки»: результат кожного рахунку й окремий рядок переказів', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c1 = await repo.addFinCategory('Цукор', kFinExpense, icon: 'hair');
      final bank = await repo.addFinAccount('Банк');
      final cash = await repo.addFinAccount('Каса');
      final now = DateTime.now();
      await repo.addFinOp(kind: kFinExpense, categoryId: c1, amount: 200, date: now, accountId: bank);
      await repo.addFinOp(kind: kFinExpense, categoryId: c1, amount: 50, date: now, accountId: cash);
      await repo.addFinTransfer(fromId: bank, toId: cash, amount: 1000, date: now);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: FinStatsScreen(repo: repo)));
      await settle(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('stat-tabs')), matching: find.text('Рахунки')));
      await settle(tester);
      // результат: у кожного рахунку - підсумок зі знаком
      expect(find.byKey(ValueKey('acc-$bank')), findsOneWidget);
      expect(find.text('−${uah(200)}'), findsWidgets);
      expect(find.text('−${uah(50)}'), findsWidgets);
      // вибір рахунку - у лінії його назва; повторний дотик знімає вибір
      await tester.tap(find.byKey(ValueKey('acc-$bank')));
      await settle(tester);
      expect(find.byKey(const ValueKey('stat-picked')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('acc-$bank')));
      await settle(tester);
      expect(find.byKey(const ValueKey('stat-picked')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('acc-transfers')));
      expect(find.textContaining(uah(1000)), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('прибуток і збиток: червоний знак, період без «День»', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final e = await repo.addFinCategory('Цукор', kFinExpense, icon: 'hair');
      final i = await repo.addFinCategory('Мед', kFinIncome);
      final now = DateTime.now();
      await repo.addFinOp(kind: kFinIncome, categoryId: i, amount: 900, date: now);
      await repo.addFinOp(kind: kFinExpense, categoryId: e, amount: 300, date: now);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: FinStatsScreen(repo: repo)));
      await settle(tester);
      expect(find.text('Прибуток'), findsOneWidget);
      expect(find.text('+${uah(600)}'), findsOneWidget);
      expect(find.text('День'), findsNothing);
      expect(find.text('Тиждень'), findsOneWidget);
      expect(find.text('Підсумки'), findsNothing);
      expect(find.byKey(const ValueKey('stat-mean')), findsOneWidget);
      expect(find.byKey(const ValueKey('stat-limits')), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('stat-kind')), matching: find.text('Дохід')));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('cats-total'))).data, '+${uah(900)}');
      expect(tester.takeException(), isNull);
    });
  });
}
