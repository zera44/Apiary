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
}
