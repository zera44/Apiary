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

  // ---- Резервні копії ----
  @override
  String get backupsSection => 'Резервні копії';
  @override
  String get backupsHint => 'Копія даних робиться сама кожні 6 годин і зберігається на цьому '
      'телефоні 2 дні. Фото в копію не входять - вони лишаються на телефоні.';
  @override
  String backupsLast(String when) => 'Остання копія: $when';
  @override
  String get backupsNone => 'Ще немає жодної копії';
  @override
  String get backupNow => 'Зробити копію зараз';
  @override
  String get backupMade => 'Копію зроблено';
  @override
  String backupFailed(String details) => 'Не вдалося зробити копію: $details';
  @override
  String get backupKindAuto => 'автоматична';
  @override
  String get backupKindManual => 'зроблена вручну';
  @override
  String get backupKindBeforeRestore => 'стан перед відновленням';
  @override
  String get backupRestore => 'Відновити';
  @override
  String get backupRestoreTitle => 'Відновити дані з копії?';
  @override
  String backupRestoreText(String when) =>
      'Дані на цьому телефоні замінить копія від $when. Поточний стан спершу збережеться '
      'окремою копією - відновлення можна буде скасувати.';
  @override
  String get backupRestored => 'Дані відновлено з копії';
  @override
  String backupRestoreFailed(String details) => 'Не вдалося відновити: $details';
  @override
  String get backupSaveToFile => 'Зберегти у файл';
  @override
  String get backupSaveDialog => 'Зберегти резервну копію';
  @override
  String get backupShare => 'Поділитися';
  @override
  String get backupSaved => 'Копію збережено у файл';
  @override
  String get backupSaveCancelled => 'Збереження скасовано';
  @override
  String backupSaveFailed(String details) => 'Не вдалося зберегти файл: $details';
  @override
  String get undo => 'Скасувати';
  @override
  String get cancel => 'Скасувати';

  @override
  String fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} МБ';
  }

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
