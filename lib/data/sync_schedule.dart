/// Розклад синхронізації (чисті функції - перевіряються тестами).
///
///  * щогодини - лише зміни, у «свою» хвилину телефона (випадкову, щоб
///    телефони всіх користувачів не стукали в сервер одночасно);
///  * зв'язку не було понад добу - одразу, щойно з'явиться інтернет (не
///    частіше за раз на [catchUpRetry]);
///  * раз на ніч (00:00-06:00) - стиснена повна копія бази на сервер.
abstract final class SyncSchedule {
  static const hourly = Duration(hours: 1);
  static const catchUpAfter = Duration(hours: 24);
  static const catchUpRetry = Duration(minutes: 5);
  static const nightEndsHour = 6;

  /// Початок поточного годинного «вікна» телефона з хвилиною [minute]:
  /// найпізніший момент hh:[minute], що не пізніше [now].
  static DateTime slotStart(DateTime now, int minute) {
    final s = DateTime(now.year, now.month, now.day, now.hour, minute);
    return s.isAfter(now) ? s.subtract(hourly) : s;
  }

  /// Пора щогодинної синхронізації: у цьому вікні ще не пробували.
  static bool hourlyDue(DateTime? lastTry, DateTime now, int minute) =>
      lastTry == null || lastTry.isBefore(slotStart(now, minute));

  /// Понад добу без успішної синхронізації - пробувати, щойно є зв'язок.
  static bool catchUpDue(DateTime? lastOk, DateTime? lastTry, DateTime now) {
    final stale = lastOk == null || now.difference(lastOk) > catchUpAfter;
    if (!stale) return false;
    return lastTry == null || now.difference(lastTry) >= catchUpRetry || lastTry.isAfter(now);
  }

  /// Чи пора синхронізуватись узагалі.
  static bool due({required DateTime? lastOk, required DateTime? lastTry, required DateTime now, required int minute}) =>
      hourlyDue(lastTry, now, minute) || catchUpDue(lastOk, lastTry, now);

  /// Пора нічної копії: зараз ніч (до 06:00) і цієї ночі копії ще не було.
  static bool nightlyDue(DateTime? lastNightly, DateTime now) {
    if (now.hour >= nightEndsHour) return false;
    if (lastNightly == null) return true;
    final sameNight = lastNightly.year == now.year &&
        lastNightly.month == now.month &&
        lastNightly.day == now.day &&
        lastNightly.hour < nightEndsHour;
    return !sameNight || lastNightly.isAfter(now);
  }
}
