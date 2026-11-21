import 'package:apiary/data/finance.dart';
import 'package:apiary/logic/fin_period.dart';
import 'package:apiary/services/fin_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

FinEntry _e(String id, String kind, double amount, DateTime date,
        {String? cat, String title = '', String? comment, bool cancelled = false}) =>
    FinEntry(
        id: id,
        kind: kind,
        categoryId: cat,
        amount: amount,
        date: date,
        title: title,
        lineCount: 0,
        cancelled: cancelled,
        fromStock: false,
        comment: comment);

String _text(Sheet s, int c, int r) =>
    s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value.toString();

double _num(Sheet s, int c, int r) => double.parse(_text(s, c, r));

void main() {
  group('FinPeriodSel', () {
    test('місяць: межі, підпис, гортання назад і вперед', () {
      final s = FinPeriodSel(period: FinPeriod.month, anchor: DateTime(2026, 11, 1));
      expect(s.range, (DateTime(2026, 11), DateTime(2026, 12)));
      expect(s.lastDay, DateTime(2026, 11, 30));
      expect(s.title, 'Листопад 2026');
      expect(s.shift(-1), isTrue);
      expect(s.range.$1, DateTime(2026, 10));
      expect(s.shift(-1), isTrue);
      expect(s.range.$1, DateTime(2026, 9));
    });

    test('у майбутнє не гортаємо', () {
      final now = DateTime.now();
      final s = FinPeriodSel(period: FinPeriod.month, anchor: DateTime(now.year, now.month, 1));
      expect(s.canGoForward, isFalse);
      expect(s.shift(1), isFalse);
    });

    test('тиждень починається з понеділка, рік - 1 січня', () {
      final w = FinPeriodSel(period: FinPeriod.week, anchor: DateTime(2026, 11, 21)); // субота
      expect(w.range, (DateTime(2026, 11, 16), DateTime(2026, 11, 23)));
      expect(w.title, '16.11 – 22.11.2026');
      final y = FinPeriodSel(period: FinPeriod.year, anchor: DateTime(2026, 6, 5));
      expect(y.range, (DateTime(2026), DateTime(2027)));
    });

    test('власний період: межі впорядковуються, гортати не можна', () {
      final s = FinPeriodSel()..setCustom(DateTime(2026, 11, 20), DateTime(2026, 10, 1));
      expect(s.range, (DateTime(2026, 10, 1), DateTime(2026, 11, 21)));
      expect(s.title, '01.10.2026 – 20.11.2026');
      expect(s.shift(-1), isFalse);
    });
  });

  group('експорт в Excel', () {
    final cats = <String, FinCategory>{
      'a': FinCategory(
          id: 'a',
          name: 'Продукти',
          kind: kFinExpense,
          toStock: false,
          icon: 'feed',
          color: 'aqua'),
    };
    final entries = [
      _e('2', kFinExpense, 120.5, DateTime(2026, 11, 20), cat: 'a', title: 'Молоко', comment: 'вранці'),
      _e('1', kFinExpense, 80, DateTime(2026, 11, 19), cat: 'a'),
      _e('3', kFinIncome, 1000, DateTime(2026, 11, 21), title: 'Мед'),
      _e('4', kFinExpense, 999, DateTime(2026, 11, 21), cat: 'a', cancelled: true),
    ];

    test('скасовані не потрапляють, вид фільтрується, порядок за датою', () {
      expect(finExportEntries(entries, FinExportKind.all).map((e) => e.id), ['1', '2', '3']);
      expect(finExportEntries(entries, FinExportKind.expenses).map((e) => e.id), ['1', '2']);
      expect(finExportEntries(entries, FinExportKind.income).map((e) => e.id), ['3']);
    });

    test('назва файлу', () {
      expect(finExportFileName(DateTime(2026, 11), DateTime(2026, 11, 30), FinExportKind.all),
          'operacii_2026-11-01_2026-11-30.xlsx');
      expect(finExportFileName(DateTime(2026, 11), DateTime(2026, 11, 30), FinExportKind.expenses),
          'operacii_2026-11-01_2026-11-30_vytraty.xlsx');
    });

    test('книга: аркуш операцій (витрата зі знаком «−») і підсумки', () {
      final bytes = buildFinWorkbook(entries: entries, cats: cats, kind: FinExportKind.all);
      final book = Excel.decodeBytes(bytes);
      final ops = book['Операції'];
      expect(_text(ops, 0, 0), 'Дата');
      expect(_text(ops, 5, 0), 'Коментар');
      expect(ops.maxRows, 4); // заголовок + 3 записи
      expect(_text(ops, 1, 1), 'Витрата');
      expect(_text(ops, 2, 1), 'Продукти');
      expect(_num(ops, 4, 1), -80);
      expect(_num(ops, 4, 2), -120.5);
      expect(_text(ops, 3, 2), 'Молоко');
      expect(_text(ops, 5, 2), 'вранці');
      expect(_num(ops, 4, 3), 1000);

      final sum = book['Підсумки'];
      expect(_text(sum, 1, 0), 'Витрати');
      expect(_text(sum, 2, 0), 'Доходи');
      // «Продукти» 200,5 і дохід без категорії 1000; підсумковий рядок
      final last = sum.maxRows - 1;
      expect(_text(sum, 0, last), 'Усього');
      expect(_num(sum, 1, last), 200.5);
      expect(_num(sum, 2, last), 1000);
    });

    test('без підсумків і коментарів: один аркуш без стовпця «Коментар»', () {
      final bytes = buildFinWorkbook(
          entries: entries,
          cats: cats,
          kind: FinExportKind.expenses,
          includeSummary: false,
          includeComment: false);
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, ['Операції']);
      expect(book['Операції'].maxColumns, 5);
      expect(book['Операції'].maxRows, 3);
    });
  });
}
