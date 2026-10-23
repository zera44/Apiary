import 'package:flutter/services.dart';

/// Поле числа: розряди тисяч відокремлюються пробілом під час введення
/// (1000 -> «1 000», 1000000 -> «1 000 000»), дробова частина - після коми
/// чи крапки без змін. Розбирає такі числа `parseAmount` (пробіли ігнорує).
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter();

  static final _ok = RegExp(r'^\d*[.,]?\d*$');
  static final _space = RegExp(r'\s');

  /// Згрупувати цілу частину по три цифри: «1234567» -> «1 234 567».
  static String group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue now) {
    final raw = now.text;
    final clean = raw.replaceAll(_space, '');
    if (!_ok.hasMatch(clean)) return now; // інші символи відсіюють інші фільтри
    final cut = clean.indexOf(RegExp(r'[.,]'));
    final whole = cut < 0 ? clean : clean.substring(0, cut);
    final tail = cut < 0 ? '' : clean.substring(cut);
    final out = group(whole) + tail;
    // курсор: стільки ж значущих символів (не пробілів) зліва, як було
    final end = now.selection.end.clamp(0, raw.length);
    var sig = 0;
    for (var i = 0; i < end; i++) {
      if (!_space.hasMatch(raw[i])) sig++;
    }
    var pos = 0;
    for (var seen = 0; pos < out.length && seen < sig; pos++) {
      if (out[pos] != ' ') seen++;
    }
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: pos),
    );
  }
}

/// Для полів кількості й грошей: лише цифри й кома/крапка, з розрядами.
final List<TextInputFormatter> thousandsInput = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
  const ThousandsFormatter(),
];
