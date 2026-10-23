import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show TextEditingValue, TextSelection;
import 'package:apiary/logic/stock_format.dart';
import 'package:apiary/logic/unit_convert.dart';
import 'package:apiary/ui/thousands_input.dart';

TextEditingValue _fmt(String text, [int? caret]) => const ThousandsFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret ?? text.length)),
    );

void main() {
  group('convertUnits', () {
    test('маса й об\'єм всередині себе', () {
      expect(convertUnits(2, 'т', 'кг').value, 2000);
      expect(convertUnits(500, 'г', 'кг').value, 0.5);
      expect(convertUnits(1.5, 'л', 'мл').value, 1500);
    });
    test('кг -> л для меду (1,4 кг/л)', () {
      final r = convertUnits(500, 'кг', 'л', density: densityOf('меду'));
      expect(r.value, closeTo(357.142857, 1e-5));
      expect(r.unit, 'л');
      expect(r.density, 1.4);
    });
    test('л -> кг', () {
      expect(convertUnits(10, 'літрів', 'кг', density: 1.4).value, closeTo(14, 1e-9));
    });
    test('без густини між масою й об\'ємом - помилка', () {
      expect(() => convertUnits(1, 'кг', 'л'), throwsArgumentError);
      expect(() => convertUnits(1, 'кг', 'шт'), throwsArgumentError);
    });
    test('назви одиниць і речовин', () {
      expect(normalizeUnit('Кілограм'), 'кг');
      expect(normalizeUnit('кг.'), 'кг');
      expect(normalizeUnit('літри'), 'л');
      expect(densityOf('липовий мед'), 1.4);
      expect(densityOf('щось'), isNull);
    });
  });

  group('роздільники тисяч', () {
    test('групує по три', () {
      expect(_fmt('1000').text, '1 000');
      expect(_fmt('1000000').text, '1 000 000');
      expect(_fmt('999').text, '999');
    });
    test('дробова частина не чіпається', () {
      expect(_fmt('1234567,89').text, '1 234 567,89');
      expect(_fmt('1000.5').text, '1 000.5');
    });
    test('parseAmount читає число з пробілами', () {
      expect(parseAmount('1 000 000'), 1000000);
      expect(parseAmount('1 234,5'), 1234.5);
    });
  });
}
