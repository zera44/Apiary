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
  Future<void>? _loading;

  /// Чи модель уже є на телефоні (розпакована).
  Future<bool> modelOnPhone() async => _loaded || await Vosk.ready(kVoskModelVersion);

  /// Завантажити розпаковану модель у пам'ять (одночасні виклики чекають
  /// той самий). Моделі немає або вона пошкоджена - помилка (тоді
  /// [download]; пошкоджену модель плагін уже прибрав).
  Future<void> ensureReady() {
    if (_loaded) return Future.value();
    return _loading ??= _init(null).whenComplete(() => _loading = null);
  }

  Future<void> _init(String? zip) async {
    await Vosk.init(version: kVoskModelVersion, zip: zip);
    _loaded = true;
  }

  bool _downloading = false;

  /// Скачати модель (докачує перерваний файл), розпакувати й завантажити.
  /// [onProgress] - частка 0..1; [cancelled] - перевіряється під час
  /// скачування (true - зупинитись, недокачане лишається для докачки).
  Future<void> download({
    required void Function(double progress) onProgress,
    required bool Function() cancelled,
  }) async {
    if (_downloading) throw StateError('модель уже скачується');
    _downloading = true;
    try {
      await _download(onProgress, cancelled);
    } finally {
      _downloading = false;
    }
  }

  Future<void> _download(void Function(double) onProgress, bool Function() cancelled) async {
    final dir = await getApplicationSupportDirectory();
    final part = File('${dir.path}/$kVoskModelName.zip.part');
    final zip = File('${dir.path}/$kVoskModelName.zip');
    // архів уже скачано (застосунок закрили під час розпакування) - не качати знову
    if (await zip.exists()) {
      try {
        onProgress(1);
        await _unpack(zip);
        return;
      } catch (_) {
        // архів пошкоджений (_unpack його видалив) - качаємо заново
      }
    }
    final client = http.Client();
    try {
      var have = await part.exists() ? await part.length() : 0;
      final req = http.Request('GET', Uri.parse(kVoskModelUrl));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        have = 0; // сервер віддає з початку
      } else if (resp.statusCode == 416 && have > 0) {
        // уже докачано повністю
      } else if (resp.statusCode != 206) {
        throw HttpException('сервер відповів ${resp.statusCode}');
      }
      if (resp.statusCode != 416) {
        final len = resp.contentLength;
        final total = len == null || len <= 0 ? kVoskModelMb * 1024 * 1024 : have + len;
        final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
        try {
          var got = have;
          var lastReport = 0;
          // зв'язок «завис» - помилка через 30 с без даних
          await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
            if (cancelled()) throw const _Cancelled();
            sink.add(chunk);
            got += chunk.length;
            if (got - lastReport > 512 * 1024) {
              lastReport = got;
              onProgress((got / total).clamp(0.0, 0.99));
            }
          }
        } finally {
          await sink.close();
        }
      }
    } finally {
      client.close();
    }
    onProgress(1);
    if (await zip.exists()) await zip.delete();
    await part.rename(zip.path);
    await _unpack(zip);
  }

  /// Розпакувати й завантажити модель з архіву [zip] (плагін потім видаляє
  /// архів). Пошкоджений архів видаляється - наступного разу скачати заново.
  Future<void> _unpack(File zip) async {
    try {
      await _init(zip.path);
    } catch (_) {
      if (await zip.exists()) await zip.delete();
      rethrow;
    }
  }
}

/// Скачування зупинив користувач.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// Чи помилка - це зупинка скачування користувачем.
bool isVoiceDownloadCancelled(Object e) => e is _Cancelled;
