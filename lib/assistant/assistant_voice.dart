import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import '../data/repository.dart';
import '../services/voice_input.dart';
import 'assistant_persona.dart';
import 'assistant_queue.dart';

/// Голос у чаті з помічником: розпізнавання (тримаєш кнопку - говориш,
/// відпустив - надіслано) і читання відповідей уголос.

/// Чим скінчилася спроба почати слухати.
enum VoiceStart {
  ok,

  /// моделі Vosk немає, а розпізнавача телефона теж - запропонувати
  /// скачати модель
  needModel,

  /// немає дозволу на мікрофон
  noPermission,

  /// без інтернету розпізнавач телефона не працює, а моделі ще немає
  offlineUnavailable,

  /// не Android / не вдалося
  unavailable,
}

/// Розпізнаний текст: частковий (поки говорять), завершена фраза (Vosk
/// ділить мову паузами - фрази складаються) або остаточний.
class VoiceText {
  final String text;
  final bool isFinal;

  /// Завершена фраза: додати до сказаного раніше.
  final bool isPhrase;
  const VoiceText(this.text, {this.isFinal = false, this.isPhrase = false});
}

/// Сказане разом: завершені фрази й поточна (часткова) частина.
class Dictation {
  final List<String> _phrases = [];
  String _partial = '';

  void add(VoiceText t) {
    if (t.isPhrase || t.isFinal) {
      if (t.text.trim().isNotEmpty) _phrases.add(t.text.trim());
      _partial = '';
    } else {
      _partial = t.text.trim();
    }
  }

  /// Розпізнавач телефона щоразу дає весь текст - не фрази.
  void replace(VoiceText t) {
    _phrases.clear();
    _partial = '';
    add(t);
  }

  String get text => [..._phrases, if (_partial.isNotEmpty) _partial].join(' ');

  void clear() {
    _phrases.clear();
    _partial = '';
  }
}

abstract class ChatVoice {
  /// Текст приходить фразами (Vosk) чи щоразу весь (розпізнавач телефона).
  bool get phrases;

  Future<VoiceStart> start(void Function(VoiceText t) onText);

  /// Відпустили кнопку: остаточний текст прийде в onText (isFinal).
  Future<void> stop();

  /// Без результату.
  Future<void> cancel();
}

/// Розпізнавання на телефоні: модель Vosk (офлайн), якщо вже скачана;
/// інакше - розпізнавач Android (зазвичай потребує інтернету).
class PhoneVoice implements ChatVoice {
  PhoneVoice({Future<bool> Function()? isOnline}) : isOnline = isOnline ?? AssistantQueue.deviceOnline;
  final Future<bool> Function() isOnline;

  final SpeechToText _system = SpeechToText();
  bool _systemReady = false;
  StreamSubscription<VoskEvent>? _vosk;
  void Function(VoiceText)? _onText;
  bool _usingVosk = false;

  @override
  bool get phrases => _usingVosk;

  @override
  Future<VoiceStart> start(void Function(VoiceText t) onText) async {
    if (kIsWeb || !Platform.isAndroid) return VoiceStart.unavailable;
    _onText = onText;
    try {
      if (await VoiceInput.instance.modelOnPhone()) {
        await VoiceInput.instance.ensureReady();
        if (!await Vosk.permission()) return VoiceStart.noPermission;
        _vosk ??= Vosk.events.listen((e) {
          if (!_usingVosk) return;
          if (e.isError) {
            _onText?.call(const VoiceText('', isFinal: true));
          } else if (e.isPartial) {
            _onText?.call(VoiceText(e.text));
          } else {
            _onText?.call(VoiceText(e.text, isFinal: e.isFinal, isPhrase: !e.isFinal));
          }
        });
        _usingVosk = true;
        await Vosk.start();
        return VoiceStart.ok;
      }
      _usingVosk = false;
      _systemReady = _systemReady ||
          await _system.initialize(
            // тиша, немає зв'язку тощо - кінець без тексту («не розчув»)
            onError: (_) => _onText?.call(const VoiceText('', isFinal: true)),
          );
      if (!_systemReady) return VoiceStart.needModel;
      if (!await isOnline()) return VoiceStart.offlineUnavailable;
      if (!await _system.hasPermission) return VoiceStart.noPermission;
      final locales = await _system.locales();
      final uk = locales.where((l) => l.localeId.toLowerCase().startsWith('uk')).firstOrNull;
      await _system.listen(
        // увесь текст щоразу - позначаємо як заміну (не фразу)
        onResult: (r) => _onText?.call(VoiceText(r.recognizedWords, isFinal: r.finalResult)),
        listenOptions: SpeechListenOptions(
            localeId: uk?.localeId ?? 'uk_UA', partialResults: true, cancelOnError: true),
      );
      return VoiceStart.ok;
    } on PlatformException catch (e) {
      debugPrint('Голос: ${e.code} ${e.message}');
      return e.code == 'NOMODEL' || e.code == 'MODEL' ? VoiceStart.needModel : VoiceStart.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    if (_usingVosk) {
      await Vosk.stop();
    } else {
      await _system.stop();
    }
  }

  @override
  Future<void> cancel() async {
    if (_usingVosk) {
      await Vosk.cancel();
    } else {
      await _system.cancel();
    }
    _onText = null;
  }
}

/// Читання відповідей уголос.
abstract class ReplySpeaker {
  /// false - українського голосу в телефоні немає. Голос - персонажа
  /// [persona] (Ведмедик чи Пасічник).
  Future<bool> speak(String text, {AssistantPersona persona = AssistantPersona.bear});
  Future<void> stop();
}

class PhoneSpeaker implements ReplySpeaker {
  FlutterTts? _tts;
  bool? _uk;

  @override
  Future<bool> speak(String text, {AssistantPersona persona = AssistantPersona.bear}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final tts = _tts ??= FlutterTts();
      _uk ??= (await tts.isLanguageAvailable('uk-UA')) == true;
      if (!_uk!) return false;
      await tts.setLanguage('uk-UA');
      await _voiceFor(tts, persona);
      await tts.setPitch(persona.pitch);
      await tts.setSpeechRate(persona.rate);
      await tts.stop();
      await tts.speak(text);
      return true;
    } catch (e) {
      debugPrint('Синтезатор: $e');
      return false;
    }
  }

  List<Map<String, String>>? _ukVoices;

  /// Якщо в телефоні кілька українських голосів - кожному персонажу свій
  /// (Ведмедику - перший, Пасічнику - останній).
  Future<void> _voiceFor(FlutterTts tts, AssistantPersona persona) async {
    try {
      _ukVoices ??= [
        for (final v in (await tts.getVoices as List? ?? const []))
          if (v is Map && '${v['locale']}'.toLowerCase().startsWith('uk'))
            {'name': '${v['name']}', 'locale': '${v['locale']}'},
      ];
      final voices = _ukVoices!;
      if (voices.length < 2) return;
      await tts.setVoice(persona == AssistantPersona.bear ? voices.first : voices.last);
    } catch (_) {
      // немає списку голосів - лише висота й темп
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

/// Налаштування → «Головне»: «Читати відповіді вголос» (за замовчуванням - ні).
class AssistantVoiceSettings {
  static const speakKey = 'assistant_speak';

  /// Пояснення про мікрофон уже показано (перед першим системним запитом).
  static const micExplainedKey = 'assistant_mic_explained';

  static Future<bool> speak(Repository repo) async => await repo.getMeta(speakKey) == '1';

  static Future<void> setSpeak(Repository repo, bool on) => repo.setMeta(speakKey, on ? '1' : '0');
}
