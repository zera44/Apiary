import 'package:flutter/foundation.dart' show ValueNotifier;

import '../data/repository.dart';
import 'strings.dart';
import 'strings_en.dart';
import 'strings_uk.dart';

export 'strings.dart';

/// Поточна мова інтерфейсу (Налаштування → «Головне» → «Змінити мову»).
///
/// Вибір зберігається в app_meta і відновлюється ([load]) на старті КОЖНОГО
/// входу - і застосунку, і фонових завдань (синхронізація, сповіщення), інакше
/// фон говоритиме українською. Після [use] застосунок перебудовує всі екрани
/// (див. ApiaryApp): const-віджети, що читають [tr], самі не оновилися б.
class L10n {
  L10n._();

  /// Налаштування цього телефона: у резервну копію не переходить (`device_`).
  static const key = 'device_language';

  /// Доступні мови: код -> тексти (у порядку показу у виборі мови).
  static final Map<String, AppStrings> supported = {
    'uk': const AppStringsUk(),
    'en': const AppStringsEn(),
  };

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

  /// Під час запуску: збережена мова (немає або невідома - українська).
  static Future<void> load(Repository repo) async {
    if (!use(await repo.getMeta(key) ?? '')) use('uk');
  }

  /// Обрати мову й запам'ятати вибір.
  static Future<void> set(Repository repo, String code) async {
    if (use(code)) await repo.setMeta(key, code);
  }

  /// Тести: підставити свої тексти (null - повернути українську).
  static void debugOverride(AppStrings? strings) {
    _current = strings ?? const AppStringsUk();
    language.value = _current.languageCode;
  }
}

/// Тексти поточної мови: `tr.settingsTabMain`.
AppStrings get tr => L10n.current;
