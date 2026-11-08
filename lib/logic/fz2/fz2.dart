/// Нечітка розмітка фіскального чека (перенесення coursework/fuzzy_v2/fz2.py).
///
/// Класи фрагментів OCR: NAME (назва), ITEM (сума позиції), PRICE (ціна за
/// одиницю), QTY (кількість), TOTAL (підсумок), DISC (знижка), VAT (ПДВ),
/// SERV (службове), OTHER (інший чек у кадрі). Висновок Мамдані: І = min,
/// агрегування = max, імплікація - відсікання, дефазифікація - центроїд.
///
/// Код навмисно повторює Python рядок за рядком (порядок обходу, округлення,
/// підсумовування numpy): тест test/fz2_test.dart вимагає, щоб розмітка
/// збігалася з Python на кожному фрагменті розмічених чеків. Змінюючи правила,
/// змінюйте їх і в fz2.py (або перегенеруйте еталон, див. tool/fz2/README.md).
library;

import 'dart:collection';
import 'dart:math' as math;

import 'py.dart';

/// Фрагмент тексту OCR: рамка в координатах вирівняного (поверненого) фото.
class Frag {
  String receipt;
  int? boxId;
  int lineId;
  String text;
  double conf;
  double x, y, w, h, xLeft, xRight;
  double? imgW, imgH;
  double angle;

  /// Рукописний рядок бланка (hand.py): клас уже відомий (NAME чи ITEM).
  String? hand;

  /// Позиція без рядка в чеку (чек оплати послуг): назва й сума.
  bool virtual;
  double? value;

  Frag({
    this.receipt = '',
    this.boxId,
    this.lineId = 0,
    required this.text,
    this.conf = 1,
    required this.x,
    required this.y,
    this.w = 0,
    required this.h,
    required this.xLeft,
    required this.xRight,
    this.imgW,
    this.imgH,
    this.angle = 0,
    this.hand,
    this.virtual = false,
    this.value,
  });

  Frag copy({String? text, double? xLeft, double? xRight}) => Frag(
        receipt: receipt,
        boxId: boxId,
        lineId: lineId,
        text: text ?? this.text,
        conf: conf,
        x: x,
        y: y,
        w: w,
        h: h,
        xLeft: xLeft ?? this.xLeft,
        xRight: xRight ?? this.xRight,
        imgW: imgW,
        imgH: imgH,
        angle: angle,
        hand: hand,
        virtual: virtual,
        value: value,
      );

  static Frag virtualItem(String name, double value) =>
      Frag(text: name, x: 0, y: 0, h: 0, xLeft: 0, xRight: 0, virtual: true, value: value)..boxId = null;

  @override
  String toString() => 'Frag($boxId, "$text", y=$y)';
}

/// Фрагмент (чи його частина) з класом і впевненостями класів.
class Labeled {
  final Frag f;
  final String cls;
  final Map<String, double> mu;
  const Labeled(this.f, this.cls, [this.mu = const {}]);
}

// ---------------------------------------------------------- функції належності

List<double> _trap(List<double> x, double a, double b, double c, double d) => [
      for (final v in x)
        math.min(b > a ? clip((v - a) / (b - a), 0, 1) : (v >= a ? 1.0 : 0.0),
            d > c ? clip((d - v) / (d - c), 0, 1) : (v <= d ? 1.0 : 0.0))
    ];

double rise(double x, double a, double b) => clip((x - a) / (b - a), 0, 1);
double fall(double x, double a, double b) => 1.0 - rise(x, a, b);

final List<double> _u = [for (var i = 0; i < 201; i++) i == 200 ? 1.0 : i * 0.005];
final Map<String, List<double>> _out = {
  'низька': _trap(_u, -1, 0, 0.15, 0.4),
  'середня': _trap(_u, 0.2, 0.45, 0.55, 0.8),
  'висока': _trap(_u, 0.6, 0.85, 1, 2),
};

typedef Rule = (String, String, double);

/// Висновок Мамдані: центроїд впевненості для кожного класу.
Map<String, double> mamdani(List<Rule> rules, List<String> classes) {
  final agg = {for (final c in classes) c: List<double>.filled(_u.length, 0.0)};
  // доповнювальне правило: «якщо жодне правило класу не спрацювало сильно, впевненість низька»
  final hi = {for (final c in classes) c: 0.0};
  for (final (c, term, a) in rules) {
    if (term != 'низька') hi[c] = math.max(hi[c]!, a);
  }
  final all = [...rules, for (final c in classes) (c, 'низька', 1 - hi[c]!)];
  for (final (c, term, a) in all) {
    if (a > 0) {
      final g = agg[c]!, o = _out[term]!;
      for (var i = 0; i < g.length; i++) {
        g[i] = math.max(g[i], math.min(a, o[i]));
      }
    }
  }
  return {
    for (final c in classes)
      c: () {
        final g = agg[c]!;
        final s = npSum(g);
        if (!(s > 0)) return 0.0;
        return npSum([for (var i = 0; i < g.length; i++) g[i] * _u[i]]) / s;
      }()
  };
}

// ------------------------------------------------- подібність слів (Левенштейн)

int lev(String a, String b) {
  final ra = a.runes.toList(), rb = b.runes.toList();
  var p = List<int>.generate(rb.length + 1, (i) => i);
  for (var i = 1; i <= ra.length; i++) {
    final q = <int>[i];
    for (var j = 1; j <= rb.length; j++) {
      q.add(math.min(math.min(p[j] + 1, q[j - 1] + 1), p[j - 1] + (ra[i - 1] != rb[j - 1] ? 1 : 0)));
    }
    p = q;
  }
  return p.last;
}

const _latFrom = 'ABCEHIKMOPTXYaceiopxy';
const _latTo = 'АВСЕНІКМОРТХУасеіорху';

String norm(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _latFrom.indexOf(ch);
    b.write(i >= 0 ? _latTo[i] : ch);
  }
  final t = b.toString().toUpperCase().replaceAll('Ї', 'І').replaceAll('Є', 'Е').replaceAll('Ґ', 'Г');
  return sub(r'[^0-9А-ЯІ ]', ' ', t);
}

final _simCache = HashMap<String, double>();

/// Найбільша нормована подібність 1 − d/|w| між словом зі списку і словом (парою слів) тексту.
double sim(String text, List<String> words) {
  final key = '${identityHashCode(words)}\u0001$text';
  final c = _simCache[key];
  if (c != null) return c;
  final t = pySplit(norm(text));
  final grams = [...t, for (var i = 0; i + 1 < t.length; i++) '${t[i]} ${t[i + 1]}'];
  var best = 0.0;
  for (final w in words) {
    final lw = w.runes.length;
    for (final g in grams) {
      final lg = g.runes.length;
      if ((lg - lw).abs() > math.max(2, lw ~/ 3)) continue;
      best = math.max(best, 1 - lev(g, w) / math.max(lw, lg));
      if (lw >= 4 && g.startsWith(w)) best = math.max(best, 0.95);
    }
  }
  if (_simCache.length > 20000) _simCache.clear();
  return _simCache[key] = best;
}

const kwTotal = ['СУМА', 'РАЗОМ', 'ДО СПЛАТИ', 'ПІДСУМОК', 'ВСЬОГО', 'УСЬОГО', 'ЗАГАЛОМ'];
const kwVat = ['ПДВ', 'АКЦИЗ', 'ПОДАТКИ'];
const kwDisc = ['ЗНИЖКА', 'ЗНИЖКИ', 'УЦІНКА', 'ДИСКОНТ'];
const kwPay = ['БЕЗГОТІВКОВА', 'ГОТІВКА', 'КАРТКА', 'КАРТКОЮ', 'РЕШТА', 'ОПЛАТА', 'СПЛАЧЕНО', 'БОНУС', 'БОНУСИ', 'БАЛАНС',
    'ЗАОКРУГЛЕННЯ', 'ЗАЛИШОК', 'НАРАХОВАНО', 'ПОЧАТОК', 'СПИСАНО', 'КЕШБЕК', 'ПЛАТІЖНА', 'ЕКВАЙРА', 'ВИНАГОРОДИ'];
const kwComm = ['КОМІСІЯ', 'КОМІСІЙНОЇ', 'КОМІСІЇ', 'КОМІСІЙНИЙ', 'ЗБІР'];
const kwServ = ['ТОВ', 'ТТН', 'ГРН', 'ЦІНА', 'ПОКУПКА', 'ТОВАРНИЙ', 'НАЗВА', 'К-СТЬ', 'КІЛЬКІСТЬ', 'ФОП', 'ПН', 'ІД', 'ШК', 'КАСА', 'ПРОВУЛОК', 'ПРОВ', 'ПРОСПЕКТ', 'ВУЛИЦЯ', 'БУД', 'ОБЛАСТЬ', 'РАЙОН', 'СЕЛО', 'НАЙМЕНУВАННЯ', 'ВІДДІЛ', 'КАСИР', 'МЕДИЧНИЙ', 'ЦЕНТР', 'ОПЕРАТОР', 'ЧЕК', 'ФН', 'ЗН', 'ВУЛ', 'ТЕЛ', 'ДЯКУЄМО', 'ТЕРМІНАЛ',
    'МАГАЗИН', 'АДРЕСА', 'ШТРИХ', 'ШТРИХКОД', 'КОД', 'ПРРО', 'ЧАС', 'ДАТА', 'ОНЛАЙН', 'ФІСКАЛЬНИЙ',
    'БАНК', 'ПРИВАТБАНК', 'ВІЗА', 'ВИД', 'ОПЕРАЦІЇ', 'КВИТАНЦІЯ', 'АВТ', 'ТРАНЗ', 'КЛІЄНТ', 'ЗАВАНТАЖУЙТЕ'];
const _kwKasyr = ['КАСИР'];
const Map<String, List<String>> kw = {
  'total': kwTotal,
  'vat': kwVat,
  'disc': kwDisc,
  'pay': kwPay,
  'comm': kwComm,
  'serv': kwServ,
};

const moneyRe = r'(?<![\d.,])(-?\d{1,6})\s?[.,]\s?(\d{2})(?![\d.,]*\d)';
const _num = r'\d{1,4}(?:[.,]\d{1,3})?';
const _unit = r'(?:\s*(?:л|Л|н|кг|КГ|Кг|г|шт)\.?)?';
const qpRe = r'(?<![\d.,])(' + _num + r')' + _unit + r'\s*[xхХX×*]\s*(\d{1,6}[.,]\s?\d{2})';
const pqRe = r'(?<![\d.,])(\d{1,6}[.,]\d{2})\s*[×xхХX*]\s*(' + _num + r')' + _unit + r'\s*(?:шт|=|$)';
/// pqRe з групами для позиції кількості: 1 - усе до кількості, 3 - кількість.
const _pqSpan = r'(?<![\d.,])((\d{1,6}[.,]\d{2})\s*[×xхХX*]\s*)(' + _num + r')' + _unit + r'\s*(?:шт|=|$)';
const _taxl = r'^\s*[АБВГДAБBаб](\s|$)';
const _money2 = r'\d+[.,]\s?\d{2}';
const _kwReTot = r'СУМА|ДО\s*СПЛАТИ|РАЗОМ|УСЬОГО|ВСЬОГО|ЗНИЖ|ОКРУГЛ|ЗАОКР';

bool oneDigit(int a, int b) {
  final sa = '$a', sb = '$b';
  if (sa.length != sb.length) return false;
  var n = 0;
  for (var i = 0; i < sa.length; i++) {
    if (sa[i] != sb[i]) n++;
  }
  return n == 1;
}

/// Ставка ПДВ: «20.00%», «А = 20%», «7%»; «Вишня 32%» чи «-40%» - ні.
bool isRate(String t) => has(r'(?<![-\d])\d{1,2}[.,]\d{2}\s*%', t) || has(r'(?:^|[\s=])(20|7|14)\s*%', t);

/// Гроші в копійках.
int kop(String s) => pyRound(pyFloat(s.replaceAll(' ', '').replaceAll(',', '.')) * 100);

const classes = ['ITEM', 'PRICE', 'TOTAL', 'DISC', 'VAT', 'SERV'];
const nameClasses = ['NAME', 'SERV'];

final _firstNames = '''Олександр Олександра Андрій Сергій Володимир Віталій Дмитро Іван Михайло Микола Петро Василь Юрій Олег Ігор
Віктор Анатолій Євген Євгеній Роман Тарас Богдан Максим Артем Владислав Денис Костянтин Павло Руслан Степан Ярослав Леонід Валентин
Валерій Григорій Борис Антон Вадим Станіслав Федір Олексій Ілля Кирило Назар Остап Тимофій Яків
Ольга Олена Наталія Наталя Тетяна Ірина Світлана Людмила Любов Галина Оксана Юлія Вікторія Катерина Анна Ганна Надія Віра Лариса
Валентина Ніна Алла Інна Яна Аліна Дарія Софія Христина Зоя Раїса Лідія Тамара Неля Жанна Інесса Мар'яна Маряна
Анастасія Ксенія Діана Вероніка Уляна Леся Лілія Олеся'''
    .split(RegExp(r'\s+'))
    .toSet();

/// ПІБ людини: по батькові (-івна, -ович …) або ім'я поряд з іншим словом з великої літери, без цін і кодів.
bool isPerson(String txt) {
  final w = [for (final m in finditer(r"[А-ЯІЇЄҐA-Z][а-яіїєґ'’a-z]+", txt)) m.group(0)!];
  if (has(r'\d{2,}[.,]\d{2}', txt) || w.length < 2) return false;
  if (has(r'\d\s*(г|кг|мл|л|шт|см|мм)\b', txt, i: true)) return false;
  if (w.any((x) => fullmatch(r"[А-ЯІЇЄҐ][а-яіїєґ']+(івна|ївна|овна|евна|ович|йович|івич|євич|ьович)", x) != null)) return true;
  return w.any(_firstNames.contains) && pySplit(txt).length <= 4;
}

/// Відкидає фрагменти іншого чека, що потрапив у кадр.
(List<Frag>, List<Frag>) mainReceipt(List<Frag> frags) {
  final h = npMedian([for (final f in frags) f.h]);
  const tot = r'\b(СУМА|СYMА|СУМA|ДО\s*СПЛАТИ|ВСЬОГО|РАЗОМ)\b';
  final ys = sortedBy(frags, (f) => f.y);
  for (var i = 1; i < ys.length; i++) {
    if (ys[i].y - ys[i - 1].y < 2.2 * h) continue;
    final up = ys.sublist(0, i), lo = ys.sublist(i);
    int ln(List<Frag> q) => q.fold(0, (s, f) => s + f.text.length);
    if (up.any((f) => has(tot, f.text, i: true)) &&
        lo.any((f) => has(tot, f.text, i: true)) &&
        ln(lo) > 2 * ln(up) &&
        up.any((f) => has(_money2, f.text))) {
      final (k, d) = mainReceipt(lo);
      return (k, [...d, ...up]);
    }
  }
  final iv = sortedBy(frags, (f) => f.xLeft);
  final cols = <List<Frag>>[];
  var cur = <Frag>[];
  double? right;
  for (final f in iv) {
    if (right != null && f.xLeft - right > 1.5 * h) {
      cols.add(cur);
      cur = [];
    }
    cur.add(f);
    right = right == null || cur.length == 1 ? f.xRight : math.max(right, f.xRight);
  }
  cols.add(cur);
  final core = [for (final f in frags) if (f.text.trim().length >= 6) f];
  if (core.length >= 8) {
    final xl = npPercentile([for (final f in core) f.xLeft], 5);
    final xr = npPercentile([for (final f in core) f.xRight], 95);
    final yt = npPercentile([for (final f in core) f.y], 2);
    final yb = npPercentile([for (final f in core) f.y], 98);
    final far0 = [
      for (final f in frags)
        if (f.x < xl - h ||
            f.x > xr + h ||
            f.xRight < xl - 2 * h ||
            f.xLeft > xr + 2 * h ||
            f.y < yt - 4 * h ||
            f.y > yb + 4 * h)
          f
    ];
    final farSet = Set<Frag>.identity()..addAll(far0);
    final far = [
      for (final f in far0)
        if (sub(r'\s', '', f.text).length > 3 ||
            !frags.any((g) =>
                !farSet.contains(g) &&
                (g.y - f.y).abs() < 0.5 * h &&
                math.min((f.xLeft - g.xRight).abs(), (g.xLeft - f.xRight).abs()) < h))
          f
    ];
    if (far.isNotEmpty) {
      final fs = Set<Frag>.identity()..addAll(far);
      final (k, d) = mainReceipt([for (final f in frags) if (!fs.contains(f)) f]);
      return (k, [...d, ...far]);
    }
  }
  if (cols.length == 1) return (frags, <Frag>[]);
  final main = maxBy(List<int>.generate(cols.length, (i) => i), (i) => cols[i].length);
  final keep = <Frag>[], drop = <Frag>[];
  for (var i = 0; i < cols.length; i++) {
    final c = cols[i];
    final numeric = npMean([
      for (final f in c)
        fullmatch(r'[\d\s.,:*xхХX×=-]*\d[\d\s.,:*xхХX×=-]*(\s?[АБВAaа]|\s?ГРН|\s?грн)?', f.text.trim()) != null ? 1.0 : 0.0
    ]);
    if (i == main || (i > main && numeric >= 0.5)) {
      keep.addAll(c);
    } else {
      drop.addAll(c);
    }
  }
  return (keep, drop);
}

class _M {
  final int start, end;
  final String g1, g2;
  _M(this.start, this.end, this.g1, this.g2);
  factory _M.of(RegExpMatch m) => _M(m.start, m.end, m.group(1)!, m.group(2)!);
}

class _Tok {
  final Frag f;
  final int a, b, v, line;
  final String left, letter;
  final bool trunc, neg, tax, factor;
  Map<String, double> mu = const {};
  String role = '';
  double dz = 0;
  bool zoneVat = false;
  _Tok(this.f, this.a, this.b, this.v, this.line, this.left, this.trunc, this.letter, this.neg, this.tax, this.factor);
}

bool _separator(String t0) {
  final t = sub(r'\s', '', t0);
  if (t.length < 10) return false;
  final cnt = <String, int>{};
  for (var i = 0; i < t.length; i++) {
    cnt[t[i]] = (cnt[t[i]] ?? 0) + 1;
  }
  var top = '';
  var n = 0;
  cnt.forEach((k, v) {
    if (v > n) {
      n = v;
      top = k;
    }
  });
  return !isDigitChar(top) && n >= 0.6 * t.length;
}

String _yKey(Frag f) => '${f.boxId}|${f.y}';

List<Labeled> _labelMain(List<Frag> frags0) {
  final sep = [for (final f in frags0) if (_separator(f.text)) f];
  var frags = [for (final f in frags0) if (!_separator(f.text)) f];
  final handf = [for (final f in frags) if (f.hand != null) f];
  frags = [for (final f in frags) if (f.hand == null) f];
  final mr = mainReceipt(frags);
  frags = mr.$1;
  final other = [...mr.$2, ...sep];
  if (frags.isEmpty) {
    return [for (final f in handf) Labeled(f, f.hand!), for (final f in other) Labeled(f, 'OTHER')];
  }
  final hmed0 = npMedian([for (final f in frags) f.h]);
  final ys0 = [for (final f in frags) f.y]..sort();
  final gaps = <double>[
    for (var i = 0; i + 1 < ys0.length; i++)
      if (ys0[i + 1] - ys0[i] > 0.25 * hmed0) ys0[i + 1] - ys0[i]
  ];
  final pitch = gaps.isNotEmpty ? clip(npMedian(gaps), 0.4 * hmed0, 2 * hmed0) : hmed0;
  // перенесення рядка: «… -20.» і нижче «06» – одне число «-20.06»
  frags = [for (final f in frags) f.copy()];
  final gone = Set<Frag>.identity();
  for (final f in frags) {
    if (!has(r'\d[.,]\s*$', f.text)) continue;
    final nx = [
      for (final g in frags)
        if (!gone.contains(g) &&
            !identical(g, f) &&
            0.5 * pitch < g.y - f.y &&
            g.y - f.y < 1.6 * pitch &&
            fullmatch(r'\s*\d{2}\s*[АБВA*]?\s*', g.text) != null)
          g
    ];
    if (nx.isNotEmpty) {
      final g = minBy(nx, (g) => g.y - f.y);
      f.text = f.text.trimRight() + g.text.trim();
      gone.add(g);
    }
  }
  frags = [for (final f in frags) if (!gone.contains(f)) f];
  var cur = -1;
  double? yStart;
  for (final f in sortedBy(frags, (f) => f.y)) {
    if (yStart == null || f.y - yStart > 0.45 * pitch) {
      cur++;
      yStart = f.y;
    }
    f.lineId = cur;
  }
  final lines = <int, List<Frag>>{};
  for (final f in frags) {
    lines.putIfAbsent(f.lineId, () => []).add(f);
  }
  for (final k in lines.keys.toList()) {
    lines[k] = sortedBy(lines[k]!, (f) => f.x);
  }
  final ly = {for (final e in lines.entries) e.key: npMean([for (final f in e.value) f.y])};
  final ltext = {for (final e in lines.entries) e.key: e.value.map((f) => f.text).join(' ')};
  final hmed = pitch;
  final x0 = pyMin(frags.map((f) => f.xLeft)).toDouble();
  final x1 = pyMax(frags.map((f) => f.xRight)).toDouble();

  final mfr = [for (final f in frags) if (has(moneyRe, f.text)) f];
  final nDec = mfr.length;
  final xmidAll = npMedian([for (final f in frags) f.x]);
  const intUah = r'^\s*(-?\d{2,5})(?=(\s?[₴sгrґаaзэЭ2z]\.?)?\s*$)';
  final xR = pyMax(frags.map((f) => f.xRight)).toDouble();
  final minXl = pyMin(frags.map((f) => f.xLeft)).toDouble();
  bool intOk(Frag f) =>
      (f.xRight > xR - 0.3 * (xR - minXl)) &&
      has(intUah, f.text) &&
      frags.any((g) => (g.y - f.y).abs() < 0.6 * pitch && g.xRight < f.xLeft && alphaCount(g.text) >= 2);
  if (nDec < 3) mfr.addAll([for (final f in frags) if (intOk(f)) f]);
  final owner = HashMap<Frag, Frag>.identity();
  final dys = <double>[];
  for (final f in mfr) {
    final lefts = [
      for (final g in frags)
        if (g.xRight < f.xLeft && !has(moneyRe, g.text) && (g.y - f.y).abs() < 0.8 * pitch) g
    ];
    if (lefts.isNotEmpty) dys.add(f.y - minBy(lefts, (g) => (g.y - f.y).abs()).y);
  }
  var dy0 = dys.length >= 5 ? npMedian(dys) : 0.0;
  dy0 = dy0.abs() > 0.25 * pitch ? dy0 : 0.0;
  double? yz;
  var dz0 = dy0;
  final kwl = [
    for (final g in frags)
      if (!has(moneyRe, g.text) && g.x < xmidAll && math.max(sim(g.text, kwTotal), sim(g.text, kwPay)) >= 0.8) g
  ];
  if (kwl.isNotEmpty) {
    final yk = pyMin(kwl.map((g) => g.y)) - 0.5 * pitch;
    final labs = [
      for (final g in frags)
        if (g.y >= yk && g.x < xmidAll && alphaCount(g.text) >= 3 && !has(moneyRe, g.text)) g
    ];
    final vals = sortedBy([for (final f in mfr) if (f.y >= yk && f.x > xmidAll) f], (f) => f.y);
    (int, double) nmatch(double sh) {
      final used = Set<Frag>.identity();
      var n = 0;
      var err = 0.0;
      for (final v in vals) {
        final c = [for (final g in labs) if (!used.contains(g) && (v.y - g.y - sh).abs() < 0.45 * pitch) g];
        if (c.isNotEmpty) {
          final g = minBy(c, (g) => (v.y - g.y - sh).abs());
          used.add(g);
          n++;
          err += (v.y - g.y - sh).abs();
        }
      }
      return (n, err);
    }

    if (vals.length >= 3) {
      final (n0, _) = nmatch(dy0);
      final cands = [
        for (final sh in npArange(-1.3 * pitch, 1.3 * pitch, 0.05 * pitch))
          () {
            final (n, e) = nmatch(sh);
            return (n, e, sh);
          }()
      ];
      final best = maxByTuple(cands, (z) => [z.$1, -z.$2]);
      final (n1, _, sh1) = best;
      if (n1 >= n0 + 2 && n1 >= 0.8 * vals.length && (sh1 - dy0).abs() > 0.5 * pitch) {
        yz = yk;
        dz0 = sh1;
      }
    }
  }
  double dyof(Frag g) => yz != null && g.y >= yz ? dz0 : dy0;
  for (final g in frags) {
    final right = [for (final f in mfr) if (!identical(f, g) && f.x > g.x) f];
    if (right.isNotEmpty) owner[g] = minBy(right, (f) => (f.y - g.y - dyof(g)).abs());
  }
  final allv = <int>{
    for (final f in frags)
      for (final m in finditer(moneyRe, f.text)) kop('${m.group(1)}.${m.group(2)}')
  };
  final toks = <_Tok>[];
  for (final f in frags) {
    var t = f.text;
    if (f.h >= 1.15 * hmed0) {
      final t2 = sub(r'^(\s*\d) (\d{1,3}[.,]\d{2})', r'\1\2', t);
      if (t2 != t) f.text = t = t2;
    }
    final t2 = sub(r'^(\s*-?\d{1,3}) (\d{3}[.,]\d{2})(?=\s*(?:[АБВAB]|грн|ГРН|д)?\.?\s*$)', r'\1\2', t);
    if (t2 != t && f.conf >= 0.8) f.text = t = t2;
    final mPct = fullmatch(r'\s*(\d{1,5}[.,]\d{2})\s?%\s*', t);
    if (mPct != null &&
        !const [0, 500, 700, 1000, 1400, 2000].contains(kop(mPct.group(1)!)) &&
        f.xRight > xR - 0.25 * (xR - minXl)) {
      f.text = t = '${mPct.group(1)!} А';
    }
    var ms = [for (final m in finditer(moneyRe, t)) _M.of(m)];
    if (ms.isEmpty) {
      final tt = t;
      List<_M> alt(String p) => [for (final m in finditer(p, tt)) _M.of(m)];
      ms = alt(r'(?<![\d.,])(\d{1,5}) ?(\d{2})(?=\s*[АAБВ]\s*$)');
      if (ms.isEmpty) ms = alt(r'(?<![\d.,])(\d{1,5})[.,](\d{2})(?=8\s*$)');
      if (ms.isEmpty) ms = alt(r'^\s*(\d{1,5})-(\d{2})(?=\s*(ГРН|грн)?\s*$)');
      if (ms.isEmpty) {
        ms = [
          for (final m in alt(r'^\s*(\d{1,5}) ?(\d{2})\s*$'))
            if (!m.g1.startsWith('0') &&
                allv.any((tv) =>
                    tv >= 600 &&
                    const [20, 7].any((r) => (kop('${m.g1}.${m.g2}') - tv * r / (100 + r)).abs() <= 1)))
              m
        ];
      }
    }
    if (ms.isNotEmpty && fullmatch(r'\s*\d{3,7}\s*', t) != null) {
      f.text = t = '${ms[0].g1}.${ms[0].g2}';
      ms = [for (final m in finditer(moneyRe, t)) _M.of(m)];
    }
    var trunc = false;
    if (ms.isEmpty && nDec < 3 && intOk(f)) {
      // група 1 стоїть одразу після пробілів: її початок - довжина пробілів
      ms = [
        for (final m in finditer(r'^(\s*)(-?\d{2,5})(?=(\s?[₴sгrґаaзэЭ2z]\.?)?\s*$)', t))
          _M(m.start + m.group(1)!.length, m.start + m.group(1)!.length + m.group(2)!.length, m.group(2)!, '00')
      ];
    }
    if (ms.isEmpty) {
      ms = [for (final m in finditer(r'^\s*(\d{1,5})[.,](\d)(?=\s*[АБВAB]?\s*$)', t)) _M.of(m)];
      trunc = ms.isNotEmpty;
    }
    for (final m in ms) {
      final after = t.substring(m.end);
      if (after.trimLeft().startsWith('%')) continue;
      if (match(r'\s*\d{0,3}[^\W\d_]{2,}', after) != null &&
          match(r'\s*[гГ]?\s*[рРоО][нНиИ]', after) == null &&
          alphaCount(t.substring(0, m.start)) >= 2) {
        continue;
      }
      if (fullmatch(r'\s*(л|мл)\.?\s*', after) != null && alphaCount(t) <= 2) continue;
      var own = [
        for (final g in frags)
          if (!identical(g, f) && g.x < f.x && identical(owner[g], f) && (g.y + dyof(g) - f.y).abs() < 0.6 * pitch) g
      ];
      if (own.isNotEmpty) {
        final dmin = pyMin(own.map((g) => (g.y + dyof(g) - f.y).abs()));
        own = [for (final g in own) if ((g.y + dyof(g) - f.y).abs() <= dmin + 0.25 * pitch) g];
      }
      final left = '${own.map((g) => g.text).join(' ')} ${t.substring(0, m.start)}';
      final ml = fullmatch(r'\s*([АБВГДABабвгд8])\s*', after);
      final letter = ml != null ? ml.group(1)!.toUpperCase().replaceAll('A', 'А').replaceAll('B', 'В').replaceAll('8', 'В') : '';
      toks.add(_Tok(
        f,
        m.start,
        m.end,
        kop('${m.g1}.${m.g2}').abs(),
        f.lineId,
        left,
        trunc,
        letter,
        m.g1.startsWith('-') || t.substring(0, m.start).trimRight().endsWith('-'),
        has(_taxl, after) || const ['А', 'A', 'Б', 'В', '8'].contains(after.trim()),
        match(_unit + r'\s*([xхХX×*]\s*\d|[xхХX×]\s*$)', after) != null ||
            has(r'(?<![^\W\d_])(?<!#)[xхХX×*]\s*$', left),
      ));
    }
  }
  if (toks.isEmpty) {
    return [for (final f in frags) Labeled(f, 'SERV'), for (final f in handf) Labeled(f, f.hand!)];
  }
  final taxLines = [for (final t in toks) if (t.tax) ly[t.line]!];
  final firstTax = taxLines.isNotEmpty ? pyMin(taxLines) : pyMin(toks.map((t) => ly[t.line]!)) - 0.5 * pitch;
  final moneyRows = {for (final t in toks) t.line};
  double kwMax(String s, String lineText) =>
      math.max(math.max(sim(s, kwTotal), sim(s, kwPay)), isRate(lineText) ? sim(s, kwVat) : 0);
  final cand = [
    for (final k in lines.keys)
      if (!has(r'[З3][ІI1]?\s*ЗН[ИІ]?[ЖК]', ltext[k]!.toUpperCase()) &&
          ly[k]! > firstTax &&
          (moneyRows.contains(k) || moneyRows.contains(k + 1)) &&
          kwMax(ltext[k]!, ltext[k]!) >= 0.8)
        k
  ];
  final vm = [for (final t in toks) if (t.v < 10000000 && !t.factor) t.v];
  final vmax = pyMax(vm.isNotEmpty ? vm : toks.map((t) => t.v)).toInt();
  final kf = [
    for (final k in cand)
      for (final f in lines[k]!)
        if (kwMax(f.text, ltext[k]!) >= 0.8) f.y
  ];
  var yTot = (kf.isNotEmpty
          ? pyMin(kf)
          : cand.isNotEmpty
              ? pyMin(cand.map((k) => ly[k]!))
              : pyMax(frags.map((f) => f.y)) + pitch)
      .toDouble();
  final prods = <int, List<int>>{
    for (final e in ltext.entries)
      e.key: [
        for (final g in findallGroups(qpRe, e.value)) pyRound(kop(g[1]) * pyFloat(g[0].replaceAll(',', '.'))),
        for (final g in findallGroups(pqRe, e.value)) pyRound(kop(g[0]) * pyFloat(g[1].replaceAll(',', '.'))),
      ]
  };
  final cnt = <int, int>{};
  for (final t in toks) {
    cnt[t.v] = (cnt[t.v] ?? 0) + 1;
  }
  final tSet = <int>{vmax, for (final t in toks) if (sim(t.left, kwTotal) >= 0.7) t.v};

  for (final t in toks) {
    final dz = (t.f.y - yTot) / hmed;
    final xr = (t.f.xRight - x0) / math.max(1.0, x1 - x0);
    final rel = vmax != 0 ? t.v / vmax : 0.0;
    final near = [
      for (final k in prods.keys)
        if (prods[k]!.isNotEmpty &&
            -2.5 * hmed <= ly[t.line]! - ly[k]! &&
            ly[t.line]! - ly[k]! <= (t.trunc ? 2.5 : 0.5) * hmed)
          ly[k]!
    ];
    final errs = [
      for (final k in prods.keys)
        if (near.contains(ly[k]))
          for (final e in prods[k]!) (t.v - (t.trunc ? e - e % 10 : e)).abs()
    ];
    final qerr = errs.isNotEmpty && !t.factor ? pyMin(errs).toDouble() : 1e9;
    final kTot = sim(t.left, kwTotal);
    var kVat = sim(t.left, kwVat);
    final kDisc = sim(t.left, kwDisc);
    final kPay = sim(t.left, kwPay);
    var kComm = sim(t.left, kwComm);
    if (has(r'КОМІС|КОМИС', t.left.toUpperCase())) kComm = 1.0;
    if (has(r'\d{1,2}[.,]\d{2}\s*%', t.left)) kVat = math.max(kVat, 0.9);
    final kAny = [kTot, kVat, kDisc, kPay, kComm].reduce(math.max);
    final verr = t.v > 0
        ? pyMin([
            for (final tt in tSet)
              for (final r in const [20, 7]) (t.v - tt * r / (100 + r)).abs()
          ]).toDouble()
        : 1e9;
    final above = fall(dz, -0.6, 0.1);
    final inzone = rise(dz, -0.3, 0.3);
    final right = rise(xr, 0.6, 0.85);
    final big = rise(rel, 0.9, 1.0);
    final prod = fall(qerr, 0, 3);
    double kwLow(double k) => fall(k, 0.55, 0.8);
    double kwHigh(double k) => rise(k, 0.6, 0.85);
    final rep = rise(cnt[t.v]!.toDouble(), 1, 3);
    final vatfit = fall(verr, 0.5, 3);
    final tax = t.tax ? 1.0 : 0.0, fac = t.factor ? 1.0 : 0.0, neg = t.neg ? 1.0 : 0.0;
    final rest = [
      for (final g in lines[t.line]!)
        if (!identical(g, t.f) && has(r'\d', g.text) && fullmatch(r'\s*\d{1,3}\s*шт\.?\s*', g.text) == null) g
    ];
    var alone = rest.isEmpty &&
            sub(r'\s*(грн|ГРН|₴)\.?\s*$', '', t.f.text.trim()).length <= t.f.text.substring(t.a, t.b).length + 3
        ? 1.0
        : 0.0;
    if (alone > 0 &&
        !lines.keys.any((k) => 0 < ly[t.line]! - ly[k]! && ly[t.line]! - ly[k]! <= 1.9 * hmed && alphaCount(ltext[k]!) >= 2)) {
      alone = 0.0;
    }
    if (alone > 0 &&
        lines.keys.any((k) =>
            0 < ly[t.line]! - ly[k]! &&
            ly[t.line]! - ly[k]! <= 1.9 * hmed &&
            ['total', 'pay', 'vat', 'disc'].map((g) => sim(ltext[k]!, kw[g]!)).reduce(math.max) >= 0.8)) {
      alone = 0.0;
    }
    double mn(List<double> xs) => xs.reduce(math.min);
    double mx(List<double> xs) => xs.reduce(math.max);
    final rules = <Rule>[
      ('ITEM', 'висока', mn([above, tax, kwLow(kAny), 1 - fac, 1 - neg])),
      ('ITEM', 'середня', mn([above, right, kwLow(kAny), 1 - fac, 1 - neg])),
      ('ITEM', 'висока', mn([prod, 1 - neg])),
      ('ITEM', 'середня', mn([above, alone, kwLow(kAny), 1 - fac, 1 - neg])),
      ('ITEM', 'середня', mn([above, tax, 1 - fac, 1 - neg])),
      ('ITEM', 'низька', mx([inzone, math.min(kwHigh(kAny), 1 - tax), fac])),
      ('PRICE', 'висока', math.min(fac, 1 - prod)),
      ('PRICE', 'низька', 1 - fac),
      ('TOTAL', 'висока', mn([kwHigh(kTot), math.max(kwLow(kVat), 1 - vatfit), kwLow(kComm), rise(kTot - kPay, 0, 0.15), 1 - fac, 1 - 0.7 * tax])),
      ('TOTAL', 'середня', mn([inzone, big, rep, kwLow(kVat), 1 - tax])),
      ('TOTAL', 'низька', mx([above, kwHigh(kVat), fac, fall(t.v.toDouble(), 0, 1)])),
      ('VAT', 'висока', mn([kwHigh(kVat), kwLow(kDisc), 1 - big, math.max(kwLow(kTot), vatfit), rise(kVat - kPay, 0, 0.1),
        mx([1 - above, isRate(t.left) ? 1.0 : 0.0, vatfit])])),
      ('VAT', 'висока', mn([vatfit, inzone, 1 - big, kwLow(kPay)])),
      ('VAT', 'низька', math.max(math.min(kwLow(kVat), 1 - vatfit), big)),
      ('DISC', 'висока', math.max(kwHigh(kDisc), math.min(neg, kwLow(kPay)))),
      ('DISC', 'низька', math.min(kwLow(kDisc), 1 - neg)),
      ('SERV', 'висока', math.min(kwHigh(kPay), kwLow(kTot))),
      ('SERV', 'висока', kwHigh(kComm)),
      ('SERV', 'середня', mn([inzone, kwLow(kTot), kwLow(kVat), kwLow(kDisc)])),
      ('SERV', 'висока', fall(t.v.toDouble(), 0, 1)),
      ('SERV', 'середня', 0.3),
    ];
    t.mu = mamdani(rules, classes);
    t.role = maxBy(classes, (c) => t.mu[c]!);
    t.dz = dz;
    if (t.trunc) t.role = ((qerr <= 3 || t.tax) && dz < -0.5) ? 'ITEM' : 'SERV';
  }

  // «96,00 × 1 =» без окремої суми праворуч: ціна при кількості 1 і є сумою позиції
  for (final t in toks) {
    if (t.role != 'PRICE') continue;
    final txt = t.f.text;
    final m1 = match(r'\s*[xхХX×*]\s*1(?:[.,]0{1,3})?\s*(шт)?\s*=?\s*$', txt.substring(t.b));
    if (m1 == null) continue;
    final right = [
      for (final u in toks)
        if (!identical(u, t) && u.line == t.line && u.f.x > t.f.x && (u.role == 'ITEM' || u.role == 'PRICE')) u
    ];
    if (right.isEmpty || right.every((u) => (u.v - t.v).abs() < 1 && u.role == 'PRICE')) {
      t.role = 'ITEM';
      for (final u in right) {
        u.role = (u.v - t.v).abs() < 1 ? 'SERV' : u.role;
      }
    }
  }
  for (final t in toks) {
    final l = t.left.toUpperCase();
    if (t.role == 'DISC') continue;
    if (has(r'ЦІ[НА]А\s*(КГ|ЗА\s*(КГ|ОД)|З\s*ЗНИЖ|ЗІ)', l)) {
      t.role = 'PRICE';
    } else if (has(r'СУМА\s*[З3][ІI1]?\s*ЗН', l) && t.dz < -0.5) {
      t.role = 'SERV';
    }
  }
  for (final e in ltext.entries) {
    if (!has(r'-\s*\d{1,2}\s*%', e.value) || ly[e.key]! > yTot) continue;
    final lt = sortedBy([for (final t in toks) if (t.line == e.key) t], (t) => t.f.xLeft + t.a);
    for (final t in lt) {
      t.role = 'SERV';
    }
    if (lt.isNotEmpty) lt.last.role = 'DISC';
  }
  if (!toks.any((t) => t.role == 'TOTAL') && cand.isEmpty) {
    final mv = pyMax(toks.map((u) => u.v));
    for (final t in toks) {
      if (t.f.h >= 1.25 * hmed0 && t.v == mv) t.role = 'TOTAL';
    }
  }
  if (!toks.any((t) => t.role == 'TOTAL')) {
    for (final t in [for (final t in toks) if (t.dz > -0.5 && t.v == vmax && t.v > 0) t]) {
      t.role = 'TOTAL';
    }
  }
  final zone = [for (final t in toks) if (t.dz > -0.5 && t.v > 0) t];
  for (final t in zone) {
    for (final u in toks) {
      if (identical(u, t) || (u.f.y - t.f.y).abs() > 2.5 * pitch || u.factor) continue;
      if (u.v >= 5 * t.v &&
          pyMin([for (final r in const [20, 7]) (t.v - u.v * r / (100 + r)).abs()]) <= 1 &&
          const ['TOTAL', 'SERV', 'ITEM', 'VAT'].contains(u.role)) {
        t.role = 'VAT';
        t.zoneVat = true;
        if (u.role != 'TOTAL' && !(sim(u.left, kwPay) >= 0.8)) u.role = 'TOTAL';
      }
    }
  }
  final tvals = [for (final t in toks) if (t.role == 'TOTAL') t.v];
  if (tvals.isNotEmpty) {
    final bigT = maxBy(cpythonSetOrder(tvals), (v) => tvals.where((x) => x == v).length);
    final vatLab = [for (final g in frags) if (sim(g.text, kwVat) >= 0.8 || isRate(g.text)) g];
    for (final t in toks) {
      if (t.dz < -0.5 || !(0 < t.v && t.v < bigT) || t.role == 'DISC' || t.role == 'TOTAL') continue;
      final exact = pyMin([for (final r in const [20, 7]) (t.v - bigT * r / (100 + r)).abs()]) <= 2;
      if (!exact && (sim(t.left, kwPay) >= 0.8 || sim(t.left, kwComm) >= 0.8)) continue;
      final nearL = vatLab.any((g) => g.x < t.f.x && (g.y - t.f.y).abs() <= 1.3 * pitch);
      if (exact || nearL) {
        t.role = 'VAT';
        t.zoneVat = true;
      }
    }
  }
  final base = <String, int>{};
  for (final t in toks) {
    if (t.dz < -0.5 && (t.role == 'ITEM' || t.role == 'SERV') && t.v > 0 && t.letter.isNotEmpty && 'АБВГД'.contains(t.letter)) {
      base[t.letter] = (base[t.letter] ?? 0) + t.v;
    }
  }
  final rates = <int>{
    for (final r in findall1(r'(\d{1,2})(?:[.,]\d{2})?\s*%', ltext.values.join(' ')))
      if (0 < int.parse(asciiDigits(r)) && int.parse(asciiDigits(r)) < 30) int.parse(asciiDigits(r)),
    20,
    7
  };
  final expVat = base.length > 1
      ? [
          for (final b in base.values)
            for (final r in rates) pyRound(b * r / (100 + r))
        ]
      : <int>[];
  final vatLab2 = [for (final g in frags) if (sim(g.text, kwVat) >= 0.8 || isRate(g.text)) g];
  for (final t in toks) {
    if (t.dz < -0.5 || t.v <= 0 || const ['TOTAL', 'DISC', 'VAT'].contains(t.role)) continue;
    if (!vatLab2.any((g) => (g.y - t.f.y).abs() <= 3 * pitch && g.x < t.f.x)) continue;
    for (final e in expVat) {
      if ((t.v - e).abs() <= 2 || (e > t.v && '${t.v}'.length >= 3 && '$e'.endsWith('${t.v}'))) {
        t.role = 'VAT';
        t.zoneVat = true;
        break;
      }
    }
  }
  for (final t in toks) {
    final l = t.left.toUpperCase();
    if (has(r'ПДВ', l) && !has(r'БЕЗ\s*ПДВ', l) && t.role == 'TOTAL' && toks.any((u) => u.role == 'TOTAL' && u.v > t.v)) {
      t.role = 'VAT';
      t.zoneVat = true;
    }
  }
  final tv = {for (final t in toks) if (t.role == 'TOTAL') t.v};
  for (final t in toks) {
    if (t.role == 'SERV' && tv.contains(t.v) && t.v > 0 && sim(t.left, kwComm) < 0.8) t.role = 'TOTAL';
  }
  final tt = [
    for (final t in toks)
      if (t.role == 'TOTAL' &&
          t.f.y < yTot - 0.5 * hmed &&
          toks.any((u) => u.role == 'ITEM' && u.f.y < t.f.y - 0.5 * hmed))
        t.f.y
  ]..sort();
  if (tt.isNotEmpty) {
    yTot = tt[0];
    final tz = pyMax([for (final t in toks) if (t.role == 'TOTAL') t.v]).toInt();
    for (final t in toks) {
      t.dz = (t.f.y - yTot) / hmed;
      if (t.role == 'ITEM' && t.dz > -0.3) {
        final ok = const [20, 7].any((r) => (t.v - tz * r / (100 + r)).abs() <= 2 || oneDigit(t.v, pyRound(tz * r / (100 + r))));
        t.role = ok ? 'VAT' : 'SERV';
        if (ok) t.zoneVat = true;
      }
    }
  }
  for (final t in toks) {
    if (t.role == 'ITEM' && toks.any((u) => u.role == 'TOTAL' && u.line == t.line && u.v > t.v)) t.role = 'SERV';
  }
  for (final f in frags) {
    if (fullmatch(r'\s*\d{1,3}(?:[.,]\d{3})?\s*[ІI]?[xхХX×]\s*', f.text) == null || (f.y - yTot) / hmed > -0.5) continue;
    final c = [
      for (final t in toks)
        if (t.f.xLeft > f.xRight &&
            (t.f.y - f.y).abs() <= 1.0 * hmed &&
            !t.tax &&
            fullmatch(r'\s*\d{1,5}[.,]\d{2,3}\s*', t.f.text) != null)
          t
    ];
    if (c.isNotEmpty) minBy(c, (t) => (t.f.y - f.y).abs()).role = 'PRICE';
  }
  for (final t in toks) {
    if (t.role != 'ITEM' || t.tax || fullmatch(r'\s*\d{1,5}[.,]\d{2}\s*', t.f.text) == null) continue;
    final below = [
      for (final u in toks)
        if (!identical(u, t) && 1.5 * hmed < u.f.y - t.f.y && u.f.y - t.f.y <= 6 * hmed) u
    ];
    if (below.isNotEmpty) {
      final u = minBy(below, (u) => u.f.y);
      if ((u.role == 'ITEM' || u.role == 'PRICE') && u.tax && (u.v - t.v).abs() < 1) {
        t.role = 'PRICE';
        u.role = 'ITEM';
      }
    }
  }
  final tvList = [for (final t in toks) if (t.role == 'TOTAL') t.v];
  double cw(Frag f) => (f.xRight - f.xLeft) / math.max(1, f.text.trim().length);
  final cwMed = toks.isNotEmpty ? npMedian([for (final t in toks) cw(t.f)]) : 0.0;
  if (tvList.isNotEmpty) {
    final bigT = pyMax(tvList).toInt();
    for (final t in toks) {
      if (t.role != 'ITEM' || t.v != bigT) continue;
      var others = 0;
      for (final u in toks) {
        if (u.role == 'ITEM' && !identical(u, t)) others += u.v;
      }
      final nearPay = lines.keys.any((k) => (ly[k]! - ly[t.line]!).abs() <= 1.5 * hmed && sim(ltext[k]!, kwPay) >= 0.8) &&
          lines.keys
                  .where((k) =>
                      1.5 * hmed < ly[t.line]! - ly[k]! && ly[t.line]! - ly[k]! <= 6 * hmed && sim(ltext[k]!, kwPay) >= 0.8)
                  .length >=
              2;
      final lowest = toks.where((u) => u.role == 'ITEM' && !identical(u, t)).every((u) => u.f.y < t.f.y);
      if ((others != 0 && (others - bigT).abs() <= 2) || nearPay || (others > 0 && lowest && cw(t.f) >= 1.4 * cwMed)) {
        t.role = 'TOTAL';
      }
    }
  }
  // текстові частини: назва чи службове
  final itemY = [for (final t in toks) if (t.role == 'ITEM' || (t.role == 'PRICE' && t.dz < -0.5)) t.f.y]..sort();
  itemY.addAll([
    for (final f in frags)
      if (fullmatch(r'\s*\d{1,3}\s*', f.text) != null &&
          (f.xRight - x0) / math.max(1.0, x1 - x0) > 0.8 &&
          (f.y - yTot) / hmed < -0.5 &&
          frags.any((g) => (g.y - f.y).abs() < 0.5 * pitch && alphaCount(g.text) >= 6))
        f.y
  ]);
  itemY.sort();
  final lineRoles = <int, Set<String>>{};
  for (final t in toks) {
    lineRoles.putIfAbsent(t.line, () => {}).add(t.role);
  }
  final priceY = [for (final t in toks) if (t.role == 'PRICE' && t.dz < -0.5) t.f.y];
  final allY = ly.values.toList()..sort();
  final gmed = allY.length > 2 ? npMedian([for (var i = 0; i + 1 < allY.length; i++) allY[i + 1] - allY[i]]) : hmed;
  bool contiguous(double ya, double yb) {
    final ys = [ya, for (final v in allY) if (ya < v && v < yb) v, yb];
    for (var i = 0; i + 1 < ys.length; i++) {
      if (!(ys[i + 1] - ys[i] <= math.max(1.7 * gmed, 1.5 * hmed0))) return false;
    }
    return true;
  }

  final itemYs = [for (final t in toks) if (t.role == 'ITEM') t.f.y];
  final lastItem = itemYs.isNotEmpty ? pyMax(itemYs).toDouble() : -1e9;
  final yTot2 = pyMin([yTot, for (final t in toks) if (t.role == 'TOTAL' && t.f.y > lastItem) t.f.y]).toDouble();

  final fio = <int>{};
  final ls = sortedBy(lines.keys, (k) => ly[k]!);
  List<Frag> lw(int k) => [for (final g in lines[k]!) if (alphaCount(g.text) >= 2) g];
  bool oneW(int k) {
    final w = lw(k);
    return w.length == 1 && !moneyRows.contains(k) && fullmatch(r"\s*[А-ЯІЇЄҐ][а-яіїєґ']{3,}\s*", w[0].text) != null;
  }

  for (var i = 0; i + 2 < ls.length; i++) {
    final run = ls.sublist(i, i + 3);
    if (run.every(oneW) && ly[run[2]]! - ly[run[0]]! <= 2.6 * pitch) fio.addAll(run);
  }

  (String, Map<String, double>) textClass(String txt, int line, [double? fx, double? fh]) {
    final fxv = fx ?? -1e9;
    final s = sub(r'\s', '', txt);
    final letters = alphaCount(s) / math.max(1, s.length);
    final dz = (ly[line]! - yTot2) / hmed;
    final y = ly[line]!;
    final nxt = [for (final iy in itemY) if (iy - y >= -1.2 * hmed) (iy - y) / hmed];
    final prv = [for (final iy in itemY) if (iy - y < -1.2 * hmed) iy];
    var d = nxt.isNotEmpty ? minBy(nxt, (v) => v.abs()) : 99.0;
    d = d < 0 ? d.abs() : d;
    if (0 < d && d < 99 && !contiguous(y, y + d * hmed)) d = 99;
    if (priceY.any((py) => 0 < y - py && y - py <= 3.5 * hmed)) d = math.min(d, 0.5);
    final lim = prv.isNotEmpty ? 6.0 : 4.5;
    var kSrv = sim(txt, kwServ);
    if (fx != null) {
      kSrv = math.max(kSrv, sim(lines[line]!.where((g) => g.x < fx).map((g) => g.text).join(' '), kwServ));
    }
    if (!moneyRows.contains(line) &&
        match(r'\s*[А-ЯІЇЄҐ][а-яіїєґ]+(івна|ївна|овна|ович|йович|івич)', txt) != null &&
        lines.keys.any((k) => 0 < ly[line]! - ly[k]! && ly[line]! - ly[k]! <= 1.3 * pitch && sim(ltext[k]!, _kwKasyr) >= 0.85)) {
      kSrv = math.max(kSrv, 0.9);
    }
    final kAll = ['total', 'vat', 'disc', 'pay', 'comm'].map((g) => sim(txt, kw[g]!)).reduce(math.max);
    const none = <String, double>{};
    if (fio.contains(line)) return ('SERV', none);
    if (isPerson(txt)) return ('SERV', none);
    final up = txt.toUpperCase();
    if (has(r'\bВІДД?\.|\bАЗ[СК]\b|\bКАСА\s*\d', up)) return ('SERV', none);
    if (has(r'VISA|CONTACTLESS|MASTER\s*CARD|MAESTRO|ПРОСТІР', up)) return ('SERV', none);
    if (has(r'БАЖАЄМ|ДЯКУЄМ|ГАРНОГО ДНЯ|ЧЕКАЄМО', up)) return ('SERV', none);
    if (dz < 0 &&
        (has(r'^\s*УКР\S{2,4}НА\s*,|\bОБЛ\b\.?\s*,|^\s*ПР\.\s?[А-ЯІЇЄ]|\bВУЛ\.|ПРОСПЕКТ|БУЛЬВАР|\bБУД\.', up) ||
            has(r'\bм\.\s?[А-ЯІЇЄ][а-яіїє]{3,}', txt))) {
      return ('SERV', none);
    }
    if (has(r'КОМІС|КОМИС', up)) return ('SERV', none);
    if (has(r'БЕЗГОТ|ГОТІВК|КАРТК', up)) return ('SERV', none);
    if (has(r'https?:|www\.|\.(ua|com|net)\b|/\w+/', txt)) return ('SERV', none);
    if (has(r'[З3][ІI1]?\s*ЗН[ИІ]?[ЖК]', up) && dz < 0) return ('SERV', none);
    if (has(r'-\s*\d{1,2}\s*%', txt) && dz < 0) return ('DISC', none);
    final order = has(r'ПДВ', up) && !has(r'БЕЗ\s*ПДВ', up)
        ? const [('vat', 'VAT'), ('total', 'TOTAL'), ('disc', 'DISC')]
        : const [('total', 'TOTAL'), ('disc', 'DISC'), ('vat', 'VAT')];
    for (final (g, c) in order) {
      var kk = sim(txt, kw[g]!);
      if (g == 'vat' && isRate(txt)) kk = 1.0;
      if (kk >= 0.75 &&
          ((lineRoles[line]?.contains(c) ?? false) ||
              toks.any((t) => t.role == c && t.f.x > fxv && (t.f.y - ly[line]!).abs() <= 1.3 * pitch))) {
        return (c, none);
      }
    }
    if (alphaCount(s) < 2) return ('SERV', none);
    var let = rise(letters, 0.4, 0.7);
    final nlet = alphaCount(s);
    if (letters >= 0.3 &&
        !has(r'\d{7,}', s) &&
        has(r'[^\W\d_]{4,}', txt) &&
        priceY.any((py) => 0 < y - py && y - py <= 3.5 * hmed)) {
      let = math.max(let, rise(nlet.toDouble(), 4, 7));
    }
    if (fh != null && fh < 0.6 * hmed0) let = 0.0;
    final nearB = fall(d, lim - 1.5, lim);
    final above = fall(dz, -0.6, 0.1);
    final rules = <Rule>[
      ('NAME', 'висока', [let, nearB, above, fall(kSrv, 0.6, 0.85), fall(kAll, 0.6, 0.85)].reduce(math.min)),
      ('NAME', 'середня', [let, fall(d, lim, lim + 1.5), above, fall(kSrv, 0.6, 0.85)].reduce(math.min)),
      ('NAME', 'низька', [1 - above, rise(kSrv, 0.7, 0.9), 1 - nearB].reduce(math.max)),
      ('SERV', 'висока', math.max(rise(kSrv, 0.7, 0.9), rise(kAll, 0.7, 0.9))),
      ('SERV', 'середня', [1 - above, 1 - let, 1 - nearB].reduce(math.max)),
      ('SERV', 'середня', 0.3),
    ];
    final mu = mamdani(rules, nameClasses);
    return (maxBy(nameClasses, (c) => mu[c]!), mu);
  }

  Frag part(Frag f, int a, int b) {
    final n = math.max(1, f.text.length);
    final w = f.xRight - f.xLeft;
    return f.copy(xLeft: f.xLeft + w * a / n, xRight: f.xLeft + w * b / n, text: f.text.substring(a, b));
  }

  const qtyL = r'(?<![\d.,*])\d{1,4}(?:[.,]\d{1,3})?(?=' + _unit + r'\s*([xхХX×]\s*\d+(?:[.,]\d|\s|$)|\*\s*\d+[.,]\d{2}))';

  final byF = HashMap<Frag, List<_Tok>>.identity();
  for (final t in toks) {
    byF.putIfAbsent(t.f, () => []).add(t);
  }
  var out = <Labeled>[];
  final qxRows = <Frag>[];
  for (final f in frags) {
    final txt = f.text;
    final segs = <(int, int, String, Map<String, double>)>[];
    for (final t in byF[f] ?? const <_Tok>[]) {
      var role = t.role;
      if (t.zoneVat) {
        segs.add((t.a, t.b, 'VAT', t.mu));
        continue;
      }
      if (role == 'PRICE' && match(_unit + r'\s*[xхХX×*]\s*\d+[.,]\d{2}(?!\d)', txt.substring(t.b)) != null) role = 'QTY';
      segs.add((t.a, t.b, role, t.mu));
    }
    var spans = <(int, int)>[
      for (final m in finditer(qtyL, txt)) (m.start, m.end),
      for (final m in finditer(_pqSpan, txt))
        (m.start + m.group(1)!.length, m.start + m.group(1)!.length + m.group(3)!.length),
    ];
    final mq = fullmatch(r'(\s*)(' + _num + r')' + _unit + r'\s*=?\s*', txt);
    if (mq != null &&
        has(r'(?<![^\W\d_])(?<![#*])[xхХX×](?![^\W\d_])|\d\s*\*\s*\d', sub(r'\d+\s*\*\s*\d+\s*\*\s*\d+', '', ltext[f.lineId]!))) {
      spans.add((mq.group(1)!.length, mq.end));
    }
    (int, int) g2(RegExpMatch m) => (m.group(1)!.length, m.group(1)!.length + m.group(2)!.length);
    final ms = match(r'(\s*)(\d{1,3}(?:[.,]\d{1,3})?)\s+-\s+(шт|\d)', txt);
    if (ms != null) spans.add(g2(ms));
    final mq2 = fullmatch(r'(\s*)(\d{1,3})\s*шт\.?\s*', txt);
    if (mq2 != null) spans.add(g2(mq2));
    final mq3 = fullmatch(r'(\s*)(\d{1,3}(?:[.,]\d{3})?)\s*[ІI]?[xхХX×]\s*', txt);
    if (mq3 != null &&
        (byF[f] ?? const []).isEmpty &&
        (toks.any((t) =>
                (t.role == 'PRICE' || t.role == 'ITEM') &&
                t.f.xLeft > f.xRight &&
                (t.f.y - f.y).abs() <= (t.role == 'PRICE' ? 1.0 : 0.6) * hmed) ||
            frags.any((q) =>
                q.xLeft > f.xRight &&
                (q.y - f.y).abs() <= 0.6 * hmed &&
                fullmatch(r'\s*\d{1,5}[.,]\d{2,3}\s*', q.text) != null))) {
      spans.add(g2(mq3));
      qxRows.add(f);
    }
    if (has(r'\d\s*(см|мм)\b', txt)) {
      final keep = ms != null ? ms.group(1)!.length : -1;
      spans = [for (final sp in spans) if (sp.$1 == keep) sp];
    }
    if ((f.y - yTot) / hmed > -0.3) spans = [];
    for (final (a, b) in spans) {
      if (!segs.any((s) => a < s.$2 && b > s.$1)) segs.add((a, b, 'QTY', const {}));
    }
    final sortedSegs = sortedBy(segs, (s) => _SegKey(s.$1, s.$2, s.$3));
    if (sortedSegs.isEmpty) {
      final right = [for (final t in toks) if (t.f.xLeft > f.xRight && (t.f.y - f.y).abs() <= 0.8 * hmed) t];
      if (f.conf < 0.5 && right.isNotEmpty && minBy(right, (t) => (t.f.y - f.y).abs()).role == 'TOTAL') {
        out.add(Labeled(f, 'TOTAL'));
        continue;
      }
      final (c, mu) = textClass(txt, f.lineId, f.x, f.h);
      out.add(Labeled(f, c, mu));
      continue;
    }
    var pos = 0;
    for (final (a, b, c, mu) in [...sortedSegs, (txt.length, txt.length, '', const <String, double>{})]) {
      final gap = a > pos ? txt.substring(pos, a) : '';
      if (gap.trim().isNotEmpty) {
        if (fullmatch(r'\s*(кг|КГ|Кг|л|Л|г|шт)?\.?\s*[xхХX×*=]?\s*', gap) != null) {
          out.add(Labeled(part(f, pos, a), 'SERV'));
        } else if (c == 'DISC' && pos == 0) {
          out.add(Labeled(part(f, pos, a), 'DISC'));
        } else if (alphaCount(gap) >= 3) {
          final (gc, gmu) = textClass(gap, f.lineId, f.x, f.h);
          out.add(Labeled(part(f, pos, a), gc, gmu));
        } else {
          out.add(Labeled(part(f, pos, a), 'SERV'));
        }
      }
      if (c.isNotEmpty) out.add(Labeled(part(f, a, b), c, mu));
      pos = math.max(pos, b);
    }
  }
  if (qxRows.isNotEmpty) {
    out = [
      for (final l in out)
        () {
          final row = [
            for (final q in qxRows)
              if (!identical(q, l.f) && (q.y - l.f.y).abs() <= 0.6 * hmed && l.f.xLeft > q.xRight) q
          ];
          if (l.cls == 'QTY' && row.isNotEmpty && !qxRows.any((q) => identical(q, l.f))) {
            return Labeled(l.f, fullmatch(r'\s*\d{1,5}[.,]\d{2,3}\s*', l.f.text) != null ? 'PRICE' : 'SERV', l.mu);
          }
          return l;
        }()
    ];
  }
  final lcls = <int, Set<String>>{};
  for (final l in out) {
    if (!l.f.virtual && alphaCount(l.f.text) >= 2) lcls.putIfAbsent(l.f.lineId, () => {}).add(l.cls);
  }
  bool servLine(int k) {
    final tx = ltext[k]!;
    final lc = lcls[k];
    return lc != null &&
        lc.length == 1 &&
        lc.first == 'SERV' &&
        alphaCount(tx) >= 8 &&
        alphaCount(tx) >= 0.6 * tx.replaceAll(' ', '').length &&
        !has(r'ШК|ШТРИХ|КОД', tx.toUpperCase());
  }

  final anc = [for (final t in toks) if (t.role == 'ITEM' || t.role == 'PRICE' || t.role == 'QTY') t.f.y];
  out = [
    for (final l in out)
      () {
        if (l.cls == 'NAME' && !l.f.virtual) {
          final y = ly[l.f.lineId]!;
          final below = [for (final a in anc) if (a > y + 0.5 * hmed) a];
          if (below.isNotEmpty && !anc.any((a) => (a - y).abs() <= 0.5 * hmed)) {
            final a = pyMin(below);
            if (lines.keys.any((k) => y < ly[k]! && ly[k]! < a - 0.5 * hmed && servLine(k))) return Labeled(l.f, 'SERV', l.mu);
          }
        }
        return l;
      }()
  ];
  final prev = out;
  out = [
    for (final l in prev)
      () {
        var c = l.cls;
        final f = l.f;
        if (c == 'SERV' &&
            !f.virtual &&
            (f.y - yTot) / hmed < -0.3 &&
            has(r'\d+\s*\*\s*\d+|\d\s*(см|мм|мл|кг|г|л)\b', f.text, i: true) &&
            !has(moneyRe, f.text) &&
            !has(r'\d{6,}', f.text) &&
            prev.any((o) =>
                o.cls == 'NAME' &&
                !identical(o.f, f) &&
                (o.f.y - f.y).abs() <= 0.5 * hmed &&
                -0.5 * (o.f.xRight - o.f.xLeft) < f.xLeft - o.f.xRight &&
                f.xLeft - o.f.xRight < f.h)) {
          c = 'NAME';
        }
        if (c == 'SERV' &&
            !f.virtual &&
            (f.y - yTot) / hmed < -0.3 &&
            fullmatch(r'\s*\d{1,4}(?:[.,]\d{1,3})?\s*(л|мл|кг|г|шт)\.?\s*', f.text) != null &&
            prev.any((o) =>
                o.cls == 'NAME' &&
                0.5 * hmed < f.y - o.f.y &&
                f.y - o.f.y <= 1.6 * hmed &&
                (o.f.xLeft - f.xLeft).abs() < 1.5 * f.h)) {
          c = 'NAME';
        }
        return c == l.cls ? l : Labeled(f, c, l.mu);
      }()
  ];
  final anc0 = [
    for (final t in toks)
      if ((t.role == 'ITEM' || t.role == 'PRICE' || t.role == 'QTY') && t.dz < -0.5) t.f.y
  ];
  if (anc0.isNotEmpty) {
    final ya = pyMin(anc0);
    final hdr = [
      for (final k in lines.keys)
        if (ly[k]! < ya - 0.5 * hmed &&
            match(r'\s*(К[АA][СCЗ][АAИ]|КАСИР|ЧЕК\b|ЧЕК\s*[№N#]|ПН\b|ПН\s*\d|І[ДD]\b|ФН\b|ЗН\b)', ltext[k]!.toUpperCase()) != null)
          ly[k]!
    ];
    out = [
      for (final l in out)
        l.cls == 'NAME' && hdr.any((y) => l.f.y + 0.5 * hmed < y) ? Labeled(l.f, 'SERV', l.mu) : l
    ];
  }
  final names = [for (final l in out) if (l.cls == 'NAME' && !l.f.virtual) l.f];
  final screen = [...frags, ...other].any((f) => match(r'\s*\d{1,2}:\d{2}(?!\d)', f.text) != null && f.y < 0.08 * (f.imgH ?? 2400));
  final pic = Set<Frag>.identity()
    ..addAll([
      for (final f in names)
        if (screen &&
            sub(r'\s', '', f.text).length <= 10 &&
            names.any((g) =>
                !identical(g, f) &&
                g.text.length >= 12 &&
                g.xLeft > f.xRight + 1.0 * f.h &&
                0.5 * pitch < (g.y - f.y).abs() &&
                (g.y - f.y).abs() <= 3 * pitch))
          f
    ]);
  if (pic.isNotEmpty) out = [for (final l in out) pic.contains(l.f) ? Labeled(l.f, 'SERV', l.mu) : l];
  final nl = [
    for (final l in out)
      if (has(r'НЕ\s*ОПОД|НЕОПОД', l.f.text.toUpperCase()) && has(r'ПДВ|ПАВ|ПЛВ', l.f.text.toUpperCase())) l.f
  ];
  if (nl.isNotEmpty) {
    out = [
      for (final l in out)
        (nl.any((q) => identical(q, l.f)) ||
                nl.any((q) =>
                    (l.f.y - q.y).abs() < 0.6 * pitch &&
                    l.f.xLeft > q.xRight &&
                    has(r'\d', l.f.text) &&
                    !has(r'[^\d\s.,АБВГДабвгд]', l.f.text.trim())))
            ? Labeled(l.f, 'VAT', l.mu)
            : l
    ];
    for (final q in nl) {
      if (out.any((l) => l.cls == 'VAT' && !identical(l.f, q) && (l.f.y - q.y).abs() < 0.6 * pitch)) continue;
      final zc = [
        for (var i = 0; i < out.length; i++)
          if (out[i].cls == 'SERV' &&
              out[i].f.xLeft > q.xRight &&
              (out[i].f.y - q.y).abs() <= 1.4 * pitch &&
              fullmatch(r'\s*1?0[.,][\d\s]*', out[i].f.text) != null)
            i
      ];
      if (zc.isNotEmpty) {
        final i = minBy(zc, (i) => (out[i].f.y - q.y).abs());
        out[i] = Labeled(out[i].f, 'VAT', out[i].mu);
      }
    }
  }
  final pdv = [
    for (final l in out)
      if (!l.f.virtual && match(r'\s*П[ДД]?[ВB]\s*[АБВГДABабвгд]?\s*=?\s*\d{1,2}([.,]\d{2})?\s*[%8]', l.f.text, i: true) != null) l.f
  ];
  final vatV = [for (final l in out) if (l.cls == 'VAT' && has(moneyRe, l.f.text) && l.f.x > (x0 + x1) / 2) l.f];
  final relab = <String>{};
  for (final l in out) {
    final f = l.f;
    if (f.virtual || f.x > (x0 + x1) / 2 || (f.y - yTot) / hmed < -0.5) continue;
    final k = _yKey(f);
    final up = f.text.toUpperCase();
    if (match(r'\s*ПДВ\s*[АБВГДAB]\b', up) != null && isRate(f.text)) {
      relab.add(k);
    } else if ((l.cls == 'SERV' || l.cls == 'VAT') &&
        vatV.any((v) => (v.y - f.y).abs() < 0.6 * pitch) &&
        pdv.any((p) =>
            !identical(p, f) &&
            0.5 * hmed < (p.y - f.y).abs() &&
            (p.y - f.y).abs() <= 1.3 * pitch &&
            (p.xLeft - f.xLeft).abs() < 2 * f.h) &&
        !has(_kwReTot, up) &&
        has(r'\d', f.text)) {
      relab.add(k);
    }
  }
  if (relab.isNotEmpty) {
    out = [for (final l in out) !l.f.virtual && relab.contains(_yKey(l.f)) ? Labeled(l.f, 'VAT', l.mu) : l];
  }
  var virt = <Labeled>[];
  if (handf.isEmpty && !out.any((l) => l.cls == 'ITEM' || l.cls == 'QTY') && out.where((l) => l.cls == 'NAME').length < 2) {
    final tvv = [for (final t in toks) if (t.role == 'TOTAL' && t.v > 0) t];
    if (tvv.isNotEmpty) {
      final vs = {for (final t in tvv) t.v};
      final bigT = maxByTuple(vs, (v) => [tvv.where((t) => t.v == v).length, v]);
      out = [for (final l in out) l.cls == 'NAME' || l.cls == 'PRICE' ? Labeled(l.f, 'SERV', l.mu) : l];
      virt = [Labeled(Frag.virtualItem(shopName([...frags, ...other]), bigT / 100), 'ITEM')];
    }
  }
  if (handf.isNotEmpty) {
    final yH = pyMax(handf.map((f) => f.y));
    out = [
      for (final l in out)
        (l.cls != 'SERV' && l.cls != 'OTHER' && l.f.y < yH) ? Labeled(l.f, 'SERV', l.mu) : l
    ];
  }
  return [...out, ...virt, for (final f in handf) Labeled(f, f.hand!), for (final f in other) Labeled(f, 'OTHER')];
}

class _SegKey implements Comparable<_SegKey> {
  final int a, b;
  final String c;
  _SegKey(this.a, this.b, this.c);
  @override
  int compareTo(_SegKey o) {
    if (a != o.a) return a.compareTo(o.a);
    if (b != o.b) return b.compareTo(o.b);
    return c.compareTo(o.c);
  }
}

// ------------------------------------------------------------- квитанція НБУ

const _coinItem = ['SERV', 'SERV', 'QTY', 'PRICE', 'ITEM'];
const _coinTot = ['SERV', 'SERV', 'TOTAL', 'SERV', 'VAT'];

Map<Frag, String>? coinBlocks(List<Frag> frags) {
  final txt = frags.map((f) => f.text.toUpperCase()).join(' ');
  if (!(has(r'НОМІНАЛ', txt) && has(r'ПРОДАЖ', txt) && has(r'НУМІЗМАТ|МЕТАЛ|МВТАЛ', txt))) return null;
  final h = npMedian([for (final f in frags) f.h]);
  final xmid = npMedian([for (final f in frags) f.x]);
  bool num(Frag f) => fullmatch(r'\s*"?\d{1,6}(?:[.,]\d{1,3})?\s*', f.text) != null && f.xLeft > xmid;
  final hdr = [for (final f in frags) if (has(r'ЗАМ.?ВЛЕННЯ|КВ.?.?ТАНЦ', f.text.toUpperCase())) f.y];
  final yH = hdr.isNotEmpty ? pyMax(hdr).toDouble() : -1e9;
  var starts = [
    for (final f in frags)
      if (match(r'\s*\d{1,2}(\s?\.\s?|\s)\S', f.text) != null && f.xLeft < xmid && !num(f) && f.y > yH) f.y
  ]..sort();
  final tot = [for (final f in frags) if (has(r'У\s*ТОМУ\s*ЧИСЛ|УСЬОГО', f.text.toUpperCase())) f.y];
  if (starts.isEmpty || tot.isEmpty) return null;
  final yTot = pyMin(tot).toDouble();
  starts = [for (final s in starts) if (s < yTot) s];
  if (starts.isEmpty) return null;
  const lab = r'М[ЕВ]ТАЛ|НОМІН|КІЛЬК|ЦІНА|ПРОДАЖ|СУМА|ВАРТ|ГРН|ШТ';
  final cls = LinkedHashMap<Frag, String>.identity();
  final bounds = [...starts, yTot];
  for (var i = 0; i + 1 < bounds.length; i++) {
    final b0 = bounds[i], b1 = bounds[i + 1];
    final inb = [for (final f in frags) if (b0 - 0.4 * h <= f.y && f.y < b1 - 0.4 * h) f];
    final labY = [for (final f in inb) if ((has(lab, f.text, i: true) && f.x < xmid) || num(f)) f.y];
    final yL = labY.isNotEmpty ? pyMin(labY).toDouble() : b1;
    for (final f in inb) {
      cls[f] = f.y < yL - 0.4 * h && !num(f) ? 'NAME' : 'SERV';
    }
    final vals = sortedBy([for (final f in inb) if (num(f)) f], (f) => f.y);
    if (vals.length == _coinItem.length) {
      for (var j = 0; j < vals.length; j++) {
        cls[vals[j]] = _coinItem[j];
      }
    } else if (vals.isNotEmpty) {
      cls[vals.last] = 'ITEM';
      if (vals.length >= 2 && _prefix(vals[vals.length - 2].text, 3) == _prefix(vals.last.text, 3)) {
        cls[vals[vals.length - 2]] = 'PRICE';
      }
    }
  }
  final ends = [for (final f in frags) if (has(r'ЗАГАЛЬНА|ПАКУВАЛЬН', f.text.toUpperCase()) && f.y > yTot) f.y];
  final yEnd = ends.isNotEmpty ? pyMin(ends).toDouble() : yTot + 8 * h;
  final tb = [for (final f in frags) if (yTot - 0.4 * h <= f.y && f.y < yEnd - 0.4 * h) f];
  for (final f in tb) {
    final t = f.text.toUpperCase();
    cls[f] = has(r'У\s*ТОМУ\s*ЧИСЛ|УСЬОГО', t)
        ? 'TOTAL'
        : (has(r'ПДВ', t) && !has(r'Б.З', t)
            ? 'VAT'
            : (has(r'ПРОДАЖ|НОМАЖ', t) && !has(r'Б.З|ПДВ', t) ? 'TOTAL' : 'SERV'));
  }
  final vals = sortedBy([for (final f in tb) if (num(f)) f], (f) => f.y);
  if (vals.length == _coinTot.length) {
    for (var j = 0; j < vals.length; j++) {
      cls[vals[j]] = _coinTot[j];
    }
  } else {
    final labs = [for (final f in tb) if (!num(f) && f.x < xmid) f];
    for (final f in vals) {
      if (labs.isNotEmpty) cls[f] = cls[minBy<Frag>(labs, (g) => (g.y - f.y).abs())]!;
      if (cls[f] == 'TOTAL' && has(r'У\s*ТОМУ|УСЬОГО', minBy<Frag>(labs, (g) => (g.y - f.y).abs()).text.toUpperCase())) {
        cls[f] = 'SERV';
      }
    }
    final v = HashMap<Frag, int>.identity();
    for (final f in vals) {
      if (has(r'\d[.,]\d{2}', f.text)) {
        final s = _prefix(sub(r'[^\d.,]', '', f.text), 12);
        v[f] = kop(s.isEmpty ? '0' : s);
      }
    }
    for (final a in vals) {
      for (final b in vals) {
        if (v.containsKey(a) && v.containsKey(b) && !identical(a, b) && v[a]! < v[b]!) {
          final tot2 = [for (final g in vals) if (v.containsKey(g) && v[g] == v[a]! + v[b]!) g];
          if (tot2.isNotEmpty) {
            cls[a] = 'VAT';
            cls[b] = 'SERV';
            for (final g in tot2) {
              cls[g] = 'TOTAL';
            }
          }
        }
      }
    }
  }
  return cls;
}

String _prefix(String s, int n) => s.length <= n ? s : s.substring(0, n);

// ----------------------------------------------------------- пошта, залізниця

const _rail = r'\bКР[З3]АЛ[ІI]|КВИТ\S*.*\|\s*ВІД\s+[А-ЯІЇЄ]{3,}[^|]*\|\s*ДО\s+[А-ЯІЇЄ]{3,}';
const _post = r'ПОШТА"?\s*ЗА\s*ЕН|УКРПОШТ|НОВА\s*ПОШТ|НОВАП[ЕА]Й|НОВА\s*П[ЕА]Й|NOVA\s*POSHTA|MEEST|У?/?КРЗАЛІЗНИЦ';
const _carriers = [
  (r'УКРПОШТ', 'Укрпошта'),
  (r'У?/?КРЗАЛІЗНИЦ|\bКР[З3]АЛ[ІI]', 'Квиток Укрзалізниці'),
  (r'MEEST', 'Meest'),
  (r'НОВА\s*ПОШТ|ПОШТА"?\s*ЗА\s*ЕН|НОВАП[ЕА]Й|НОВА\s*П[ЕА]Й|NOVA\s*POSHTA', 'Нова пошта'),
];

List<Labeled> postal(List<Labeled> out, List<Frag> frags) {
  final txt = sortedBy(frags, (f) => f.y).map((f) => f.text).join(' | ').toUpperCase();
  if (!has(_post, txt) && !has(_rail, txt)) return out;
  var name = 'Квиток Укрзалізниці';
  for (final (rx, n) in _carriers) {
    if (has(rx, txt)) {
      name = n;
      break;
    }
  }
  final tv = <int>[];
  for (final l in out) {
    if (l.cls == 'TOTAL') {
      for (final m in finditer(moneyRe, l.f.text)) {
        tv.add(kop('${m.group(1)}.${m.group(2)}'));
      }
    }
  }
  final pos = [for (final v in tv) if (v > 0) v];
  final res = [
    for (final l in out)
      if (!l.f.virtual) const ['ITEM', 'QTY', 'PRICE', 'NAME'].contains(l.cls) ? Labeled(l.f, 'SERV', l.mu) : l
  ];
  if (pos.isNotEmpty) {
    final t = maxByTuple(pos.toSet(), (v) => [pos.where((x) => x == v).length, v]);
    res.add(Labeled(Frag.virtualItem(name, t / 100), 'ITEM'));
  }
  return res;
}

const _banks = [
  (r'ПРИВАТ\s*БАНК|PRIVAT\s*BANK', 'ПриватБанк'),
  (r'\bПУМ[Б6B]\b|FUIB', 'ПУМБ'),
  (r'МОНО\s*БАНК|MONOBANK', 'monobank'),
  (r'ОЩАД\s*БАНК', 'Ощадбанк'),
  (r'\bА-?\s*БАНК', 'А-Банк'),
];
const _notShop =
    r'ФОП|ФО-П|ТОВ|ПРАТ|\bАТ\b|РНОК|ЕДРПОУ|ЄДРПОУ|ІПН|\bПН\b|\bІД\b|\bФН\b|\bЗН\b|ВУЛ|\bМ\.|ОБЛ|БУД|ПР-Т|ПРОСП|РАЙОН|Р-Н|ЧЕК|КАС[АИ]|ТЕЛ|БАНК|ПУМ[Б6B]|ОЩАД|МОНО';

/// Назва для чека без позицій: «Магазин X» -> X; інакше перший рядок шапки, що
/// не є ФОП/ТОВ, кодом, адресою чи банком; інакше назва банку; інакше «Оплата послуг».
String shopName(List<Frag> frags) {
  var top = sortedBy(frags, (f) => f.y);
  if (top.isEmpty) return 'Оплата послуг';
  final y0 = top.first.y, y1 = top.last.y;
  top = [for (final f in top) if (f.y <= y0 + 0.35 * (y1 - y0)) f].take(10).toList();
  String nice(String t) => pySplit(t).map((w) => isUpper(w) && w.length > 3 ? capitalize(w) : w).join(' ');
  for (final f in top) {
    final m = search(r'МАГАЗ[ИІ]Н\s+["«]?([^"»]{3,})["»]?', f.text, i: true);
    if (m != null && !has(r'\d{3,}', m.group(1)!)) return nice(m.group(1)!.trim());
  }
  for (final f in top) {
    final t = f.text.trim();
    if (alphaCount(t) >= 5 && !has(_notShop, t.toUpperCase()) && !has(r'\d{4,}|[,:]', t) && f.conf >= 0.85) return nice(t);
  }
  for (final f in top) {
    for (final (rx, n) in _banks) {
      if (has(rx, f.text.toUpperCase())) return n;
    }
  }
  return 'Оплата послуг';
}

String _key3(Frag f) => '${f.boxId}|${f.xLeft}|${f.y}';

/// Розмітка фрагментів одного чека. Повертає фрагменти (чи їх частини) з
/// класами; позиція без рядка в чеку (чек оплати, пошти) - віртуальний фрагмент.
List<Labeled> label(List<Frag> frags) {
  final out = postal(_labelMain(frags), frags);
  Map<Frag, String>? cls;
  try {
    cls = coinBlocks([for (final f in frags) if (f.hand == null || f.hand!.isEmpty) f]);
  } catch (_) {
    cls = null;
  }
  if (cls == null || cls.isEmpty) return out;
  final ck = <String, String>{};
  cls.forEach((f, c) => ck[_key3(f)] = c);
  final res = <Labeled>[];
  final seen = <String>{};
  for (final l in out) {
    if (l.f.virtual) continue;
    final k = _key3(l.f);
    if (ck.containsKey(k) && l.cls != 'OTHER') {
      if (seen.contains(k)) continue;
      seen.add(k);
      final src = frags.firstWhere((g) => _key3(g) == k);
      res.add(Labeled(src, ck[k]!));
      continue;
    }
    res.add(l);
  }
  return res;
}
