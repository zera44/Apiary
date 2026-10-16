import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';

/// Орієнтація екрана (Налаштування → «Головне»): авто (як повернуто телефон),
/// лише вертикальна або лише горизонтальна. Налаштування цього телефона:
/// у резервну копію не переходить (ключ `device_`).
enum ScreenOrientation { auto, portrait, landscape }

abstract final class AppOrientation {
  static const key = 'device_orientation';

  /// Обрана орієнтація (одразу застосовується).
  static final ValueNotifier<ScreenOrientation> value = ValueNotifier(ScreenOrientation.auto);

  /// Під час запуску: збережена орієнтація (немає або невідома - авто).
  static Future<void> load(Repository repo) async {
    value.value = _parse(await repo.getMeta(key));
    await _apply(value.value);
  }

  static Future<void> set(Repository repo, ScreenOrientation o) async {
    value.value = o;
    await repo.setMeta(key, o.name);
    await _apply(o);
  }

  static ScreenOrientation _parse(String? s) =>
      ScreenOrientation.values.where((o) => o.name == s).firstOrNull ?? ScreenOrientation.auto;

  static Future<void> _apply(ScreenOrientation o) async {
    try {
      await SystemChrome.setPreferredOrientations(switch (o) {
        // порожній список - як дозволяє система (автоповорот телефона)
        ScreenOrientation.auto => const [],
        ScreenOrientation.portrait => const [DeviceOrientation.portraitUp],
        ScreenOrientation.landscape => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
      });
    } catch (_) {
      // тести й платформи без поворотів - без змін
    }
  }
}
