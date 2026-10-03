/// Планування нагадувань про обхід вуликів. Чиста логіка без плагінів —
/// щоб її можна було перевіряти тестами; самі повідомлення показує
/// `services/reminders.dart`.

/// Об'єкт (вулик або група вуликів), для якого діє періодичність обходу.
class VisitTarget {
  /// Стабільний ключ власника значень: "g:<group_id>" або "e:<element_id>".
  final String key;

  /// Id вулика (для групи — першого вулика групи), щоб можна було відкрити.
  final String elementId;
  final String apiaryName;

  /// Назва вулика як на карті ("Вулик 5"); порожньою не буває.
  final String name;

  /// Періодичність обходу, днів (більше 0), або null, якщо не задана.
  final int? periodDays;

  /// Дата останнього обходу "ДД.ММ.РРРР" (як зберігається), або null.
  final String? lastVisit;

  /// Коли періодичність було задано востаннє — точка відліку, якщо дати
  /// останнього обходу ще немає.
  final DateTime? periodSetAt;

  const VisitTarget({
    required this.key,
    required this.elementId,
    required this.apiaryName,
    required this.name,
    this.periodDays,
    this.lastVisit,
    this.periodSetAt,
  });
}

/// Одне заплановане нагадування.
class PlannedReminder {
  final String elementId;
  final String title;
  final String body;
  final DateTime when;
  const PlannedReminder(this.elementId, this.title, this.body, this.when);
}

/// Текст нагадування.
String reminderBody(String hiveName) {
  // "Вулик 5" → "5", щоб не вийшло "у вулик Вулик 5"
  final m = RegExp(r'^вулик\s+(.+)$', caseSensitive: false, unicode: true).firstMatch(hiveName.trim());
  final label = m == null ? hiveName.trim() : m.group(1)!;
  return 'Ти давно не заглядав у вулик $label. Перевір його';
}

/// Найбільша піддержувана періодичність (років вистачить із запасом).
const kMaxVisitPeriodDays = 3650;

DateTime? _parseDate(String? text) {
  if (text == null) return null;
  final parts = text.trim().split('.');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]), m = int.tryParse(parts[1]), y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  final dt = DateTime(y, m, d);
  if (dt.day != d || dt.month != m || dt.year != y) return null;
  return dt;
}

/// Моменти нагадувань: [lastVisit] + період, далі кожен наступний період;
/// лише ті, що ще попереду. Так, початок 1.10 і період 2 дні дає 3.10, 5.10…
/// а якщо 3.10 обійшли (дата обходу стала 3.10) — 5.10, 7.10…
/// Календарна арифметика (а не 24-годинні Duration), тож перехід на літній
/// час не зсуває годину.
List<DateTime> reminderTimes({
  required DateTime lastVisit,
  required int periodDays,
  required DateTime now,
  int count = 3,
  int hour = 9,
}) {
  if (periodDays <= 0 || periodDays > kMaxVisitPeriodDays || count <= 0) return const [];
  final last = DateTime(lastVisit.year, lastVisit.month, lastVisit.day);
  // стрибок одразу до потрібного періоду, а не цикл із першого
  final diff = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(last.year, last.month, last.day))
      .inDays;
  var k = diff ~/ periodDays;
  if (k < 1) k = 1;
  final out = <DateTime>[];
  for (var guard = 0; out.length < count && guard < 1000; guard++, k++) {
    final t = DateTime(last.year, last.month, last.day + periodDays * k, hour);
    if (t.isAfter(now)) out.add(t);
  }
  return out;
}

/// Усі нагадування для набору об'єктів, за зростанням часу, не більше
/// [limit] (ліміти системи на кількість запланованих сповіщень).
List<PlannedReminder> planReminders(
  Iterable<VisitTarget> targets, {
  required DateTime now,
  int? perTarget,
  int limit = 200,
}) {
  final out = <PlannedReminder>[];
  for (final t in targets) {
    final period = t.periodDays;
    if (period == null) continue;
    final anchor = _parseDate(t.lastVisit) ?? t.periodSetAt;
    if (anchor == null) continue;
    final title = t.apiaryName.isEmpty ? 'Моя пасіка' : t.apiaryName;
    // наперед — приблизно на 45 днів (щоб непройдений обхід «не замовкав»,
    // навіть якщо застосунок довго не відкривали), але не менше 3
    final count = perTarget ?? (45 ~/ period).clamp(3, 45);
    for (final when in reminderTimes(
        lastVisit: anchor, periodDays: period, now: now, count: count)) {
      out.add(PlannedReminder(t.elementId, title, reminderBody(t.name), when));
    }
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// Найпізніше нагадування, час якого вже настав (для Windows, де система
/// не вміє відкладені сповіщення: застосунок показує їх сам), або null.
PlannedReminder? dueReminder(VisitTarget t, {required DateTime now, int hour = 9}) {
  final period = t.periodDays;
  if (period == null || period <= 0 || period > kMaxVisitPeriodDays) return null;
  final anchor = _parseDate(t.lastVisit) ?? t.periodSetAt;
  if (anchor == null) return null;
  final last = DateTime(anchor.year, anchor.month, anchor.day);
  final diff = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(last.year, last.month, last.day))
      .inDays;
  var k = diff ~/ period;
  DateTime at(int n) => DateTime(last.year, last.month, last.day + period * n, hour);
  while (k >= 1 && at(k).isAfter(now)) {
    k--;
  }
  if (k < 1) return null;
  final title = t.apiaryName.isEmpty ? 'Моя пасіка' : t.apiaryName;
  return PlannedReminder(t.elementId, title, reminderBody(t.name), at(k));
}

/// Днів до наступного обходу: період мінус дні, що минули від останнього
/// обходу (або від дня, коли задали періодичність). Не менше 0. null - якщо
/// періодичності чи точки відліку немає.
int? visitDaysLeft(VisitTarget t, DateTime now) {
  final period = t.periodDays;
  if (period == null || period <= 0) return null;
  final anchor = _parseDate(t.lastVisit) ?? t.periodSetAt;
  if (anchor == null) return null;
  final elapsed = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
      .inDays;
  final left = period - elapsed;
  return left < 0 ? 0 : left;
}
