import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../logic/fz2/fz2.dart';
import '../logic/stock_format.dart';
import '../services/receipt_ocr.dart';
import '../ui/common.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';

/// Кольори класів - як у курсовій (coursework/fuzzy_v2/draw.py); службові не малюються.
const markupColors = <String, Color>{
  'NAME': Color(0xFF1E6EFF),
  'ITEM': Color(0xFF00AA3C),
  'PRICE': Color(0xFFFFAA00),
  'QTY': Color(0xFF00BED2),
  'TOTAL': Color(0xFFE61414),
  'DISC': Color(0xFF9628C8),
  'VAT': Color(0xFFFF3CC8),
};

/// Перегляд розміченого чека: фото з рамками класів, легенда й позиції.
class ReceiptMarkupScreen extends StatelessWidget {
  final MarkedReceipt marked;

  const ReceiptMarkupScreen({super.key, required this.marked});

  @override
  Widget build(BuildContext context) {
    final fz = marked.fz;
    final img = marked.image;
    final hasImg = img != null && File(img).existsSync();
    final boxes = [
      for (final l in fz.labels)
        if (!l.f.virtual && markupColors.containsKey(l.cls)) l
    ];
    return Scaffold(
      body: SafeArea(
        child: ScreenColumn(children: [
          TopBar(title: tr.receiptMarkupTitle, onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), children: [
              Wrap(spacing: 10, runSpacing: 6, children: [
                for (final e in markupColors.entries)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            color: e.value.withValues(alpha: 0.45),
                            border: Border.all(color: e.value, width: 2),
                            borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 5),
                    Text(tr.receiptMarkupClass(e.key), style: TextStyle(color: AppColors.text, fontSize: 12)),
                  ]),
              ]),
              const SizedBox(height: 10),
              if (hasImg)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: _MarkedImage(file: File(img), boxes: boxes, angle: marked.angle),
                  ),
                )
              else
                Text(tr.receiptMarkupNoImage, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 14),
              for (final r in fz.rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(r.name.isEmpty ? '—' : r.name,
                          style: TextStyle(color: AppColors.text, fontSize: 13.5)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        r.qty == 1 ? '' : '${formatAmount(r.qty)} ${r.unit} × ${formatMoney(r.price)}  ',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    Text(r.sum == null ? '?' : formatMoney(r.sum!),
                        style: TextStyle(color: markupColors['ITEM'], fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(),
              Text(
                tr.receiptMarkupSum(uah(fz.rowsSum), fz.total == null ? '—' : uah(fz.total!)),
                style: TextStyle(
                    color: fz.total != null && (fz.total! - fz.rowsSum).abs() >= 0.015 ? AppColors.caution : AppColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MarkedImage extends StatefulWidget {
  final File file;
  final List<Labeled> boxes;
  final double angle;

  const _MarkedImage({required this.file, required this.boxes, required this.angle});

  @override
  State<_MarkedImage> createState() => _MarkedImageState();
}

class _MarkedImageState extends State<_MarkedImage> {
  Size? _size;
  late final FileImage _img = FileImage(widget.file);
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (mounted) setState(() => _size = Size(info.image.width.toDouble(), info.image.height.toDouble()));
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = _img.resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _size;
    if (s == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    return AspectRatio(
      aspectRatio: s.width / s.height,
      child: CustomPaint(
        foregroundPainter: _BoxPainter(widget.boxes, widget.angle, s),
        child: Image(image: _img, fit: BoxFit.fill),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final List<Labeled> boxes;
  final double angle;
  final Size img;

  _BoxPainter(this.boxes, this.angle, this.img);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / img.width;
    final c = math.cos(angle), s = math.sin(angle);
    Offset p(double x, double y) => Offset((x * c - y * s) * k, (x * s + y * c) * k);
    for (final l in boxes) {
      final col = markupColors[l.cls]!;
      final f = l.f;
      final y0 = f.y - f.h / 2, y1 = f.y + f.h / 2;
      final path = Path()
        ..moveTo(p(f.xLeft, y0).dx, p(f.xLeft, y0).dy)
        ..lineTo(p(f.xRight, y0).dx, p(f.xRight, y0).dy)
        ..lineTo(p(f.xRight, y1).dx, p(f.xRight, y1).dy)
        ..lineTo(p(f.xLeft, y1).dx, p(f.xLeft, y1).dy)
        ..close();
      canvas.drawPath(path, Paint()..color = col.withValues(alpha: 0.28));
      canvas.drawPath(
          path,
          Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter o) => o.boxes != boxes || o.angle != angle || o.img != img;
}
