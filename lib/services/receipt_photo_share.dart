import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../data/repository.dart';
import 'app_config.dart';

/// Надсилання фото чеків розробнику для вдосконалення розпізнавання.
///
/// Лише після згоди людини ([consent]: «1» - так, «0» - ні, немає - ще не
/// питали). Без входу: фото йде функції `receipt-photo`
/// (supabase/functions/receipt-photo) під випадковим `device_id`, який
/// живе лише на цьому телефоні й не пов'язаний із відгуками. Помилки мовчки
/// ігноруються: розпізнавання чека від надсилання не залежить.
class ReceiptPhotoShare {
  final Repository repo;
  final http.Client? client;
  final Uri? endpoint;

  ReceiptPhotoShare(this.repo, {this.client, Uri? endpoint}) : endpoint = endpoint ?? serverEndpoint(AppConfig.current);

  static const consentKey = 'receipt_share_consent';
  static const idKey = 'device_receipt_share_id';

  /// Найбільший файл, який приймає сервер (4 МБ).
  static const maxBytes = 4 * 1024 * 1024;

  static Uri? serverEndpoint(AppConfig c) {
    final base = c.supabaseBase;
    return base == null ? null : base.replace(path: '${base.path}/functions/v1/receipt-photo');
  }

  /// Чи є куди надсилати (сервер у збірці).
  bool get available => endpoint != null;

  /// true / false - людина відповіла, null - ще не питали.
  Future<bool?> consent() async {
    final v = await repo.getMeta(consentKey);
    return v == null ? null : v == '1';
  }

  Future<void> setConsent(bool yes) => repo.setMeta(consentKey, yes ? '1' : '0');

  static bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

  Future<String> _deviceId() async {
    var id = await repo.getMeta(idKey);
    if (id == null) {
      id = const Uuid().v4();
      await repo.setMeta(idKey, id);
    }
    return id;
  }

  /// Надіслати фото за шляхом [path], якщо людина дала згоду. true -
  /// сервер прийняв (чи вже мав).
  Future<bool> sendIfAllowed(String path) async {
    final e = endpoint;
    if (e == null || await consent() != true) return false;
    final c = client ?? http.Client();
    try {
      final bytes = await File(path).readAsBytes();
      if (!_isJpeg(bytes) || bytes.length > maxBytes) return false;
      final r = await c
          .post(e,
              headers: const {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode({'device_id': await _deviceId(), 'photo_b64': base64Encode(bytes)}))
          .timeout(const Duration(seconds: 30));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (client == null) c.close();
    }
  }
}
