/// Позиції чека з нечіткої розмітки fz2: назви (NAME), кількість (QTY), ціна
/// (PRICE) і сума позиції (ITEM) збираються в рядки таблиці; підсумок чека -
/// з фрагментів TOTAL. У курсовій такого збирача немає (там лише класи
/// фрагментів), тож правила тут свої:
///  * назва, кількість і ціна належать позиції на тому самому рядку, інакше -
///    найближчій позиції нижче (назва над «кількість x ціна ... сума»);
///  * після останньої позиції (до підсумку) - попередній позиції, якщо близько;
///  * кількість і ціна приймаються, лише якщо їх добуток дає суму позиції.
library;

import 'fz2.dart';
import 'py.dart';

class FzRow {
  final String name;
  final double qty;
  final String unit;
  final double price;

  /// Сума позиції з чека (null - не прочитана, напр. рукописна).
  final double? sum;

  /// Фрагменти позиції (для показу на фото).
  final List<Labeled> parts;

  const FzRow(this.name, this.qty, this.unit, this.price, this.sum, this.parts);

  @override
  String toString() => 'FzRow($name, $qty $unit x $price = $sum)';
}

class FzReceipt {
  final List<Labeled> labels;
  final List<FzRow> rows;

  /// Підсумок чека («СУМА», «ДО СПЛАТИ»), null - не знайдено.
  final double? total;

  const FzReceipt(this.labels, this.rows, this.total);

  double get rowsSum => rows.fold(0.0, (s, r) => s + (r.sum ?? 0));
}

/// Гроші з тексту фрагмента (остання сума у вигляді 12,34), гривні.
double? moneyOf(String t) {
  final m = finditer(moneyRe, t).toList();
  if (m.isEmpty) return null;
  final g = m.last;
  return kop('${g.group(1)}.${g.group(2)}') / 100;
}

double? _numOf(String t) {
  final m = RegExp(r'\d{1,4}(?:[.,]\d{1,3})?').firstMatch(t);
  return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
}

String _unitOf(String t) {
  final m = RegExp(r'\d\s*(кг|г|л|мл)(?![а-яіїєґ])', caseSensitive: false).firstMatch(t);
  return m == null ? 'шт' : m.group(1)!.toLowerCase();
}

/// Сума рукописної позиції: прочитані цифри без розділювача.
double? _handSum(String t) {
  if (!RegExp(r'^\d{2,6}$').hasMatch(t)) return null;
  return double.parse(t);
}

double? itemValue(Frag f) {
  if (f.virtual) return f.value;
  if (f.hand != null && f.hand!.isNotEmpty) return _handSum(f.text);
  return moneyOf(f.text);
}

/// Підсумок: сума серед TOTAL, що дорівнює сумі позицій [rowsSum], інакше
/// найчастіша; порівну - та, що нижче на чеку.
double? receiptTotal(List<Labeled> lab, [double? rowsSum]) {
  final cnt = <int, int>{}, lastY = <int, double>{};
  for (final l in lab) {
    if (l.cls != 'TOTAL' || l.f.virtual) continue;
    final v = moneyOf(l.f.text);
    if (v == null || v <= 0) continue;
    final k = (v * 100).round();
    cnt[k] = (cnt[k] ?? 0) + 1;
    lastY[k] = l.f.y > (lastY[k] ?? double.negativeInfinity) ? l.f.y : lastY[k]!;
  }
  if (cnt.isEmpty) return null;
  if (rowsSum != null) {
    final k = (rowsSum * 100).round();
    if (cnt.containsKey(k)) return k / 100;
  }
  final best = cnt.keys.reduce((a, b) {
    if (cnt[a]! != cnt[b]!) return cnt[a]! > cnt[b]! ? a : b;
    return lastY[a]! >= lastY[b]! ? a : b;
  });
  return best / 100;
}

FzReceipt assemble(List<Labeled> lab) {
  final rows = _rows(lab);
  final sum = rows.fold<double>(0, (s, r) => s + (r.sum ?? 0));
  var total = receiptTotal(lab, sum);
  // підсумок, менший за половину суми позицій, - зіпсоване читання («5, 20» замість 215,20)
  if (total != null && total < 0.5 * sum) total = null;
  return FzReceipt(lab, rows, total);
}

List<FzRow> _rows(List<Labeled> lab) {
  final items = [for (final l in lab) if (l.cls == 'ITEM') l];
  final real = [for (final l in items) if (!l.f.virtual) l]..sort((a, b) => a.f.y.compareTo(b.f.y));
  final rows = <FzRow>[];
  // позиції без рядка (оплата послуг): назва вже в тексті
  for (final l in items.where((l) => l.f.virtual)) {
    rows.add(FzRow(l.f.text, 1, 'шт', l.f.value ?? 0, l.f.value, [l]));
  }
  if (real.isEmpty) return rows;
  final hs = [for (final l in lab) if (!l.f.virtual && l.f.h > 0) l.f.h]..sort();
  final h = hs.isEmpty ? 30.0 : hs[hs.length ~/ 2];
  double? yTot;
  for (final l in lab) {
    if (l.cls == 'TOTAL' && !l.f.virtual && l.f.y > real.last.f.y && (yTot == null || l.f.y < yTot)) yTot = l.f.y;
  }
  final names = List.generate(real.length, (_) => <Labeled>[]);
  final qtys = List.generate(real.length, (_) => <Labeled>[]);
  final prices = List.generate(real.length, (_) => <Labeled>[]);

  int? owner(Frag f) {
    var best = -1;
    var bd = double.infinity;
    for (var i = 0; i < real.length; i++) {
      final d = (real[i].f.y - f.y).abs();
      if (d < 0.6 * h && d < bd) { best = i; bd = d; }
    }
    if (best >= 0) return best;
    for (var i = 0; i < real.length; i++) {
      if (real[i].f.y > f.y) return f.y > real[i].f.y - 6 * h ? i : null;
    }
    // після останньої позиції: лише близько й до підсумку
    final last = real.length - 1;
    if (f.y - real[last].f.y < 2.2 * h && (yTot == null || f.y < yTot - 0.3 * h)) return last;
    return null;
  }

  // назва на тому самому рядку, що й сума позиції; назва над цим рядком
  final ownName = List.generate(real.length, (i) => lab.any((l) =>
      l.cls == 'NAME' && !l.f.virtual && (l.f.y - real[i].f.y).abs() < 0.6 * h));
  final nameAbove = List.generate(real.length, (i) => lab.any((l) =>
      l.cls == 'NAME' && !l.f.virtual && real[i].f.y - l.f.y >= 0.6 * h && real[i].f.y - l.f.y < 1.6 * h));
  for (final l in lab) {
    if (l.f.virtual) continue;
    final List<List<Labeled>> to;
    switch (l.cls) {
      case 'NAME':
        to = names;
      case 'QTY':
        to = qtys;
      case 'PRICE':
        to = prices;
      default:
        continue;
    }
    var i = owner(l.f);
    // друга строка довгої назви: одразу під рядком попередньої позиції, чия назва
    // починається на рядку суми, а наступна позиція має назву на своєму рядку
    if (i != null && l.cls == 'NAME' && i > 0 && ownName[i] && ownName[i - 1] && !nameAbove[i - 1] &&
        (real[i].f.y - l.f.y).abs() >= 0.6 * h && l.f.y - real[i - 1].f.y < 1.6 * h && l.f.y > real[i - 1].f.y) {
      i = i - 1;
    }
    if (i != null) to[i].add(l);
  }
  for (var i = 0; i < real.length; i++) {
    final it = real[i];
    final sum = itemValue(it.f);
    final nm = [...names[i]]..sort((a, b) {
        final dy = a.f.y - b.f.y;
        if (dy.abs() > 0.5 * h) return dy.sign.toInt();
        return a.f.xLeft.compareTo(b.f.xLeft);
      });
    var name = nm.map((l) => l.f.text.trim()).where((t) => t.isNotEmpty).join(' ');
    if (it.f.hand != null && name.isEmpty) name = '[рукопис]';
    var qty = 1.0, unit = 'шт', price = sum ?? 0.0;
    // кількість і ціна: беруться, якщо їх добуток - сума позиції
    for (final q in qtys[i]) {
      final qv = _numOf(q.f.text);
      if (qv == null || qv <= 0) continue;
      for (final p in prices[i]) {
        final pv = moneyOf(p.f.text);
        if (pv == null || sum == null) continue;
        if ((qv * pv - sum).abs() <= 0.011 + 0.005 * sum) {
          qty = qv;
          price = pv;
          unit = _unitOf(q.f.text);
          if (unit == 'шт' && qv != qv.roundToDouble()) unit = 'кг'; // вагове: дробова кількість
        }
      }
    }
    if (qty == 1 && sum != null && prices[i].isNotEmpty) {
      // кількість не прочитана, але ціна ділить суму націло (2 x 15,00 = 30,00)
      final pv = moneyOf(prices[i].first.f.text);
      if (pv != null && pv > 0) {
        final n = sum / pv;
        if (n >= 2 && n <= 99 && (n - n.round()).abs() < 0.001) {
          qty = n.roundToDouble();
          price = pv;
        }
      }
    }
    rows.add(FzRow(name, qty, unit, price, sum, [...nm, ...qtys[i], ...prices[i], it]));
  }
  // позиції без прочитаної суми на краях переліку (шапка, хвіст) відкидаються,
  // всередині лишаються з назвою (ціну людина впише, різниця - у «Корегуванні»)
  final virt = rows.where((r) => r.parts.length == 1 && r.parts.first.f.virtual).length;
  final body = rows.sublist(virt);
  while (body.isNotEmpty && body.first.sum == null && body.first.parts.last.f.hand == null) {
    body.removeAt(0);
  }
  while (body.isNotEmpty && body.last.sum == null && body.last.parts.last.f.hand == null) {
    body.removeLast();
  }
  body.removeWhere((r) => r.sum == null && r.name.isEmpty);
  return [...rows.sublist(0, virt), ...body];
}

/// Розмітка й позиції чека з фрагментів OCR.
FzReceipt markReceipt(List<Frag> frags) => assemble(label(frags));
