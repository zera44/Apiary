import 'package:flutter/widgets.dart';

/// Чи застосунок зараз на екрані. Періодичні таймери у згорнутому
/// застосунку нічого не роблять (фонові завдання Android і так працюють
/// окремо), а після повернення наступний тик усе наздожене.
bool appInForeground() {
  try {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
  } catch (_) {
    return true; // без прив'язки Flutter (тести) - працюємо як завжди
  }
}
