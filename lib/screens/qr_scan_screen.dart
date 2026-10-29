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

/// Повноекранна камера: код вулика й чек (перемикач угорі). QR-код: з'являється
/// рамка, тримайте телефон нерухомо [qrHold], і код зчитується. Чек: обводиться
/// його контур, знімає кнопка «Зняти» (без відліку); «Камерою телефона» й «З
/// галереї» дають найякісніше фото.
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
  static const qrHold = Duration(milliseconds: 1500);

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

  /// Режим «Чек» (перемикач угорі): камера шукає контур чека, а не QR-код.
  bool _receipt = false;

  void _setMode(bool receipt) {
    if (_receipt == receipt) return;
    setState(() {
      _receipt = receipt;
      _qr = null;
      _qrSince = null;
      _quad = null;
      _quadMisses = 0;
    });
  }

  Widget _modeSwitch() {
    Widget tab(String text, bool receipt) => Expanded(
          child: PillButton(
            text: text,
            bg: _receipt == receipt ? AppColors.accent : AppColors.roundBtn,
            fg: _receipt == receipt ? Colors.white : AppColors.text,
            height: 40,
            fontSize: 13,
            onPressed: () => _setMode(receipt),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [tab('Код вулика', false), const SizedBox(width: 8), tab('Чек', true)]),
    );
  }

  /// Частка (0..1) витриманого часу над QR-кодом або над чеком.
  double get _progress {
    final now = DateTime.now();
    if (_qr != null && _qrSince != null) {
      return (now.difference(_qrSince!).inMilliseconds / QrScanScreen.qrHold.inMilliseconds)
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
    if (_receiptOn && _receipt && !_manualOpen && !_capturing && _ticks % 3 == 0) {
      unawaited(_analyse());
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
      if (data == null || !mounted || _done || !_receipt) return;
      final q = detectReceipt(data.buffer.asUint8List(), w, h);
      if (q == null) {
        // один пропущений кадр не скидає відлік (рука трохи тремтить)
        if (++_quadMisses >= 2) _quad = null;
        return;
      }
      _quadMisses = 0;
      _quad = q;
    } catch (_) {
      // кадр не вдалося прочитати - спробуємо наступного разу
    } finally {
      _analysing = false;
    }
  }

  /// Зберегти чек із екрана (обрізаний по контуру) й відкрити таблицю витрати.
  Future<void> _captureReceipt(ReceiptQuad? q) async {
    final repo = widget.receiptRepo;
    if (repo == null || _capturing || _done) return;
    _capturing = true;
    try {
      final ro = _previewKey.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final full = await ro.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
      final xs = q == null ? const [0.0, 1.0] : [for (final c in q.corners) c.dx];
      final ys = q == null ? const [0.0, 1.0] : [for (final c in q.corners) c.dy];
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
      // знімок не вдався - можна ще раз
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
    if (_done || _manualOpen || _receipt) return;
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
    return _receipt
        ? 'Покладіть чек рівно на контрастний фон і натисніть «Зняти»'
        : 'Наведіть камеру на QR-код вулика і потримайте секунду-дві';
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final left = (QrScanScreen.qrHold.inMilliseconds / 1000 * (1 - p)).ceil().clamp(1, 9);
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
                    idleFrame: !_receipt,
                    progress: p,
                    color: AppColors.accent,
                  ),
                  child: Center(
                    child: _qr != null && p < 1
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TopBar(
                      title: _receipt ? 'Сканувати чек' : widget.title,
                      onBack: () {
                        if (_done) return;
                        _done = true; // камера ще працює під час закриття - не закривати вдруге
                        Navigator.pop(context);
                      }),
                  if (_receiptOn) _modeSwitch(),
                ]),
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
                if (_receipt) ...[
                  PillButton(
                    text: 'Зняти',
                    bg: AppColors.accent,
                    height: 48,
                    width: double.infinity,
                    onPressed: () => _captureReceipt(_quad),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: PillButton(
                        text: 'Камерою телефона',
                        bg: AppColors.roundBtn,
                        fg: AppColors.text,
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
                if (!_receipt)
                PillButton(
                  text: 'Ввести код вручну',
                  bg: AppColors.roundBtn,
                  fg: AppColors.text,
                  height: 44,
                  width: double.infinity,
                  onPressed: _manual,
                ),
                if (!_receipt && widget.skipLabel != null) ...[
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
  final bool idleFrame;
  final double progress;
  final Color color;
  const _FramePainter(
      {required this.quad, required this.qr, required this.idleFrame, required this.progress, required this.color});

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
      if (!idleFrame) return;
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
      o.progress != progress || o.qr != qr || o.quad != quad || o.idleFrame != idleFrame;
}
