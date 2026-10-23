/// Розбір тексту чека (після розпізнавання) на позиції: товар, кількість, ціна.
///
/// Текст від OCR «брудний», тому розбір поблажливий: пробує кілька типових
/// видів рядка українських чеків і пропускає службові (сума, ПДВ, картка…).
/// Буває два порядки рядків:
///  * назва, а під нею «кількість x ціна [сума]» (супермаркети);
///  * «кількість x ціна», а під нею «назва … сума» (каси кафе, Checkbox тощо).
/// Порядок визначається для всього чека; ціна й кількість звіряються із сумою
/// рядка (вона надрукована великим і читається найнадійніше).
/// Результат завжди показують людині в таблиці, де його можна виправити.
library;

import 'stock_format.dart';

class ReceiptRow {
  String name;

  /// Кількість (для ваги - дробова).
  double qty;

  /// Одиниця: шт, кг, г, л, мл…
  String unit;

  /// Ціна за одиницю.
  double price;

  ReceiptRow({required this.name, this.qty = 1, this.unit = 'шт', this.price = 0});

  double get total => qty * price;

  @override
  String toString() => 'ReceiptRow($name, $qty $unit x $price)';
}

const _letters = r'A-Za-zА-ЯІЇЄҐа-яіїєґ';
const _number = r'\d+(?:[.,]\d+)?';

/// «2 x 45.50», «2.000 кг х 120,00», «3 шт * 10.00 = 30.00», далі може бути
/// сума, літера податкової групи й дрібне сміття від згинів паперу
/// («1,000 х/112,00 |»).
final _qtyLine = RegExp(
  r'^(?:(?<name>.*?)\s+)?(?<qty>' +
      _number +
      r')\s*(?<unit>шт|кг|г|л|мл|м|уп)?\.?\s*[xх×*][^\d\s]{0,2}\s*(?<price>' +
      _number +
      r')\s*(?:=?\s*(?<sum>\d+[.,]\d{2}))?[^\d\s]*(?:\s+\S{1,4})*\s*$',
  caseSensitive: false,
);

/// «Мед липовий 0.5кг 150.00 А»: назва і сума в кінці.
final _priceLine = RegExp(
  r'^(?<name>.*?[' + _letters + r'].*?)\s+(?<sum>\d+[.,]\d{2})\s*[' + _letters + r']?$',
);

/// Службові рядки чека - не товари.
final _skip = RegExp(
  r'(пдв|податк|фн(?=\s|$|[.:№])|пн(?=\s|$|[.:№])|чек|каса|касир|готівк|картк|безготів|решта|дякуєм|знижк|'
  r'округл|дата|час(?=\s|$|[.:])|еквайр|термінал|термiнал|рнок|iпн|іпн|код(?=\s|$|[.:])|номер|тел(?=\s|$|[.:])|'
  r'www|http|фіскал|фiскал|сплачено|повернен|бонус|акція|сума до|вартість|гарантій|епз|платіжн|рнн|термін|'
  r'\*{2,}|rrn|auth|visa|master)',
  caseSensitive: false,
);

/// Кінець переліку товарів («СУМА», «Сума!», «РАЗОМ:»…).
final _end = RegExp(r'^(сума|разом|всього|до сплати|усього|підсумок)(?![а-яіїєґa-z])', caseSensitive: false);

/// Велика літера «О» всередині числа (45.5О, 1О0) - це нуль.
String _fixDigits(String s) => s.replaceAllMapped(
    RegExp(r'(?<=\d)[OО](?=\d)|(?<=\d[.,])[OО]|(?<=\d)[OО](?=[.,]\d)|(?<=\d)[OО](?=\s|$)'), (_) => '0');

double? _num(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(',', '.'));
}

/// Кома, крапка, риска чи «|» в кінці рядка - сліди згинів, не текст.
String _trimTail(String s) => s.replaceAll(RegExp(r'[\s,.;:|]+$'), '');

String _cleanName(String s) {
  var t = s.replaceAll(RegExp(r'^[\d\s.,)\-–#*№]+(?=[' + _letters + r'])'), ''); // «1. », «12) »
  t = t.replaceAll(RegExp(r'[|_~=«»"“”]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  // окремі символи в кінці («… 75,00 А .», «КИЇВСЬК ї») - сміття, крім одиниці
  // після числа («200/10 г»)
  while (true) {
    final m = RegExp(r'\s(\S)$').firstMatch(t);
    if (m == null || RegExp(r'\d\s\S$').hasMatch(t)) break;
    t = t.substring(0, m.start).trimRight();
  }
  return t.replaceAll(RegExp(r"[\s.,;:'`]+$"), '');
}

/// Хоч одне слово з 3+ літер: рядок схожий на назву, а не на сміття OCR.
bool _hasWord(String s) => RegExp('[$_letters]{3,}').hasMatch(s);

bool _round(double v, int decimals) {
  var k = 1.0;
  for (var i = 0; i < decimals; i++) {
    k *= 10;
  }
  return ((v * k) - (v * k).roundToDouble()).abs() < 1e-6;
}

double _to(double v, int decimals) {
  var k = 1.0;
  for (var i = 0; i < decimals; i++) {
    k *= 10;
  }
  return (v * k).roundToDouble() / k;
}

/// Звірити кількість і ціну з сумою рядка: OCR частіше псує дрібні цифри
/// («1,060 х/12,00» при сумі 112,00), а суму друкують великою.
(double, double) _reconcile(double qty, double price, double? sum) {
  if (sum == null || (qty * price - sum).abs() <= 0.02) return (qty, price);
  if (price > 0) {
    final q = sum / price;
    if (q > 0 && _round(q, 3)) return (_to(q, 3), price);
  }
  final p = sum / qty;
  if (_round(p, 2)) return (qty, _to(p, 2));
  final whole = qty.roundToDouble();
  if (whole > 0 && (qty - whole).abs() < 0.07) return (whole, _to(sum / whole, 2));
  return (qty, price);
}

String _guessUnit(String? unit, double qty) {
  final u = unit?.toLowerCase();
  if (u != null && u.isNotEmpty) return u == 'уп' ? 'упаковка' : u;
  return qty == qty.truncateToDouble() ? 'шт' : 'кг';
}

/// Чи текст здебільшого ВЕЛИКИМИ літерами.
bool _mostlyUpper(String s) {
  var up = 0, all = 0;
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final lo = c.toLowerCase(), hi = c.toUpperCase();
    if (lo == hi) continue; // не літера
    all++;
    if (c == hi) up++;
  }
  return all > 0 && up >= all * 0.6;
}

/// «МОРКВА ПО-КОРЕЙСЬКИ 120Г» → «Морква по-корейськи 120 г».
String _sentenceCase(String s) {
  if (s.isEmpty) return s;
  var t = s.toLowerCase();
  t = t[0].toUpperCase() + t.substring(1);
  return t.replaceAllMapped(RegExp(r'(\d)\s*(кг|г|мл|л)(?![а-яіїєґ])'), (m) => '${m[1]} ${m[2]}');
}

class _Qty {
  final RegExpMatch m;
  final double qty;
  final double price;
  _Qty(this.m, this.qty, this.price);
}

_Qty? _qtyInfo(String line) {
  final m = _qtyLine.firstMatch(line);
  if (m == null) return null;
  final qty = _num(m.namedGroup('qty'));
  final price = _num(m.namedGroup('price'));
  if (qty == null || qty <= 0 || price == null) return null;
  return _Qty(m, qty, price);
}

/// Чи «кількість x ціна» друкується ПЕРЕД назвою (назва з сумою - рядком нижче).
bool _qtyFirst(List<String> lines) {
  var first = 0, after = 0;
  for (var i = 0; i < lines.length - 1; i++) {
    final q = _qtyInfo(lines[i]);
    if (q == null || _hasWord(_cleanName(q.m.namedGroup('name') ?? ''))) continue;
    final next = _priceLine.firstMatch(_trimTail(lines[i + 1]));
    if (next != null && _hasWord(_cleanName(next.namedGroup('name')!))) {
      final sum = _num(next.namedGroup('sum'))!;
      final t = q.qty * q.price;
      if ((t - sum).abs() <= 0.02 ||
          (sum > 0 && t / sum > 0.9 && t / sum < 1.1) ||
          q.m.namedGroup('price')!.endsWith(next.namedGroup('sum')!)) {
        first++;
        continue;
      }
    }
    if (i > 0) {
      final prev = lines[i - 1];
      if (_hasWord(prev) &&
          _qtyInfo(prev) == null &&
          _priceLine.firstMatch(prev) == null &&
          !_skip.hasMatch(prev.toLowerCase())) {
        after++;
      }
    }
  }
  return first > after;
}


/// «ШК 4820217000055» / «Штрихкод 2099901024039»: початок позиції в чеках, де
/// кожному товару передує його штрихкод (АТБ, «Вигідна покупка» тощо).
final _barcodeLine = RegExp(r'^(?:[ШЩ]К|штрихкод)(?![а-яіїєґa-z])', caseSensitive: false);

/// «Арт № 138807 Навушники» - артикул перед назвою.
final _articlePrefix = RegExp(r'^арт\.?\s*[^\s\d]{0,2}\d?\s*\d{4,}\s*', caseSensitive: false);

/// Рядок, що закінчується сумою: «… 31,90 А», «… 134,00 А».
final _moneyEnd = RegExp(
    r'^(?<name>.*?)\s*(?<sum>\d+[.,]\s?\d{2})\s*[A-Za-zА-ЯІЇЄҐа-яіїєґ]?\s*(?:грн\.?)?\s*$');

/// Службовий кінець назви: «Гарантійний термін 1 рік».
final _nameNoise = RegExp(r'гарантій|термін', caseSensitive: false);

/// Знижка під позицією: «ЗНИЖКА -3,16», «ЦІНА КГ/Л ЗІ ЗНИЖКОЮ 29,32».
final _discountLine = RegExp(r'^(?:зни[а-яіїєґ]{1,2}ка|ціна\s)', caseSensitive: false);

/// «СУМА ЗІ ЗНИЖКОЮ 58,64» (OCR часом читає «СНМА»).
final _discountSum = RegExp(r'^[сc][а-яіa-z]{2,3}\s+[зз3][іi]\s', caseSensitive: false);

double? _lastMoney(String l) {
  final all = RegExp(r'(\d+[.,]\s?\d{2})(?!\d)').allMatches(l).toList();
  if (all.isEmpty) return null;
  return _num(all.last.group(1)!.replaceAll(' ', ''));
}

/// Чеки, де кожну позицію відкриває штрихкод: усе між «ШК …» і рядком із сумою
/// - назва (в одному-двох рядках); «2 x 30,90 61,80» - кількість і ціна; під
/// ними може бути знижка. Усе поза такими блоками (реквізити, картка, ПДВ,
/// «Гарантійний термін») - не товар. Порожній список - у чеку немає штрихкодів.
List<ReceiptRow> _barcodeBlocks(List<String> lines) {
  final rows = <ReceiptRow>[];
  bool bc(String l) => _barcodeLine.hasMatch(l);
  for (var i = 0; i < lines.length; i++) {
    if (!bc(lines[i])) continue;
    // «1X 134,00» перед штрихкодом - кількість
    double? qty;
    if (i > 0) {
      final qi = _qtyInfo(lines[i - 1]);
      if (qi != null && !_hasWord(_cleanName(qi.m.namedGroup('name') ?? ''))) qty = qi.qty;
    }
    final name = <String>[];
    double? sum;
    String? unit;
    var j = i + 1;
    for (; j < lines.length; j++) {
      final l = lines[j];
      if (bc(l) || _end.hasMatch(l.toLowerCase())) break;
      final qi = _qtyInfo(l);
      if (qi != null) {
        final n = _cleanName(qi.m.namedGroup('name') ?? '');
        if (_hasWord(n)) name.add(n);
        qty = qi.qty;
        unit = qi.m.namedGroup('unit');
        sum = _num(qi.m.namedGroup('sum')) ?? qi.qty * qi.price;
        j++;
        break;
      }
      final m = _moneyEnd.firstMatch(l);
      if (m != null) {
        final n = _cleanName(m.namedGroup('name')!.replaceFirst(_articlePrefix, ''));
        if (_hasWord(n) && !_nameNoise.hasMatch(n)) name.add(n);
        sum = _num(m.namedGroup('sum')!.replaceAll(' ', ''));
        j++;
        break;
      }
      final n = _cleanName(l.replaceFirst(_articlePrefix, ''));
      if (_hasWord(n)) name.add(n);
    }
    if (sum == null) continue; // блок без суми - не позиція
    // знижка: «СУМА ЗІ ЗНИЖКОЮ» - те, що справді заплачено
    for (var k = j; k < lines.length && k < j + 4; k++) {
      final l = lines[k];
      final low = l.toLowerCase();
      if (bc(l)) break;
      if (_discountSum.hasMatch(low)) {
        sum = _lastMoney(l) ?? sum;
      } else if (!_discountLine.hasMatch(low)) {
        break;
      }
    }
    final title = name.join(' ').trim();
    if (!_hasWord(title)) continue;
    final q = (qty == null || qty <= 0) ? 1.0 : qty;
    rows.add(ReceiptRow(
        name: title, qty: q, unit: _guessUnit(unit, q), price: _to(sum / q, 2)));
  }
  // штрихкод тут не відкриває позицію (інший порядок рядків): хай читає звичайний розбір
  if (rows.length * 2 < lines.where(bc).length) return [];
  return rows;
}

/// Розібрати текст чека на позиції. Порожній список - нічого не впізнано.
List<ReceiptRow> parseReceipt(String text) {
  final rows = <ReceiptRow>[];
  String? pending; // рядок-назва, чекає на рядок «кількість x ціна»

  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => _fixDigits(l.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t]+'), ' ').trim()))
      .where((l) => l.isNotEmpty)
      .toList();
  final blocks = _barcodeBlocks(lines);
  if (blocks.isNotEmpty) return blocks;
  final qtyFirst = _qtyFirst(lines);

  void add(String name, double qty, String? unit, double price) {
    if (!_hasWord(name) || _skip.hasMatch(name.toLowerCase())) return;
    // номери карток і коди з чека (4412 **** 4) не є кількістю та ціною
    if (qty > 999 || price > 100000 || qty * price > 1000000) return;
    rows.add(ReceiptRow(name: name, qty: qty, unit: _guessUnit(unit, qty), price: price));
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final low = line.toLowerCase();
    if (_end.hasMatch(low) && rows.isNotEmpty) break;

    final q = _qtyInfo(line);
    if (q != null) {
      var sum = _num(q.m.namedGroup('sum'));
      var name = _cleanName(q.m.namedGroup('name') ?? '');
      if (!_hasWord(name)) {
        if (qtyFirst && i + 1 < lines.length && _hasWord(lines[i + 1]) && _qtyInfo(lines[i + 1]) == null) {
          // назва (і сума) - наступним рядком
          final next = _trimTail(lines[i + 1]);
          final p = _priceLine.firstMatch(next);
          if (p != null) {
            name = _cleanName(p.namedGroup('name')!);
            sum = _num(p.namedGroup('sum'));
          } else {
            name = _cleanName(next);
          }
          i++;
        } else {
          name = pending ?? '';
        }
      }
      pending = null;
      final (qty, price) = _reconcile(q.qty, q.price, sum);
      add(name, qty, q.m.namedGroup('unit'), price);
      continue;
    }

    if (_skip.hasMatch(low)) {
      pending = null;
      continue;
    }

    // перенесений кінець назви («… 200/10» + «г»)
    if (rows.isNotEmpty && pending == null && RegExp('^[$_letters]{1,2}\\.?\$').hasMatch(line)) {
      final last = rows.last;
      final glue = RegExp(r'[\d/]$').hasMatch(last.name) ? '' : ' ';
      last.name = '${last.name}$glue${line.toLowerCase()}';
      continue;
    }

    final p = _priceLine.firstMatch(_trimTail(line));
    if (p != null) {
      var name = _cleanName(p.namedGroup('name')!);
      final sum = _num(p.namedGroup('sum'));
      if (!_hasWord(name) && pending != null) name = pending;
      if (_hasWord(name) && sum != null) {
        add(name, 1, null, sum);
        pending = null;
        continue;
      }
    }

    // просто текст: ймовірно, назва товару, а «кількість x ціна» - у наступному рядку
    if (_hasWord(line)) pending = _cleanName(line);
  }

  // чек надруковано ВЕЛИКИМИ - назви звичайним реченням («Морква по-корейськи 120 г»)
  if (rows.isNotEmpty && _mostlyUpper(rows.map((r) => r.name).join(' '))) {
    for (final r in rows) {
      r.name = _sentenceCase(r.name);
    }
  }
  return rows;
}

/// Список у вигляді «Назва 1 шт, 75 грн, сума 75 грн» - по рядку на позицію.
String receiptAsText(List<ReceiptRow> rows) => rows
    .map((r) => '${r.name} ${formatAmount(r.qty)} ${r.unit}, ${formatMoney(r.price)} грн, '
        'сума ${formatMoney(r.total)} грн')
    .join('\n');

/// Підсумок, надрукований на чеку («СУМА 1 250,00», «РАЗОМ: 97.00»; число може
/// стояти й у наступному рядку). null - не знайдено. Потрібен, щоб звірити
/// суму розпізнаної таблиці з чеком.
double? receiptDeclaredTotal(String text) {
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) _fixDigits(l.trim())
  ];
  final money = RegExp(r'(\d[\d ]*[.,]\d{2})(?!\d)');
  double? read(String l) {
    final all = money.allMatches(l).toList();
    if (all.isEmpty) return null;
    return double.tryParse(all.last.group(1)!.replaceAll(' ', '').replaceAll(',', '.'));
  }

  for (var i = 0; i < lines.length; i++) {
    if (!_end.hasMatch(lines[i].toLowerCase())) continue;
    final v = read(lines[i]) ?? (i + 1 < lines.length ? read(lines[i + 1]) : null);
    if (v != null) return v;
  }
  return null;
}
