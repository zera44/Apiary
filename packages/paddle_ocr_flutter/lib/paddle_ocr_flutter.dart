/// Офлайн-розпізнавання тексту чеків (Android): PaddleOCR PP-OCR (детекція
/// рядків + читання, ONNX Runtime). Моделі лежать у застосунку:
/// assets/ocr/det.onnx, rec.onnx, dict.txt. Уся логіка - у Java (OcrPipeline).
library;

import 'package:flutter/services.dart';

/// Результат розпізнавання фото.
class PaddleOcrResult {
  /// Рядки тексту зверху вниз (назва й ціна на одній висоті - в одному рядку).
  final List<String> lines;

  /// На скільки градусів за годинниковою повернуто фото, щоб текст був прямо.
  final int rotation;

  /// Середня впевненість читача (0..1).
  final double confidence;

  /// Скільки тривало розпізнавання, мс.
  final int millis;

  const PaddleOcrResult(this.lines, this.rotation, this.confidence, this.millis);

  String get text => lines.join('\n');
}

/// Фрагмент тексту з координатами (для нечіткої розмітки чека). Координати - у
/// кадрі зображення, яке читалося, повернутому на -[angle] (рядки горизонтальні).
class OcrFrag {
  final int boxId;
  final String text;
  final double conf, x, y, w, h, xLeft, xRight, angle;
  final int imgW, imgH;

  /// Дочитаний фрагмент (пропущена назва, «1x» тощо), а не рамка детектора.
  final bool recovered;

  /// Рукописний рядок бланка: 'NAME' або 'ITEM'; null - друкований текст.
  final String? hand;

  const OcrFrag({
    required this.boxId,
    required this.text,
    required this.conf,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.xLeft,
    required this.xRight,
    required this.angle,
    required this.imgW,
    required this.imgH,
    this.recovered = false,
    this.hand,
  });

  factory OcrFrag.fromMap(Map<Object?, Object?> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return OcrFrag(
      boxId: (m['box_id'] as num?)?.toInt() ?? 0,
      text: '${m['text'] ?? ''}',
      conf: d('conf'),
      x: d('x'),
      y: d('y'),
      w: d('w'),
      h: d('h'),
      xLeft: d('x_left'),
      xRight: d('x_right'),
      angle: d('angle'),
      imgW: (m['img_w'] as num?)?.toInt() ?? 0,
      imgH: (m['img_h'] as num?)?.toInt() ?? 0,
      recovered: m['recovered'] == true,
      hand: m['hand'] as String?,
    );
  }
}

/// Результат розпізнавання з фрагментами.
class PaddleOcrFrags {
  final List<OcrFrag> frags;
  final int rotation;
  final double confidence;
  final int millis;

  const PaddleOcrFrags(this.frags, this.rotation, this.confidence, this.millis);
}

class PaddleOcr {
  PaddleOcr._();

  static const _channel = MethodChannel('paddle_ocr_flutter');

  /// Чи є на цьому пристрої плагін і моделі.
  static Future<bool> ready() async {
    try {
      return (await _channel.invokeMethod<bool>('ready')) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Розпізнати фото за шляхом [path]. Кидає [PlatformException], якщо не вдалося.
  static Future<PaddleOcrResult> recognize(String path) async {
    final m = await _channel.invokeMapMethod<String, Object?>('recognize', {'path': path});
    if (m == null) throw PlatformException(code: 'ocr', message: 'порожня відповідь');
    final lines = [for (final l in (m['lines'] as List? ?? const [])) '$l'];
    return PaddleOcrResult(
      lines,
      (m['rotation'] as num?)?.toInt() ?? 0,
      (m['conf'] as num?)?.toDouble() ?? 0,
      (m['ms'] as num?)?.toInt() ?? 0,
    );
  }

  /// Розпізнати фото з координатами фрагментів (як курсова: кілька поворотів,
  /// дочитування сум і назв, рукописні рядки бланка). Якщо дано [imagePath], туди
  /// записується JPEG зображення, у кадрі якого задані координати.
  static Future<PaddleOcrFrags> recognizeFrags(String path, {String? imagePath}) async {
    final m = await _channel.invokeMapMethod<String, Object?>(
        'recognizeFrags', {'path': path, if (imagePath != null) 'image': imagePath});
    if (m == null) throw PlatformException(code: 'ocr', message: 'порожня відповідь');
    return PaddleOcrFrags(
      [for (final f in (m['frags'] as List? ?? const [])) OcrFrag.fromMap(f as Map<Object?, Object?>)],
      (m['rotation'] as num?)?.toInt() ?? 0,
      (m['conf'] as num?)?.toDouble() ?? 0,
      (m['ms'] as num?)?.toInt() ?? 0,
    );
  }
}
