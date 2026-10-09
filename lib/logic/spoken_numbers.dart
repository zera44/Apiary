/// Число, сказане словами (українською), -> цифри для числових полів:
/// «дванадцять» -> 12, «два кома п'ять» -> 2,5, «три цілих двадцять п'ять
/// сотих» -> 3,25, «півтора» -> 1,5, «сто двадцять з половиною» -> 120,5,
/// «мінус три» -> -3. Цифри, якщо їх уже розпізнано цифрами, лишаються.
/// Не число - null.
library;

const Map<String, int> _units = {
  'нуль': 0,
  'один': 1, 'одна': 1, 'одне': 1, 'одну': 1, 'одного': 1, 'одній': 1, 'одним': 1, 'одної': 1,
  'два': 2, 'дві': 2, 'двох': 2, 'двом': 2, 'двома': 2,
  'три': 3, 'трьох': 3, 'трьом': 3, 'трьома': 3,
  'чотири': 4, 'чотирьох': 4, 'чотирьом': 4,
  "п'ять": 5, "п'яти": 5, "п'ятьох": 5,
  'шість': 6, 'шести': 6, 'шістьох': 6,
  'сім': 7, 'семи': 7, 'сімох': 7,
  'вісім': 8, 'восьми': 8, 'вісьмох': 8,
  "дев'ять": 9, "дев'яти": 9,
  'десять': 10, 'десяти': 10,
  'одинадцять': 11, 'одинадцяти': 11,
  'дванадцять': 12, 'дванадцяти': 12,
  'тринадцять': 13, 'тринадцяти': 13,
  'чотирнадцять': 14, 'чотирнадцяти': 14,
  "п'ятнадцять": 15, "п'ятнадцяти": 15,
  'шістнадцять': 16, 'шістнадцяти': 16,
  'сімнадцять': 17, 'сімнадцяти': 17,
  'вісімнадцять': 18, 'вісімнадцяти': 18,
  "дев'ятнадцять": 19, "дев'ятнадцяти": 19,
  'двадцять': 20, 'двадцяти': 20,
  'тридцять': 30, 'тридцяти': 30,
  'сорок': 40, 'сорока': 40,
  "п'ятдесят": 50, "п'ятдесяти": 50,
  'шістдесят': 60, 'шістдесяти': 60,
  'сімдесят': 70, 'сімдесяти': 70,
  'вісімдесят': 80, 'вісімдесяти': 80,
  "дев'яносто": 90,
  'сто': 100, 'ста': 100,
  'двісті': 200, 'двохсот': 200,
  'триста': 300, 'трьохсот': 300,
  'чотириста': 400, 'чотирьохсот': 400,
  "п'ятсот": 500, "п'ятисот": 500,
  'шістсот': 600, 'шестисот': 600,
  'сімсот': 700, 'семисот': 700,
  'вісімсот': 800, 'восьмисот': 800,
  "дев'ятсот": 900, "дев'ятисот": 900,
};

bool _isThousand(String w) => w.startsWith('тисяч');

/// Ціле з токенів (null - не число). Порожньо - null.
int? _int(List<String> words) {
  if (words.isEmpty) return null;
  var total = 0, cur = 0;
  var any = false;
  for (final w in words) {
    final d = int.tryParse(w);
    if (d != null) {
      cur += d;
      any = true;
    } else if (_units.containsKey(w)) {
      cur += _units[w]!;
      any = true;
    } else if (_isThousand(w)) {
      total += (cur == 0 ? 1 : cur) * 1000;
      cur = 0;
      any = true;
    } else {
      return null;
    }
  }
  return any ? total + cur : null;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[’ʼ`´]'), "'")
    .replaceAll(RegExp(r"[^0-9a-zа-яіїєґ',.\- ]"), ' ')
    .trim();

/// Число з тексту [text] у вигляді для поля («12», «2,5»). [decimal] -
/// дозволено дробову частину.
String? spokenToNumber(String text, {bool decimal = true}) {
  final s = _norm(text);
  if (s.isEmpty) return null;
  // уже цифрами: «12», «2.5», «2,5»
  final direct = RegExp(r'^-?\d+([.,]\d+)?$').firstMatch(s.replaceAll(' ', ''));
  if (direct != null) {
    final v = s.replaceAll(' ', '').replaceAll('.', ',');
    return decimal || !v.contains(',') ? v : null;
  }
  var words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  var neg = false;
  if (words.isNotEmpty && words.first == 'мінус') {
    neg = true;
    words = words.sublist(1);
  }
  String sign(String v) => neg && v != '0' ? '-$v' : v;

  // «півтора», «пів»
  if (words.length == 1 && (words.first == 'півтора' || words.first == 'півтори')) {
    return decimal ? sign('1,5') : null;
  }
  if (words.length == 1 && words.first == 'пів') return decimal ? sign('0,5') : null;

  // «… з половиною»
  if (words.length >= 3 &&
      words[words.length - 2] == 'з' &&
      words.last.startsWith('половин')) {
    final n = _int(words.sublist(0, words.length - 2));
    return n == null || !decimal ? null : sign('$n,5');
  }

  // «два кома нуль п'ять», «три цілих двадцять п'ять сотих»
  final sep = words.indexWhere((w) => w == 'кома' || w.startsWith('ціл'));
  if (sep >= 0) {
    if (!decimal) return null;
    final whole = _int(words.sublist(0, sep));
    var frac = words.sublist(sep + 1);
    if (whole == null || frac.isEmpty) return null;
    int? places;
    final last = frac.last;
    // «десятих», «сотих», «тисячних» - знаменник; але «десять», «десяти» - число
    if (!_units.containsKey(last)) {
      if (last.startsWith('десят')) {
        places = 1;
      } else if (last.startsWith('сот')) {
        places = 2;
      } else if (last.startsWith('тисячн')) {
        places = 3;
      }
    }
    if (places != null) frac = frac.sublist(0, frac.length - 1);
    // провідні нулі після «кома»: «нуль п'ять» -> 05
    var zeros = 0;
    while (zeros < frac.length - 1 && frac[zeros] == 'нуль') {
      zeros++;
    }
    final f = _int(frac.sublist(zeros));
    if (f == null) return null;
    var digits = '${'0' * zeros}$f';
    if (places != null) {
      if (digits.length > places) return null;
      digits = digits.padLeft(places, '0');
    }
    return sign('$whole,$digits');
  }

  final n = _int(words);
  return n == null ? null : sign('$n');
}
