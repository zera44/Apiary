import 'dart:typed_data';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/fin_accounts.dart';
import 'package:apiary/data/fin_import_repo.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/logic/fin_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List _book() {
  final x = Excel.createExcel();
  x.rename('Sheet1', 'Витрати');
  final head = [
    'Дата і час', 'Категорія', 'Рахунок', 'Сума у валюті за замовчуванням',
    'Валюта за замовчуванням', 'Сума у валюті рахунку', 'Валюта рахунку',
    'Сума операції у валюті операції', 'Валюта операції', 'Теги', 'Коментувати',
  ];
  DateTimeCellValue d(int day) => DateTimeCellValue(year: 2026, month: 11, day: day, hour: 0, minute: 0);
  final e = x['Витрати'];
  e.appendRow([TextCellValue('список витрати')]);
  e.appendRow([for (final h in head) TextCellValue(h)]);
  e.appendRow([d(11), TextCellValue('Їжа'), TextCellValue('Головний'), DoubleCellValue(194.97),
    TextCellValue('UAH'), DoubleCellValue(194.97), TextCellValue('UAH'), TextCellValue(''),
    TextCellValue(''), TextCellValue(''), TextCellValue('хліб')]);
  e.appendRow([d(10), TextCellValue('Їжа'), TextCellValue('Готівка'), IntCellValue(100)]);
  e.appendRow([d(9), TextCellValue('Їжа'), TextCellValue('Готівка'), IntCellValue(0)]); // нульова - пропуск
  e.appendRow([d(5), TextCellValue('Їжа'), TextCellValue('Долари'), IntCellValue(410),
    TextCellValue('UAH'), IntCellValue(10), TextCellValue('USD')]);
  final i = x['Дохід'];
  i.appendRow([TextCellValue('список дохід')]);
  i.appendRow([for (final h in head) TextCellValue(h)]);
  i.appendRow([d(6), TextCellValue('Зарплата'), TextCellValue('Головний'), IntCellValue(1000)]);
  final t = x['Перекази'];
  t.appendRow([TextCellValue('список перекази')]);
  t.appendRow([
    for (final h in ['Дата і час', 'Вихідні', 'Вхідні', 'Сума у вихідній валюті', 'Вихідна валюта',
      'Сума у валюті надходження', 'Вхідна валюта', 'Коментувати'])
      TextCellValue(h)
  ]);
  t.appendRow([d(8), TextCellValue('Головний'), TextCellValue('Готівка'), DoubleCellValue(300),
    TextCellValue('UAH'), TextCellValue(''), TextCellValue(''), TextCellValue('')]);
  t.appendRow([d(7), TextCellValue('Головний'), TextCellValue('Долари'), DoubleCellValue(50),
    TextCellValue('UAH'), DoubleCellValue(1.2), TextCellValue('USD'), TextCellValue('')]); // з гривні в долари
  return Uint8List.fromList(x.encode()!);
}

void main() {
  late Repository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false);
    repo = Repository(db);
    await repo.init();
  });
  tearDown(() => repo.db.close());

  test('файл читається: витрати, доходи, перекази, пропущені рядки', () {
    final d = parseFinWorkbook(_book());
    expect(d.expenses, 3);
    expect(d.incomes, 1);
    expect(d.transfers.length, 2);
    expect(d.skipped, 1); // нульова сума
    expect(d.currencies['Долари'], 'USD');
    expect(d.currencies['Головний'], 'UAH');
    expect(d.transfers.last.toAmount, 1.2);
    expect(d.ops.firstWhere((o) => o.account == 'Долари').accountAmount, 10);
    expect(d.ops.first.comment, 'хліб');
    expect(d.ops.first.amount, 194.97);
    expect(d.ops.first.date, DateTime(2026, 11, 11));
  });

  test('не схожий файл - помилка формату', () {
    final x = Excel.createExcel();
    x['Sheet1'].appendRow([TextCellValue('щось')]);
    expect(() => parseFinWorkbook(Uint8List.fromList(x.encode()!)), throwsFormatException);
  });

  test('імпорт створює рахунки й категорії, рахує залишки, повторно дублів не дає', () async {
    final data = parseFinWorkbook(_book());
    final plan = await repo.planFinImport(data);
    expect(plan.newAccounts.toSet(), {'Головний', 'Готівка', 'Долари (USD)'});
    final r = await repo.importFinData(data);
    expect(r.added, 6);
    expect(r.duplicates, 0);
    final accounts = {for (final a in await repo.listFinAccounts()) a.name: a.id};
    final bal = await repo.finAccountBalances();
    expect(bal[accounts['Головний']], closeTo(1000 - 194.97 - 300 - 50, 0.001));
    expect(bal[accounts['Готівка']], closeTo(-100 + 300, 0.001));
    // долларовий рахунок: у своїй валюті (переказ +1,2, витрата -10)
    expect(bal[accounts['Долари']], closeTo(1.2 - 10, 0.001));
    final usd = (await repo.listFinAccounts()).firstWhere((a) => a.name == 'Долари');
    expect(usd.currency, 'USD');
    final again = await repo.importFinData(data);
    expect(again.added, 0);
    expect(again.duplicates, 6);
    final entries = await repo.listFinEntries(from: DateTime(2000), to: DateTime(2100));
    expect(entries.length, 4);
    // у статистиці - гривневі суми
    expect(entries.where((e) => e.isExpense).fold<double>(0, (s, e) => s + e.amount),
        closeTo(194.97 + 100 + 410, 0.001));
  });
}
