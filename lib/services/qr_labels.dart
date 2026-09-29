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

/// PDF на A4: сітка наліпок 3 × 4 на сторінці, ширина наліпки 6 см.
Future<Uint8List> buildLabelsPdf(List<Uint8List> pngs) async {
  final doc = pw.Document(title: 'QR-коди вуликів');
  const perPage = 12;
  const w = 60 * PdfPageFormat.mm;
  for (var i = 0; i < pngs.length; i += perPage) {
    final part = pngs.sublist(i, i + perPage > pngs.length ? pngs.length : i + perPage);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
      build: (_) => pw.Wrap(
        spacing: 4 * PdfPageFormat.mm,
        runSpacing: 4 * PdfPageFormat.mm,
        children: [
          for (final png in part)
            pw.SizedBox(width: w, child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
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
      dialogTitle: 'Зберегти наліпки',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (uri == null) return 'Збереження скасовано.';
    if (uri.scheme == 'file') {
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() == 0) {
        await f.writeAsBytes(bytes, flush: true);
      }
      return 'Збережено:\n${f.path}';
    }
    final name = uri.pathSegments.isNotEmpty ? Uri.decodeComponent(uri.pathSegments.last) : fileName;
    return 'Збережено:\n${p.basename(name)}';
  } catch (_) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, fileName));
      await f.writeAsBytes(bytes, flush: true);
      return 'Не вдалось відкрити діалог збереження — файл збережено тут:\n${f.path}';
    } catch (e) {
      return 'Не вдалось зберегти файл:\n$e';
    }
  }
}
