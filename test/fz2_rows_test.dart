// Збирач позицій чека з нечіткої розмітки (lib/logic/fz2/receipt_rows.dart).
import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/logic/fz2/receipt_rows.dart';
import 'package:flutter_test/flutter_test.dart';

Labeled l(String cls, String text, double y, [double x = 200]) =>
    Labeled(Frag(text: text, x: x, y: y, w: 100, h: 30, xLeft: x - 50, xRight: x + 50), cls);

void main() {
  test('назва на рядку суми, кількість і ціна над нею (каса кафе)', () {
    final r = assemble([
      l('QTY', '1,000', 100, 100), l('PRICE', '75,00', 100, 300),
      l('NAME', 'МОРКВА ПО-КОРЕЙСЬКИ', 150), l('ITEM', '75,00', 150, 900),
      l('QTY', '2,000', 200, 100), l('PRICE', '97,00', 200, 300),
      l('NAME', 'СОЛЯНКА', 250), l('ITEM', '194,00', 250, 900),
      l('TOTAL', 'СУМА', 350), l('TOTAL', '269,00', 350, 900),
    ]);
    expect([for (final x in r.rows) x.name], ['МОРКВА ПО-КОРЕЙСЬКИ', 'СОЛЯНКА']);
    expect(r.rows[1].qty, 2);
    expect(r.rows[1].price, 97);
    expect(r.total, 269);
  });

  test('назва у два рядки над сумою, вагове', () {
    final r = assemble([
      l('NAME', 'Часник 20 г Своя лінія', 100), l('NAME', 'гранульований м/уп', 140), l('ITEM', '18,30', 145, 900),
      l('NAME', 'Шашлик', 200), l('QTY', '1.522', 240, 100), l('PRICE', '189,99', 240, 300), l('ITEM', '289,16', 240, 900),
      l('TOTAL', '307,46', 320, 900),
    ]);
    expect(r.rows[0].name, 'Часник 20 г Своя лінія гранульований м/уп');
    expect(r.rows[1].name, 'Шашлик');
    expect(r.rows[1].unit, 'кг');
    expect(r.rows[1].qty, 1.522);
  });

  test('друга строка назви під рядком суми', () {
    final r = assemble([
      l('NAME', 'Право вимоги згідно заяви про', 100), l('ITEM', '3000.00', 100, 900),
      l('NAME', 'приєднання до публічної оферти', 140),
      l('NAME', 'Подарункове упакування', 250), l('ITEM', '300.00', 250, 900),
      l('TOTAL', '3300.00', 350, 900),
    ]);
    expect([for (final x in r.rows) x.name],
        ['Право вимоги згідно заяви про приєднання до публічної оферти', 'Подарункове упакування']);
  });

  test('підсумок: той, що дорівнює сумі позицій; зіпсований відкидається', () {
    final r = assemble([
      l('NAME', 'А', 100), l('ITEM', '10,00', 100, 900),
      l('TOTAL', '12,00', 200, 900), l('TOTAL', '12,00', 250, 900), l('TOTAL', '10,00', 300, 900),
    ]);
    expect(r.total, 10);
    final bad = assemble([
      l('NAME', 'А', 100), l('ITEM', '215,20', 100, 900),
      l('TOTAL', '5, 20', 200, 900),
    ]);
    expect(bad.total, isNull);
  });

  test('позиція без рядка (оплата послуг)', () {
    final r = assemble([Labeled(Frag.virtualItem('Нова пошта', 120), 'ITEM')]);
    expect(r.rows.single.name, 'Нова пошта');
    expect(r.rows.single.sum, 120);
  });
}
