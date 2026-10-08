import 'dart:io';
import 'dart:typed_data';

import 'package:apiary/logic/receipt_image.dart';
import 'package:apiary/logic/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Чек кафе: «кількість x ціна» друкується НАД назвою, сума - праворуч від
/// назви, назва переноситься («200/10» + «Г»). Текст - як на папері.
const _cafe = '''
ТОВ "ДІННЕРЗ ПРОДАКШН"
КАФЕ Кафе
УКРАЇНА, М.КИЇВ ПОДІЛЬСЬКИЙ Р-Н, ВУЛИЦЯ
ЯРОСЛАВСЬКА, БУД. 58
ПН 433771726509
------------------------------------------
1,000 X 75,00
МОРКВА ПО-КОРЕЙСЬКИ 120Г           75,00 А
1,000 X 97,00
СОЛЯНКА МЯСНА ПО-ДОМАШНЬОМУ 200/10 97,00 А
Г
1,000 X 112,00
ВІДБИВНА ПО-КИЇВСЬКИ 95Г          112,00 А
1,000 X 65,00
КУС КУС З ОВОЧАМИ 180Г             65,00 А
------------------------------------------
ТЕРМІНАЛ                          R2224223
КОМІСІЯ ЕКВАЙРА                   0,00 ГРН
БЕЗГОТІВКОВА                    349,00 ГРН
ЗАСІБ ОПЛАТИ                        КАРТКА
СУМА                                349,00
ПДВ_А = 20,00%                       58,17
''';

void main() {
  group('чек кафе: кількість x ціна над назвою', () {
    test('назви звичайним реченням, ціни, кількість', () {
      final rows = parseReceipt(_cafe);
      expect(rows.map((r) => r.name), [
        'Морква по-корейськи 120 г',
        'Солянка мясна по-домашньому 200/10 г',
        'Відбивна по-київськи 95 г',
        'Кус кус з овочами 180 г',
      ]);
      expect(rows.map((r) => r.price), [75, 97, 112, 65]);
      expect(rows.every((r) => r.qty == 1 && r.unit == 'шт'), isTrue);
    });

    test('список текстом: «назва к-сть, ціна, сума»', () {
      expect(
          receiptAsText(parseReceipt(_cafe)),
          'Морква по-корейськи 120 г 1 шт, 75 грн, сума 75 грн\n'
          'Солянка мясна по-домашньому 200/10 г 1 шт, 97 грн, сума 97 грн\n'
          'Відбивна по-київськи 95 г 1 шт, 112 грн, сума 112 грн\n'
          'Кус кус з овочами 180 г 1 шт, 65 грн, сума 65 грн');
      expect(receiptAsText([ReceiptRow(name: 'Цукор', qty: 2.5, unit: 'кг', price: 30.5)]),
          'Цукор 2,5 кг, 30,50 грн, сума 76,25 грн');
    });

    test('вага: кількість над назвою береться, а не губиться', () {
      final rows = parseReceipt('2,350 X 120,00\nМЕД ЛИПОВИЙ 282,00 А\n1,000 X 10,00\nПАКЕТ 10,00 А');
      expect(rows.first.qty, 2.35);
      expect(rows.first.unit, 'кг');
      expect(rows.first.price, 120);
      expect(rows.last.name, 'Пакет');
    });

    // справжній текст Tesseract з двох фото цього чека (зім'ятий папір):
    // цифри біля згинів зіпсовані («х197,00», «1,060 х/Р12,00»), але сума
    // праворуч читається - за нею ціни й відновлюються
    for (final f in ['receipt_cafe_ocr_1.txt', 'receipt_cafe_ocr_2.txt']) {
      test('сирий OCR із фото: $f', () {
        final rows = parseReceipt(File('test/fixtures/$f').readAsStringSync());
        expect(rows.length, 4, reason: rows.toString());
        expect(rows.map((r) => r.price), [75, 97, 112, 65]);
        expect(rows.every((r) => r.qty == 1), isTrue, reason: rows.toString());
        expect(rows[0].name, startsWith('Морква'));
        expect(rows[1].name.toLowerCase(), startsWith('солянка'));
        expect(rows[2].name.toLowerCase(), contains('відби'));
        expect(rows[3].name, startsWith('Кус'));
        // нічого після «СУМА» (картка, ПДВ) не стало товаром
        expect(rows.map((r) => r.name.toLowerCase()).join('|'), isNot(contains('сума')));
      });
    }
  });

  group('підготовка фото', () {
    test('тінь зникає, текст - чорний, тло - біле', () {
      const w = 120, h = 40;
      final gray = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final bg = 90 + x; // ліворуч тінь (90), праворуч світло (209)
          final ink = y >= 15 && y < 25 && x % 20 < 4; // «літери»
          gray[y * w + x] = ink ? bg - 60 : bg;
        }
      }
      final bw = binarizeAdaptive(gray, w, h);
      // текст у тіні й на світлі - однаково чорний
      expect(bw[20 * w + 1], 0);
      expect(bw[20 * w + 101], 0);
      // тло і в тіні, і на світлі - біле
      expect(bw[5 * w + 10], 255);
      expect(bw[5 * w + 110], 255);
      expect(bw[20 * w + 10], 255);
    });

    test('велике фото зменшується до робочої ширини, виходить png', () {
      final photo = img.Image(width: 2100, height: 300);
      img.fill(photo, color: img.ColorRgb8(200, 200, 190));
      img.fillRect(photo, x1: 100, y1: 100, x2: 400, y2: 140, color: img.ColorRgb8(30, 30, 30));
      final out = prepareReceiptImage(img.encodeJpg(photo));
      expect(out, isNotNull);
      final back = img.decodePng(out!)!;
      expect(back.width, receiptOcrWidth);
      expect(back.height, 150);
      expect(back.getPixel(5, 5).r, 255);
      // край темного прямокутника - чорний
      expect(back.getPixel(52, 60).r, 0);
    });

    test('не картинка - null, без винятку', () {
      expect(prepareReceiptImage(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
