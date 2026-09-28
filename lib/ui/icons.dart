import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Іконки застосунку, намальовані лініями (порт widgets_common.py) — щоб
/// не залежати від шрифтів і мати однаковий вигляд усюди.
///
/// Геометрію перенесено один до одного зі старої версії, де вісь y
/// спрямована ВГОРУ; клас [_Pen] сам перевертає її для Flutter.

/// Множник товщини ліній відносно старих значень (Kivy малював лінію
/// товщиною приблизно 2×width).
const double _kStroke = 1.8;

class _Pen {
  final Canvas canvas;
  final double cx, cy;
  final Color color;
  _Pen(this.canvas, this.cx, this.cy, this.color);

  /// Точка у "старих" координатах (y вгору) -> Offset у Flutter.
  Offset o(double x, double y) => Offset(x, 2 * cy - y);

  Paint _stroke(double w, {bool round = true}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * _kStroke
    ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
    ..strokeJoin = round ? StrokeJoin.round : StrokeJoin.miter
    ..isAntiAlias = true;

  Paint get _fill => Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  void line(List<double> pts, double width, {bool close = false, bool round = true}) {
    if (pts.length < 4) return;
    final path = Path()..moveTo(o(pts[0], pts[1]).dx, o(pts[0], pts[1]).dy);
    for (var i = 2; i + 1 < pts.length; i += 2) {
      final p = o(pts[i], pts[i + 1]);
      path.lineTo(p.dx, p.dy);
    }
    if (close) path.close();
    canvas.drawPath(path, _stroke(width, round: round));
  }

  void triangle(List<double> pts) {
    final path = Path()
      ..moveTo(o(pts[0], pts[1]).dx, o(pts[0], pts[1]).dy)
      ..lineTo(o(pts[2], pts[3]).dx, o(pts[2], pts[3]).dy)
      ..lineTo(o(pts[4], pts[5]).dx, o(pts[4], pts[5]).dy)
      ..close();
    canvas.drawPath(path, _fill);
  }

  void circle(double x, double y, double r, double width) {
    canvas.drawCircle(o(x, y), r, _stroke(width));
  }

  void disc(double x, double y, double r) {
    canvas.drawCircle(o(x, y), r, _fill);
  }

  /// Заокруглений прямокутник-контур; (x, y) — лівий НИЖНІЙ кут.
  void roundRect(double x, double y, double w, double h, double r, double width) {
    final tl = o(x, y + h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(tl.dx, tl.dy, w, h), Radius.circular(r)),
      _stroke(width),
    );
  }
}

typedef _Drawer = void Function(_Pen p, double w, double h);

List<double> _hexagonPoints(double cx, double cy, double r) {
  final pts = <double>[];
  for (var i = 0; i < 6; i++) {
    final a = math.pi / 3 * i - math.pi / 2;
    pts..add(cx + r * math.cos(a))..add(cy + r * math.sin(a));
  }
  return pts;
}

void _hexagon(_Pen p, double w, double h) {
  final r = math.min(w, h) / 2 * 0.5;
  p.line(_hexagonPoints(p.cx, p.cy, r), 1.6, close: true);
}

void _menu(_Pen p, double w, double h) {
  final hw = w * 0.22, gap = h * 0.13;
  for (final dy in [-gap, 0.0, gap]) {
    p.line([p.cx - hw, p.cy + dy, p.cx + hw, p.cy + dy], 2.2);
  }
}

void _mountain(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final bw = w * 0.55, bh = h * 0.5;
  final bx = cx - bw / 2, by = cy - bh / 2;
  final baseY = by + bh * 0.15;
  p.line([
    bx, baseY,
    bx + bw * 0.35, by + bh * 0.85,
    bx + bw * 0.55, baseY + bh * 0.25,
    bx + bw * 0.7, by + bh * 0.75,
    bx + bw, baseY,
  ], 1.5);
  p.line([bx, baseY, bx + bw, baseY], 1.5);
}

void _rotate(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final r = math.min(w, h) * 0.30;
  const lw = 2.6;
  void arc(double startDeg, double spanDeg) {
    final pts = <double>[];
    const steps = 24;
    for (var i = 0; i < steps; i++) {
      final ang = (startDeg + i * (spanDeg / (steps - 1))) * math.pi / 180;
      pts..add(cx + r * math.cos(ang))..add(cy + r * math.sin(ang));
    }
    p.line(pts, lw);
    final tipX = pts[pts.length - 2], tipY = pts[pts.length - 1];
    final angEnd = (startDeg + spanDeg) * math.pi / 180;
    final tangent = angEnd + math.pi / 2;
    final ah = r * 0.52, aw = ah * 0.62;
    final baseX = tipX - ah * math.cos(tangent);
    final baseY = tipY - ah * math.sin(tangent);
    final perp = tangent + math.pi / 2;
    p.triangle([
      tipX, tipY,
      baseX + aw * math.cos(perp), baseY + aw * math.sin(perp),
      baseX - aw * math.cos(perp), baseY - aw * math.sin(perp),
    ]);
  }

  arc(-15, 195);
  arc(165, 195);
}

void _trash(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.6;
  final bw = w * 0.42, bh = h * 0.44;
  final bx = cx - bw / 2, by = cy - bh / 2 - h * 0.05;
  p.line([bx - bw * 0.12, by + bh, bx + bw * 1.12, by + bh], lw);
  p.line([
    cx - bw * 0.22, by + bh, cx - bw * 0.22, by + bh + h * 0.08,
    cx + bw * 0.22, by + bh + h * 0.08, cx + bw * 0.22, by + bh,
  ], lw);
  p.line([
    bx + bw * 0.08, by + bh,
    bx + bw * 0.16, by,
    bx + bw * 0.84, by,
    bx + bw * 0.92, by + bh,
  ], lw);
  p.line([cx - bw * 0.15, by + bh * 0.15, cx - bw * 0.15, by + bh * 0.8], lw);
  p.line([cx + bw * 0.15, by + bh * 0.15, cx + bw * 0.15, by + bh * 0.8], lw);
}

void _backArrow(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final s = math.min(w, h);
  final tipX = cx - s * 0.32, tipY = cy - s * 0.02;
  final backX = cx - s * 0.08;
  final aw = s * 0.13;
  p.triangle([tipX, tipY, backX, tipY + aw, backX, tipY - aw]);
  final p0x = backX, p0y = tipY;
  final ccx = backX + s * 0.30, ccy = tipY + s * 0.30;
  final p2x = cx + s * 0.30, p2y = tipY - s * 0.20;
  final pts = <double>[];
  const steps = 20;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    pts
      ..add((1 - t) * (1 - t) * p0x + 2 * (1 - t) * t * ccx + t * t * p2x)
      ..add((1 - t) * (1 - t) * p0y + 2 * (1 - t) * t * ccy + t * t * p2y);
  }
  p.line(pts, s * 0.10 / _kStroke * 1.2);
}

void _pencil(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.6;
  final length = math.min(w, h) * 0.5;
  const ang = math.pi / 4;
  final dx = math.cos(ang) * length / 2, dy = math.sin(ang) * length / 2;
  final x0 = cx - dx, y0 = cy - dy, x1 = cx + dx, y1 = cy + dy;
  final tipCut = length * 0.16;
  final tx = x0 + (x1 - x0) * (tipCut / length);
  final ty = y0 + (y1 - y0) * (tipCut / length);
  const perp = ang + math.pi / 2;
  final pw = math.min(w, h) * 0.09;
  final px = math.cos(perp) * pw, py = math.sin(perp) * pw;
  p.line([tx + px, ty + py, x1 + px, y1 + py, x1 - px, y1 - py, tx - px, ty - py], lw,
      close: true);
  p.line([tx + px, ty + py, x0, y0, tx - px, ty - py], lw);
}

void _beehive(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.3;
  final bw = w * 0.66, bh = h * 0.62;
  final bx = cx - bw / 2, by = cy - bh / 2;
  final r = math.min(bw, bh) * 0.16;
  p.roundRect(bx, by, bw, bh, r, lw);
  final ww = bw * 0.5, wh = bh * 0.34;
  final wx = cx - ww / 2, wy = by + bh * 0.5;
  p.line([wx, wy, wx, wy + wh, wx + ww, wy + wh, wx + ww, wy, wx, wy], lw * 0.85);
  final hr = math.min(ww, wh) * 0.36;
  p.line(_hexagonPoints(cx, wy + wh / 2, hr), lw * 0.75, close: true);
  final beeX = bx + bw * 0.76, beeY = by + bh * 0.20;
  final br = w * 0.045;
  p.circle(beeX, beeY, br, lw * 0.85);
  p.line([beeX - br * 1.7, beeY + br * 1.3, beeX - br * 0.25, beeY + br * 0.25], lw * 0.85);
  p.line([beeX + br * 0.25, beeY + br * 0.25, beeX + br * 1.7, beeY + br * 1.3], lw * 0.85);
  p.line([bx + bw * 0.26, by + bh * 0.16, bx + bw * 0.56, by + bh * 0.16], lw * 0.85);
}

void _check(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  p.line([
    cx - w * 0.24, cy + h * 0.02,
    cx - w * 0.06, cy - h * 0.18,
    cx + w * 0.26, cy + h * 0.22,
  ], 1.8);
}

void _close(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final d = math.min(w, h) * 0.2;
  p.line([cx - d, cy - d, cx + d, cy + d], 2);
  p.line([cx - d, cy + d, cx + d, cy - d], 2);
}

void _plusCircle(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.6;
  final r = math.min(w, h) * 0.42;
  p.circle(cx, cy, r, lw);
  final arm = r * 0.55;
  p.line([cx - arm, cy, cx + arm, cy], lw);
  p.line([cx, cy - arm, cx, cy + arm], lw);
}

void _eye(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.5;
  final ew = w * 0.64, eh = h * 0.36;
  final top = <double>[], bot = <double>[];
  const steps = 16;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = cx - ew / 2 + t * ew;
    final yoff = eh / 2 * math.sin(t * math.pi);
    top..add(x)..add(cy + yoff);
    bot..add(x)..add(cy - yoff);
  }
  p.line(top, lw);
  p.line(bot, lw);
  p.disc(cx, cy, math.min(ew, eh) * 0.24);
}

void _river(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  for (var row = 0; row < 2; row++) {
    final y = cy - h * 0.12 + row * h * 0.24;
    final pts = <double>[];
    for (var i = 0; i < 13; i++) {
      final t = i / 12;
      pts
        ..add(cx - w * 0.4 + t * w * 0.8)
        ..add(y + math.sin(t * math.pi * 2 + row * 1.4) * h * 0.07);
    }
    p.line(pts, 1.5);
  }
}

void _lake(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final rw = w * 0.42, rh = h * 0.30;
  final pts = <double>[];
  for (var i = 0; i < 25; i++) {
    final ang = i * 2 * math.pi / 24;
    final wob = 1 + 0.12 * math.sin(ang * 3);
    pts..add(cx + rw * wob * math.cos(ang))..add(cy + rh * wob * math.sin(ang));
  }
  p.line(pts, 1.5, close: true);
}

void _trees(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.4;
  void tree(double ox, double scale) {
    final tx = cx + ox;
    final tw = w * 0.30 * scale, th = h * 0.42 * scale;
    final topY = cy + h * 0.24 * scale;
    final baseY = topY - th;
    p.line([tx - tw / 2, baseY, tx, topY, tx + tw / 2, baseY, tx - tw / 2, baseY], lw);
    p.line([tx, baseY, tx, baseY - h * 0.14 * scale], lw);
  }

  tree(-w * 0.18, 0.85);
  tree(w * 0.20, 1.0);
}

void _houses(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.4;
  void house(double ox, double scale) {
    final hx = cx + ox;
    final bw = w * 0.32 * scale, bh = h * 0.26 * scale;
    final bx = hx - bw / 2, by = cy - h * 0.14 * scale;
    p.line([bx, by, bx, by + bh, bx + bw, by + bh, bx + bw, by], lw);
    p.line([bx - bw * 0.12, by + bh, hx, by + bh + bh * 0.7, bx + bw * 1.12, by + bh], lw);
  }

  house(-w * 0.16, 0.85);
  house(w * 0.18, 1.0);
}

void _fence(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.4;
  final fw = w * 0.7, fh = h * 0.46;
  final fx = cx - fw / 2, fy = cy - fh / 2;
  const n = 4;
  for (var i = 0; i < n; i++) {
    final x = fx + i * fw / (n - 1);
    p.line([x, fy, x, fy + fh], lw);
  }
  p.line([fx, fy + fh * 0.64, fx + fw, fy + fh * 0.64], lw);
  p.line([fx, fy + fh * 0.20, fx + fw, fy + fh * 0.20], lw);
}

void _road(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.5;
  final rw = w * 0.56, rh = h * 0.62;
  p.line([cx - rw / 2, cy - rh / 2, cx - rw * 0.14, cy + rh / 2], lw);
  p.line([cx + rw / 2, cy - rh / 2, cx + rw * 0.14, cy + rh / 2], lw);
  for (var i = 0; i < 3; i++) {
    final y0 = cy - rh / 2 + rh * (i + 0.2) / 3;
    p.line([cx, y0, cx, y0 + rh * 0.16], lw, round: false);
  }
}

void _arrowLeft(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final s = math.min(w, h) * 0.5;
  p.triangle([cx - s * 0.5, cy, cx + s * 0.34, cy + s * 0.46, cx + s * 0.34, cy - s * 0.46]);
}

void _arrowRight(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  final s = math.min(w, h) * 0.5;
  p.triangle([cx + s * 0.5, cy, cx - s * 0.34, cy + s * 0.46, cx - s * 0.34, cy - s * 0.46]);
}

void _history(_Pen p, double w, double h) {
  final cx = p.cx, cy = p.cy;
  const lw = 1.5;
  final r = math.min(w, h) * 0.36;
  p.circle(cx, cy, r, lw);
  p.line([cx, cy, cx - r * 0.05, cy + r * 0.5], lw);
  p.line([cx, cy, cx + r * 0.55, cy + r * 0.2], lw);
  const ang0 = 200 * math.pi / 180, ang1 = 150 * math.pi / 180;
  final ax0 = cx + r * 1.3 * math.cos(ang0), ay0 = cy + r * 1.3 * math.sin(ang0);
  final ax1 = cx + r * 1.3 * math.cos(ang1), ay1 = cy + r * 1.3 * math.sin(ang1);
  p.line([ax0, ay0, ax1, ay1], lw);
  p.triangle([ax0, ay0, ax0 + r * 0.28, ay0 + r * 0.16, ax0 + r * 0.02, ay0 - r * 0.26]);
}

const Map<String, _Drawer> _drawers = {
  'hexagon': _hexagon,
  'menu': _menu,
  'beehive': _beehive,
  'mountain': _mountain,
  'rotate': _rotate,
  'trash': _trash,
  'back_arrow': _backArrow,
  'pencil': _pencil,
  'eye': _eye,
  'river': _river,
  'lake': _lake,
  'trees': _trees,
  'houses': _houses,
  'fence': _fence,
  'road': _road,
  'plus_circle': _plusCircle,
  'check': _check,
  'close': _close,
  'arrow_left': _arrowLeft,
  'arrow_right': _arrowRight,
  'history': _history,
};

/// Намалювати іконку [name] з центром у [center] у прямокутнику w×h.
void paintAppIcon(Canvas canvas, String name, Offset center, double w, double h, Color color) {
  final d = _drawers[name];
  if (d == null) return;
  d(_Pen(canvas, center.dx, center.dy, color), w, h);
}

bool hasAppIcon(String name) => _drawers.containsKey(name);

/// Варіанти перешкоди (порядок і назви — як у старій версії).
const obstacleVariants = <(String, String)>[
  ('mountain', 'Інше'),
  ('river', 'Річка'),
  ('lake', 'Озеро'),
  ('trees', 'Дерева'),
  ('houses', 'Домівки'),
  ('fence', 'Забор'),
  ('road', 'Дорога'),
];

String obstacleVariantLabel(String? key) {
  for (final (k, l) in obstacleVariants) {
    if (k == (key ?? 'mountain')) return l;
  }
  return '';
}

/// Іконки, які можна обрати для будь-якого об'єкта.
const objectIconChoices = <(String, String)>[
  ('beehive', 'Вулик'),
  ('hexagon', 'Стільник'),
  ('mountain', 'Гора'),
  ('river', 'Річка'),
  ('lake', 'Озеро'),
  ('trees', 'Дерева'),
  ('houses', 'Домівки'),
  ('fence', 'Забор'),
  ('road', 'Дорога'),
];

/// Кольори об'єкта (без службових кольорів карти).
const objectColorChoices = <(String, String)>[
  ('#ED9D2F', 'Медовий оранжевий'),
  ('#F2B705', 'Бурштиновий жовтий'),
  ('#CD6133', 'Теракотовий'),
  ('#D64550', 'Малиновий червоний'),
  ('#E0729C', 'Рожевий'),
  ('#9B4F96', 'Пурпуровий'),
  ('#C9A227', 'Гірчичний'),
  ('#FF7A59', 'Кораловий'),
  ('#8C3B3B', 'Бордовий'),
  ('#F2A65A', 'Персиковий'),
];

/// Варіанти "Мітки матки" (тип даних "Колір"); null — без кольору.
const queenTagChoices = <(String, Color?)>[
  ('Без кольору', null),
  ('Білий', Color(0xFFF2F2F2)),
  ('Жовтий', Color(0xFFF2D926)),
  ('Червоний', Color(0xFFD93333)),
  ('Зелений', Color(0xFF40994D)),
  ('Синій', Color(0xFF3373D9)),
];

/// Віджет-іконка.
class AppIcon extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const AppIcon(this.name, {super.key, this.color = Colors.white, this.size = 46});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _AppIconPainter(name, color)),
      );
}

class _AppIconPainter extends CustomPainter {
  final String name;
  final Color color;
  _AppIconPainter(this.name, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    paintAppIcon(canvas, name, size.center(Offset.zero), size.width, size.height, color);
  }

  @override
  bool shouldRepaint(_AppIconPainter old) => old.name != name || old.color != color;
}
