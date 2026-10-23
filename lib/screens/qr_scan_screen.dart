import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/repository.dart';
import '../logic/receipt_detect.dart';
import '../services/receipt_ocr.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../data/finance.dart';
import 'fin_add_screen.dart';

/// Чи є на цьому пристрої камера-сканер (телефон/планшет).
bool get qrCameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Отримати текст QR-коду: на телефоні — камерою, на комп'ютері (де
/// сканера немає) — ручним вводом. null — скасовано.
///
/// З [receiptRepo] у сканері є ще й режим «Чек»: фото чека розпізнається й
/// потрапляє у таблицю нової витрати у фінансах (рядки «на склад» стають приходом).
Future<String?> scanQrCode(BuildContext context,
    {String title = 'Сканувати QR-код', String? skipLabel, Repository? receiptRepo}) async {
  if (!qrCameraAvailable) return _manualEntry(context);
  return Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => QrScanScreen(title: title, skipLabel: skipLabel, receiptRepo: receiptRepo),
  ));
}

/// Повертається замість коду, коли натиснули [skipLabel] («Пропустити цей вулик»).
const kQrSkip = '\u0000skip';

Future<String?> _manualEntry(BuildContext context) async {
  final v = await showTextPrompt(context, title: 'Введіть код (посилання) вручну', initial: '');
  final t = v?.trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Повноекранна камера для всього: код вулика й чек. Камера сама розуміє, що
/// в кадрі. QR-код - з'являється рамка; чек - обводиться його контур. Тримайте
/// телефон нерухомо кілька секунд ([qrHold] для коду, [receiptHold] для чека),
/// і код зчитується, а чек знімається. Ручні кнопки лишаються на випадок,
/// коли автоматика не бачить (темно, блиск, чек лежить на світлому).
class QrScanScreen extends StatefulWidget {
  final String title;

  /// Додаткова кнопка «пропустити» (наприклад, при прив'язці наліпок підряд).
  final String? skipLabel;

  /// Склад, куди потрапляє чек: якщо задано - камера шукає ще й чек і
  /// передає його у таблицю нової витрати у фінансах.
  final Repository? receiptRepo;
  const QrScanScreen(
      {super.key, this.title = 'Сканувати QR-код', this.skipLabel, this.receiptRepo});

  /// Скільки тримати камеру над QR-кодом.
  static const qrHold = Duration(seconds: 3);

  /// Скільки тримати камеру над чеком.
  static const receiptHold = Duration(milliseconds: 3500);

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _ctrl = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
  );
  final _previewKey = GlobalKey();
  Timer? _timer;
  int _ticks = 0;

  // камера видає той самий код багато разів на секунду - повертаємо лише
  // перший, інакше pop викликався б кілька разів і закрив зайві екрани
  bool _done = false;

  // поки відкрите вікно ручного вводу чи системна камера, кадри не слухаємо
  bool _manualOpen = false;

  // QR: який код бачимо, відколи й коли востаннє
  String? _qr;
  DateTime? _qrSince;
  DateTime _qrSeen = DateTime.fromMillisecondsSinceEpoch(0);

  // чек: контур у кадрі, відколи він стоїть на місці
  ReceiptQuad? _quad;
  DateTime? _quadSince;
  int _quadMisses = 0;
  bool _analysing = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 150), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_ctrl.dispose());
    super.dispose();
  }

  bool get _receiptOn => widget.receiptRepo != null;

  /// Частка (0..1) витриманого часу над QR-кодом або над чеком.
  double get _progress {
    final now = DateTime.now();
    if (_qr != null && _qrSince != null) {
      return (now.difference(_qrSince!).inMilliseconds / QrScanScreen.qrHold.inMilliseconds)
          .clamp(0.0, 1.0);
    }
    if (_quad != null && _quadSince != null) {
      return (now.difference(_quadSince!).inMilliseconds /
              QrScanScreen.receiptHold.inMilliseconds)
          .clamp(0.0, 1.0);
    }
    return 0;
  }

  void _tick() {
    if (!mounted || _done) return;
    _ticks++;
    final now = DateTime.now();
    // код зник із кадру більш ніж на 0,7 с - відлік спочатку
    if (_qr != null && now.difference(_qrSeen).inMilliseconds > 700) {
      _qr = null;
      _qrSince = null;
    }
    if (_qr != null && _qrSince != null && now.difference(_qrSince!) >= QrScanScreen.qrHold) {
      _done = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(_qr);
      return;
    }
    if (_receiptOn && _qr == null && !_manualOpen && !_capturing && _ticks % 3 == 0) {
      unawaited(_analyse());
    }
    if (_qr != null && _quad != null) {
      _quad = null;
      _quadSince = null;
    }
    setState(() {});
  }

  /// Знімок того, що видно на екрані (зменшений) -> чи є там чек.
  Future<void> _analyse() async {
    if (_analysing) return;
    _analysing = true;
    try {
      final ro = _previewKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary || ro.size.width <= 0) return;
      final img = await ro.toImage(pixelRatio: 120 / ro.size.width);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width, h = img.height;
      img.dispose();
      if (data == null || !mounted || _done || _qr != null) return;
      final q = detectReceipt(data.buffer.asUint8List(), w, h);
      final now = DateTime.now();
      if (q == null) {
        // один пропущений кадр не скидає відлік (рука трохи тремтить)
        if (++_quadMisses >= 2) {
          _quad = null;
          _quadSince = null;
        }
        return;
      }
      _quadMisses = 0;
      final prev = _quad;
      if (prev == null || !q.similarTo(prev)) _quadSince = now;
      _quad = q;
      if (_quadSince != null && now.difference(_quadSince!) >= QrScanScreen.receiptHold) {
        await _captureReceipt(q);
      }
    } catch (_) {
      // кадр не вдалося прочитати - спробуємо наступного разу
    } finally {
      _analysing = false;
    }
  }

  /// Зберегти чек із екрана (обрізаний по контуру) й відкрити таблицю витрати.
  Future<void> _captureReceipt(ReceiptQuad q) async {
    final repo = widget.receiptRepo;
    if (repo == null || _capturing || _done) return;
    _capturing = true;
    try {
      final ro = _previewKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final full = await ro.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
      final xs = [for (final c in q.corners) c.dx], ys = [for (final c in q.corners) c.dy];
      final x0 = (xs.reduce((a, b) => a < b ? a : b) - 0.03).clamp(0.0, 1.0);
      final x1 = (xs.reduce((a, b) => a > b ? a : b) + 0.03).clamp(0.0, 1.0);
      final y0 = (ys.reduce((a, b) => a < b ? a : b) - 0.03).clamp(0.0, 1.0);
      final y1 = (ys.reduce((a, b) => a > b ? a : b) + 0.03).clamp(0.0, 1.0);
      final src = Rect.fromLTRB(x0 * full.width, y0 * full.height, x1 * full.width, y1 * full.height);
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(
          full, src, Rect.fromLTWH(0, 0, src.width, src.height), Paint()..filterQuality = FilterQuality.high);
      final crop = await rec.endRecording().toImage(src.width.round(), src.height.round());
      full.dispose();
      final png = await crop.toByteData(format: ui.ImageByteFormat.png);
      crop.dispose();
      if (png == null || !mounted || _done) return;
      final file = File('${Directory.systemTemp.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      if (!mounted || _done) return;
      _done = true;
      HapticFeedback.mediumImpact();
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => FinAddScreen(repo: repo, kind: kFinExpense, imagePath: file.path)));
    } catch (_) {
      _quad = null;
      _quadSince = null;
    } finally {
      _capturing = false;
    }
  }

  /// Знімок системною камерою чи вибір з галереї: найякісніший спосіб.
  Future<void> _receiptPhoto({required bool camera}) async {
    final repo = widget.receiptRepo;
    if (repo == null || _done || _manualOpen) return;
    _manualOpen = true; // поки відкрита камера/галерея, коди не слухаємо
    String? path;
    try {
      await _ctrl.stop(); // камера потрібна системному знімку
      path = await pickReceiptPhoto(camera: camera);
    } finally {
      _manualOpen = false;
    }
    if (path == null || !mounted || _done) {
      if (mounted && !_done) unawaited(_ctrl.start());
      return;
    }
    _done = true;
    // екран чека стає на місце сканера
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => FinAddScreen(repo: repo, kind: kFinExpense, imagePath: path!)));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || _manualOpen) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        final now = DateTime.now();
        if (v != _qr) {
          _qr = v;
          _qrSince = now;
        }
        _qrSeen = now;
        return;
      }
    }
  }

  Future<void> _manual() async {
    if (_manualOpen || _done) return;
    _manualOpen = true;
    String? v;
    try {
      v = await _manualEntry(context);
    } finally {
      _manualOpen = false;
    }
    if (v == null || !mounted || _done) return;
    _done = true;
    Navigator.of(context).pop(v);
  }

  String get _hint {
    if (_qr != null) return 'QR-код знайдено - тримайте камеру нерухомо';
    if (_quad != null) return 'Чек знайдено - тримайте телефон нерухомо';
    return _receiptOn
        ? 'Наведіть камеру на QR-код вулика або на чек і потримайте кілька секунд'
        : 'Наведіть камеру на QR-код вулика і потримайте кілька секунд';
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final total = (_qr != null ? QrScanScreen.qrHold : QrScanScreen.receiptHold).inMilliseconds / 1000;
    final left = (total * (1 - p)).ceil().clamp(1, 9);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _done = true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _previewKey,
                child: MobileScanner(controller: _ctrl, onDetect: _onDetect),
              ),
            ),
            // рамка: QR - квадрат у центрі, чек - його контур
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FramePainter(
                    quad: _quad,
                    qr: _qr != null,
                    progress: p,
                    color: AppColors.accent,
                  ),
                  child: Center(
                    child: (_qr != null || _quad != null) && p < 1
                        ? Text('$left',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 54,
                                fontWeight: FontWeight.w800,
                                shadows: [Shadow(blurRadius: 8, color: Colors.black87)]))
                        : null,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                child: TopBar(
                    title: _receiptOn ? 'Сканувати код або чек' : widget.title,
                    onBack: () {
                      if (_done) return;
                      _done = true; // камера ще працює під час закриття - не закривати вдруге
                      Navigator.pop(context);
                    }),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
                const SizedBox(height: 12),
                if (_receiptOn) ...[
                  Row(children: [
                    Expanded(
                      child: PillButton(
                        text: 'Фото чека',
                        bg: AppColors.accent,
                        height: 44,
                        onPressed: () => _receiptPhoto(camera: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PillButton(
                        text: 'З галереї',
                        bg: AppColors.roundBtn,
                        fg: AppColors.text,
                        height: 44,
                        onPressed: () => _receiptPhoto(camera: false),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
                PillButton(
                  text: 'Ввести код вручну',
                  bg: AppColors.roundBtn,
                  fg: AppColors.text,
                  height: 44,
                  width: double.infinity,
                  onPressed: _manual,
                ),
                if (widget.skipLabel != null) ...[
                  const SizedBox(height: 8),
                  PillButton(
                    text: widget.skipLabel!,
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    height: 44,
                    width: double.infinity,
                    onPressed: () {
                      if (_done) return;
                      _done = true;
                      Navigator.of(context).pop(kQrSkip);
                    },
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Рамка на камері: тьмяний приціл, коли нічого не видно; рамка коду чи
/// контур чека з індикатором витриманого часу, коли щось знайдено.
class _FramePainter extends CustomPainter {
  final ReceiptQuad? quad;
  final bool qr;
  final double progress;
  final Color color;
  const _FramePainter(
      {required this.quad, required this.qr, required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    Path path;
    var found = true;
    if (qr) {
      final r = Rect.fromCenter(center: size.center(Offset.zero), width: 240, height: 240);
      path = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(20)));
    } else if (quad != null) {
      final pts = [for (final c in quad!.corners) Offset(c.dx * size.width, c.dy * size.height)];
      path = Path()..addPolygon(pts, true);
    } else {
      found = false;
      final r = Rect.fromCenter(center: size.center(Offset.zero), width: 240, height: 240);
      path = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(20)));
    }
    if (!found) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.white38);
      return;
    }
    // знайдене: напівпрозора заливка, тонка рамка й товстий індикатор часу
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.12 + 0.18 * progress));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.5));
    final bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), bar);
    }
  }

  @override
  bool shouldRepaint(_FramePainter o) =>
      o.progress != progress || o.qr != qr || o.quad != quad;
}
