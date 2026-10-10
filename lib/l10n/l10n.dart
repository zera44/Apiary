import 'package:flutter/foundation.dart' show ValueNotifier;

import 'strings.dart';
import 'strings_uk.dart';

export 'strings.dart';

/// Поточна мова інтерфейсу. Поки одна - українська; коли з'являться інші,
/// [use] перемикає мову, а [language] - сигнал перебудувати екрани.
class L10n {
  L10n._();

  /// Доступні мови: код -> тексти.
  static final Map<String, AppStrings> supported = {'uk': const AppStringsUk()};

  static AppStrings _current = const AppStringsUk();
  static AppStrings get current => _current;

  /// Код поточної мови (слухати, щоб перебудувати інтерфейс після зміни).
  static final ValueNotifier<String> language = ValueNotifier('uk');

  /// Увімкнути мову [code]; невідома - лишається поточна. Повертає, чи вдалося.
  static bool use(String code) {
    final s = supported[code];
    if (s == null) return false;
    _current = s;
    language.value = code;
    return true;
  }

  /// Тести: підставити свої тексти (null - повернути українську).
  static void debugOverride(AppStrings? strings) {
    _current = strings ?? const AppStringsUk();
    language.value = _current.languageCode;
  }
}

/// Тексти поточної мови: `tr.settingsTabMain`.
AppStrings get tr => L10n.current;
