import 'strings.dart';

/// Українська (типова мова застосунку).
class AppStringsUk extends AppStrings {
  const AppStringsUk();

  @override
  String get languageCode => 'uk';

  @override
  String plural(int n, {required String one, required String few, required String many}) =>
      pluralUk(n, one: one, few: few, many: many);

  // ---- Налаштування ----
  @override
  String get settingsTitle => 'Налаштування';
  @override
  String get settingsTabMain => 'Головне';
  @override
  String get settingsTabTemplates => 'Шаблони';

  // ---- Синхронізація ----
  @override
  String get syncSection => 'Синхронізація';
  @override
  String get syncDisabled => 'Синхронізацію ще не налаштовано - дані лише на цьому пристрої';
  @override
  String get syncOffline => 'Немає зв\'язку із сервером - зміни збережено на пристрої';
  @override
  String syncPending(int n) =>
      'Очікує відправки: $n ${plural(n, one: 'зміна', few: 'зміни', many: 'змін')}';
  @override
  String syncLastOk(String when) => 'Остання синхронізація: $when';
  @override
  String syncError(String details) => 'Помилка синхронізації: $details';

  // ---- Загальне ----
  @override
  String get close => 'Закрити';

  // ---- Фото складу ----
  @override
  String get photoOpen => 'Відкрити фото';
  @override
  String photoFailed(String details) => 'Не вдалося отримати фото: $details';

  // ---- Дата й час ----
  @override
  String todayAt(String hm) => 'сьогодні $hm';

  // ---- База даних ----
  @override
  String get startupErrorTitle => 'Не вдалося відкрити дані пасіки';
  @override
  String get startupErrorHint =>
      'Можливі причини: програму вже запущено в іншому вікні, закінчилось місце на диску '
      'або файл даних пошкоджено. Закрийте інші копії програми й спробуйте ще раз.';
  @override
  String get startupOpening => 'Відкриваємо…';
  @override
  String get retry => 'Спробувати ще раз';
  @override
  String dbTooNew(int found, int supported) =>
      'Дані збережено новішою версією застосунку (версія бази $found, ця версія '
      'знає до $supported). Оновіть застосунок.';
}
