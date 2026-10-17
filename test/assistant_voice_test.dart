import 'package:apiary/assistant/assistant_chat_screen.dart';
import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_persona.dart';
import 'package:apiary/assistant/assistant_voice.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/settings_main_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Фейковий розпізнавач: [result] - чим скінчиться start; поки тримають
/// кнопку, тест сам «говорить» через [say]; відпустили - [finalText].
class FakeVoice implements ChatVoice {
  VoiceStart result = VoiceStart.ok;
  String finalText = '';
  void Function(VoiceText)? _on;
  int starts = 0;
  @override
  bool phrases = true;
  @override
  Future<VoiceStart> start(void Function(VoiceText t) onText) async {
    starts++;
    _on = onText;
    return result;
  }

  void say(VoiceText t) => _on?.call(t);

  @override
  Future<void> stop() async => _on?.call(VoiceText(finalText, isFinal: true));
  @override
  Future<void> cancel() async => _on = null;
}

class FakeSpeaker implements ReplySpeaker {
  final spoken = <String>[];
  bool hasUk = true;
  final personas = <AssistantPersona>[];
  @override
  Future<bool> speak(String text, {AssistantPersona persona = AssistantPersona.bear}) async {
    personas.add(persona);
    if (!hasUk) return false;
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}

ModelTurn say(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  late Repository repo;
  late AssistantQueue q;
  late FakeVoice voice;
  late FakeSpeaker speaker;

  setUpAll(sqfliteFfiInit);

  Future<void> open(WidgetTester tester, List<ModelTurn> script,
      {bool explained = true, bool speak = false, String? earlierReply}) async {
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
      if (explained) await repo.setMeta(AssistantVoiceSettings.micExplainedKey, '1');
      await AssistantVoiceSettings.setSpeak(repo, speak);
      if (earlierReply != null) await AssistantStore(repo.db).addAssistant(earlierReply);
    });
    voice = FakeVoice();
    speaker = FakeSpeaker();
    q = AssistantQueue(repo, AssistantStore(repo.db), DemoAssistantModel(script),
        isOnline: () async => true, onlineChanges: const Stream.empty());
    await tester.pumpWidget(MaterialApp(
      home: AssistantChatScreen(
          repo: repo, queue: q, navigate: (_) async => true, voice: voice, speaker: speaker),
    ));
    await settle(tester);
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    try {
      await repo.db.close();
    } catch (_) {} // тест без бази
  });

  /// Дотик до мікрофона (старт або стоп).
  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('assistant-mic')));
    await settle(tester);
  }

  String field(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const ValueKey('assistant-input'))).controller!.text;

  test('сказане фразами складається; розпізнавач телефона - щоразу весь текст', () {
    final d = Dictation()
      ..add(const VoiceText('запиши'))
      ..add(const VoiceText('запиши огляд', isPhrase: true))
      ..add(const VoiceText('п\'ятого'));
    expect(d.text, 'запиши огляд п\'ятого');
    d.add(const VoiceText('п\'ятого вулика', isFinal: true));
    expect(d.text, 'запиши огляд п\'ятого вулика');
    d
      ..clear()
      ..replace(const VoiceText('відкрий'))
      ..replace(const VoiceText('відкрий склад', isFinal: true));
    expect(d.text, 'відкрий склад');
  });

  testWidgets('дотик - слухаю, сказане одразу пишеться в поле; ще дотик - стоп; надсилає людина',
      (tester) async {
    await open(tester, [say('Відкриваю склад.')]);
    await tapMic(tester);
    expect(voice.starts, 1);
    expect(find.text(tr.assistantListening), findsOneWidget);
    voice.say(const VoiceText('відкрий'));
    await tester.pump();
    expect(field(tester), 'відкрий'); // видно в полі, поки людина говорить
    voice.finalText = 'відкрий склад';
    await tapMic(tester); // стоп
    expect(field(tester), 'відкрий склад');
    expect(find.byKey(const ValueKey('assistant-voice-strip')), findsNothing);
    // нічого не надіслано саме - людина бачить текст і може виправити
    expect(await tester.runAsync(() => q.store.items()), isEmpty);
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('відкрий склад'), findsOneWidget);
    expect(find.text('Відкриваю склад.'), findsOneWidget);
  });

  testWidgets('розпізнавач сам зупинився (пауза) - текст лишається в полі', (tester) async {
    await open(tester, []);
    await tapMic(tester);
    voice.say(const VoiceText('скільки вуликів', isFinal: true));
    await settle(tester);
    expect(field(tester), 'скільки вуликів');
    expect(find.byKey(const ValueKey('assistant-voice-strip')), findsNothing);
  });

  testWidgets('дописати голосом до вже набраного', (tester) async {
    await open(tester, []);
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'Запиши');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-mic-more')));
    await settle(tester);
    voice.say(const VoiceText('огляд п\'ятого', isFinal: true));
    await settle(tester);
    expect(field(tester), 'Запиши огляд п\'ятого');
  });

  testWidgets('нічого не розчув - підказка, нічого не надіслано', (tester) async {
    await open(tester, []);
    await tapMic(tester);
    await tapMic(tester); // стоп без слів
    expect(find.text(tr.assistantNotHeard), findsOneWidget);
    expect(field(tester), '');
    expect(await tester.runAsync(() => q.store.items()), isEmpty);
  });

  testWidgets('перший раз - пояснення про мікрофон, потім - системний запит', (tester) async {
    await open(tester, [], explained: false);
    await tester.tap(find.byKey(const ValueKey('assistant-mic')));
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantMicExplainTitle), findsOneWidget);
    expect(voice.starts, 0); // дозвіл ще не просили
    await tester.tap(find.text(tr.assistantMicExplainOk));
    await settle(tester);
    expect(await tester.runAsync(() => repo.getMeta(AssistantVoiceSettings.micExplainedKey)), '1');
    await tapMic(tester);
    expect(voice.starts, 1);
    await tapMic(tester);
  });

  testWidgets('без інтернету й без моделі - сказати, що розпізнавання недоступне', (tester) async {
    await open(tester, []);
    voice.result = VoiceStart.offlineUnavailable;
    await tapMic(tester);
    expect(find.text(tr.assistantVoiceOffline), findsOneWidget);
  });

  testWidgets('моделі немає - запропонувати завантажити', (tester) async {
    await open(tester, []);
    voice.result = VoiceStart.needModel;
    await tester.tap(find.byKey(const ValueKey('assistant-mic')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text(tr.assistantVoiceDownload), findsOneWidget);
  });

  testWidgets('немає дозволу на мікрофон - підказка, де ввімкнути', (tester) async {
    await open(tester, []);
    voice.result = VoiceStart.noPermission;
    await tapMic(tester);
    expect(find.text(tr.assistantNoMic), findsOneWidget);
  });

  testWidgets('«Читати вголос» увімкнено - нова відповідь читається, стара - ні', (tester) async {
    await open(tester, [say('Готово, записав.')], speak: true, earlierReply: 'Стара відповідь');
    expect(find.text('Стара відповідь'), findsOneWidget);
    expect(speaker.spoken, isEmpty); // історію при відкритті не читаємо
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'Запиши');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    expect(speaker.spoken, ['Готово, записав.']);
    expect(speaker.personas, [AssistantPersona.bear]); // демо-модель - голос Ведмедика
  });

  testWidgets('«Читати вголос» вимкнено - мовчить', (tester) async {
    await open(tester, [say('Тихо.')]);
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'Привіт');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    expect(find.text('Тихо.'), findsOneWidget);
    expect(speaker.spoken, isEmpty);
  });

  testWidgets('немає української в синтезаторі - одна підказка', (tester) async {
    await open(tester, [say('Раз.')], speak: true);
    speaker.hasUk = false;
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'Привіт');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await settle(tester);
    expect(find.text(tr.assistantNoUkVoice), findsOneWidget);
  });

  testWidgets('Налаштування → «Головне»: перемикач «Читати відповіді вголос»', (tester) async {
    await tester.runAsync(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await repo.init();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MainSettingsTab(repo: repo))));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('assistant-speak')), 200);
    expect(find.text(tr.assistantSpeakSetting), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-speak')));
    await settle(tester);
    expect(await tester.runAsync(() => AssistantVoiceSettings.speak(repo)), isTrue);
  });

  test('налаштування «Читати відповіді вголос» зберігається', () async {
    sqfliteFfiInit();
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false));
    await repo.init();
    expect(await AssistantVoiceSettings.speak(repo), isFalse);
    await AssistantVoiceSettings.setSpeak(repo, true);
    expect(await AssistantVoiceSettings.speak(repo), isTrue);
  });
}
