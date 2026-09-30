import 'dart:io';

import 'package:flutter/foundation.dart';

/// Автозапуск разом з Windows (для нагадувань про обхід: на Windows їх
/// показує сам застосунок, тож він має бути запущений). Запис у
/// HKCU\...\Run — права адміністратора не потрібні. Автозапущений
/// застосунок стартує згорнутим (прапорець --autostart).
class Autostart {
  static bool get supported => !kIsWeb && Platform.isWindows;

  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'MojaPasika';

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      final r = await Process.run('reg', ['query', _key, '/v', _name]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Якщо автозапуск увімкнено, але в реєстрі шлях до іншого exe (програму
  /// оновили, розпакувавши в нову теку, чи перенесли), — оновити шлях на
  /// поточний. Викликається при кожному запуску.
  static Future<void> syncPath() async {
    if (!supported) return;
    try {
      final r = await Process.run('reg', ['query', _key, '/v', _name]);
      if (r.exitCode != 0) return; // вимкнено
      final out = '${r.stdout}'.toLowerCase();
      if (out.contains(Platform.resolvedExecutable.toLowerCase())) return;
      await setEnabled(true);
    } catch (_) {}
  }

  /// Повертає true, якщо вдалося.
  static Future<bool> setEnabled(bool on) async {
    if (!supported) return false;
    try {
      final r = on
          ? await Process.run('reg', [
              'add', _key, '/v', _name, '/t', 'REG_SZ',
              '/d', '"${Platform.resolvedExecutable}" --autostart', '/f',
            ])
          : await Process.run('reg', ['delete', _key, '/v', _name, '/f']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
