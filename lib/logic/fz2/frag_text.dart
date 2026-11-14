/// Текст чека зі вже прочитаних фрагментів (без повторного розпізнавання фото).
///
/// Розмітка ([markReceipt]) і розбір тексту ([parseReceipt]) беруть той самий чек з двох боків. Коли розмітка
/// не зійшлась із сумою чека, розбір тексту може врятувати результат, а текст для нього збирається з
/// фрагментів, які розмітка вже має: координати (x, y - центр у кадрі, де рядки горизонтальні), ширина й висота.
/// Три способи збирання рядків: [fragLines] зливає в один рядок усе, що перекривається по висоті, а
/// [fragLinesAnchored] і [fragLinesDeskewed] розділяють сусідні рядки на фото під кутом чи з вигнутим папером.
library;

import 'dart:math' as math;

import 'fz2.dart';

/// Рядки тексту зверху вниз: фрагменти, що перекриваються по висоті, - один рядок (назва й ціна).
List<String> fragLines(List<Frag> frags) {
  final fr = _sorted(frags);
  final lines = <List<Frag>>[];
  double top = 0, bot = 0;
  for (final f in fr) {
    final t = f.y - f.h / 2, b = f.y + f.h / 2;
    if (lines.isNotEmpty) {
      final ov = (bot < b ? bot : b) - (top > t ? top : t);
      final hh = (bot - top) < (b - t) ? (bot - top) : (b - t);
      if (ov >= 0.5 * hh) {
        lines.last.add(f);
        if (t < top) top = t;
        if (b > bot) bot = b;
        continue;
      }
    }
    lines.add([f]);
    top = t;
    bot = b;
  }
  return _render(lines);
}

/// Спершу найширші фрагменти (назви) задають рядки, коротші (ціни) пристають до рядка, найближчого по висоті
/// до їхнього найближчого по горизонталі сусіда; фрагменти один над одним в один рядок не потрапляють.
/// Далі з рядків береться місцевий нахил (права рамка відносно лівої, медіана по 5 сусідніх рядках), фрагменти
/// зсуваються вздовж нього до опорної вертикалі, і рядки збираються ще раз.
List<String> fragLinesAnchored(List<Frag> frags) {
  final fr = _sorted(frags);
  final n = fr.length;
  if (n == 0) return [];
  final y0 = [for (final f in fr) f.y];
  var lines = _anchored(fr, y0);
  final slopes = <(double, double)>[]; // висота, нахил
  for (final l in lines) {
    var lo = l.first, hi = l.first;
    for (final j in l) {
      if (fr[j].x < fr[lo].x) lo = j;
      if (fr[j].x > fr[hi].x) hi = j;
    }
    if (lo == hi || fr[hi].x - fr[lo].x < 2 * (fr[lo].w + fr[hi].w) / 2 + 1) continue;
    slopes.add(((fr[lo].y + fr[hi].y) / 2, (fr[hi].y - fr[lo].y) / (fr[hi].x - fr[lo].x)));
  }
  if (slopes.length >= 4) {
    final xs = [for (final f in fr) f.x]..sort();
    final xref = xs[n ~/ 2];
    final yy = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final near = [...slopes]..sort((p, q) => (p.$1 - y0[i]).abs().compareTo((q.$1 - y0[i]).abs()));
      final k = near.length < 5 ? near.length : 5;
      final v = [for (var m = 0; m < k; m++) near[m].$2]..sort();
      yy[i] = y0[i] - v[k ~/ 2] * (fr[i].x - xref);
    }
    lines = _anchored(fr, yy);
  }
  return _render([for (final l in lines) [for (final j in l) fr[j]]]);
}

/// Залишковий нахил довгих фрагментів наближається прямою від висоти (фото під кутом - рядки вгорі й унизу
/// нахилені по-різному; тричі, з відкиданням викидів), фрагменти зсуваються вздовж нього до опорної вертикалі.
/// Далі фрагменти йдуть згори донизу, і кожен пристає до найближчого по висоті з чотирьох останніх рядків.
/// Потрібен нахил кожної рамки ([Frag.skew]); без нього (менше 6 довгих рамок із нахилом) - як [fragLines].
List<String> fragLinesDeskewed(List<Frag> frags) {
  final fr = _sorted(frags);
  final n = fr.length;
  if (n == 0) return [];
  final yy = [for (final f in fr) f.y];
  var pts = <List<double>>[]; // висота, нахил, вага
  for (final f in fr) {
    if (f.skew.isNaN || f.w < 5 * f.h || f.skew.abs() > 0.3) continue;
    pts.add([f.y, f.skew, f.w]);
  }
  if (pts.length >= 6) {
    var c0 = 0.0, c1 = 0.0;
    for (var it = 0; it < 3; it++) {
      var sw = 0.0, sy = 0.0, st = 0.0, syy = 0.0, syt = 0.0;
      for (final p in pts) {
        sw += p[2];
        sy += p[2] * p[0];
        st += p[2] * p[1];
        syy += p[2] * p[0] * p[0];
        syt += p[2] * p[0] * p[1];
      }
      final den = sw * syy - sy * sy;
      if (den.abs() < 1e-9) {
        c1 = 0;
        c0 = st / sw;
      } else {
        c1 = (sw * syt - sy * st) / den;
        c0 = (st - c1 * sy) / sw;
      }
      var ss = 0.0;
      for (final p in pts) {
        final r = p[1] - c0 - c1 * p[0];
        ss += r * r;
      }
      final sd = math.sqrt(ss / pts.length);
      final keep = [for (final p in pts) if ((p[1] - c0 - c1 * p[0]).abs() <= 2 * sd + 1e-6) p];
      if (keep.length < 6 || keep.length == pts.length) break;
      pts = keep;
    }
    final xs = [for (final f in fr) f.x]..sort();
    final xref = xs[n ~/ 2];
    for (var i = 0; i < n; i++) {
      yy[i] -= math.tan(c0 + c1 * yy[i]) * (fr[i].x - xref);
    }
  }
  final idx = List<int>.generate(n, (i) => i)..sort((p, q) => yy[p].compareTo(yy[q]));
  final lines = <List<int>>[];
  for (final i in idx) {
    var best = -1;
    var bestD = double.infinity;
    for (var li = lines.length - 1; li >= 0 && li >= lines.length - 4; li--) {
      final d = _fit(fr, lines[li], i, yy);
      if (d >= 0 && d < bestD) {
        best = li;
        bestD = d;
      }
    }
    if (best >= 0) {
      lines[best].add(i);
    } else {
      lines.add([i]);
    }
  }
  return _render([for (final l in lines) [for (final j in l) fr[j]]]);
}

/// Відстань по висоті від фрагмента [i] до найближчого по горизонталі фрагмента рядка; -1 - рядку не належить.
double _fit(List<Frag> fr, List<int> line, int i, List<double> yy) {
  if (_stacked(fr, line, i)) return -1;
  var near = line.first;
  for (final j in line) {
    if ((fr[j].x - fr[i].x).abs() < (fr[near].x - fr[i].x).abs()) near = j;
  }
  final d = (yy[i] - yy[near]).abs();
  final minH = fr[i].h < fr[near].h ? fr[i].h : fr[near].h;
  return d <= (fr[i].h + fr[near].h) / 2 - 0.5 * minH ? d : -1;
}

List<Frag> _sorted(List<Frag> frags) {
  final fr = [for (final f in frags) if (f.text.trim().isNotEmpty && !f.virtual) f];
  fr.sort((a, b) => a.y.compareTo(b.y));
  return fr;
}

/// Фрагмент [i] стоїть над/під одним із фрагментів рядка: проміжки по горизонталі перекриваються.
bool _stacked(List<Frag> fr, List<int> line, int i) {
  for (final j in line) {
    final lo = (fr[i].x - fr[i].w / 2) > (fr[j].x - fr[j].w / 2) ? fr[i].x - fr[i].w / 2 : fr[j].x - fr[j].w / 2;
    final hi = (fr[i].x + fr[i].w / 2) < (fr[j].x + fr[j].w / 2) ? fr[i].x + fr[i].w / 2 : fr[j].x + fr[j].w / 2;
    final m = fr[i].w < fr[j].w ? fr[i].w : fr[j].w;
    if (hi - lo > 0.3 * m) return true;
  }
  return false;
}

List<List<int>> _anchored(List<Frag> fr, List<double> yy) {
  final n = fr.length;
  final idx = List<int>.generate(n, (i) => i)
    ..sort((p, q) => fr[p].w != fr[q].w ? fr[q].w.compareTo(fr[p].w) : yy[p].compareTo(yy[q]));
  final lines = <List<int>>[];
  for (final i in idx) {
    var best = -1;
    var bestD = double.infinity;
    for (var li = 0; li < lines.length; li++) {
      final d = _fit(fr, lines[li], i, yy);
      if (d >= 0 && d < bestD) {
        best = li;
        bestD = d;
      }
    }
    if (best >= 0) {
      lines[best].add(i);
    } else {
      lines.add([i]);
    }
  }
  // згори донизу - за найширшим фрагментом рядка (він у списку перший)
  lines.sort((p, q) => yy[p.first].compareTo(yy[q.first]));
  return lines;
}

List<String> _render(List<List<Frag>> lines) {
  final out = <String>[];
  for (final l in lines) {
    final s = [...l]..sort((a, b) => a.x.compareTo(b.x));
    final sb = StringBuffer();
    for (var m = 0; m < s.length; m++) {
      if (m > 0) {
        final p = s[m - 1], f = s[m];
        final gap = (f.x - f.w / 2) - (p.x + p.w / 2);
        sb.write(gap > 4 * f.h ? '   ' : ' ');
      }
      sb.write(s[m].text);
    }
    out.add(sb.toString());
  }
  return out;
}
