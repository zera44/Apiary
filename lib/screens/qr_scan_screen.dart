import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/common.dart';
import '../ui/theme.dart';

/// Чи є на цьому пристрої камера-сканер (телефон/планшет).
bool get qrCameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Отримати текст QR-коду: на телефоні — камерою, на комп'ютері (де
/// сканера немає) — ручним вводом. null — скасовано.
Future<String?> scanQrCode(BuildContext context,
    {String title = 'Сканувати QR-код', String? skipLabel}) async {
  if (!qrCameraAvailable) return _manualEntry(context);
  return Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => QrScanScreen(title: title, skipLabel: skipLabel),
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
  const QrScanScreen({super.key, this.title = 'Сканувати QR-код', this.skipLabel});
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
          Positioned.fill(child: MobileScanner(onDetect: _onDetect)),
          // рамка-приціл
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
              child: TopBar(
                  title: widget.title,
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
