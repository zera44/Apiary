import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image_picker/image_picker.dart';

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

  @override
  Future<String> read(String imagePath) {
    return FlutterTesseractOcr.extractText(
      imagePath,
      language: 'ukr',
      args: {
        // psm 6 - один суцільний блок тексту: так чек читається рядок за рядком
        'psm': '6',
        'preserve_interword_spaces': '1',
      },
    );
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
