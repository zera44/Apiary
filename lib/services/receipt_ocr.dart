import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:paddle_ocr_flutter/paddle_ocr_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/fz2/fz2.dart';
import '../logic/fz2/receipt_rows.dart';
import '../logic/fz2/recover.dart';
import '../logic/receipt_parser.dart';

/// Розмічений чек: класи фрагментів (нечітка розмітка fz2), позиції й підсумок,
/// а також зображення, у кадрі якого задані координати фрагментів.
class MarkedReceipt {
  final FzReceipt fz;

  /// Сіре зображення, яке читалося (повернуте прямо); null - не збережено.
  final String? image;

  /// Нахил рядків на [image], радіани: точка фрагмента (x, y) на зображенні -
  /// (x·cos - y·sin, x·sin + y·cos).
  final double angle;

  /// Кроки дочитування, що впали й були пропущені (розмітка все одно відпрацювала).
  final List<String> skipped;

  const MarkedReceipt(this.fz, this.image, this.angle, {this.skipped = const []});
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
    final session = await PaddleOcr.begin(imagePath);
    final List<Frag> frags;
    final List<String> skipped;
    FzReceipt fz;
    try {
      frags = [for (final f in session.frags) _frag(f)];
      final backend = _PluginBackend(session);
      // правила дочитування - тут (Dart), модель і зображення - у плагіні;
      // збій кроку дочитування не зупиняє розмітку
      skipped = await recoverAll(frags, backend);
      // розмітка - кілька тисяч нечітких висновків: в окремому ізоляті, щоб не гальмував інтерфейс
      fz = await Isolate.run(() => markReceipt(frags));
      // позиції не дають підсумок: загублений старший розряд суми перечитується ширшою рамкою
      try {
        if (await reconcileSums(frags, fz, backend)) fz = await Isolate.run(() => markReceipt(frags));
      } catch (e) {
        skipped.add('reconcile: $e');
      }
    } finally {
      await session.end(imagePath: image);
    }
    final ok = image != null && File(image).existsSync();
    return MarkedReceipt(fz, ok ? image : null, frags.isEmpty ? 0 : frags.first.angle, skipped: skipped);
  }
}

/// Текст чека для розбору. Рядки з фото збираються кількома способами: основний і
/// запасні, що розділяють сусідні рядки на фото під кутом. [pickReceiptText] бере
/// запасний лише тоді, коли з ним сума позицій дорівнює сумі чека, а з основним ні.
Future<String> readReceiptText(ReceiptOcr ocr, String imagePath) async {
  if (ocr is! PaddleReceiptOcr) return ocr.read(imagePath);
  if (!ocr.supported || !await PaddleOcr.ready()) {
    throw StateError('PaddleOCR недоступний на цьому пристрої');
  }
  final r = await PaddleOcr.recognize(imagePath);
  return pickReceiptText([r.text, ...r.altTexts]);
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

Frag _frag(OcrFrag f) => Frag(
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
      recovered: f.recovered,
    );

OcrFrag _ocrFrag(Frag f) => OcrFrag(
      boxId: f.boxId ?? 0,
      text: f.text,
      conf: f.conf,
      x: f.x,
      y: f.y,
      w: f.w,
      h: f.h,
      xLeft: f.xLeft,
      xRight: f.xRight,
      angle: f.angle,
      imgW: (f.imgW ?? 0).round(),
      imgH: (f.imgH ?? 0).round(),
      recovered: f.recovered,
      hand: f.hand,
    );

/// Те, що дочитування бере з плагіна: читання рамок, тісна рамка виродженого фрагмента, рукописні рядки.
class _PluginBackend implements OcrBackend {
  final PaddleOcrSession s;

  _PluginBackend(this.s);

  @override
  Future<List<ReadRes>> read(double angle, List<ReadReq> reqs) async => [
        for (final r in await s.read(angle, [for (final q in reqs) OcrReadReq(q.x1, q.x2, q.y1, q.y2, q.st)]))
          ReadRes(r.text, r.conf)
      ];

  @override
  Future<void> degen(Frag f, double angle) async {
    final r = await s.degen(angle, _ocrFrag(f));
    f
      ..x = r.x
      ..y = r.y
      ..w = r.w
      ..h = r.h
      ..xLeft = r.xLeft
      ..xRight = r.xRight;
  }

  @override
  Future<List<Frag>> hand(List<Frag> fr) async => [for (final f in await s.hand([for (final f in fr) _ocrFrag(f)])) _frag(f)];
}
