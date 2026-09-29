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
