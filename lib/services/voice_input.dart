import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Модель Vosk у ресурсах (скачує збірка, див. assets/vosk/README.md).
const kVoskAsset = 'assets/vosk/model.zip';

/// Назва версії моделі: інша назва - модель на телефоні розпакується заново.
const kVoskModelVersion = 'uk-v3-small';

/// Голосовий ввід (Vosk, офлайн): лише Android і лише коли модель вкладена
/// в збірку.
class VoiceInput {
  VoiceInput._();
  static final instance = VoiceInput._();

  bool get platformOk => !kIsWeb && Platform.isAndroid;

  Future<bool>? _available;

  /// Чи є модель у ресурсах збірки.
  Future<bool> available() => _available ??= () async {
        if (!platformOk) return false;
        try {
          final m = await AssetManifest.loadFromAssetBundle(rootBundle);
          return m.listAssets().contains(kVoskAsset);
        } catch (_) {
          return false;
        }
      }();

  Future<void>? _ready;

  /// Підготувати модель (першого разу - розпакування, кілька секунд).
  Future<void> ensureReady() => _ready ??= Vosk.init(asset: kVoskAsset, version: kVoskModelVersion)
      .catchError((Object e) {
        _ready = null;
        throw e;
      });
}
