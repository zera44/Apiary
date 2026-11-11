import 'package:apiary/data/database.dart';
import 'package:apiary/data/fin_accounts.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('операція без рахунку йде на «Готівку», залишок враховує дохід і витрату', () async {
    final cat = await repo.addFinCategory('Корми', kFinExpense);
    final inc = await repo.addFinCategory('Мед', kFinIncome);
    await repo.addFinOp(kind: kFinIncome, categoryId: inc, amount: 1000, date: DateTime.now());
    await repo.addFinOp(kind: kFinExpense, categoryId: cat, amount: 300, date: DateTime.now());
    final accounts = await repo.listFinAccounts();
    expect(accounts.length, 1);
    expect(accounts.first.name, kFinDefaultAccountName);
    expect((await repo.finAccountBalances())[accounts.first.id], 700);
  });

  test('переказ переносить гроші між рахунками й не чіпає статистику', () async {
    final a = await repo.addFinAccount('Готівка', startBalance: 500);
    final b = await repo.addFinAccount('Картка');
    await repo.addFinTransfer(fromId: a, toId: b, amount: 200, date: DateTime.now());
    final bal = await repo.finAccountBalances();
    expect(bal[a], 300);
    expect(bal[b], 200);
    final now = DateTime.now();
    final list = await repo.listFinTransfers(
        from: DateTime(now.year, now.month), to: DateTime(now.year, now.month + 1));
    expect(list.length, 1);
    final entries = await repo.listFinEntries(from: DateTime(2000), to: DateTime(2100));
    expect(entries, isEmpty);
    await repo.deleteFinTransfer(list.first.id);
    expect((await repo.finAccountBalances())[a], 500);
    expect(() => repo.addFinTransfer(fromId: a, toId: a, amount: 1, date: now), throwsArgumentError);
  });

  test('виправлення суми: мінус - витрата, плюс - дохід, різниця видна в журналі', () async {
    final a = await repo.addFinAccount('Готівка', startBalance: 100);
    expect(await repo.setFinAccountBalance(a, 60), -40);
    expect((await repo.finAccountBalances())[a], 60);
    expect(await repo.setFinAccountBalance(a, 260), 200);
    expect((await repo.finAccountBalances())[a], 260);
    expect(await repo.setFinAccountBalance(a, 260), 0);
    final entries = await repo.listFinEntries(from: DateTime(2000), to: DateTime(2100));
    expect(entries.length, 2);
    final exp = entries.firstWhere((e) => e.isExpense);
    final inc = entries.firstWhere((e) => !e.isExpense);
    expect(exp.amount, 40);
    expect(inc.amount, 200);
    final cats = await repo.finCategoryMap();
    expect(cats[exp.categoryId]!.name, kFinAdjustName);
    expect(cats[inc.categoryId]!.kind, kFinIncome);
  });

  test('видалений рахунок не рахується, а операції лишаються', () async {
    final a = await repo.addFinAccount('Готівка');
    final b = await repo.addFinAccount('Картка');
    await repo.deleteFinAccount(b);
    expect((await repo.listFinAccounts()).map((x) => x.id), [a]);
    expect((await repo.finAccountBalances()).keys, [a]);
    expect((await repo.finAccountMap()).containsKey(b), isTrue);
  });
}
