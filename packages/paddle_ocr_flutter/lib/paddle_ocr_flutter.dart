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

  /// Ті самі фрагменти, зібрані в рядки іншими способами (розділяють сусідні рядки на
  /// фото під кутом чи з вигнутим папером). Запасні варіанти для розбору чека.
  final List<List<String>> altLines;

  const PaddleOcrResult(this.lines, this.rotation, this.confidence, this.millis, {this.altLines = const []});

  String get text => lines.join('\n');

  /// Тексти з [altLines], без повторів і без такого самого, як [text].
  List<String> get altTexts {
    final out = <String>[];
    for (final l in altLines) {
      final t = l.join('\n');
      if (t.isNotEmpty && t != text && !out.contains(t)) out.add(t);
    }
    return out;
  }
}

/// Фрагмент тексту з координатами (для нечіткої розмітки чека). Координати - у
/// кадрі зображення, яке читалося, повернутому на -[angle] (рядки горизонтальні).
class OcrFrag {
  final int boxId;
  final String text;
  final double conf, x, y, w, h, xLeft, xRight, angle;

  /// Нахил самої рамки відносно загального ([angle]), радіани; NaN - невідомий (дочитаний фрагмент).
  final double skew;
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
    this.skew = double.nan,
    this.recovered = false,
    this.hand,
  });

  Map<String, Object?> toMap() => {
        'box_id': boxId,
        'text': text,
        'conf': conf,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'x_left': xLeft,
        'x_right': xRight,
        'angle': angle,
        'skew': skew,
        'img_w': imgW,
        'img_h': imgH,
        'recovered': recovered,
        'hand': hand,
      };

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
      skew: (m['skew'] as num?)?.toDouble() ?? double.nan,
      imgW: (m['img_w'] as num?)?.toInt() ?? 0,
      imgH: (m['img_h'] as num?)?.toInt() ?? 0,
      recovered: m['recovered'] == true,
      hand: m['hand'] as String?,
    );
  }
}

/// Запит на читання рамки (x1..x2, y1..y2 - у системі фрагментів, повернутій на нахил фото).
class OcrReadReq {
  final double x1, x2, y1, y2;

  /// Розтягнення рядка перед читанням (див. OcrV2.read).
  final List<double> st;

  const OcrReadReq(this.x1, this.x2, this.y1, this.y2, this.st);

  Map<String, Object?> toMap() => {'x1': x1, 'x2': x2, 'y1': y1, 'y2': y2, 'st': st};
}

class OcrRead {
  final String text;
  final double conf;

  const OcrRead(this.text, this.conf);
}

/// Відкрите розпізнавання: детектор уже відпрацював, далі потрібні лише читання рамок на тому самому зображенні.
/// Правила дочитування - у застосунку (Dart), тут лише те, що потребує моделей і зображення.
class PaddleOcrSession {
  final String _id;

  /// Фрагменти детектора (до дочитування).
  final List<OcrFrag> frags;
  final int rotation;
  final double confidence;
  final int millis;

  PaddleOcrSession._(this._id, this.frags, this.rotation, this.confidence, this.millis);

  static const _ch = PaddleOcr._channel;

  /// Прочитати рамки (відповіді - у порядку запитів).
  Future<List<OcrRead>> read(double angle, List<OcrReadReq> reqs) async {
    if (reqs.isEmpty) return const [];
    final r = await _ch.invokeListMethod<Map<Object?, Object?>>(
        'ocrRead', {'session': _id, 'angle': angle, 'reqs': [for (final q in reqs) q.toMap()]});
    return [for (final m in r ?? const []) OcrRead('${m['text'] ?? ''}', (m['conf'] as num?)?.toDouble() ?? 0)];
  }

  /// Тісна рамка за чорнилом для фрагмента з виродженою рамкою.
  Future<OcrFrag> degen(double angle, OcrFrag f) async {
    final m = await _ch.invokeMapMethod<Object?, Object?>('ocrDegen', {'session': _id, 'angle': angle, 'frag': f.toMap()});
    return OcrFrag.fromMap(m ?? f.toMap());
  }

  /// Рукописні рядки бланка «Товарний чек».
  Future<List<OcrFrag>> hand(List<OcrFrag> fr) async {
    final r = await _ch.invokeListMethod<Map<Object?, Object?>>(
        'ocrHand', {'session': _id, 'frags': [for (final f in fr) f.toMap()]});
    return [for (final m in r ?? const []) OcrFrag.fromMap(m)];
  }

  /// Закрити сесію; якщо дано [imagePath], туди записується JPEG зображення, яке читалося.
  Future<void> end({String? imagePath}) async {
    await _ch.invokeMethod<bool>('ocrEnd', {'session': _id, if (imagePath != null) 'image': imagePath});
  }
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
      altLines: [
        for (final v in (m['altLines'] as List? ?? const [])) [for (final l in (v as List? ?? const [])) '$l'],
      ],
    );
  }

  /// Відкрити розпізнавання фото з координатами фрагментів (кілька поворотів, детектор): далі дочитування
  /// ведеться через [PaddleOcrSession.read] тощо, наприкінці - [PaddleOcrSession.end].
  static Future<PaddleOcrSession> begin(String path) async {
    final m = await _channel.invokeMapMethod<String, Object?>('ocrBegin', {'path': path});
    if (m == null) throw PlatformException(code: 'ocr', message: 'порожня відповідь');
    return PaddleOcrSession._(
      '${m['session']}',
      [for (final f in (m['frags'] as List? ?? const [])) OcrFrag.fromMap(f as Map<Object?, Object?>)],
      (m['rotation'] as num?)?.toInt() ?? 0,
      (m['conf'] as num?)?.toDouble() ?? 0,
      (m['ms'] as num?)?.toInt() ?? 0,
    );
  }
}
