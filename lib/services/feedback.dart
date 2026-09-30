import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Результат відправки відгуку.
enum FeedbackResult {
  /// Лист прийнято сервісом — він прийде на [FeedbackService.email].
  sent,

  /// У цій збірці не задано адресу форми (APIARY_FEEDBACK_URL).
  notConfigured,

  /// Немає інтернету, сервіс відповів помилкою тощо.
  failed,
}

/// Зворотний зв'язок: текст користувача відправляється через сервіс форм
/// (Formspree), а той пересилає його листом на [email].
///
/// Пароль від пошти в застосунку не зберігається — лише адреса форми, яку
/// задають під час збірки:
///   flutter build apk --dart-define=APIARY_FEEDBACK_URL=https://formspree.io/f/XXXXXXXX
/// (у CI — із секрету репозиторію APIARY_FEEDBACK_URL). Адресу, на яку
/// приходять листи, задають у налаштуваннях форми на formspree.io.
class FeedbackService {
  static const email = 'myapiaryrezvin@gmail.com';
  static const subject = "Моя пасіка: зворотний зв'язок";
  static const maxLength = 5000;
  static const url = String.fromEnvironment('APIARY_FEEDBACK_URL');

  /// Адреса форми придатна лише з HTTPS і без паролів в адресі.
  static Uri? endpoint(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.host.isEmpty || u.scheme != 'https') return null;
    if (u.userInfo.isNotEmpty) return null;
    return u;
  }

  /// Відправити [message]. [client] і [formUrl] — для тестів.
  static Future<FeedbackResult> send(String message,
      {http.Client? client, String formUrl = url}) async {
    final text = message.trim();
    if (text.isEmpty) return FeedbackResult.failed;
    final target = endpoint(formUrl);
    if (target == null) return FeedbackResult.notConfigured;
    final c = client ?? http.Client();
    try {
      final resp = await c
          .post(
            target,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              '_subject': subject,
              'message': text.length > maxLength ? text.substring(0, maxLength) : text,
              'platform': _platform(),
              'sent_at': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300
          ? FeedbackResult.sent
          : FeedbackResult.failed;
    } catch (_) {
      return FeedbackResult.failed;
    } finally {
      if (client == null) c.close();
    }
  }

  static String _platform() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }
}
