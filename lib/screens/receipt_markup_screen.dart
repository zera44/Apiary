import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

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
    // усі прочитані фрагменти: праворуч видно весь текст, рамки - лише в тих, що мають клас
    final shown = [
      for (final l in fz.labels)
        if (!l.f.virtual && l.f.text.trim().isNotEmpty) l
    ];
    return Scaffold(
      body: SafeArea(
        child: ScreenColumn(children: [
          TopBar(title: tr.receiptMarkupTitle, onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 16), children: [
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
                  child: GestureDetector(
                    key: const Key('receipt-fullscreen'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => _FullScreenReceipt(
                            child: _MarkedImage(file: File(img), items: shown, angle: marked.angle)))),
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

/// Фото чека на весь екран: стрілка «назад» зліва вгорі, масштабування щипком.
class _FullScreenReceipt extends StatelessWidget {
  final Widget child;
  const _FullScreenReceipt({required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: Center(child: InteractiveViewer(maxScale: 8, child: child)),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                key: const Key('receipt-fullscreen-back'),
                tooltip: tr.back,
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black54, minimumSize: const Size(48, 48)),
                icon: const Icon(TablerIcons.arrow_left, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
        ),
      );
}

/// Ліворуч - чек (фото, яке читалося) з рамками класів, праворуч - увесь прочитаний текст на тих самих
/// місцях, підсвічений за класом (як у курсовій, draw.py). Обидві половини обрізані до чека
/// й масштабуються разом.
class _MarkedImage extends StatefulWidget {
  final File file;
  final List<Labeled> items;
  final double angle;

  const _MarkedImage({required this.file, required this.items, required this.angle});

  @override
  State<_MarkedImage> createState() => _MarkedImageState();
}

class _MarkedImageState extends State<_MarkedImage> {
  ui.Image? _image;
  late final FileImage _img = FileImage(widget.file);
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    final old = _image;
    setState(() => _image = info.image.clone());
    old?.dispose();
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
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final im = _image;
    if (im == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    final full = Size(im.width.toDouble(), im.height.toDouble());
    final crop = markupCropRect(widget.items, widget.angle, full);
    final ratio = crop.width / crop.height;
    Widget half(bool text) => Expanded(
          child: AspectRatio(
            aspectRatio: ratio,
            child: CustomPaint(painter: _BoxPainter(widget.items, widget.angle, im, crop, text: text)),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [half(false), const SizedBox(width: 3), half(true)]);
  }
}

/// Прямокутник чека на зображенні (px): охоплює всі прочитані фрагменти з невеликим полем.
/// Немає фрагментів - усе зображення.
Rect markupCropRect(List<Labeled> items, double angle, Size img) {
  final c = math.cos(angle), s = math.sin(angle);
  double? x0, y0, x1, y1;
  for (final l in items) {
    final f = l.f;
    for (final (x, y) in [(f.xLeft, f.y - f.h / 2), (f.xRight, f.y - f.h / 2), (f.xRight, f.y + f.h / 2), (f.xLeft, f.y + f.h / 2)]) {
      final px = x * c - y * s, py = x * s + y * c;
      x0 = x0 == null ? px : math.min(x0, px);
      x1 = x1 == null ? px : math.max(x1, px);
      y0 = y0 == null ? py : math.min(y0, py);
      y1 = y1 == null ? py : math.max(y1, py);
    }
  }
  final full = Offset.zero & img;
  if (x0 == null || x1 == null || y0 == null || y1 == null || x1 - x0 < 10 || y1 - y0 < 10) return full;
  final pad = math.max(12.0, 0.03 * math.max(x1 - x0, y1 - y0));
  final r = Rect.fromLTRB(x0 - pad, y0 - pad, x1 + pad, y1 + pad).intersect(full);
  return r.width < 10 || r.height < 10 ? full : r;
}

class _BoxPainter extends CustomPainter {
  final List<Labeled> items;
  final double angle;
  final ui.Image img;

  /// Ділянка зображення (px), що показується: чек без тла.
  final Rect crop;

  /// true - білий аркуш з текстом на місцях фрагментів; false - фото з рамками поверх.
  final bool text;

  _BoxPainter(this.items, this.angle, this.img, this.crop, {required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    if (text) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    } else {
      canvas.drawImageRect(img, crop, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    }
    final k = size.width / crop.width;
    final c = math.cos(angle), s = math.sin(angle);
    Offset p(double x, double y) => Offset((x * c - y * s - crop.left) * k, (x * s + y * c - crop.top) * k);
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
  bool shouldRepaint(_BoxPainter o) => o.items != items || o.angle != angle || o.img != img || o.crop != crop || o.text != text;
}
