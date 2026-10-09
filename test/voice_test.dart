import 'package:apiary/logic/spoken_numbers.dart';
import 'package:apiary/ui/voice_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

void main() {
  group('число словами', () {
    final cases = {
      'дванадцять': '12',
      'сто двадцять п\'ять': '125',
      'п’ять': '5',
      'тисяча двісті': '1200',
      'дві тисячі двадцять шість': '2026',
      'два кома п\'ять': '2,5',
      'два кома нуль п\'ять': '2,05',
      'три цілих двадцять п\'ять сотих': '3,25',
      'нуль цілих п\'ять десятих': '0,5',
      'півтора': '1,5',
      'сто з половиною': '100,5',
      'мінус три': '-3',
      '12': '12',
      '2.5': '2,5',
      'сорок два': '42',
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(spokenToNumber(e.key), e.value));
    }
    test('не число', () {
      expect(spokenToNumber('мед гречаний'), isNull);
      expect(spokenToNumber(''), isNull);
    });
    test('ціле поле не бере дробу', () {
      expect(spokenToNumber('два кома п\'ять', decimal: false), isNull);
      expect(spokenToNumber('сім', decimal: false), '7');
    });
  });

  group('вставка сказаного', () {
    TextEditingValue v(String t, [int? at]) =>
        TextEditingValue(text: t, selection: TextSelection.collapsed(offset: at ?? t.length));

    test('у порожнє поле - з великої літери', () {
      final r = insertSpoken(v(''), 'бджоли спокійні', capitalize: true);
      expect(r.text, 'Бджоли спокійні');
      expect(r.selection.baseOffset, r.text.length);
    });
    test('продовження - через пробіл, без великої', () {
      expect(insertSpoken(v('Матка є'), 'черва гарна', capitalize: true).text, 'Матка є черва гарна');
    });
    test('після крапки - з великої', () {
      expect(insertSpoken(v('Матка є. '), 'черва гарна', capitalize: true).text,
          'Матка є. Черва гарна');
    });
    test('у середину тексту', () {
      final r = insertSpoken(v('рамки вощина', 6), 'чотири');
      expect(r.text, 'рамки чотири вощина');
    });
    test('виділене замінюється', () {
      const val = TextEditingValue(
          text: 'старе слово', selection: TextSelection(baseOffset: 0, extentOffset: 5));
      expect(insertSpoken(val, 'нове').text, 'нове слово');
    });
  });

  test('JSON Vosk', () {
    expect(Vosk.textOf('{"partial" : "два кома"}'), 'два кома');
    expect(Vosk.textOf('{\n  "text" : "дванадцять"\n}'), 'дванадцять');
    expect(Vosk.textOf('не json'), '');
  });

  testWidgets('без Android і моделі застосунок не змінюється', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => VoiceInputHost(child: child!),
      home: const Scaffold(body: TextField()),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byKey(const ValueKey('voice-mic')), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });
}
