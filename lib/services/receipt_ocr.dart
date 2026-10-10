import 'dart:io';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/receipt_image.dart';
import '../logic/receipt_parser.dart';

/// Розпізнавання тексту на фото чека (Tesseract, українська мова:
/// assets/tessdata/ukr.traineddata). Працює на телефоні; на комп'ютері
/// розпізнавання недоступне - там фото лише обирають, а таблицю заповнюють вручну.
abstract class ReceiptOcr {
  /// Чи вміє цей пристрій розпізнавати текст.
  bool get supported;

  /// Текст із зображення за шляхом [imagePath].
  Future<String> read(String imagePath);

  /// Підміняється в тестах.
  static ReceiptOcr instance = TesseractReceiptOcr();
}

class TesseractReceiptOcr implements ReceiptOcr {
  @override
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<String> _tesseract(String path) => FlutterTesseractOcr.extractText(
        path,
        language: 'ukr',
        args: {
          // psm 6 - один суцільний блок тексту: так чек читається рядок за рядком
          'psm': '6',
          'preserve_interword_spaces': '1',
        },
      );

  /// Спершу - підготовлене фото (чорне на білому, без тіней: див.
  /// logic/receipt_image.dart), воно читається значно краще. Якщо з нього не
  /// вийшло жодної позиції - ще раз з оригіналу.
  @override
  Future<String> read(String imagePath) async {
    String? prepared;
    try {
      final bytes = await compute(prepareReceiptImage, await File(imagePath).readAsBytes());
      if (bytes != null) {
        prepared = '$imagePath.ocr.png';
        await File(prepared).writeAsBytes(bytes, flush: true);
      }
    } catch (_) {
      prepared = null; // не вдалося підготувати - читаємо як є
    }
    if (prepared != null) {
      try {
        final text = await _tesseract(prepared);
        if (parseReceipt(text).isNotEmpty) return text;
      } finally {
        File(prepared).delete().ignore();
      }
    }
    return _tesseract(imagePath);
  }
}

/// Фото чека: [camera] - знімок камерою, інакше - з галереї (на комп'ютері - файл).
/// null - скасовано.
Future<String?> pickReceiptPhoto({required bool camera}) async {
  final cameraOk = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final x = await ImagePicker().pickImage(
    source: camera && cameraOk ? ImageSource.camera : ImageSource.gallery,
    // чек вузький і довгий: потрібна роздільність, інакше дрібний шрифт не читається
    maxWidth: 2400,
    maxHeight: 4800,
    imageQuality: 92,
  );
  return x?.path;
}
