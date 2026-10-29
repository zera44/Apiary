import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart' show QrErrorCorrectLevel;
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/l10n.dart';

/// Одна наліпка: QR-код, під ним назва вулика й номер.
class QrLabel {
  final String code;
  final String name;
  final int? number;
  const QrLabel({required this.code, required this.name, this.number});

  String get numberText => number == null ? '' : '№ ${number.toString().padLeft(4, '0')}';
}

/// Розмір картинки наліпки в пікселях (для друку ~5 см — це ~300 dpi).
const double kLabelW = 600, kLabelH = 740;

/// Малює наліпку в PNG. Текст малює Flutter (системний шрифт із
/// кирилицею), тож у PDF не потрібно вкладати окремий шрифт.
Future<Uint8List> renderLabelPng(QrLabel l) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, kLabelW, kLabelH));
  canvas.drawRect(const Rect.fromLTWH(0, 0, kLabelW, kLabelH), Paint()..color = Colors.white);
  // тонка рамка-лінія відрізу
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(3, 3, kLabelW - 6, kLabelH - 6), const Radius.circular(24)),
    Paint()
      ..color = const Color(0xFFBDBDBD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  const qrSize = 500.0;
  canvas.save();
  canvas.translate((kLabelW - qrSize) / 2, 36);
  QrPainter(
    data: l.code,
    version: QrVersions.auto,
    // M — наліпка лишається читабельною навіть трохи подряпаною
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
  ).paint(canvas, const Size(qrSize, qrSize));
  canvas.restore();

  void text(String s, double y, double size, FontWeight w) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: Colors.black, fontSize: size, fontWeight: w)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: kLabelW - 40);
    tp.paint(canvas, Offset((kLabelW - tp.width) / 2, y));
  }

  text(l.name, 560, 52, FontWeight.bold);
  if (l.numberText.isNotEmpty) text(l.numberText, 632, 46, FontWeight.w500);

  final img = await rec.endRecording().toImage(kLabelW.toInt(), kLabelH.toInt());
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}

/// Наліпка в PDF: ширина 5 см (висота — за пропорцією картинки), проміжок
/// між наліпками й поля аркуша, мм.
const double kPdfLabelWmm = 50, kPdfGapMm = 4, kPdfMarginMm = 10;

/// Висота наліпки в PDF, мм.
double get pdfLabelHmm => kPdfLabelWmm * kLabelH / kLabelW;

/// Скільки наліпок уміщається на аркуші A4: (стовпці, рядки). Рахується з
/// розмірів, а не задається числом — щоб жоден ряд не вийшов за аркуш.
(int, int) labelsGridA4() {
  const pageW = 210 - 2 * kPdfMarginMm, pageH = 297 - 2 * kPdfMarginMm;
  final cols = ((pageW + kPdfGapMm) / (kPdfLabelWmm + kPdfGapMm)).floor();
  final rows = ((pageH + kPdfGapMm) / (pdfLabelHmm + kPdfGapMm)).floor();
  return (cols, rows);
}

/// PDF на A4: наліпки сіткою [labelsGridA4] (3 × 4 = 12 на аркуш).
Future<Uint8List> buildLabelsPdf(List<Uint8List> pngs) async {
  final doc = pw.Document(title: tr.hiveQrCodes);
  final (cols, rows) = labelsGridA4();
  final perPage = cols * rows;
  const mm = PdfPageFormat.mm;
  final w = kPdfLabelWmm * mm, h = pdfLabelHmm * mm, gap = kPdfGapMm * mm;
  for (var i = 0; i < pngs.length; i += perPage) {
    final part = pngs.sublist(i, i + perPage > pngs.length ? pngs.length : i + perPage);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(kPdfMarginMm * mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var r = 0; r * cols < part.length; r++) ...[
            if (r > 0) pw.SizedBox(height: gap),
            pw.Row(children: [
              for (var c = 0; c < cols && r * cols + c < part.length; c++) ...[
                if (c > 0) pw.SizedBox(width: gap),
                pw.SizedBox(
                  width: w,
                  height: h,
                  child: pw.Image(pw.MemoryImage(part[r * cols + c]), fit: pw.BoxFit.contain),
                ),
              ],
            ]),
          ],
        ],
      ),
    ));
  }
  return doc.save();
}

/// Зберегти PDF через системний діалог "Зберегти як…". Повертає текст
/// для користувача.
Future<String> saveLabelsPdf(Uint8List bytes, String fileName) async {
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
      dialogTitle: tr.saveLabels,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (uri == null) return tr.saveCancelled;
    if (uri.scheme == 'file') {
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() == 0) {
        await f.writeAsBytes(bytes, flush: true);
      }
      return tr.savedAt(f.path);
    }
    // Android: адреса — внутрішній код документа (наприклад, 1361), не показуємо
    return tr.saved;
  } catch (_) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, fileName));
      await f.writeAsBytes(bytes, flush: true);
      return tr.savedFallback(f.path);
    } catch (e) {
      return tr.fileSaveFailed('$e');
    }
  }
}
