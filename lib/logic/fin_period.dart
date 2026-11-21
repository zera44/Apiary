import '../l10n/l10n.dart';

/// Період огляду фінансів.
enum FinPeriod { day, week, month, year, custom }

/// Вибраний період: вид, «якір» (день, з якого рахуємо) і власні межі.
/// Один спосіб гортати й підписувати період для екранів «Фінанси» й «Операції».
class FinPeriodSel {
  FinPeriod period;
  DateTime anchor;
  DateTime? customFrom;
  DateTime? customTo;

  FinPeriodSel({this.period = FinPeriod.month, DateTime? anchor, this.customFrom, this.customTo})
      : anchor = anchor ?? today();

  /// Сьогоднішня дата без часу (рахуємо щоразу: екран може жити після півночі).
  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Межі: від початку першого дня до початку дня після останнього.
  (DateTime, DateTime) get range {
    final a = anchor;
    switch (period) {
      case FinPeriod.day:
        return (DateTime(a.year, a.month, a.day), DateTime(a.year, a.month, a.day + 1));
      case FinPeriod.week:
        final d = a.day - (a.weekday - 1);
        return (DateTime(a.year, a.month, d), DateTime(a.year, a.month, d + 7));
      case FinPeriod.month:
        return (DateTime(a.year, a.month), DateTime(a.year, a.month + 1));
      case FinPeriod.year:
        return (DateTime(a.year), DateTime(a.year + 1));
      case FinPeriod.custom:
        final f = customFrom ?? DateTime(a.year, a.month);
        final t = customTo ?? DateTime(a.year, a.month + 1, 0);
        return (f, DateTime(t.year, t.month, t.day + 1));
    }
  }

  /// Останній день періоду (включно).
  DateTime get lastDay {
    final t = range.$2;
    return DateTime(t.year, t.month, t.day - 1);
  }

  static String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  static String _dm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  /// Підпис над списком: «Листопад 2026», «21.11.2026», «16.11 – 22.11.2026», «2026».
  String get title {
    final f = range.$1;
    switch (period) {
      case FinPeriod.day:
        return _dmy(f);
      case FinPeriod.week:
        return '${_dm(f)} – ${_dmy(lastDay)}';
      case FinPeriod.month:
        return '${tr.monthNames[f.month]} ${f.year}';
      case FinPeriod.year:
        return '${f.year}';
      case FinPeriod.custom:
        return '${_dmy(f)} – ${_dmy(lastDay)}';
    }
  }

  /// У майбутнє не гортаємо: наступний період має починатися не пізніше сьогодні.
  bool get canGoForward => !range.$2.isAfter(today());

  /// Крок назад ([d] = -1) чи вперед ([d] = 1). Для власного періоду нічого не робить.
  bool shift(int d) {
    final a = anchor;
    final DateTime next;
    switch (period) {
      case FinPeriod.day:
        next = DateTime(a.year, a.month, a.day + d);
      case FinPeriod.week:
        next = DateTime(a.year, a.month, a.day + 7 * d);
      case FinPeriod.month:
        next = DateTime(a.year, a.month + d, 1);
      case FinPeriod.year:
        next = DateTime(a.year + d, 1, 1);
      case FinPeriod.custom:
        return false;
    }
    if (d > 0 && !canGoForward) return false;
    anchor = next;
    return true;
  }

  /// Вкладка: завжди поточний день, тиждень, місяць, рік.
  void select(FinPeriod p) {
    period = p;
    final t = today();
    anchor = p == FinPeriod.month ? DateTime(t.year, t.month, 1) : t;
  }

  /// Власний період; межі впорядковуються.
  void setCustom(DateTime a, DateTime b) {
    period = FinPeriod.custom;
    customFrom = b.isBefore(a) ? b : a;
    customTo = b.isBefore(a) ? a : b;
  }
}
