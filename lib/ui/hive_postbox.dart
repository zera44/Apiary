import 'package:flutter/material.dart';

/// Вулик-поштомат (головний екран): корпус вулика з дашком, спереду —
/// комірки-дверцята, як у поштоматі. Коли є важливі повідомлення
/// (прострочені огляди, час докупити) — одна комірка відчинена, з неї
/// визирає лист, а на дашку червоний значок з кількістю.
class HivePostbox extends StatelessWidget {
  final int count;
  final double height;
  final VoidCallback? onTap;
  const HivePostbox({super.key, this.count = 0, this.height = 96, this.onTap});

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      height: height,
      width: height * 0.72,
      child: CustomPaint(painter: _PostboxPainter(count)),
    );
    return Semantics(
      button: onTap != null,
      label: count > 0 ? 'Вулик-поштомат: повідомлень $count' : 'Вулик-поштомат',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box),
    );
  }
}

class _PostboxPainter extends CustomPainter {
  final int count;
  _PostboxPainter(this.count);

  // кольори з палітри застосунку (медовий, коричневий контур)
  static const outline = Color(0xFF3A2410);
  static const honey = Color(0xFFED9D2F);
  static const honeyLight = Color(0xFFF6C26B);
  static const honeyDark = Color(0xFFC97A1A);
  static const roof = Color(0xFF8A5A2B);
  static const paper = Color(0xFFFBF3E2);
  static const badge = Color(0xFFCD4C28);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final stroke = w * 0.045;
    final line = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;
    Paint fill(Color c) => Paint()..color = c;

    // ніжки-підставка
    final legs = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.90, w * 0.72, h * 0.07), Radius.circular(w * 0.03));
    canvas.drawRRect(legs, fill(roof));
    canvas.drawRRect(legs, line);

    // корпус
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.24, w * 0.84, h * 0.67), Radius.circular(w * 0.06));
    canvas.drawRRect(body, fill(honey));

    // комірки поштомату: 2 × 3
    const cols = 2, rows = 3;
    final gx = w * 0.15, gy = h * 0.29, gw = w * 0.70, gh = h * 0.50;
    final cw = gw / cols, ch = gh / rows, gap = w * 0.03;
    final open = count > 0 ? (row: 1, col: 1) : null; // відчинена комірка з листом
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(gx + c * cw + gap / 2, gy + r * ch + gap / 2, cw - gap, ch - gap);
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.025));
        final isOpen = open != null && open.row == r && open.col == c;
        canvas.drawRRect(rr, fill(isOpen ? outline : honeyLight));
        canvas.drawRRect(rr, line..strokeWidth = stroke * 0.6);
        if (!isOpen) {
          // ручка дверцят
          canvas.drawCircle(Offset(rect.right - rect.width * 0.22, rect.center.dy), w * 0.022,
              fill(honeyDark));
        } else {
          // лист визирає з комірки
          final env = Rect.fromLTWH(rect.left + rect.width * 0.12, rect.top - rect.height * 0.35,
              rect.width * 0.76, rect.height * 0.9);
          final er = RRect.fromRectAndRadius(env, Radius.circular(w * 0.015));
          canvas.drawRRect(er, fill(paper));
          canvas.drawRRect(er, line..strokeWidth = stroke * 0.5);
          final flap = Path()
            ..moveTo(env.left, env.top)
            ..lineTo(env.center.dx, env.top + env.height * 0.45)
            ..lineTo(env.right, env.top);
          canvas.drawPath(flap, line..strokeWidth = stroke * 0.5);
        }
      }
    }
    line.strokeWidth = stroke;

    // льоток унизу
    final entrance = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.30, h * 0.81, w * 0.40, h * 0.05), Radius.circular(w * 0.03));
    canvas.drawRRect(entrance, fill(outline));
    canvas.drawRRect(body, line);

    // дашок
    final roofPath = Path()
      ..moveTo(w * 0.02, h * 0.25)
      ..lineTo(w * 0.50, h * 0.06)
      ..lineTo(w * 0.98, h * 0.25)
      ..close();
    canvas.drawPath(roofPath, fill(roof));
    canvas.drawPath(roofPath, line);

    // значок з кількістю повідомлень
    if (count > 0) {
      final c = Offset(w * 0.80, h * 0.12);
      final r = w * 0.15;
      canvas.drawCircle(c, r, fill(badge));
      canvas.drawCircle(c, r, line..strokeWidth = stroke * 0.7);
      final tp = TextPainter(
        text: TextSpan(
          text: count > 9 ? '9+' : '$count',
          style: TextStyle(color: Colors.white, fontSize: r * 1.15, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PostboxPainter old) => old.count != count;
}
