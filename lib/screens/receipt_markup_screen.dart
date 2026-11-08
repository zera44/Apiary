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
    final shown = [
      for (final l in fz.labels)
        if (!l.f.virtual && l.cls != 'OTHER') l
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
                    maxScale: 8,
                    child: _MarkedImage(file: File(img), items: shown, angle: marked.angle),
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

/// Ліворуч - чек (фото, яке читалося) з рамками класів, праворуч - прочитаний текст на тих самих
/// місцях, підсвічений за класом (як у курсовій, draw.py). Обидві половини масштабуються разом.
class _MarkedImage extends StatefulWidget {
  final File file;
  final List<Labeled> items;
  final double angle;

  const _MarkedImage({required this.file, required this.items, required this.angle});

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
    final ratio = s.width / s.height;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: AspectRatio(
          aspectRatio: ratio,
          child: CustomPaint(
            foregroundPainter: _BoxPainter(widget.items, widget.angle, s, text: false),
            child: Image(image: _img, fit: BoxFit.fill),
          ),
        ),
      ),
      const SizedBox(width: 3),
      Expanded(
        child: AspectRatio(
          aspectRatio: ratio,
          child: CustomPaint(
            painter: _BoxPainter(widget.items, widget.angle, s, text: true),
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    ]);
  }
}

class _BoxPainter extends CustomPainter {
  final List<Labeled> items;
  final double angle;
  final Size img;

  /// true - білий аркуш з текстом на місцях фрагментів; false - лише рамки поверх фото.
  final bool text;

  _BoxPainter(this.items, this.angle, this.img, {required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    if (text) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final k = size.width / img.width;
    final c = math.cos(angle), s = math.sin(angle);
    Offset p(double x, double y) => Offset((x * c - y * s) * k, (x * s + y * c) * k);
    for (final l in items) {
      final col = markupColors[l.cls];
      final f = l.f;
      final y0 = f.y - f.h / 2, y1 = f.y + f.h / 2;
      final a = p(f.xLeft, y0), b = p(f.xRight, y0), d = p(f.xRight, y1), e = p(f.xLeft, y1);
      if (col != null) {
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(d.dx, d.dy)
          ..lineTo(e.dx, e.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = col.withValues(alpha: text ? 0.38 : 0.28));
        canvas.drawPath(
            path,
            Paint()
              ..color = col
              ..style = PaintingStyle.stroke
              ..strokeWidth = text ? 1.2 : 1.6);
      }
      if (!text) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: f.text.trim(),
            style: TextStyle(color: const Color(0xFF222222), fontSize: math.max(3.0, f.h * k * 0.72))),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = (f.xRight - f.xLeft) * k;
      final sx = tp.width <= 0 ? 1.0 : (w / tp.width).clamp(0.3, 2.0);
      canvas.save();
      canvas.translate(a.dx, (a.dy + e.dy) / 2 - tp.height / 2);
      canvas.scale(sx, 1);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BoxPainter o) => o.items != items || o.angle != angle || o.img != img || o.text != text;
}
