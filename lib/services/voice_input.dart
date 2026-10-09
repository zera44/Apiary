import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Українська модель Vosk. У APK її немає (~133 МБ): скачується один раз
/// при першому голосовому вводі, далі все працює без інтернету.
const kVoskModelName = 'vosk-model-small-uk-v3-small';
const kVoskModelUrl = 'https://alphacephei.com/vosk/models/$kVoskModelName.zip';

/// Приблизний розмір архіву (для підказки й відсотків, якщо сервер не
/// назвав розмір).
const kVoskModelMb = 133;

/// Назва версії моделі на телефоні: інша назва - модель розпакується заново.
const kVoskModelVersion = 'uk-v3-small';

/// Голосовий ввід (Vosk, офлайн): лише Android.
class VoiceInput {
  VoiceInput._();
  static final instance = VoiceInput._();

  bool get platformOk => !kIsWeb && Platform.isAndroid;

  Future<bool> available() async => platformOk;

  bool _loaded = false;

  /// Чи модель уже є на телефоні (розпакована).
  Future<bool> modelOnPhone() async => _loaded || await Vosk.ready(kVoskModelVersion);

  /// Завантажити розпаковану модель у пам'ять. Моделі немає - помилка
  /// (спершу [download]).
  Future<void> ensureReady() async {
    if (_loaded) return;
    await Vosk.init(version: kVoskModelVersion);
    _loaded = true;
  }

  /// Скачати модель (докачує перерваний файл), розпакувати й завантажити.
  /// [onProgress] - частка 0..1; [cancelled] - перевіряється під час
  /// скачування (true - зупинитись, недокачане лишається для докачки).
  Future<void> download({
    required void Function(double progress) onProgress,
    required bool Function() cancelled,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final part = File('${dir.path}/$kVoskModelName.zip.part');
    final client = http.Client();
    try {
      var have = await part.exists() ? await part.length() : 0;
      final req = http.Request('GET', Uri.parse(kVoskModelUrl));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final resp = await client.send(req);
      if (resp.statusCode == 200) {
        have = 0; // сервер віддає з початку
      } else if (resp.statusCode == 416) {
        // уже докачано повністю
      } else if (resp.statusCode != 206) {
        throw HttpException('сервер відповів ${resp.statusCode}');
      }
      final total = resp.statusCode == 416
          ? have
          : (resp.contentLength == null ? kVoskModelMb * 1024 * 1024 : have + resp.contentLength!);
      if (resp.statusCode != 416) {
        final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
        try {
          var got = have;
          var lastReport = 0;
          await for (final chunk in resp.stream) {
            if (cancelled()) throw const _Cancelled();
            sink.add(chunk);
            got += chunk.length;
            if (got - lastReport > 512 * 1024) {
              lastReport = got;
              onProgress((got / total).clamp(0.0, 1.0));
            }
          }
        } finally {
          await sink.close();
        }
      }
      onProgress(1);
      final zip = File('${dir.path}/$kVoskModelName.zip');
      if (await zip.exists()) await zip.delete();
      await part.rename(zip.path);
      try {
        await Vosk.init(version: kVoskModelVersion, zip: zip.path);
      } catch (_) {
        // пошкоджений архів - наступного разу скачати заново
        if (await zip.exists()) await zip.delete();
        rethrow;
      }
      _loaded = true;
    } finally {
      client.close();
    }
  }
}

/// Скачування зупинив користувач.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// Чи помилка - це зупинка скачування користувачем.
bool isVoiceDownloadCancelled(Object e) => e is _Cancelled;
