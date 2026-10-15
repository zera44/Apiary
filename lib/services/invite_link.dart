import 'package:flutter/foundation.dart' show ValueNotifier;

/// Запрошувальне посилання: код помічника з адреси, яку відкрили.
///
/// Посилання, яке надсилає власник: `<сервер>/functions/v1/join?t=<код>`;
/// воно перенаправляє у застосунок на `vulyk://join?t=<код>` (див.
/// supabase/functions/join). Розуміємо обидва вигляди.
abstract final class InviteLink {
  static const scheme = 'vulyk';
  static final _token = RegExp(r'^[0-9a-f]{64}$');

  /// Код із адреси або null - це не наше посилання.
  static String? tokenFrom(Uri uri) {
    final t = uri.queryParameters['t'];
    if (t == null || !_token.hasMatch(t)) return null;
    final app = uri.scheme == scheme && uri.host == 'join';
    final web = (uri.scheme == 'https' || uri.scheme == 'http') && uri.path.endsWith('/functions/v1/join');
    return app || web ? t : null;
  }

  /// Те саме з тексту (вставили посилання вручну).
  static String? tokenFromText(String text) {
    final u = Uri.tryParse(text.trim());
    return u == null ? null : tokenFrom(u);
  }

  /// Посилання для надсилання: [base] - адреса сервера (https://x.supabase.co).
  static Uri build(Uri base, String token) => base.replace(
        path: '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/functions/v1/join',
        queryParameters: {'t': token},
      );

  /// Код посилання, яке відкрили й яке ще не прийняте (головний екран
  /// приймає його, щойно сервер підключиться; відкрили до входу - чекає).
  static final ValueNotifier<String?> pending = ValueNotifier(null);
}
