import 'package:flutter/material.dart';

import 'theme.dart';

/// Підказка режиму навчання: пасічник-провідник (малюнок автора,
/// assets/guide) зліва і «хмарка» з текстом справа.
class GuideBubble extends StatelessWidget {
  /// Текст підказки; виділені слова — через [GuideBubble.highlight].
  final List<InlineSpan> text;
  final String image;

  /// Під хмаркою (у проміжку між нею й низом пасічника) — наприклад,
  /// «Пропустити».
  final Widget? below;
  const GuideBubble(
      {super.key, required this.text, this.image = 'assets/guide/beekeeper.png', this.below});

  /// Назва кнопки в тексті підказки: іншим кольором і жирним.
  static TextSpan highlight(String s) => TextSpan(
        text: s,
        style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w800),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Image.asset(image, height: 170, filterQuality: FilterQuality.medium),
        const SizedBox(width: 4),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
              painter: _BubblePainter(fill: AppColors.popupBg, border: AppColors.create),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
                child: Text.rich(
                  TextSpan(children: text),
                  style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.35),
                ),
              ),
            ),
            SizedBox(height: 70, child: Center(child: below)),
          ]),
        ),
      ]),
    );
  }
}

/// Заокруглена хмарка з «хвостиком» ліворуч (до пасічника).
class _BubblePainter extends CustomPainter {
  final Color fill;
  final Color border;
  _BubblePainter({required this.fill, required this.border});

  static const tail = 10.0;

  Path _shape(Size s) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(tail, 0, s.width - tail, s.height), const Radius.circular(16));
    final y = s.height * 0.62;
    final tip = Path()
      ..moveTo(tail + 1, y - 9)
      ..lineTo(0, y + 6)
      ..lineTo(tail + 1, y + 5)
      ..close();
    return Path.combine(PathOperation.union, Path()..addRRect(body), tip);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _shape(size);
    canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(
        p,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.fill != fill || old.border != border;
}
