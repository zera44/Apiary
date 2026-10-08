import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/repository.dart';
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

/// Повноекранна камера: перший розпізнаний QR-код повертається через
/// Navigator.pop.
class QrScanScreen extends StatefulWidget {
  final String title;

  /// Додаткова кнопка «пропустити» (наприклад, при прив'язці наліпок підряд).
  final String? skipLabel;

  /// Склад, куди потрапляє чек: якщо задано - зверху перемикач «Код вулика / Чек».
  final Repository? receiptRepo;
  const QrScanScreen(
      {super.key, this.title = 'Сканувати QR-код', this.skipLabel, this.receiptRepo});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  // камера видає той самий код багато разів на секунду — повертаємо лише
  // перший, інакше pop викликався б кілька разів і закрив зайві екрани
  bool _done = false;

  // поки відкрите вікно ручного вводу, камеру не слухаємо: інакше pop
  // закрив би саме вікно, а екран камери лишився б "завислим"
  bool _manualOpen = false;

  /// Режим «Чек»: камера QR вимкнена, чек фотографують і розпізнають.
  bool _receipt = false;

  Future<void> _receiptPhoto({required bool camera}) async {
    final repo = widget.receiptRepo;
    if (repo == null || _done || _manualOpen) return;
    _manualOpen = true; // поки відкрита камера/галерея, коди не слухаємо
    String? path;
    try {
      path = await pickReceiptPhoto(camera: camera);
    } finally {
      _manualOpen = false;
    }
    if (path == null || !mounted || _done) return;
    _done = true;
    // екран чека стає на місце сканера
    await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) =>
            FinAddScreen(repo: repo, kind: kFinExpense, imagePath: path)));
  }

  Widget _modeSwitch() {
    Widget tab(String text, bool receipt) => Expanded(
          child: PillButton(
            text: text,
            bg: _receipt == receipt ? AppColors.accent : AppColors.roundBtn,
            fg: _receipt == receipt ? Colors.white : AppColors.text,
            height: 40,
            fontSize: 13,
            onPressed: () => setState(() => _receipt = receipt),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [tab('Код вулика', false), const SizedBox(width: 8), tab('Чек', true)]),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || _manualOpen) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v);
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _done = true;
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          if (!_receipt) Positioned.fill(child: MobileScanner(onDetect: _onDetect)),
          // рамка-приціл
          if (!_receipt)
          Center(
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent, width: 4),
                  borderRadius: BorderRadius.circular(20),
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
                if (widget.receiptRepo != null) _modeSwitch(),
              ]),
            ),
          ),
          if (_receipt)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 150, 24, 24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.receipt_long_outlined, size: 84, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  const Text(
                      'Сфотографуйте чек рівно, при гарному світлі, щоб було видно весь текст. '
                      'Товар, кількість і ціна потраплять у таблицю, яку можна виправити.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
                  const SizedBox(height: 22),
                  PillButton(
                    text: 'Сфотографувати чек',
                    bg: AppColors.accent,
                    height: 48,
                    radius: 16,
                    width: double.infinity,
                    onPressed: () => _receiptPhoto(camera: true),
                  ),
                  const SizedBox(height: 10),
                  PillButton(
                    text: 'Обрати фото з галереї',
                    bg: AppColors.roundBtn,
                    fg: AppColors.text,
                    height: 44,
                    width: double.infinity,
                    onPressed: () => _receiptPhoto(camera: false),
                  ),
                ]),
              ),
            ),
          if (!_receipt)
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Наведіть камеру на QR-код вулика',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 12),
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
