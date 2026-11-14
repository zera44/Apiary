import '../data/repository.dart';

/// Графік днів, у які приходять нагадування про обхід.
enum NotifyMode { daily, w52, w22, custom }

/// Налаштування сповіщень про обхід: час ранкового й повторного нагадування
/// (хвилини від півночі) і графік днів. Чиста логіка без плагінів.
class NotifySchedule {
  final bool enabled;
  final int morning;
  final int repeat;
  final NotifyMode mode;

  /// Дата початку для 5/2 і 2/2 (лише рік-місяць-день).
  final DateTime? start;

  /// Дні довільного графіка (лише рік-місяць-день).
  final Set<DateTime> custom;

  const NotifySchedule({
    this.enabled = true,
    this.morning = 9 * 60,
    this.repeat = 14 * 60,
    this.mode = NotifyMode.daily,
    this.start,
    this.custom = const {},
  });

  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Чи приходять нагадування в цей день.
  bool allows(DateTime d) {
    if (!enabled) return false;
    final x = day(d);
    switch (mode) {
      case NotifyMode.daily:
        return true;
      case NotifyMode.w52:
      case NotifyMode.w22:
        final s = start == null ? null : day(start!);
        if (s == null) return true;
        final n = DateTime.utc(x.year, x.month, x.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays;
        if (n < 0) return false;
        return mode == NotifyMode.w52 ? n % 7 < 5 : n % 4 < 2;
      case NotifyMode.custom:
        return custom.contains(x);
    }
  }

  /// Найближчий дозволений день від [from] (включно) у межах [within] днів.
  DateTime? nextAllowed(DateTime from, {int within = 60}) {
    final f = day(from);
    for (var i = 0; i <= within; i++) {
      final d = DateTime(f.year, f.month, f.day + i);
      if (allows(d)) return d;
    }
    return null;
  }

  /// Довільний графік закінчився: усі його дні вже позаду.
  bool customEnded(DateTime now) {
    if (!enabled || mode != NotifyMode.custom || custom.isEmpty) return false;
    final last = custom.reduce((a, b) => a.isAfter(b) ? a : b);
    return last.isBefore(day(now));
  }

  /// День, коли треба нагадати про кінець графіка (наступний після останнього).
  DateTime? get endNoticeDay {
    if (mode != NotifyMode.custom || custom.isEmpty) return null;
    final last = custom.reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime(last.year, last.month, last.day + 1);
  }

  NotifySchedule copyWith({
    bool? enabled,
    int? morning,
    int? repeat,
    NotifyMode? mode,
    DateTime? start,
    Set<DateTime>? custom,
  }) =>
      NotifySchedule(
        enabled: enabled ?? this.enabled,
        morning: morning ?? this.morning,
        repeat: repeat ?? this.repeat,
        mode: mode ?? this.mode,
        start: start ?? this.start,
        custom: custom ?? this.custom,
      );

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _kEnabled = 'notif_enabled';
  static const _kMorning = 'notif_morning';
  static const _kRepeat = 'notif_repeat';
  static const _kMode = 'notif_mode';
  static const _kStart = 'notif_start';
  static const _kCustom = 'notif_days';

  static Future<NotifySchedule> load(Repository repo) async {
    const d = NotifySchedule();
    final mode = await repo.getMeta(_kMode);
    final custom = <DateTime>{};
    for (final s in (await repo.getMeta(_kCustom) ?? '').split(',')) {
      final t = DateTime.tryParse(s.trim());
      if (t != null) custom.add(day(t));
    }
    final start = await repo.getMeta(_kStart);
    return NotifySchedule(
      enabled: (await repo.getMeta(_kEnabled)) != '0',
      morning: int.tryParse(await repo.getMeta(_kMorning) ?? '') ?? d.morning,
      repeat: int.tryParse(await repo.getMeta(_kRepeat) ?? '') ?? d.repeat,
      mode: NotifyMode.values.firstWhere((m) => m.name == mode, orElse: () => NotifyMode.daily),
      start: start == null ? null : DateTime.tryParse(start),
      custom: custom,
    );
  }

  Future<void> save(Repository repo) async {
    await repo.setMeta(_kEnabled, enabled ? '1' : '0');
    await repo.setMeta(_kMorning, '$morning');
    await repo.setMeta(_kRepeat, '$repeat');
    await repo.setMeta(_kMode, mode.name);
    await repo.setMeta(_kStart, start == null ? '' : _iso(start!));
    final days = custom.toList()..sort();
    await repo.setMeta(_kCustom, days.map(_iso).join(','));
  }
}
