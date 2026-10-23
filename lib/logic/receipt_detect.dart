/// Пошук чека в кадрі камери: світла видовжена пляма з текстом на темнішому
/// тлі. Працює на зменшеному кадрі (≈120 пікселів завширшки), тож дешевий:
/// його можна виконувати кілька разів на секунду просто на екрані.
///
/// Без зовнішніх бібліотек: поріг Отсу -> найбільша світла пляма -> опукла
/// оболонка -> найменший прямокутник (з нахилом). Прямокутник вважається чеком,
/// якщо він видовжений, займає помітну частину кадру, добре заповнений
/// плямою й усередині є «текст» (темні штрихи на світлому).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Чек у кадрі: чотири кути (ліво-верх, право-верх, право-низ, ліво-низ) у
/// частках кадру (0..1).
class ReceiptQuad {
  final List<Offset> corners;

  /// Частка кадру, яку займає чек (0..1).
  final double area;

  /// Довга сторона / коротка.
  final double aspect;
  const ReceiptQuad(this.corners, this.area, this.aspect);

  Offset get center {
    var x = 0.0, y = 0.0;
    for (final c in corners) {
      x += c.dx;
      y += c.dy;
    }
    return Offset(x / corners.length, y / corners.length);
  }

  /// Чи це приблизно той самий чек, що й [o] (кадр до кадру тремтить).
  bool similarTo(ReceiptQuad o) {
    if ((center - o.center).distance > 0.07) return false;
    final r = area / o.area;
    return r > 0.82 && r < 1.22;
  }
}

/// Знайти чек у кадрі RGBA ([w] x [h]); null - чека не видно.
ReceiptQuad? detectReceipt(Uint8List rgba, int w, int h) {
  final n = w * h;
  if (n < 400 || rgba.length < n * 4) return null;
  final luma = Uint8List(n);
  final hist = List<int>.filled(256, 0);
  for (var i = 0; i < n; i++) {
    final j = i * 4;
    final l = (rgba[j] * 77 + rgba[j + 1] * 150 + rgba[j + 2] * 29) >> 8;
    luma[i] = l;
    hist[l]++;
  }

  final t = _otsu(hist, n);
  if (t == null) return null;

  // світла пляма: пікселі вище порогу
  final mask = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (luma[i] > t) mask[i] = 1;
  }

  final comp = _largest(mask, w, h);
  if (comp == null || comp.length < n * 0.08) return null;

  final pts = [for (final i in comp) Offset((i % w).toDouble(), (i ~/ w).toDouble())];
  final hull = _hull(pts);
  if (hull.length < 3) return null;
  final rect = _minRect(hull);
  if (rect == null) return null;

  final area = rect.w * rect.h;
  final frac = area / n;
  if (frac < 0.10) return null;
  final aspect = math.max(rect.w, rect.h) / math.max(1e-6, math.min(rect.w, rect.h));
  // чек майже на весь кадр (піднесли близько) - форма кадру, не чека
  if (aspect < 1.2 && frac < 0.9) return null;
  // пляма має добре заповнювати свій прямокутник (не «хмара» й не дві плями)
  if (comp.length / area < 0.55) return null;
  if (_polyArea(hull) / area < 0.78) return null;

  // усередині прямокутника є текст: темні штрихи серед світлого
  var inside = 0, dark = 0;
  final c = math.cos(rect.angle), s = math.sin(rect.angle);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x - rect.cx, dy = y - rect.cy;
      final u = dx * c + dy * s, v = -dx * s + dy * c;
      if (u.abs() > rect.w / 2 - 1 || v.abs() > rect.h / 2 - 1) continue;
      inside++;
      if (luma[y * w + x] <= t) dark++;
    }
  }
  if (inside == 0) return null;
  final ink = dark / inside;
  if (ink < 0.02 || ink > 0.45) return null;

  final corners = <Offset>[];
  for (final (su, sv) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
    final u = su * rect.w / 2, v = sv * rect.h / 2;
    corners.add(Offset(
      (rect.cx + u * c - v * s) / w,
      (rect.cy + u * s + v * c) / h,
    ));
  }
  return ReceiptQuad(_clockwiseFromTopLeft(corners), frac, aspect);
}

/// Кути за годинниковою стрілкою, починаючи з лівого верхнього.
List<Offset> _clockwiseFromTopLeft(List<Offset> p) {
  var start = 0;
  var best = double.infinity;
  for (var i = 0; i < p.length; i++) {
    final d = p[i].dx + p[i].dy;
    if (d < best) {
      best = d;
      start = i;
    }
  }
  return [for (var k = 0; k < p.length; k++) p[(start + k) % p.length]];
}

/// Поріг Отсу; null, коли світлого й темного майже немає (однотонний кадр).
int? _otsu(List<int> hist, int total) {
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var wB = 0, sumB = 0.0;
  var best = -1.0;
  var thr = 0;
  double meanB = 0, meanF = 0;
  double bestGap = 0;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      thr = t;
      meanB = mB;
      meanF = mF;
      bestGap = mF - mB;
    }
  }
  if (best < 0 || bestGap < 28 || meanF <= meanB) return null;
  return thr;
}

/// Найбільша зв'язна (4 сусіди) пляма одиниць у масці: індекси пікселів.
List<int>? _largest(Uint8List mask, int w, int h) {
  final seen = Uint8List(mask.length);
  List<int>? best;
  final stack = <int>[];
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || seen[start] == 1) continue;
    final cur = <int>[];
    stack.add(start);
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      cur.add(i);
      final x = i % w, y = i ~/ w;
      if (x > 0 && mask[i - 1] == 1 && seen[i - 1] == 0) {
        seen[i - 1] = 1;
        stack.add(i - 1);
      }
      if (x < w - 1 && mask[i + 1] == 1 && seen[i + 1] == 0) {
        seen[i + 1] = 1;
        stack.add(i + 1);
      }
      if (y > 0 && mask[i - w] == 1 && seen[i - w] == 0) {
        seen[i - w] = 1;
        stack.add(i - w);
      }
      if (y < h - 1 && mask[i + w] == 1 && seen[i + w] == 0) {
        seen[i + w] = 1;
        stack.add(i + w);
      }
    }
    if (best == null || cur.length > best.length) best = cur;
  }
  return best;
}

double _cross(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

/// Опукла оболонка (ланцюжок Ендрю).
List<Offset> _hull(List<Offset> pts) {
  final p = [...pts]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (p.length < 3) return p;
  final lo = <Offset>[];
  for (final q in p) {
    while (lo.length >= 2 && _cross(lo[lo.length - 2], lo.last, q) <= 0) {
      lo.removeLast();
    }
    lo.add(q);
  }
  final up = <Offset>[];
  for (final q in p.reversed) {
    while (up.length >= 2 && _cross(up[up.length - 2], up.last, q) <= 0) {
      up.removeLast();
    }
    up.add(q);
  }
  lo.removeLast();
  up.removeLast();
  return [...lo, ...up];
}

double _polyArea(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a.abs() / 2;
}

class _Rect {
  final double cx, cy, w, h, angle;
  const _Rect(this.cx, this.cy, this.w, this.h, this.angle);
}

/// Найменший за площею прямокутник, описаний навколо оболонки: одна зі
/// сторін збігається з якоюсь стороною оболонки.
_Rect? _minRect(List<Offset> hull) {
  _Rect? best;
  var bestArea = double.infinity;
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i], b = hull[(i + 1) % hull.length];
    final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final c = math.cos(ang), s = math.sin(ang);
    var minU = double.infinity, maxU = -double.infinity;
    var minV = double.infinity, maxV = -double.infinity;
    for (final p in hull) {
      final u = p.dx * c + p.dy * s, v = -p.dx * s + p.dy * c;
      minU = math.min(minU, u);
      maxU = math.max(maxU, u);
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    final w = maxU - minU, h = maxV - minV;
    if (w * h < bestArea) {
      bestArea = w * h;
      final cu = (minU + maxU) / 2, cv = (minV + maxV) / 2;
      best = _Rect(cu * c - cv * s, cu * s + cv * c, w, h, ang);
    }
  }
  return best;
}
