/// Дочитування після розпізнавання (перенесення coursework/fuzzy_v2/recover.py): перечитування невпевнених
/// і «зіпсованих» сум з іншими рамками й розтягненнями, пропущені назви ліворуч від суми, «1x» ліворуч від ціни,
/// рукописні рядки бланка. Правила тут, у Dart; сама нейромережа, вирізання рамок зі зображення і пошук
/// рукописних рядків - у плагіні й подаються через [OcrBackend].
///
/// Усі читання одного фрагмента не залежать від вибору серед них, тож вони йдуть одним пакетом (плагін читає
/// пакет паралельно), а вибір - тими самими правилами й у тому самому порядку, що й у курсовій.
library;

import 'fz2.dart';
import 'py.dart';

/// Запит на читання рамки (x1..x2, y1..y2 - у системі фрагментів, повернутій на нахил фото) з розтягненнями.
class ReadReq {
  final double x1, x2, y1, y2;
  final List<double> st;

  const ReadReq(this.x1, this.x2, this.y1, this.y2, this.st);
}

class ReadRes {
  final String text;
  final double conf;

  const ReadRes(this.text, this.conf);
}

/// Те, що вміє лише плагін: моделі й зображення.
abstract class OcrBackend {
  /// Прочитати рамки (порядок відповіді - як запитів).
  Future<List<ReadRes>> read(double angle, List<ReadReq> reqs);

  /// Тісна рамка за чорнилом навколо центру фрагмента з виродженою рамкою (змінює x, y, w, h, xLeft, xRight).
  Future<void> degen(Frag f, double angle);

  /// Рукописні рядки бланка «Товарний чек» за фрагментами [fr].
  Future<List<Frag>> hand(List<Frag> fr);
}

const _money = r'(?<![\d.,])-?\d{1,6}\s?[.,]\s?\d{2}(?![\d.,]*\d)';
const _kwRe = r'СУМА|ПДВ|ДО\s*СПЛАТИ|РАЗОМ|УСЬОГО|ВСЬОГО';
const _clean = r'\s*-?\d{1,6}[.,]\d{2}\s*([АБВAB]|грн|ГРН)?\.?\s*';
const _susp = r'\d[.,]\s\d{2}(?!\d)|\d[.,]{2}\d|(?<![\d.,])\d{3,5}\s*[гГ][рР]?[нН]|\d[.,]\d\s*[гГ]';
const _taxEnd = r'[АБВГДABд]\s*$';
const _mkRe = r'\s*\d{1,2}\s*[xхХX×]\s*';

final _digit = RegExp(r'\p{Nd}', unicode: true);

int _digits(String s) => _digit.allMatches(s).length;

/// kop із recover.py: усе, крім цифр, крапок, ком і мінуса, відкидається; FormatException - як ValueError.
int _kopLoose(String t) {
  final s = t.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '.');
  final v = double.tryParse(s);
  if (v == null) throw FormatException('kop: $t');
  return (v * 100 + 0.5).floor(); // Math.round
}

String _fixSplit(String t) => sub(r'(\d[.,])\s(\d{2})', r'\1\2', t);

/// Стійке сортування за компаратором.
List<T> _stable<T>(Iterable<T> xs, int Function(T, T) cmp) {
  final l = xs.toList();
  final idx = List<int>.generate(l.length, (i) => i);
  idx.sort((a, b) {
    final c = cmp(l[a], l[b]);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in idx) l[i]];
}

Set<int> _moneyValues(List<Frag> fr) {
  final vals = <int>{};
  for (final f in fr) {
    for (final m in finditer(_money, f.text)) {
      try {
        vals.add(_kopLoose(m.group(0)!.replaceAll(' ', '')));
      } on FormatException {
        // як у курсовій: не число - пропускається
      }
    }
  }
  return vals;
}

/// Невпевнений фрагмент з цифрами без чистої суми: перечитати тісну рамку з кількома розтягненнями.
Future<void> reread(List<Frag> fr, OcrBackend b) async {
  final a = fr.first.angle;
  for (final f in fr) {
    final t0 = f.text;
    if (f.conf >= 0.85 || !has(r'\d', t0) || has(_money, t0)) continue;
    final reqs = <ReadReq>[
      for (final pad in const [0.6, 0.7])
        for (final st in const [1.5, 1.0, 0.8]) ReadReq(f.xLeft, f.xRight, f.y - pad * f.h, f.y + pad * f.h, [st])
    ];
    final rs = await b.read(a, reqs);
    var t = '';
    var cf = 0.0;
    for (final r in rs) {
      final t1 = _fixSplit(r.text);
      if (r.conf > cf && fullmatch(_clean, t1) != null) {
        t = t1;
        cf = r.conf;
      }
    }
    if (cf > f.conf + 0.08) {
      f.text = t;
      f.conf = cf;
    }
  }
}

class _Cand {
  final double cf, px;
  final String t;
  final List<double> bx;

  const _Cand(this.cf, this.t, this.px, this.bx);
}

/// Порядок кортежів Python (cf, t, px, bx) за спаданням.
int _candDesc(_Cand p, _Cand q) {
  var c = q.cf.compareTo(p.cf);
  if (c != 0) return c;
  c = q.t.compareTo(p.t);
  if (c != 0) return c;
  c = q.px.compareTo(p.px);
  if (c != 0) return c;
  for (var i = 0; i < 4; i++) {
    c = q.bx[i].compareTo(p.bx[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Друге перечитування з кількома рамками й розтягненнями; нове прочитання приймається, лише якщо воно чисте
/// й узгоджене з чеком.
Future<void> reread2(List<Frag> fr, OcrBackend b) async {
  final a = fr.first.angle;
  final vals = _moneyValues(fr);
  bool consistent(int v) {
    if (v <= 0) return false;
    for (final u in vals) {
      if (u > 0 && (v - u).abs() <= 1) return true;
    }
    for (final u in vals) {
      for (final r in const [20, 7]) {
        if ((v - u * r.toDouble() / (100 + r)).abs() <= 1.5) return true;
      }
    }
    return false;
  }

  var xrMax = double.negativeInfinity;
  for (final q in fr) {
    if (q.xRight > xrMax) xrMax = q.xRight;
  }
  for (final f in fr) {
    final t0 = f.text;
    final h = f.h;
    final degen = f.xRight - f.xLeft < 0.6 * h;
    final clean0 = fullmatch(_clean, t0) != null;
    if (!has(r'\d', t0) && !(degen && f.conf < 0.9)) continue;
    if (!(f.conf < 0.9 || has(_susp, t0) || (clean0 && f.conf < 0.93))) continue;
    final pxs = degen ? const [0.5, 0.8, 1.0, 1.3, 1.6] : const [0.0, 0.5];
    final reqs = <ReadReq>[];
    final meta = <List<double>>[]; // px, x1, x2, y1, y2 для кожного запиту
    final cut = !degen && has(r'\d[.,]\s\d{2}(?!\d)', t0);
    if (cut) {
      // рамка відрізала початок великого числа - ширше ліворуч
      for (final l in const [1.5, 2.0, 2.5, 3.0]) {
        for (final pad in const [0.6, 0.8, 1.0]) {
          final x1 = f.xLeft - l * h, x2 = f.xRight, y1 = f.y - pad * h, y2 = f.y + pad * h;
          for (final st in const [1.0, 0.8]) {
            reqs.add(ReadReq(x1, x2, y1, y2, [st]));
            meta.add([l, x1, x2, y1, y2]);
          }
        }
      }
    }
    for (final px in pxs) {
      for (final pad in degen ? const [0.5, 0.6, 0.8, 1.0] : const [0.6, 0.8, 1.0]) {
        final double x1, x2;
        if (degen) {
          x1 = f.x - px * h;
          x2 = f.x + px * h;
        } else {
          x1 = f.xLeft - px * h;
          x2 = f.xRight + px * h;
        }
        final y1 = f.y - pad * h, y2 = f.y + pad * h;
        for (final st in const [1.5, 1.0, 0.8]) {
          reqs.add(ReadReq(x1, x2, y1, y2, [st]));
          meta.add([px, x1, x2, y1, y2]);
        }
      }
    }
    final rs = await b.read(a, reqs);
    var best = <_Cand>[
      for (var i = 0; i < rs.length; i++)
        _Cand(rs[i].conf, _fixSplit(rs[i].text.trim()), meta[i][0], [meta[i][1], meta[i][2], meta[i][3], meta[i][4]])
    ];
    best = _stable(best, _candDesc);
    if (cut) {
      // спершу прочитання, узгоджені з іншими сумами чека
      final mv = search(r'\d{1,6}[.,]\s\d{2}', t0)!;
      final v0 = _kopLoose(mv.group(0)!.replaceAll(' ', ''));
      final ok = <_Cand>[], no = <_Cand>[];
      for (final c in best) {
        var good = false;
        if (fullmatch(_clean, c.t) != null) {
          final v = _kopLoose(match(r'\s*-?\d{1,6}[.,]\d{2}', c.t)!.group(0)!);
          good = v != v0 && consistent(v);
        }
        (good ? ok : no).add(c);
      }
      best = [...ok, ...no];
    }
    var edge = f.xRight >= 0.97 * xrMax;
    if (edge) {
      for (final q in fr) {
        if (!identical(q, f) && (q.y - f.y).abs() < 0.5 * h && q.xLeft > f.xRight) {
          edge = false;
          break;
        }
      }
    }
    final tax0 = has(_taxEnd, t0);
    _Cand? acc;
    String? accText;
    for (final c in best) {
      final t = c.t;
      final cf = c.cf;
      if (t0.contains('%') && !t.contains('%')) continue;
      if (tax0 && !has(_taxEnd, t)) continue;
      if (fullmatch(_clean, t) != null) {
        final v = _kopLoose(match(r'\s*-?\d{1,6}[.,]\d{2}', t)!.group(0)!);
        if (clean0) {
          final v0 = _kopLoose(match(r'\s*-?\d{1,6}[.,]\d{2}', t0)!.group(0)!);
          if (t.trim() != t0.trim() && cf >= 0.97 && v0 != v && consistent(v)) {
            acc = c;
            accText = t;
          }
        } else if (cf >= 0.85 &&
            (consistent(v) ||
                (cf >= (0.9 > f.conf + 0.05 ? 0.9 : f.conf + 0.05) &&
                    c.px == 0 &&
                    _digits(t0) >= 2 &&
                    _digits(t) >= _digits(t0) - 1))) {
          acc = c;
          accText = t;
        }
      } else if ((fullmatch(r'\s*\d\s+\d{2,3}\s*', t0) != null &&
              fullmatch(r'\s*\d{2,3}\s*', t) != null &&
              cf >= (0.93 > f.conf + 0.1 ? 0.93 : f.conf + 0.1) &&
              t0.replaceAll(RegExp(r'\s'), '').endsWith(t.trim()) &&
              edge &&
              f.y > 0.08 * (f.imgH ?? 0)) ||
          (fullmatch(r'\s*(\d)\1\s*', t0) != null &&
              fullmatch(r'\s*\d\s*', t) != null &&
              t.trim() == t0.trim().substring(0, 1) &&
              cf >= (0.95 > f.conf + 0.15 ? 0.95 : f.conf + 0.15))) {
        acc = c;
        accText = t;
      } else if (fullmatch(r'\s*ПДВ\s*[АБВГДAB]?\s*=?\s*(20|7|14|0)[.,]00\s*%\S?\s*', t.toUpperCase()) != null &&
          cf >= 0.9 &&
          f.conf < 0.85 &&
          !has(_kwRe, t0.toUpperCase()) &&
          !t0.contains('%')) {
        acc = c;
        accText = t.replaceAll(RegExp('%.*'), '%');
      } else if ((!has(r'\d', t0) || f.conf < 0.5 || has(r'ПДВ.*\d{1,2}[.,]\d{2}\s*%', t.toUpperCase())) &&
          has(_kwRe, t.toUpperCase()) &&
          !has(_kwRe, t0.toUpperCase()) &&
          cf >= 0.95 &&
          f.conf < 0.85) {
        acc = c;
        accText = t;
      }
      if (acc != null) break;
    }
    if (acc != null) {
      f.text = accText!;
      f.conf = acc.cf;
      if (degen) await b.degen(f, a);
    }
  }
}

/// Сума позиції, прочитана як «ціна× 1=»: перечитати без множення.
Future<void> reread3(List<Frag> fr, OcrBackend b) async {
  final a = fr.first.angle;
  for (final f in fr) {
    final t0 = f.text;
    final h = f.h;
    final m = fullmatch(r'\s*(\d{1,6}[.,]\d{2})\s*[×xхХX]\s*1?\s*=?\s*', t0);
    if (m == null) continue;
    final v = m.group(1)!;
    var right = false, leftSame = false;
    for (final q in fr) {
      if (identical(q, f) || (q.y - f.y).abs() >= 0.5 * h) continue;
      if (q.xLeft > f.xRight) right = true;
      if (q.xRight < f.xLeft && has('${RegExp.escape(v)}\\s*[×xхХX]', q.text)) leftSame = true;
    }
    if (right || !leftSame) continue;
    final reqs = <ReadReq>[
      for (final px in const [-0.5, -0.3, 0.0])
        for (final pad in const [0.5, 0.6, 0.8])
          for (final st in const [1.5, 1.0, 0.8]) ReadReq(f.xLeft, f.xRight + px * h, f.y - pad * h, f.y + pad * h, [st])
    ];
    final rs = await b.read(a, reqs);
    final best = <({double cf, int len, String t})>[];
    for (final r in rs) {
      if (fullmatch('\\s*${RegExp.escape(v)}\\s*(-\\s*[АA]?)?\\s*', r.text) != null) {
        best.add((cf: r.conf, len: r.text.trim().length, t: r.text.trim()));
      }
    }
    final sorted = _stable(best, (p, q) {
      var c = q.cf.compareTo(p.cf);
      if (c != 0) return c;
      c = q.len.compareTo(p.len);
      if (c != 0) return c;
      return q.t.compareTo(p.t);
    });
    if (sorted.isNotEmpty && sorted.first.cf >= 0.9) {
      final ok = _stable([for (final c in sorted) if (c.cf >= 0.9) c], (p, q) {
        final c = q.len.compareTo(p.len);
        return c != 0 ? c : q.cf.compareTo(p.cf);
      });
      f.text = ok.first.t;
      f.conf = sorted.first.cf;
    }
  }
}

/// «1 х 34,00» у рамці, куди влазить лише «34,00»: префікс «N х» дописано з рисок над числом.
void stripQty(List<Frag> fr) {
  for (final f in fr) {
    final t0 = f.text;
    final m = fullmatch(r'\s*\d{1,3}\s*[хxХX×]\s*(\d{1,5}[.,]\d{2})\s*', t0);
    if (m != null && (f.xRight - f.xLeft) / (f.h * t0.trim().length) < 0.25) f.text = m.group(1)!;
  }
  final allt = fr.map((f) => f.text).join(' | ');
  for (final f in fr) {
    final t0 = f.text;
    final m = fullmatch(r'\s*1\s+(\d{1,5}[.,]\d{2})\s*', t0);
    if (m != null &&
        f.conf < 0.9 &&
        has('(?<![\\d.,])(?<!1 )${RegExp.escape(m.group(1)!)}(?!\\d)', allt.replaceAll(t0, ''))) {
      final g = m.group(1)!;
      f.xLeft = f.xRight - (f.xRight - f.xLeft) * g.length / t0.trim().length;
      f.x = (f.xLeft + f.xRight) / 2;
      f.text = g;
    }
  }
}

/// Ціна під пунктирною лінією: риска над числом читається як «1» - рамка звужується.
Future<void> reread4(List<Frag> fr, OcrBackend b) async {
  final a = fr.first.angle;
  final vals = _moneyValues(fr);
  for (final f in fr) {
    final t0 = f.text;
    final h = f.h;
    if (f.conf >= 0.9 || fullmatch(r'\s*1\s*[хxХX×]?\s*[\d.,]*\d[\d.,]*\s*', t0) == null || fullmatch(_clean, t0) != null) {
      continue;
    }
    final reqs = <ReadReq>[
      for (final dy in const [0.0, 0.1, 0.2])
        for (final pad in const [0.4, 0.5])
          for (final st in const [1.5, 1.0])
            ReadReq(f.xLeft + 0.3 * h, f.xRight + 0.2 * h, f.y + (dy - pad) * h, f.y + (dy + pad) * h, [st])
    ];
    final rs = await b.read(a, reqs);
    var bc = -1.0;
    String? bt;
    for (final r in rs) {
      final t = r.text.trim();
      if (fullmatch(r'\d{1,5}[.,]\d{2}', t) != null && r.conf >= 0.93 && _kopLoose(t) > 0 && vals.contains(_kopLoose(t))) {
        if (bt == null || r.conf > bc || (r.conf == bc && t.compareTo(bt) > 0)) {
          bc = r.conf;
          bt = t;
        }
      }
    }
    if (bt != null) {
      f.text = bt;
      f.conf = bc;
    }
  }
}

/// «1x» ліворуч від ціни, які детектор пропустив (лише в чеку, де хоч один такий уже знайдено).
Future<List<Frag>> qtyMarks(List<Frag> fr, OcrBackend b) async {
  final a = fr.first.angle;
  final mk = [for (final f in fr) if (fullmatch(_mkRe, f.text) != null) f];
  final add = <Frag>[];
  if (mk.isEmpty) return add;
  final xl = npMedian([for (final f in mk) f.xLeft]);
  final xmid = npMedian([for (final f in fr) f.x]);
  for (final p in fr) {
    if (fullmatch(r'\s*\d{1,5}[.,]\d{2}\s*', p.text) == null || p.x < xmid) continue;
    final h = p.h;
    var has0 = false;
    for (final q in [...fr, ...add]) {
      if ((q.y - p.y).abs() < 1.0 * h && q.xLeft < xl + 2 * h && q.xRight > xl && fullmatch(_mkRe, q.text) != null) {
        has0 = true;
        break;
      }
    }
    if (has0) continue;
    final reqs = <ReadReq>[];
    final ycs = <double>[];
    for (final dy in const [-0.4, -0.2, 0.0, 0.2, 0.4]) {
      final yc = p.y + dy * h;
      var busy = false;
      for (final q in fr) {
        if ((q.y - yc).abs() < 0.5 * h && q.xLeft < xl + 1.7 * h && q.xRight > xl) {
          busy = true;
          break;
        }
      }
      if (busy) continue;
      for (final pad in const [0.5, 0.6]) {
        for (final st in const [1.5, 1.0]) {
          reqs.add(ReadReq(xl - 0.3 * h, xl + 1.7 * h, yc - pad * h, yc + pad * h, [st]));
          ycs.add(yc);
        }
      }
    }
    if (reqs.isEmpty) continue;
    final rs = await b.read(a, reqs);
    String? bt;
    var bc = 0.0, bx1 = 0.0, bx2 = 0.0, byc = 0.0;
    for (var i = 0; i < rs.length; i++) {
      final r = rs[i];
      if (fullmatch(_mkRe, r.text) != null && r.conf >= 0.9 && (bt == null || r.conf > bc)) {
        bt = r.text.trim();
        bc = r.conf;
        bx1 = reqs[i].x1;
        bx2 = reqs[i].x2;
        byc = ycs[i];
      }
    }
    if (bt != null) {
      final n = p.copy();
      n.boxId = 20000 + add.length;
      n.text = bt;
      n.conf = bc;
      n.x = (bx1 + bx2) / 2;
      n.w = bx2 - bx1;
      n.xLeft = bx1 + 0.3 * h;
      n.xRight = bx1 + 0.3 * h + 1.2 * h;
      n.y = byc;
      n.recovered = true;
      add.add(n);
    }
  }
  return add;
}

Set<String> _stems(String u) => {
      for (final m in finditer(r'[^\W\d_]{5,}', u)) m.group(0)!.substring(0, 5).toUpperCase(),
    };

/// Пропущена назва: праворуч є сума, а ліворуч у тому самому рядку детектор не знайшов жодної рамки.
Future<List<Frag>> recover(List<Frag> fr, OcrBackend b) async {
  final a = fr.first.angle;
  final x0 = npPercentile([for (final f in fr) f.xLeft], 5);
  final xmid = npMedian([for (final f in fr) f.x]);
  final add = <Frag>[];
  for (final f in fr) {
    if (!has(_money, f.text) || f.x < xmid) continue;
    final h = f.h;
    var left = false;
    for (final q in fr) {
      if (!identical(q, f) && alphaCount(q.text) >= 2 && q.xRight < f.xLeft + 0.2 * h && (q.y - f.y).abs() < 0.45 * h) {
        left = true;
        break;
      }
    }
    if (left || f.xLeft - x0 < 4 * h) continue;
    final x1 = x0 - 0.3 * h, x2 = f.xLeft - 0.3 * h;
    var cover = 0.0;
    for (final q in fr) {
      if (!identical(q, f) && alphaCount(q.text) > 0 && (q.y - f.y).abs() < 0.45 * h) {
        final c = (q.xRight < f.xLeft ? q.xRight : f.xLeft) - (q.xLeft > x0 ? q.xLeft : x0);
        cover += c > 0 ? c : 0;
      }
    }
    if (cover > 0.3 * (f.xLeft - x0)) continue;
    final r = (await b.read(a, [ReadReq(x1, x2, f.y - 0.55 * h, f.y + 0.55 * h, const [1.0, 2.0])])).first;
    final t = r.text.trim();
    if (alphaCount(t) < 4 || r.conf < 0.85 || has('$_money(?!\\s*%)', t)) continue;
    final st = _stems(t);
    final near = <String>{};
    for (final q in fr) {
      if ((q.y - f.y).abs() < 1.6 * h) near.addAll(_stems(q.text));
    }
    if (st.any(near.contains)) continue;
    final n = f.copy();
    n.boxId = 10000 + add.length;
    n.text = t;
    n.conf = r.conf;
    n.x = (x1 + x2) / 2;
    n.w = x2 - x1;
    n.xLeft = x1;
    n.xRight = x2;
    n.recovered = true;
    add.add(n);
  }
  return add;
}

/// Дочитування всіх видів на фрагментах [fr] (після OcrV2.run): змінює [fr] і дописує знайдені фрагменти.
///
/// Кроки незалежні: збій одного (наприклад, у плагіні) пропускає лише його, решта
/// й подальша розмітка працюють. Повертає причини пропущених кроків (порожньо - усе гаразд).
Future<List<String>> recoverAll(List<Frag> fr, OcrBackend b) async {
  final errors = <String>[];
  if (fr.isEmpty) return errors;
  Future<void> step(String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      errors.add('$name: $e');
    }
  }

  await step('reread', () => reread(fr, b));
  await step('reread2', () => reread2(fr, b));
  await step('reread3', () => reread3(fr, b));
  await step('reread4', () => reread4(fr, b));
  stripQty(fr);
  for (final f in fr) {
    if (match(r'\s*-\s*-\s*\d', f.text) != null) f.text = sub(r'^\s*-\s*-', '-', f.text);
  }
  final add = <Frag>[];
  await step('recover', () async => add.addAll(await recover(fr, b)));
  await step('hand', () async => add.addAll(await b.hand(fr)));
  await step('qtyMarks', () async => add.addAll(await qtyMarks(fr, b)));
  fr.addAll(add);
  return errors;
}
