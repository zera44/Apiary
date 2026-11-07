/// Допоміжні функції, що відтворюють поведінку Python і numpy, на яких
/// написано нечітку розмітку fz2 (coursework/fuzzy_v2/fz2.py). Перенесення
/// вважається правильним, лише коли розмітка збігається з Python до класу
/// кожного фрагмента, тому тут важливі навіть дрібниці: округлення «до
/// парного», порядок підсумовування numpy, юнікодні \d, \w, \b у регулярних
/// виразах.
library;

import 'dart:math' as math;

// ------------------------------------------------------------- регулярні вирази

const _word = r'\p{L}\p{N}_';
const _letterNoDigit = r'[\p{L}\p{Nl}\p{No}]'; // Python [^\W\d_]
const _boundary = '(?:(?<=[$_word])(?![$_word])|(?<![$_word])(?=[$_word]))';
const _syntax = r'^$\.*+?()[]{}|/';

final _cache = <String, RegExp>{};

/// Регулярний вираз Python (модуль re, рядок str) як RegExp Dart: \d, \w, \W,
/// \b у Python юнікодні, а в Dart - лише ASCII, тож вони переписуються на
/// класи \p{...}.
RegExp pyRe(String pattern, {bool ignoreCase = false}) {
  final key = '${ignoreCase ? 'i' : 's'}$pattern';
  return _cache[key] ??= RegExp(translatePattern(pattern), unicode: true, caseSensitive: !ignoreCase);
}

String translatePattern(String p) {
  p = p.replaceAll(r'[^\W\d_]', '\u0000');
  final b = StringBuffer();
  var inClass = false;
  for (var i = 0; i < p.length; i++) {
    final c = p[i];
    if (c == '\u0000') {
      b.write(_letterNoDigit);
      continue;
    }
    if (c == r'\' && i + 1 < p.length) {
      final n = p[++i];
      switch (n) {
        case 'd':
          b.write(r'\p{Nd}');
        case 'D':
          b.write(r'\P{Nd}');
        case 'w':
          b.write(inClass ? _word : '[$_word]');
        case 'W':
          if (inClass) throw UnsupportedError('\\W у класі: $p');
          b.write('[^$_word]');
        case 'b':
          if (inClass) throw UnsupportedError('\\b у класі: $p');
          b.write(_boundary);
        case 's' || 'S' || 'n' || 't' || 'r' || 'f' || 'v' || 'x' || 'u':
          b.write('\\$n');
        default:
          if (_syntax.contains(n) || (n == '-' && inClass)) {
            b.write('\\$n');
          } else {
            b.write(n); // \' \" \# ... - звичайний символ
          }
      }
      continue;
    }
    if (c == '[' && !inClass) {
      inClass = true;
    } else if (c == ']' && inClass) {
      inClass = false;
    }
    b.write(c);
  }
  return b.toString();
}

/// re.search
RegExpMatch? search(String p, String s, {bool i = false}) => pyRe(p, ignoreCase: i).firstMatch(s);
bool has(String p, String s, {bool i = false}) => pyRe(p, ignoreCase: i).hasMatch(s);

/// re.match (збіг з початку рядка)
RegExpMatch? match(String p, String s, {bool i = false}) =>
    pyRe(p, ignoreCase: i).matchAsPrefix(s) as RegExpMatch?;

/// re.fullmatch
RegExpMatch? fullmatch(String p, String s, {bool i = false}) {
  final m = pyRe('(?:$p)\$', ignoreCase: i).matchAsPrefix(s);
  return m as RegExpMatch?;
}

/// re.finditer
List<RegExpMatch> finditer(String p, String s, {bool i = false}) => pyRe(p, ignoreCase: i).allMatches(s).toList();

/// re.findall для виразу з групами: кортежі груп.
List<List<String>> findallGroups(String p, String s) => [
      for (final m in pyRe(p).allMatches(s)) [for (var g = 1; g <= m.groupCount; g++) m.group(g) ?? '']
    ];

/// re.findall для виразу з однією групою.
List<String> findall1(String p, String s) => [for (final m in pyRe(p).allMatches(s)) m.group(1) ?? ''];

/// re.sub з підстановкою груп \1, \2 (count = 0 - усі).
String sub(String p, String repl, String s, {int count = 0}) {
  final re = pyRe(p);
  var n = 0;
  final out = StringBuffer();
  var last = 0;
  for (final m in re.allMatches(s)) {
    if (count > 0 && n >= count) break;
    out.write(s.substring(last, m.start));
    out.write(repl.replaceAllMapped(RegExp(r'\\(\d)'), (g) => m.group(int.parse(g[1]!)) ?? ''));
    last = m.end;
    n++;
  }
  out.write(s.substring(last));
  return out.toString();
}

// ------------------------------------------------------------------ рядки

final _alpha = RegExp(r'\p{L}', unicode: true);
final _space = RegExp(r'\s+', unicode: true);

/// sum(ch.isalpha() for ch in s)
int alphaCount(String s) => _alpha.allMatches(s).length;

bool isAlpha(String ch) => ch.isNotEmpty && _alpha.hasMatch(ch);

/// str.split() без аргументів.
List<String> pySplit(String s) {
  final t = s.trim();
  return t.isEmpty ? <String>[] : t.split(_space);
}

/// str.isupper()
bool isUpper(String s) {
  var cased = false;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final up = ch.toUpperCase(), low = ch.toLowerCase();
    if (up == low) continue;
    cased = true;
    if (ch != up) return false;
  }
  return cased;
}

/// str.capitalize()
String capitalize(String s) {
  if (s.isEmpty) return s;
  final first = String.fromCharCode(s.runes.first);
  return first.toUpperCase() + s.substring(first.length).toLowerCase();
}

/// str.isdigit() для символу (ASCII, «०» та верхні індекси/цифри в колах словника OCR).
bool isDigitChar(String ch) =>
    RegExp(r'^\p{Nd}$', unicode: true).hasMatch(ch) || '²³¹①②③④⑤⑥⑦⑧⑨❶❷❸❹❺❻❼❽❾➀➁➂➃➄➅➆➇➈➊➋➌➍➎➏➐➑➒'.contains(ch);

/// Юнікодні цифри (\p{Nd}) - в ASCII, як їх розуміють int() і float() Python.
String asciiDigits(String s) {
  const zeros = [0x660, 0x6F0, 0x7C0, 0x966, 0x9E6, 0xA66, 0xAE6, 0xB66, 0xBE6, 0xC66, 0xCE6, 0xD66, 0xDE6, 0xE50, 0xED0, 0xF20, 0x1040, 0x1090, 0x17E0, 0x1810, 0xFF10];
  if (s.runes.every((r) => r < 128)) return s;
  final b = StringBuffer();
  for (final r in s.runes) {
    var out = r;
    for (final z in zeros) {
      if (r >= z && r <= z + 9) out = 0x30 + r - z;
    }
    b.writeCharCode(out);
  }
  return b.toString();
}

/// float(s) Python (кидає FormatException, як Python - ValueError).
double pyFloat(String s) {
  final t = asciiDigits(s.trim());
  if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(t)) throw FormatException('float: $s');
  return double.parse(t);
}

// ------------------------------------------------------------------- числа

/// round(x) Python: до найближчого цілого, рівно посередині - до парного.
int pyRound(double x) {
  final f = x.floorToDouble();
  final d = x - f;
  if (d > 0.5) return f.toInt() + 1;
  if (d < 0.5) return f.toInt();
  final fi = f.toInt();
  return fi.isEven ? fi : fi + 1;
}

/// Підсумовування numpy (попарне, з розгортанням на 8) - як np.sum для float64.
double npSum(List<double> a) => _pairwise(a, 0, a.length);

double _pairwise(List<double> a, int s, int n) {
  if (n < 8) {
    var res = 0.0;
    for (var i = 0; i < n; i++) {
      res += a[s + i];
    }
    return res;
  } else if (n <= 128) {
    final r = List<double>.generate(8, (j) => a[s + j]);
    var i = 8;
    for (; i < n - (n % 8); i += 8) {
      for (var j = 0; j < 8; j++) {
        r[j] += a[s + i + j];
      }
    }
    var res = ((r[0] + r[1]) + (r[2] + r[3])) + ((r[4] + r[5]) + (r[6] + r[7]));
    for (; i < n; i++) {
      res += a[s + i];
    }
    return res;
  } else {
    var n2 = n ~/ 2;
    n2 -= n2 % 8;
    return _pairwise(a, s, n2) + _pairwise(a, s + n2, n - n2);
  }
}

double npMean(List<double> a) => npSum(a) / a.length;

double npMedian(List<double> a) {
  if (a.isEmpty) return double.nan;
  final s = [...a]..sort();
  final n = s.length;
  if (n.isOdd) return s[n ~/ 2];
  return npMean([s[n ~/ 2 - 1], s[n ~/ 2]]);
}

/// np.percentile (метод linear).
double npPercentile(List<double> a, double q) {
  final s = [...a]..sort();
  final n = s.length;
  final qq = q / 100;
  final virt = qq * (n - 1);
  final prev = virt.floorToDouble();
  var lo = prev.toInt(), hi = lo + 1;
  if (lo < 0) lo = 0;
  if (lo > n - 1) lo = n - 1;
  if (hi > n - 1) hi = n - 1;
  final gamma = virt - prev;
  final x = s[lo], y = s[hi];
  final diff = y - x;
  return gamma >= 0.5 ? y - diff * (1 - gamma) : x + diff * gamma;
}

/// np.arange(start, stop, step) для float.
List<double> npArange(double start, double stop, double step) {
  final len = ((stop - start) / step).ceil();
  if (len <= 0) return [];
  final out = <double>[start];
  if (len == 1) return out;
  final next = start + step;
  out.add(next);
  final delta = next - start;
  for (var i = 2; i < len; i++) {
    out.add(start + i * delta);
  }
  return out;
}

double clip(double x, double lo, double hi) => x < lo ? lo : (x > hi ? hi : x);

// ---------------------------------------------------------------- колекції

/// min(xs, key=...) Python: перший найменший; порожній список - помилка.
T minBy<T>(Iterable<T> xs, num Function(T) key) {
  final it = xs.iterator;
  if (!it.moveNext()) throw StateError('min() arg is an empty sequence');
  var best = it.current;
  var bk = key(best);
  while (it.moveNext()) {
    final k = key(it.current);
    if (k < bk) {
      best = it.current;
      bk = k;
    }
  }
  return best;
}

/// max(xs, key=...) Python: перший найбільший.
T maxBy<T>(Iterable<T> xs, num Function(T) key) {
  final it = xs.iterator;
  if (!it.moveNext()) throw StateError('max() arg is an empty sequence');
  var best = it.current;
  var bk = key(best);
  while (it.moveNext()) {
    final k = key(it.current);
    if (k > bk) {
      best = it.current;
      bk = k;
    }
  }
  return best;
}

/// max за ключем-кортежем (порівняння по черзі).
T maxByTuple<T>(Iterable<T> xs, List<num> Function(T) key) {
  final it = xs.iterator;
  if (!it.moveNext()) throw StateError('max() arg is an empty sequence');
  var best = it.current;
  var bk = key(best);
  while (it.moveNext()) {
    final k = key(it.current);
    if (_cmpTuple(k, bk) > 0) {
      best = it.current;
      bk = k;
    }
  }
  return best;
}

int _cmpTuple(List<num> a, List<num> b) {
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return a.length.compareTo(b.length);
}

num pyMin(Iterable<num> xs) => minBy<num>(xs, (x) => x);
num pyMax(Iterable<num> xs) => maxBy<num>(xs, (x) => x);

/// sorted(xs, key=...) - стійке сортування, як у Python.
List<T> sortedBy<T>(Iterable<T> xs, Comparable Function(T) key) {
  final l = xs.toList();
  final idx = List<int>.generate(l.length, (i) => i);
  final keys = [for (final x in l) key(x)];
  idx.sort((a, b) {
    final c = keys[a].compareTo(keys[b]);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in idx) l[i]];
}

/// Порядок обходу set(ints) у CPython (від нього залежить max(set(...), key=...) при рівних ключах).
List<int> cpythonSetOrder(Iterable<int> values) {
  const linear = 9, shift = 5;
  var mask = 7;
  var table = List<int?>.filled(8, null);
  var fill = 0, used = 0;

  int hashOf(int v) {
    const m = (1 << 61) - 1;
    var h = v.abs() % m;
    if (v < 0) h = -h;
    return h == -1 ? -2 : h;
  }

  void insertClean(List<int?> t, int msk, int key) {
    final h = hashOf(key);
    var perturb = BigInt.from(h).toUnsigned(64);
    var i = BigInt.from(h).toUnsigned(64).toInt() & msk;
    while (true) {
      if (t[i] == null) {
        t[i] = key;
        return;
      }
      if (i + linear <= msk) {
        for (var j = 1; j <= linear; j++) {
          if (t[i + j] == null) {
            t[i + j] = key;
            return;
          }
        }
      }
      perturb = perturb >> shift;
      i = ((BigInt.from(i) * BigInt.from(5) + BigInt.one + perturb) & BigInt.from(msk)).toInt();
    }
  }

  for (final v in values) {
    final h = hashOf(v);
    var perturb = BigInt.from(h).toUnsigned(64);
    var i = BigInt.from(h).toUnsigned(64).toInt() & mask;
    var found = false;
    int? slot;
    outer:
    while (true) {
      final probes = i + linear <= mask ? linear : 0;
      for (var j = 0; j <= probes; j++) {
        final e = table[i + j];
        if (e == null) {
          slot = i + j;
          break outer;
        }
        if (e == v) {
          found = true;
          break outer;
        }
      }
      perturb = perturb >> shift;
      i = ((BigInt.from(i) * BigInt.from(5) + BigInt.one + perturb) & BigInt.from(mask)).toInt();
    }
    if (found) continue;
    table[slot!] = v;
    fill++;
    used++;
    if (fill * 5 < mask * 3) continue;
    final minused = used > 50000 ? used * 2 : used * 4;
    var newsize = 8;
    while (newsize <= minused) {
      newsize <<= 1;
    }
    final nt = List<int?>.filled(newsize, null);
    for (final e in table) {
      if (e != null) insertClean(nt, newsize - 1, e);
    }
    table = nt;
    mask = newsize - 1;
    fill = used;
  }
  return [for (final e in table) if (e != null) e];
}
