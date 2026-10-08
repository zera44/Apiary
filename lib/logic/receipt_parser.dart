/// Розбір тексту чека (після розпізнавання) на позиції: товар, кількість, ціна.
///
/// Текст від OCR «брудний», тому розбір поблажливий: пробує кілька типових
/// видів рядка українських чеків і пропускає службові (сума, ПДВ, картка…).
/// Результат завжди показують людині в таблиці, де його можна виправити.
library;

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

const _number = r'\d+(?:[.,]\d+)?';

/// «2 x 45.50», «2.000 кг х 120,00», «3 шт * 10.00 = 30.00», далі може бути
/// сума й літера податкової групи.
final _qtyLine = RegExp(
  r'^(?:(?<name>.*?)\s+)?(?<qty>' +
      _number +
      r')\s*(?<unit>шт|кг|г|л|мл|м|уп)?\.?\s*[xх×*]\s*(?<price>' +
      _number +
      r')\s*(?:=?\s*(?<sum>' +
      _number +
      r'))?\s*[A-Za-zА-ЯІЇЄа-яіїє]?$',
  caseSensitive: false,
);

/// «Мед липовий 0.5кг 150.00 А»: назва і сума в кінці.
final _priceLine = RegExp(
  r'^(?<name>.*?[A-Za-zА-ЯІЇЄҐа-яіїєґ].*?)\s+(?<sum>\d+[.,]\d{2})\s*[A-Za-zА-ЯІЇЄа-яіїє]?$',
);

/// Службові рядки чека - не товари.
final _skip = RegExp(
  r'(пдв|податк|фн(?=\s|$|[.:№])|пн(?=\s|$|[.:№])|чек|каса|касир|готівк|картк|безготів|решта|дякуєм|знижк|'
  r'округл|дата|час(?=\s|$|[.:])|еквайр|термінал|термiнал|рнок|iпн|іпн|код(?=\s|$|[.:])|номер|тел(?=\s|$|[.:])|'
  r'www|http|фіскал|фiскал|сплачено|повернен|бонус|акція|сума до|вартість)',
  caseSensitive: false,
);

/// Кінець переліку товарів.
final _end = RegExp(r'^(сума|разом|всього|до сплати|усього|підсумок)(?=\s|$|[.:])', caseSensitive: false);

/// Велика літера «О» всередині числа (45.5О, 1О0) - це нуль.
String _fixDigits(String s) => s.replaceAllMapped(
    RegExp(r'(?<=\d)[OО](?=\d)|(?<=\d[.,])[OО]|(?<=\d)[OО](?=[.,]\d)|(?<=\d)[OО](?=\s|$)'), (_) => '0');

double? _num(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(',', '.'));
}

String _cleanName(String s) {
  var t = s.replaceAll(RegExp(r'^[\d\s.,)\-–#*№]+(?=[A-Za-zА-ЯІЇЄҐа-яіїєґ])'), ''); // «1. », «12) »
  t = t.replaceAll(RegExp(r'[|_~=]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

bool _hasLetters(String s) => RegExp(r'[A-Za-zА-ЯІЇЄҐа-яіїєґ]{2,}').hasMatch(s);

String _guessUnit(String? unit, double qty) {
  final u = unit?.toLowerCase();
  if (u != null && u.isNotEmpty) return u == 'уп' ? 'упаковка' : u;
  return qty == qty.truncateToDouble() ? 'шт' : 'кг';
}

/// Розібрати текст чека на позиції. Порожній список - нічого не впізнано.
List<ReceiptRow> parseReceipt(String text) {
  final rows = <ReceiptRow>[];
  String? pending; // рядок-назва, чекає на рядок «кількість x ціна»

  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => _fixDigits(l.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t]+'), ' ').trim()))
      .where((l) => l.isNotEmpty);

  for (final line in lines) {
    final low = line.toLowerCase();
    if (_end.hasMatch(low) && rows.isNotEmpty) break;

    final q = _qtyLine.firstMatch(line);
    if (q != null) {
      final qty = _num(q.namedGroup('qty'));
      var price = _num(q.namedGroup('price'));
      final sum = _num(q.namedGroup('sum'));
      if (qty != null && qty > 0 && price != null) {
        // «2 x 45.50 91.00»: якщо ціна й сума не сходяться, а сума з кількістю - ні,
        // вірніше та, що дає цілу ціну за одиницю
        if (sum != null && (qty * price - sum).abs() > 0.02 && qty > 0) {
          final byUnit = sum / qty;
          if ((byUnit * 100 - (byUnit * 100).roundToDouble()).abs() < 1e-6) price = byUnit;
        }
        var name = _cleanName(q.namedGroup('name') ?? '');
        if (!_hasLetters(name)) name = pending ?? '';
        pending = null;
        if (_hasLetters(name) && !_skip.hasMatch(name.toLowerCase())) {
          rows.add(ReceiptRow(
              name: name, qty: qty, unit: _guessUnit(q.namedGroup('unit'), qty), price: price));
        }
        continue;
      }
    }

    if (_skip.hasMatch(low)) {
      pending = null;
      continue;
    }

    final p = _priceLine.firstMatch(line);
    if (p != null) {
      final name = _cleanName(p.namedGroup('name')!);
      final sum = _num(p.namedGroup('sum'));
      if (_hasLetters(name) && sum != null) {
        rows.add(ReceiptRow(name: name, price: sum));
        pending = null;
        continue;
      }
    }

    // просто текст: ймовірно, назва товару, а «кількість x ціна» - у наступному рядку
    if (_hasLetters(line)) pending = _cleanName(line);
  }
  return rows;
}
