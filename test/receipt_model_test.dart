import 'dart:io';

import 'package:apiary/services/receipt_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tessdata'));
  tearDown(() async => dir.delete(recursive: true));

  test('модель у застосунку оновилась - стара копія на телефоні прибирається', () async {
    final copy = File('${dir.path}/ukr.traineddata')..writeAsBytesSync(List.filled(421660, 1));
    expect(await TesseractReceiptOcr.dropStaleModel(copy, 965871), isTrue);
    expect(copy.existsSync(), isFalse); // плагін покладе нову
  });

  test('та сама модель чи копії ще немає - нічого не чіпає', () async {
    final copy = File('${dir.path}/ukr.traineddata')..writeAsBytesSync(List.filled(100, 1));
    expect(await TesseractReceiptOcr.dropStaleModel(copy, 100), isFalse);
    expect(copy.existsSync(), isTrue);
    expect(await TesseractReceiptOcr.dropStaleModel(File('${dir.path}/none'), 100), isFalse);
  });

  test('у застосунку - донавчена модель v2 (не стара tessdata_fast)', () {
    expect(File('assets/tessdata/ukr.traineddata').lengthSync(), 965871);
  });
}
