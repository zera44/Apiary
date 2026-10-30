import 'package:apiary/services/app_config.dart';
import 'package:apiary/logic/cell_value.dart';
import 'package:apiary/logic/geometry.dart';
import 'package:apiary/logic/merge_layout.dart';
import 'package:apiary/logic/stock_format.dart';
import 'package:apiary/logic/visit_reminders.dart';
import 'dart:convert';

import 'package:apiary/services/feedback.dart';
import 'package:apiary/ui/date_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('склад: числа', () {
    test('parseAmount приймає кому й крапку, відкидає від\'ємні й не-числа', () {
      expect(parseAmount('2,5'), 2.5);
      expect(parseAmount(' 10 '), 10);
      expect(parseAmount('0.125'), 0.125);
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('-1'), isNull);
    });
    test('formatAmount без зайвих нулів і з комою', () {
      expect(formatAmount(5), '5');
      expect(formatAmount(2.5), '2,5');
      expect(formatAmount(0.125), '0,125');
      expect(formatAmount(1 / 3), '0,333');
      expect(formatAmount(7.0000001), '7');
    });
  });

  group('rotatedPositions', () {
    test('лежак 2×1 після повороту лишається злитим (не розсипається)', () {
      final r = rotatedPositions({'a': (0, 0), 'b': (1, 0)});
      final a = r['a']!, b = r['b']!;
      // стала вертикальною: той самий x, сусідні y
      expect(a.$1, b.$1);
      expect((a.$2 - b.$2).abs(), 1);
    });

    test('чотири повороти повертають фігуру в ту саму форму', () {
      Map<String, Cell> cells = {'a': (5, 5), 'b': (6, 5), 'c': (6, 6)};
      for (var i = 0; i < 4; i++) {
        cells = rotatedPositions(cells);
      }
      expect(cells, {'a': (5, 5), 'b': (6, 5), 'c': (6, 6)});
    });
  });

  group('mergeLayout', () {
    test('прямокутник 2×2 - одна фігура, одна іконка по центру', () {
      final items = [
        const MergeItem('a', 0, 0, 'k'),
        const MergeItem('b', 1, 0, 'k'),
        const MergeItem('c', 0, 1, 'k'),
        const MergeItem('d', 1, 1, 'k'),
      ];
      final r = mergeLayout(items);
      expect(r.components.length, 1);
      expect(r.iconDraw.values.where((v) => v).length, 1);
      final rep = r.iconDraw.entries.firstWhere((e) => e.value).key;
      final off = r.iconOffset[rep]!;
      // іконка зсунута рівно в центр фігури (на півклітинки по кожній осі)
      expect(off.$1.abs(), closeTo(0.5, 1e-9));
      expect(off.$2.abs(), closeTo(0.5, 1e-9));
      expect(r.merges['a']!.right, isTrue);
      expect(r.merges['a']!.top, isTrue);
      expect(r.merges['a']!.left, isFalse);
    });

    test('різні ключі не зливаються', () {
      final r = mergeLayout(const [MergeItem('a', 0, 0, 'x'), MergeItem('b', 1, 0, 'y')]);
      expect(r.components.length, 2);
      expect(r.merges['a']!.any, isFalse);
    });

    test('Г-подібна фігура: іконка в центрі реальної клітинки (без зсуву)', () {
      final r = mergeLayout(const [
        MergeItem('a', 0, 0, 'k'),
        MergeItem('b', 1, 0, 'k'),
        MergeItem('c', 0, 1, 'k'),
      ]);
      expect(r.components.single.length, 3);
      final rep = r.iconDraw.entries.firstWhere((e) => e.value).key;
      expect(r.iconOffset[rep], (0.0, 0.0));
    });
  });

  group('CellValue', () {
    test('рядкові значення старого формату', () {
      expect(CellValue.parse('hive').isHive, isTrue);
      final o = CellValue.parse('obstacle:trees');
      expect(o.type, 'obstacle');
      expect(o.effectiveVariant, 'trees');
      expect(CellValue.parse('obstacle').effectiveVariant, 'mountain');
    });

    test('без перевизначень серіалізується рядком, з ними - словником', () {
      expect(const CellValue(type: 'hive').toJson(), 'hive');
      const v = CellValue(type: 'obstacle', variant: 'lake', color: '#F2B705', parameters: ['p1']);
      final json = v.toJson() as Map;
      expect(json['type'], 'obstacle');
      expect(json['variant'], 'lake');
      final back = CellValue.parse(json);
      expect(back.color, '#F2B705');
      expect(back.parameters, ['p1']);
    });

    test('copyWith може скинути іконку в null', () {
      const v = CellValue(type: 'hive', icon: 'trees');
      expect(v.copyWith(icon: null).icon, isNull);
      expect(v.copyWith(color: '#FFFFFF').icon, 'trees');
    });

    test('parseCellKey', () {
      expect(parseCellKey('3,4'), (3, 4));
      expect(parseCellKey('bad'), isNull);
    });
  });

  test('сітка календаря завжди починається з понеділка о 00:00 (також навколо зміни часу)', () {
    for (var y = 2024; y <= 2027; y++) {
      for (var m = 1; m <= 12; m++) {
        final g = calendarGridStart(y, m);
        expect(g.weekday, DateTime.monday, reason: '$y-$m');
        expect(g.hour, 0, reason: '$y-$m');
        // 1-ше число потрапляє в перший рядок (0..6 днів після початку)
        final first = DateTime(y, m, 1);
        final lead = DateTime(first.year, first.month, first.day)
            .difference(DateTime(g.year, g.month, g.day))
            .inDays;
        expect(lead >= 0 && lead <= 6, isTrue, reason: '$y-$m');
      }
    }
    expect(calendarGridStart(2026, 4), DateTime(2026, 3, 30));
  });

  group('нагадування про обхід', () {
    test('днів до обходу: 5 - 0 днів = 5, щодня на 1 менше, не менше 0, після обходу знову 5', () {
      VisitTarget t(String? last) => VisitTarget(
          key: 'e:1', elementId: '1', apiaryName: 'П', name: 'В', periodDays: 5, lastVisit: last);
      expect(visitDaysLeft(t('01.10.2026'), DateTime(2026, 10, 1, 8)), 5);
      expect(visitDaysLeft(t('01.10.2026'), DateTime(2026, 10, 3, 8)), 3);
      expect(visitDaysLeft(t('01.10.2026'), DateTime(2026, 10, 9, 8)), 0);
      expect(visitDaysLeft(t('09.10.2026'), DateTime(2026, 10, 9, 8)), 5);
      expect(
          visitDaysLeft(const VisitTarget(key: 'e:1', elementId: '1', apiaryName: '', name: 'В'),
              DateTime(2026, 10, 9)),
          isNull);
    });
    test('початок 1.10 і період 2 дні: нагадування 3.10, 5.10, 7.10 о 9:00', () {
      final t = reminderTimes(
          lastVisit: DateTime(2026, 10, 1), periodDays: 2, now: DateTime(2026, 10, 1, 10));
      expect(t, [DateTime(2026, 10, 3, 9), DateTime(2026, 10, 5, 9), DateTime(2026, 10, 7, 9)]);
    });

    test('обійшов 3.10 - наступне нагадування 5.10', () {
      final t = reminderTimes(
          lastVisit: DateTime(2026, 10, 3), periodDays: 2, now: DateTime(2026, 10, 3, 12));
      expect(t.first, DateTime(2026, 10, 5, 9));
    });

    test('прострочений обхід: далі кожні період днів у майбутньому', () {
      final t = reminderTimes(
          lastVisit: DateTime(2026, 10, 1), periodDays: 2, now: DateTime(2026, 10, 10, 12));
      expect(t, [DateTime(2026, 10, 11, 9), DateTime(2026, 10, 13, 9), DateTime(2026, 10, 15, 9)]);
    });

    test('нульовий/від\'ємний/завеликий період - без нагадувань', () {
      for (final p in [0, -1, 100000]) {
        expect(reminderTimes(lastVisit: DateTime(2026, 10, 1), periodDays: p, now: DateTime(2026, 10, 1)),
            isEmpty);
      }
    });

    VisitTarget target({int? period = 2, String? last = '01.10.2026', DateTime? setAt}) => VisitTarget(
        key: 'e:1',
        elementId: '1',
        apiaryName: 'Пасіка',
        name: 'Вулик 5',
        periodDays: period,
        lastVisit: last,
        periodSetAt: setAt);

    VisitTarget hive(String key, String name,
            {int period = 2, String? last = '01.10.2026', String apiaryId = 'a1', String apiary = 'Пасіка'}) =>
        VisitTarget(
            key: 'e:$key',
            elementId: key,
            apiaryId: apiaryId,
            apiaryName: apiary,
            name: name,
            periodDays: period,
            lastVisit: last);

    test('одне нагадування на день о 9:00 і друге о 14:00, а не по одному на вулик', () {
      final p = planReminders([
        hive('5', 'Вулик 5'),
        hive('6', 'Вулик 6'),
        hive('7', 'Вулик 7'),
      ], now: DateTime(2026, 10, 1, 10));
      // 3.10: усі троє настали одночасно - два сповіщення на всіх
      expect(p.take(2).map((r) => r.when), [DateTime(2026, 10, 3, 9), DateTime(2026, 10, 3, 14)]);
      expect(p[0].title, 'Пасіка');
      expect(p[0].body, 'Оглянути 3 вулики: Вулик 5, Вулик 6, Вулик 7');
      expect(p[1].title, 'Пасіка');
      expect(p[1].body, 'Лишилось оглянути 3 вулики: Вулик 5, Вулик 6, Вулик 7');
      expect(p[0].elementId, '5'); // натискання відкриває карту його пасіки
    });

    test('окреме сповіщення на кожну пасіку з її назвою і лише її вуликами', () {
      final p = planReminders([
        hive('1', 'Вулик 1', apiaryId: 'a1', apiary: 'Біля хати'),
        hive('2', 'Вулик 2', apiaryId: 'a2', apiary: 'Поле'),
        hive('3', 'Вулик 3', apiaryId: 'a1', apiary: 'Біля хати'),
        hive('4', 'Вулик 4', apiaryId: 'a3', apiary: ''),
        // та сама назва, але інша пасіка - не зливається
        hive('5', 'Вулик 5', apiaryId: 'a4', apiary: 'Поле'),
      ], now: DateTime(2026, 10, 1, 10));
      final morning = p.where((r) => r.when == DateTime(2026, 10, 3, 9)).toList();
      expect([for (final r in morning) (r.title, r.body, r.elementId)], [
        ('Біля хати', 'Оглянути 2 вулики: Вулик 1, Вулик 3', '1'),
        ('Поле', 'Оглянути 1 вулик: Вулик 2', '2'),
        ('Моя пасіка', 'Оглянути 1 вулик: Вулик 4', '4'),
        ('Поле', 'Оглянути 1 вулик: Вулик 5', '5'),
      ]);
      final afternoon = p.where((r) => r.when == DateTime(2026, 10, 3, 14)).toList();
      expect(afternoon.map((r) => r.title), ['Біля хати', 'Поле', 'Моя пасіка', 'Поле']);
    });

    test('у пасіці, де всіх оглянули, другого нагадування немає, в іншій - є', () {
      final p = planReminders([
        hive('1', 'Вулик 1', apiaryId: 'a1', apiary: 'Біля хати', last: '03.10.2026'),
        hive('2', 'Вулик 2', apiaryId: 'a2', apiary: 'Поле'),
      ], now: DateTime(2026, 10, 3, 10));
      final today = p.where((r) => r.when.day == 3 && r.when.month == 10).toList();
      expect([for (final r in today) (r.title, r.body)], [('Поле', 'Лишилось оглянути 1 вулик: Вулик 2')]);
    });

    test('довгий список вуликів скорочується', () {
      final many = [for (var i = 1; i <= 7; i++) hive('$i', 'Вулик $i')];
      final p = planReminders(many, now: DateTime(2026, 10, 1, 10));
      expect(p.first.body, 'Оглянути 7 вуликів: Вулик 1, Вулик 2, Вулик 3, Вулик 4 і ще 3');
    });

    test('пізніше настав термін в одного - у його день сповіщення лише про тих, кому пора', () {
      final p = planReminders([
        hive('5', 'Вулик 5', period: 2),
        hive('8', 'Вулик 8', period: 3, last: '02.10.2026'),
      ], now: DateTime(2026, 10, 1, 10));
      // 3.10 настав термін Вулика 5; Вулик 8 - 5.10 (разом із черговим термінам Вулика 5)
      expect(p[0].body, 'Оглянути 1 вулик: Вулик 5');
      final fifth = p.where((r) => r.when == DateTime(2026, 10, 5, 9)).single;
      expect(fifth.body, 'Оглянути 2 вулики: Вулик 5, Вулик 8');
    });

    test('сьогодні після 9:00 і вулик не оглянуто - лишається друге о 14:00', () {
      final p = planReminders([hive('5', 'Вулик 5')], now: DateTime(2026, 10, 3, 10));
      expect(p.first.when, DateTime(2026, 10, 3, 14));
      expect(p.first.body, 'Лишилось оглянути 1 вулик: Вулик 5');
    });

    test('сьогодні вулик оглянули вранці - ні другого, ні ранкового нагадування', () {
      // після обходу дата останнього обходу - сьогодні: нагадування лише через період
      final p = planReminders([hive('5', 'Вулик 5', last: '03.10.2026')],
          now: DateTime(2026, 10, 3, 10));
      expect(p.first.when, DateTime(2026, 10, 5, 9));
      expect(p.where((r) => r.when.day == 3), isEmpty);
    });

    test('оглянули частину вуликів - друге нагадування лише про решту', () {
      final p = planReminders([
        hive('5', 'Вулик 5', last: '03.10.2026'),
        hive('6', 'Вулик 6'),
      ], now: DateTime(2026, 10, 3, 10));
      expect(p.first.when, DateTime(2026, 10, 3, 14));
      expect(p.first.body, 'Лишилось оглянути 1 вулик: Вулик 6');
    });

    test('після 14:00 сьогодні нічого нагадувати, наступне - у наступний термін', () {
      final p = planReminders([hive('5', 'Вулик 5')], now: DateTime(2026, 10, 3, 15));
      expect(p.first.when, DateTime(2026, 10, 5, 9));
    });

    test('без періоду або без дати відліку - нічого; дата відліку з моменту задання періоду', () {
      final now = DateTime(2026, 10, 1, 10);
      expect(planReminders([target(period: null)], now: now), isEmpty);
      expect(planReminders([target(last: null)], now: now), isEmpty);
      final p = planReminders([target(last: null, setAt: DateTime(2026, 10, 1, 8))], now: now);
      expect(p.first.when, DateTime(2026, 10, 3, 9));
    });

    test('горизонт планування: ~45 днів наперед, але не менше 3 термінів (по 2 сповіщення)', () {
      final now = DateTime(2026, 10, 1, 10);
      expect(planReminders([target(period: 1)], now: now).length, 90);
      expect(planReminders([target(period: 2)], now: now).length, 44);
      expect(planReminders([target(period: 30)], now: now).length, 6);
    });

    test('ліміт кількості й порядок за часом', () {
      final p = planReminders([target(period: 1)], now: DateTime(2026, 10, 1, 10), limit: 20);
      expect(p.length, 20);
      for (var i = 1; i < p.length; i++) {
        expect(p[i].when.isBefore(p[i - 1].when), isFalse);
      }
    });

    test('dueReminder: найпізніше нагадування, що вже настало', () {
      final d = dueReminder(target(), now: DateTime(2026, 10, 10, 12))!;
      expect(d.when, DateTime(2026, 10, 9, 9));
      expect(dueReminder(target(), now: DateTime(2026, 10, 2, 12)), isNull);
      expect(dueReminder(target(), now: DateTime(2026, 10, 3, 8)), isNull);
      expect(dueReminder(target(), now: DateTime(2026, 10, 3, 9, 1))!.when, DateTime(2026, 10, 3, 9));
    });
  });

  group('безпека', () {
    test('синхронізація лише через https (http - тільки локальний сервер розробки)', () {
      expect(AppConfig.secureBase('https://api.example.com/v1/').toString(),
          'https://api.example.com/v1');
      expect(AppConfig.secureBase('http://api.example.com'), isNull);
      expect(AppConfig.secureBase('ftp://api.example.com'), isNull);
      expect(AppConfig.secureBase('https://user:pass@api.example.com'), isNull);
      expect(AppConfig.secureBase('не адреса'), isNull);
      expect(AppConfig.secureBase('http://localhost:8080'), isNotNull);
      expect(AppConfig.secureBase('https://h.example/api?k=v#x').toString(), 'https://h.example/api');
      expect(AppConfig.secureBase('https://h.example:8443').toString(), 'https://h.example:8443');
    });

    test('Supabase: без адреси чи ключа синхронізацію вимкнено', () {
      expect(const AppConfig().syncConfigured, isFalse);
      expect(const AppConfig(supabaseUrl: 'https://x.supabase.co').syncConfigured, isFalse);
      expect(const AppConfig(supabaseAnonKey: 'key').syncConfigured, isFalse);
      // небезпечна адреса - теж вимкнено
      expect(const AppConfig(supabaseUrl: 'http://x.supabase.co', supabaseAnonKey: 'key')
          .syncConfigured, isFalse);
      expect(const AppConfig(supabaseUrl: ' ', supabaseAnonKey: 'key').syncConfigured, isFalse);
      const ok = AppConfig(supabaseUrl: 'https://x.supabase.co/', supabaseAnonKey: 'key');
      expect(ok.syncConfigured, isTrue);
      expect(ok.supabaseBase.toString(), 'https://x.supabase.co');
      // у тестовій збірці адреси й ключа немає
      expect(AppConfig.fromEnvironment.syncConfigured, isFalse);
    });
  });

  group("зворотний зв'язок", () {
    test('адреса форми лише https і без паролів', () {
      expect(FeedbackService.endpoint('https://formspree.io/f/abc'), isNotNull);
      expect(FeedbackService.endpoint('http://formspree.io/f/abc'), isNull);
      expect(FeedbackService.endpoint('https://u:p@formspree.io/f/abc'), isNull);
      expect(FeedbackService.endpoint(''), isNull);
    });

    test('без адреси форми - «не налаштовано», запит не йде', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      expect(await FeedbackService.send('Привіт', client: client, formUrl: ''),
          FeedbackResult.notConfigured);
      expect(calls, 0);
    });

    test('текст іде JSON-ом на адресу форми', () async {
      http.Request? sent;
      final client = MockClient((r) async {
        sent = r;
        return http.Response('{"ok":true}', 200);
      });
      final r = await FeedbackService.send('  Чудовий застосунок  ',
          client: client, formUrl: 'https://formspree.io/f/abc');
      expect(r, FeedbackResult.sent);
      expect(sent!.url.toString(), 'https://formspree.io/f/abc');
      expect(sent!.headers['Accept'], 'application/json');
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect(body['message'], 'Чудовий застосунок');
      expect(body['_subject'], FeedbackService.subject);
    });

    test('помилка сервісу чи мережі - «не надіслано»', () async {
      final bad = MockClient((_) async => http.Response('{"error":"x"}', 422));
      expect(await FeedbackService.send('a', client: bad, formUrl: 'https://formspree.io/f/abc'),
          FeedbackResult.failed);
      final offline = MockClient((_) async => throw const SocketExceptionStub());
      expect(await FeedbackService.send('a', client: offline, formUrl: 'https://formspree.io/f/abc'),
          FeedbackResult.failed);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
