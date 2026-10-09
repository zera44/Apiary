/// Офлайн-розпізнавання мови Vosk (Android). Коротка копія плагіна
/// vosk_flutter (Apache-2.0, alphacep): модель розпаковується з ресурсу
/// застосунку, мікрофон слухає Vosk SDK (`org.vosk.android.SpeechService`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Подія розпізнавання.
class VoskEvent {
  /// partial - проміжний текст (змінюється, поки людина говорить);
  /// result - фраза завершилась (пауза); final - слухання завершено;
  /// error - помилка.
  final String type;
  final String text;
  const VoskEvent(this.type, this.text);

  bool get isPartial => type == 'partial';
  bool get isFinal => type == 'final';
  bool get isError => type == 'error';
}

class Vosk {
  Vosk._();

  static const _channel = MethodChannel('vosk_flutter');
  static const _events = EventChannel('vosk_flutter/events');

  static Stream<VoskEvent>? _stream;

  /// Події розпізнавання (одна підписка на весь застосунок).
  static Stream<VoskEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) {
        final m = Map<String, Object?>.from(e as Map);
        final type = m['type'] as String? ?? 'error';
        final raw = m['text'] as String? ?? '';
        return VoskEvent(type, type == 'error' ? raw : textOf(raw));
      })
      .asBroadcastStream();

  /// Текст із JSON Vosk: {"partial": "..."} або {"text": "..."}.
  static String textOf(String json) {
    try {
      final m = jsonDecode(json);
      if (m is Map) return ((m['text'] ?? m['partial']) as String? ?? '').trim();
    } catch (_) {}
    return '';
  }

  /// Підготувати модель із ресурсу [asset] (zip). Першого разу архів
  /// розпаковується (кілька секунд); [version] - назва версії моделі: нова
  /// версія розпакується заново, стара видалиться.
  static Future<void> init({required String asset, required String version}) =>
      _channel.invokeMethod('init', {'asset': asset, 'version': version});

  /// Дозвіл на мікрофон (за потреби - системний запит). true - є.
  static Future<bool> permission() async =>
      (await _channel.invokeMethod<bool>('permission')) ?? false;

  static Future<void> start() => _channel.invokeMethod('start');

  /// Зупинити: остаточний текст прийде подією final.
  static Future<void> stop() => _channel.invokeMethod('stop');

  /// Зупинити без результату.
  static Future<void> cancel() => _channel.invokeMethod('cancel');
}
