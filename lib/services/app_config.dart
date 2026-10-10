import 'package:flutter/foundation.dart' show kReleaseMode;

/// Налаштування збірки (задаються під час збірки, у коді їх немає):
///
///   flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///                     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Поки адреси й ключа немає, синхронізація вимкнена, а все локальне (дані,
/// фото, резервні копії, налаштування) працює повністю.
class AppConfig {
  /// Адреса проєкту Supabase (лише https).
  final String supabaseUrl;

  /// Публічний («anon») ключ проєкту Supabase. Він не секретний: доступ до
  /// даних обмежують правила на сервері (Row Level Security).
  final String supabaseAnonKey;

  const AppConfig({this.supabaseUrl = '', this.supabaseAnonKey = ''});

  /// Те, що задано під час збірки.
  static const fromEnvironment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  /// Поточні налаштування (тести підставляють свої).
  static AppConfig current = fromEnvironment;

  /// Адреса сервера, якщо вона безпечна (див. [secureBase]); інакше null.
  Uri? get supabaseBase => supabaseUrl.trim().isEmpty ? null : secureBase(supabaseUrl);

  /// Синхронізація можлива: є безпечна адреса й ключ.
  bool get syncConfigured => supabaseBase != null && supabaseAnonKey.trim().isNotEmpty;

  /// Адреса сервера придатна лише з HTTPS (дані - зокрема координати пасік -
  /// не повинні йти відкритим текстом). Виняток - локальний сервер розробки
  /// і лише не в release-збірці. Без паролів в адресі, без ?параметрів і #.
  static Uri? secureBase(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty) return null;
    final local = u.host == 'localhost' || u.host == '127.0.0.1' || u.host == '10.0.2.2';
    if (u.scheme != 'https' && !(u.scheme == 'http' && local && !kReleaseMode)) return null;
    if (u.userInfo.isNotEmpty) return null;
    final path = u.path.endsWith('/') ? u.path.substring(0, u.path.length - 1) : u.path;
    return Uri(scheme: u.scheme, host: u.host, port: u.port, path: path);
  }
}
