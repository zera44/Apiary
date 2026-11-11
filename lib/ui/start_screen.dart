import 'package:flutter/foundation.dart';

import '../data/repository.dart';

/// Початковий екран (Налаштування → «Головне»): що відкривається одразу після
/// запуску застосунку. За замовчуванням - головна сторінка; інші екрани
/// відкриваються поверх неї, тож «назад» повертає на головну.
/// Налаштування цього телефона: у резервну копію не переходить (ключ `device_`).
enum StartScreen { home, scanner, apiary, stock, finances }

abstract final class AppStartScreen {
  static const key = 'device_start_screen';

  /// Обраний початковий екран.
  static final ValueNotifier<StartScreen> value = ValueNotifier(StartScreen.home);

  /// Вибраний екран уже відкривали за цей запуск: повернення на головну
  /// (чи новий вхід) не відкриває його вдруге.
  static bool opened = false;

  static Future<StartScreen> load(Repository repo) async =>
      value.value = parse(await repo.getMeta(key));

  static Future<void> set(Repository repo, StartScreen s) async {
    value.value = s;
    await repo.setMeta(key, s.name);
  }

  static StartScreen parse(String? s) =>
      StartScreen.values.where((o) => o.name == s).firstOrNull ?? StartScreen.home;
}
