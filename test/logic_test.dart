import 'package:apiary/logic/cell_value.dart';
import 'package:apiary/logic/geometry.dart';
import 'package:apiary/logic/merge_layout.dart';
import 'package:apiary/logic/visit_reminders.dart';
import 'package:apiary/ui/date_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    test('прямокутник 2×2 — одна фігура, одна іконка по центру', () {
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

    test('без перевизначень серіалізується рядком, з ними — словником', () {
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
    test('початок 1.10 і період 2 дні: нагадування 3.10, 5.10, 7.10 о 9:00', () {
      final t = reminderTimes(
          lastVisit: DateTime(2026, 10, 1), periodDays: 2, now: DateTime(2026, 10, 1, 10));
      expect(t, [DateTime(2026, 10, 3, 9), DateTime(2026, 10, 5, 9), DateTime(2026, 10, 7, 9)]);
    });

    test('обійшов 3.10 — наступне нагадування 5.10', () {
      final t = reminderTimes(
          lastVisit: DateTime(2026, 10, 3), periodDays: 2, now: DateTime(2026, 10, 3, 12));
      expect(t.first, DateTime(2026, 10, 5, 9));
    });

    test('прострочений обхід: далі кожні період днів у майбутньому', () {
      final t = reminderTimes(
          lastVisit: DateTime(2026, 10, 1), periodDays: 2, now: DateTime(2026, 10, 10, 12));
      expect(t, [DateTime(2026, 10, 11, 9), DateTime(2026, 10, 13, 9), DateTime(2026, 10, 15, 9)]);
    });

    test('нульовий/від\'ємний/завеликий період — без нагадувань', () {
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

    test('текст сповіщення', () {
      final p = planReminders([target()], now: DateTime(2026, 10, 1, 10));
      expect(p.first.body, 'Ти давно не заглядав у вулик 5. Перевір його');
      expect(p.first.title, 'Пасіка');
      expect(reminderBody('Лежак 1'), 'Ти давно не заглядав у вулик Лежак 1. Перевір його');
    });

    test('без періоду або без дати відліку — нічого; дата відліку з моменту задання періоду', () {
      final now = DateTime(2026, 10, 1, 10);
      expect(planReminders([target(period: null)], now: now), isEmpty);
      expect(planReminders([target(last: null)], now: now), isEmpty);
      final p = planReminders([target(last: null, setAt: DateTime(2026, 10, 1, 8))], now: now);
      expect(p.first.when, DateTime(2026, 10, 3, 9));
    });

    test('ліміт кількості й порядок за часом', () {
      final many = [for (var i = 0; i < 50; i++) target()];
      final p = planReminders(many, now: DateTime(2026, 10, 1, 10), limit: 20);
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
}
