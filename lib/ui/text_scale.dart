import 'package:flutter/material.dart';

import '../data/repository.dart';

/// Розмір шрифту в усьому застосунку (Налаштування → «Головне»). Найменший
/// рівень - звичайний розмір; далі лише більші (для людей зі слабким зором).
/// Множиться на системний масштаб тексту Android. Налаштування цього
/// телефона: у резервну копію не переходить (ключ `device_`).
abstract final class AppTextScale {
  static const key = 'device_text_scale';

  /// Рівні: звичайний, більший, великий, дуже великий, найбільший
  /// (на 15% більший за «дуже великий»).
  static const levels = [1.0, 1.15, 1.3, 1.5, 1.725];

  /// Обраний рівень (одразу перебудовує застосунок).
  static final ValueNotifier<double> value = ValueNotifier(levels.first);

  /// Під час запуску: збережений рівень (немає або невідомий - звичайний).
  static Future<void> load(Repository repo) async {
    value.value = _valid(double.tryParse(await repo.getMeta(key) ?? ''));
  }

  static Future<void> set(Repository repo, double v) async {
    value.value = _valid(v);
    await repo.setMeta(key, '${value.value}');
  }

  static double _valid(double? v) => levels.contains(v) ? v! : levels.first;

  /// Обгортка над усім застосунком (MaterialApp.builder).
  static Widget apply(Widget child) => ValueListenableBuilder<double>(
    valueListenable: value,
    // MediaQuery - завжди (і для звичайного рівня): інакше зміна рівня
    // перебудувала б застосунок з нуля й закрила відкриті екрани
    builder: (context, k, _) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: k == 1.0 ? mq : mq.copyWith(textScaler: _Times(mq.textScaler, k)),
        child: child,
      );
    },
  );
}

/// Системний масштаб × обраний рівень.
class _Times extends TextScaler {
  final TextScaler base;
  final double k;
  const _Times(this.base, this.k);

  @override
  double scale(double fontSize) => base.scale(fontSize) * k;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * k;

  @override
  bool operator ==(Object other) => other is _Times && other.base == base && other.k == k;

  @override
  int get hashCode => Object.hash(base, k);
}
