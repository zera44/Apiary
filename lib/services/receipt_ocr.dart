import 'dart:io';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image_picker/image_picker.dart';
import 'package:paddle_ocr_flutter/paddle_ocr_flutter.dart';

import '../logic/receipt_image.dart';
import '../logic/receipt_parser.dart';

/// Розпізнавання тексту на фото чека. Основний рушій - PaddleOCR (нейромережа
/// PP-OCR в ONNX Runtime, пакет paddle_ocr_flutter, моделі в assets/ocr/);
/// запасний - Tesseract (українська: assets/tessdata/ukr.traineddata).
/// Працює на телефоні; на комп'ютері розпізнавання недоступне - там фото
/// лише обирають, а таблицю заповнюють вручну.
abstract class ReceiptOcr {
  /// Чи вміє цей пристрій розпізнавати текст.
  bool get supported;

  /// Текст із зображення за шляхом [imagePath].
  Future<String> read(String imagePath);

  /// Підміняється в тестах.
  static ReceiptOcr instance = HybridReceiptOcr();
}

/// Спершу PaddleOCR (Android); якщо його немає, він упав або не знайшов жодної
/// позиції - Tesseract.
class HybridReceiptOcr implements ReceiptOcr {
  HybridReceiptOcr({ReceiptOcr? fallback}) : _fallback = fallback ?? TesseractReceiptOcr();

  final ReceiptOcr _fallback;

  @override
  bool get supported => _fallback.supported;

  @override
  Future<String> read(String imagePath) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        if (await PaddleOcr.ready()) {
          final r = await PaddleOcr.recognize(imagePath);
          if (parseReceipt(r.text).isNotEmpty) return r.text;
        }
      } catch (_) {
        // плагін чи модель не спрацювали - читаємо Tesseract-ом
      }
    }
    return _fallback.read(imagePath);
  }
}

class TesseractReceiptOcr implements ReceiptOcr {
  @override
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool _modelChecked = false;

  /// Плагін копіює модель (assets/tessdata/ukr.traineddata) на телефон лише
  /// раз - якщо її там ще немає. Тож після оновлення застосунку з новою
  /// моделлю (донавчання на чеках) стара лишилася б назавжди: копія іншого
  /// розміру прибирається, і плагін кладе нову.
  static Future<void> _freshModel() async {
    if (_modelChecked) return;
    _modelChecked = true;
    try {
      final asset = await rootBundle.load('assets/tessdata/ukr.traineddata');
      final dir = await FlutterTesseractOcr.getTessdataPath();
      await dropStaleModel(File('$dir/ukr.traineddata'), asset.lengthInBytes);
    } catch (_) {
      // не вийшло перевірити - працюємо з тим, що є
    }
  }

  /// Прибрати копію моделі [copy], якщо вона не того розміру, що в
  /// застосунку ([assetBytes]). true - прибрано.
  static Future<bool> dropStaleModel(File copy, int assetBytes) async {
    if (!await copy.exists() || await copy.length() == assetBytes) return false;
    await copy.delete();
    return true;
  }

  Future<String> _tesseract(String path) async {
    await _freshModel();
    return FlutterTesseractOcr.extractText(
        path,
        language: 'ukr',
        args: {
          // psm 6 - один суцільний блок тексту: так чек читається рядок за рядком
          'psm': '6',
          'preserve_interword_spaces': '1',
        },
      );
  }

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
