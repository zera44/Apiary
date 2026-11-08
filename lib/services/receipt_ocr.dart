import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:paddle_ocr_flutter/paddle_ocr_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/fz2/fz2.dart';
import '../logic/fz2/receipt_rows.dart';

/// Розмічений чек: класи фрагментів (нечітка розмітка fz2), позиції й підсумок,
/// а також зображення, у кадрі якого задані координати фрагментів.
class MarkedReceipt {
  final FzReceipt fz;

  /// Сіре зображення, яке читалося (повернуте прямо); null - не збережено.
  final String? image;

  /// Нахил рядків на [image], радіани: точка фрагмента (x, y) на зображенні -
  /// (x·cos - y·sin, x·sin + y·cos).
  final double angle;

  const MarkedReceipt(this.fz, this.image, this.angle);
}


/// Розпізнавання тексту на фото чека: PaddleOCR (нейромережа PP-OCR в ONNX
/// Runtime, пакет paddle_ocr_flutter, моделі в assets/ocr/), повністю офлайн.
/// Працює на Android; деінде розпізнавання недоступне - там фото лише
/// обирають, а таблицю заповнюють вручну.
abstract class ReceiptOcr {
  /// Чи вміє цей пристрій розпізнавати текст.
  bool get supported;

  /// Текст із зображення за шляхом [imagePath].
  Future<String> read(String imagePath);

  /// Розпізнавання з нечіткою розміткою (як у курсовій): позиції, підсумок і
  /// класи фрагментів. null - цей розпізнавач розмітки не вміє (тоді - [read]).
  Future<MarkedReceipt?> mark(String imagePath);

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

  @override
  Future<MarkedReceipt?> mark(String imagePath) async {
    if (!supported || !await PaddleOcr.ready()) {
      throw StateError('PaddleOCR недоступний на цьому пристрої');
    }
    String? image;
    try {
      final dir = await getTemporaryDirectory();
      image = '${dir.path}/receipt_marked_${DateTime.now().millisecondsSinceEpoch}.jpg';
    } catch (_) {
      image = null;
    }
    final r = await PaddleOcr.recognizeFrags(imagePath, imagePath: image);
    final frags = [
      for (final f in r.frags)
        Frag(
          boxId: f.boxId,
          text: f.text,
          conf: f.conf,
          x: f.x,
          y: f.y,
          w: f.w,
          h: f.h,
          xLeft: f.xLeft,
          xRight: f.xRight,
          imgW: f.imgW.toDouble(),
          imgH: f.imgH.toDouble(),
          angle: f.angle,
          hand: f.hand,
        )
    ];
    // розмітка - кілька тисяч нечітких висновків: в окремому ізоляті, щоб не гальмував інтерфейс
    final fz = await Isolate.run(() => markReceipt(frags));
    final ok = image != null && File(image).existsSync();
    return MarkedReceipt(fz, ok ? image : null, frags.isEmpty ? 0 : frags.first.angle);
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
