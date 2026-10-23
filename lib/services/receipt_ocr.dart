import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:paddle_ocr_flutter/paddle_ocr_flutter.dart';


/// Розпізнавання тексту на фото чека: PaddleOCR (нейромережа PP-OCR в ONNX
/// Runtime, пакет paddle_ocr_flutter, моделі в assets/ocr/), повністю офлайн.
/// Працює на Android; деінде розпізнавання недоступне - там фото лише
/// обирають, а таблицю заповнюють вручну.
abstract class ReceiptOcr {
  /// Чи вміє цей пристрій розпізнавати текст.
  bool get supported;

  /// Текст із зображення за шляхом [imagePath].
  Future<String> read(String imagePath);

  /// Підміняється в тестах.
  static ReceiptOcr instance = PaddleReceiptOcr();
}

class PaddleReceiptOcr implements ReceiptOcr {
  @override
  bool get supported => !kIsWeb && Platform.isAndroid;

  @override
  Future<String> read(String imagePath) async {
    if (!supported || !await PaddleOcr.ready()) {
      throw StateError('PaddleOCR недоступний на цьому пристрої');
    }
    return (await PaddleOcr.recognize(imagePath)).text;
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
