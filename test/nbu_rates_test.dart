import 'package:apiary/data/database.dart';
import 'package:apiary/data/fin_accounts.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/services/nbu_rates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('відповідь НБУ розбирається, зіпсовані записи пропускаються', () {
    final r = parseNbuRates(
        '[{"r030":840,"txt":"Долар США","rate":41.5,"cc":"USD"},{"cc":"EUR","rate":45.25},{"cc":"XXX"},5]');
    expect(r, {'USD': 41.5, 'EUR': 45.25});
    expect(() => parseNbuRates('{"a":1}'), throwsFormatException);
  });

  test('курси: беруться з НБУ, запам’ятовуються й працюють без інтернету', () async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false);
    final repo = Repository(db);
    await repo.init();
    expect((await repo.finRates())['USD'], isNull);
    var calls = 0;
    final ok = MockClient((_) async {
      calls++;
      return http.Response('[{"cc":"USD","rate":41.5}]', 200);
    });
    await repo.refreshFinRates(client: ok);
    expect(await repo.finRate('USD'), 41.5);
    expect(await repo.finRate(kFinUah), 1);
    // свіжі курси удруге не качаємо
    await repo.refreshFinRates(client: ok);
    expect(calls, 1);
    // немає інтернету - лишаються збережені
    final offline = MockClient((_) async => throw http.ClientException('offline'));
    await repo.refreshFinRates(client: offline, maxAge: Duration.zero);
    expect(await repo.finRate('USD'), 41.5);
    await db.close();
  });

  test('коригування залишку долларового рахунку: статистика в гривнях за курсом', () async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false);
    final repo = Repository(db);
    await repo.init();
    await repo.setMeta('fin_rates', '{"at":${DateTime.now().millisecondsSinceEpoch},"rates":{"USD":40}}');
    final usd = await repo.addFinAccount('Долари', currency: 'USD', startBalance: 100);
    final uah = await repo.addFinAccount('Гривня');
    expect(await repo.setFinAccountBalance(usd, 90), -10);
    expect((await repo.finAccountBalances())[usd], 90);
    final entries = await repo.listFinEntries(from: DateTime(2000), to: DateTime(2100));
    expect(entries.single.amount, 400); // 10 USD × 40
    // переказ з гривні в долари: списано 4000 ₴, зараховано 100 $
    await repo.addFinTransfer(fromId: uah, toId: usd, amount: 4000, toAmount: 100, date: DateTime.now());
    final bal = await repo.finAccountBalances();
    expect(bal[uah], -4000);
    expect(bal[usd], 190);
    await db.close();
  });
}
