import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../logic/fin_analytics.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Карта контролю: одна точка - один місяць, точки з'єднані лінією процесу.
/// Суцільна лінія - середнє, пунктир крапками - медіана, заливка між двома
/// пунктирними лініями - межі нормальності. Точка поза межами - червона.
/// Торкнутися точки (чи її місяця) - вибрати; обрані точки мають плашку із сумою.
class FinControlChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final FinControlStats stats;
  final Color color;
  final Set<int> selected;
  final ValueChanged<int> onTap;
  final double height;

  /// Ряд зі знаком (результат): шкала сягає нижче нуля, нульова лінія червона,
  /// частина лінії й точки нижче нуля теж червоні.
  final bool signed;
  const FinControlChart({
    super.key,
    required this.values,
    required this.labels,
    required this.stats,
    required this.color,
    required this.selected,
    required this.onTap,
    this.height = 260,
    this.signed = false,
  });

  /// Круглий верх шкали: 1, 2, 5 × 10ⁿ.
  static double niceMax(double v) {
    if (v <= 0) return 1;
    var p = 1.0;
    while (v > 10 * p) {
      p *= 10;
    }
    while (v < p) {
      p /= 10;
    }
    final r = v / p;
    final f = r <= 1 ? 1 : (r <= 2 ? 2 : (r <= 5 ? 5 : 10));
    return f * p;
  }

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    return LayoutBuilder(builder: (context, box) {
      final painter = _ChartPainter(
          values: values,
          labels: labels,
          stats: stats,
          color: color,
          selected: selected,
          textColor: AppColors.text,
          muted: AppColors.textMuted,
          bg: AppColors.bg,
          alert: finColor('terra'),
          signed: signed);
      return GestureDetector(
        key: const ValueKey('fin-control-chart'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (n == 0) return;
          final i = painter.indexAt(d.localPosition.dx, box.maxWidth);
          if (i >= 0 && i < values.length) onTap(i);
        },
        child: CustomPaint(size: Size(box.maxWidth, height), painter: painter),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final FinControlStats stats;
  final Color color, textColor, muted, bg, alert;
  final Set<int> selected;
  final bool signed;
  _ChartPainter({
    required this.values,
    required this.labels,
    required this.stats,
    required this.color,
    required this.selected,
    required this.textColor,
    required this.muted,
    required this.bg,
    required this.alert,
    this.signed = false,
  });

  static const _left = 40.0, _right = 8.0, _top = 44.0, _bottom = 26.0;

  double _x(int i, double w) {
    final n = labels.length;
    final inner = w - _left - _right;
    return _left + inner * (i + 0.5) / n;
  }

  int indexAt(double dx, double w) {
    final n = labels.length;
    final inner = w - _left - _right;
    return ((dx - _left) / (inner / n)).floor().clamp(0, n - 1);
  }

  void _text(Canvas c, String s, Offset at, TextStyle st, {bool centered = true, bool right = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)
      ..layout();
    final double dx = centered ? -tp.width / 2 : (right ? -tp.width : 0.0);
    tp.paint(c, at + Offset(dx, -tp.height / 2));
  }

  void _dashed(Canvas c, double x1, double x2, double y, Paint p, double dash, double gap) {
    for (var x = x1; x < x2; x += dash + gap) {
      c.drawLine(Offset(x, y), Offset(x + dash > x2 ? x2 : x + dash, y), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final plotH = h - _top - _bottom;
    final maxData = [
      ...values,
      stats.high,
    ].fold(0.0, (a, b) => a > b ? a : b);
    final minData = signed
        ? [...values, stats.low].fold(0.0, (a, b) => a < b ? a : b)
        : 0.0;
    double maxY, minY = 0;
    List<double> ticks;
    if (minData < 0) {
      // шкала в обидва боки від нуля: крок - половина круглого розміру
      final u = FinControlChart.niceMax(
              [maxData * 1.05, -minData * 1.05].reduce((a, b) => a > b ? a : b)) /
          2;
      maxY = maxData > 0 ? (maxData * 1.05 / u).ceil() * u : 0.0;
      minY = -((-minData * 1.05 / u).ceil() * u);
      ticks = [for (var v = minY; v <= maxY + u / 2; v += u) v];
    } else {
      maxY = FinControlChart.niceMax(maxData * 1.05);
      ticks = [for (var t = 0; t <= 4; t++) maxY * t / 4];
    }
    final span = maxY - minY;
    double y(double v) => _top + plotH * (1 - ((v - minY) / span).clamp(0.0, 1.0));
    final axis = TextStyle(color: muted, fontSize: 11);

    // шкала й осі; у ряді зі знаком нульова лінія - суцільна червона
    final grid = Paint()
      ..color = muted.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final zero = Paint()
      ..color = alert
      ..strokeWidth = 1.8;
    for (final v in ticks) {
      final isZero = signed && v.abs() < 1e-9;
      canvas.drawLine(Offset(_left, y(v)), Offset(w - _right, y(v)), isZero ? zero : grid);
      _text(canvas, _short(v), Offset(_left - 6, y(v)), axis, centered: false, right: true);
    }

    // смуга нормальності
    canvas.drawRect(
        Rect.fromLTRB(_left, y(stats.high), w - _right, y(stats.low)),
        Paint()..color = color.withValues(alpha: 0.14));
    final lim = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    _dashed(canvas, _left, w - _right, y(stats.high), lim, 6, 4);
    _dashed(canvas, _left, w - _right, y(stats.low), lim, 6, 4);

    // середнє й медіана
    canvas.drawLine(Offset(_left, y(stats.mean)), Offset(w - _right, y(stats.mean)),
        Paint()
          ..color = textColor
          ..strokeWidth = 2);
    _dashed(canvas, _left, w - _right, y(stats.median),
        Paint()
          ..color = textColor
          ..strokeWidth = 1.5, 2, 3);

    // лінія процесу
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (!signed) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final o = Offset(_x(i, w), y(values[i]));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, line);
    } else {
      // нижче нуля лінія червона: відрізок, що перетинає нуль, ділимо в точці перетину
      void seg(Offset a, Offset b, Color c) => canvas.drawLine(
          a,
          b,
          Paint()
            ..color = c
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
      for (var i = 0; i + 1 < values.length; i++) {
        final v1 = values[i], v2 = values[i + 1];
        final p1 = Offset(_x(i, w), y(v1)), p2 = Offset(_x(i + 1, w), y(v2));
        if (v1 >= 0 && v2 >= 0) {
          seg(p1, p2, color);
        } else if (v1 <= 0 && v2 <= 0) {
          seg(p1, p2, alert);
        } else {
          final xc = p1.dx + (p2.dx - p1.dx) * (v1 / (v1 - v2));
          final pc = Offset(xc, y(0));
          seg(p1, pc, v1 > 0 ? color : alert);
          seg(pc, p2, v2 > 0 ? color : alert);
        }
      }
    }

    // підписи місяців
    final step = labels.length > 12 ? (labels.length / 6).ceil() : 1;
    for (var i = 0; i < labels.length; i++) {
      final on = selected.contains(i);
      if (step > 1 && i % step != 0 && !on) continue;
      _text(
          canvas,
          labels[i],
          Offset(_x(i, w), h - _bottom / 2),
          TextStyle(
              color: on || selected.isEmpty ? muted : muted.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400));
    }

    // точки
    for (var i = 0; i < values.length; i++) {
      final o = Offset(_x(i, w), y(values[i]));
      final out = stats.outside.contains(i);
      final on = selected.contains(i);
      final c = out || (signed && values[i] < 0) ? alert : color;
      if (on) canvas.drawCircle(o, 11, Paint()..color = c.withValues(alpha: 0.3));
      canvas.drawCircle(o, on ? 7 : 5, Paint()..color = bg);
      canvas.drawCircle(o, on ? 5.5 : 3.8, Paint()..color = c);
    }

    // плашки із сумою над обраними точками
    for (final i in selected) {
      if (i >= values.length) continue;
      final o = Offset(_x(i, w), y(values[i]));
      final tp = TextPainter(
          text: TextSpan(
              text: uah(values[i]),
              style: TextStyle(color: bg, fontSize: 12, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      final bw = tp.width + 16, bh = tp.height + 8;
      var left = o.dx - bw / 2;
      left = left.clamp(2.0, w - bw - 2);
      final top = (o.dy - bh - 14).clamp(0.0, h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(left, top, bw, bh), const Radius.circular(8)),
          Paint()..color = textColor);
      tp.paint(canvas, Offset(left + 8, top + 4));
    }
  }

  /// Підпис осі: 1500 -> «1,5т», 800 -> «800».
  static String _short(double v) {
    if (v < 0) return '−${_short(-v)}';
    if (v >= 1000) {
      final k = v / 1000;
      final s = k == k.roundToDouble() ? k.toInt().toString() : k.toStringAsFixed(1).replaceAll('.', ',');
      return '$s${tr.languageCode == 'uk' ? 'т' : 'k'}';
    }
    return v.round().toString();
  }

  @override
  bool shouldRepaint(covariant _ChartPainter o) =>
      o.values != values ||
      o.selected != selected ||
      o.color != color ||
      o.stats != stats ||
      o.signed != signed ||
      o.textColor != textColor;
}
