import 'package:flutter_test/flutter_test.dart';
import 'package:apiary/logic/notify_schedule.dart';

void main() {
  group('графік сповіщень', () {
    test('5/2: п\'ять днів так, два ні, від дати початку', () {
      final s = NotifySchedule(mode: NotifyMode.w52, start: DateTime(2026, 11, 2)); // понеділок
      final on = [for (var i = 0; i < 14; i++) s.allows(DateTime(2026, 11, 2 + i))];
      expect(on, [true, true, true, true, true, false, false, true, true, true, true, true, false, false]);
      expect(s.allows(DateTime(2026, 11, 1)), isFalse); // до початку
    });

    test('2/2: два дні так, два ні', () {
      final s = NotifySchedule(mode: NotifyMode.w22, start: DateTime(2026, 11, 14));
      final on = [for (var i = 0; i < 8; i++) s.allows(DateTime(2026, 11, 14 + i))];
      expect(on, [true, true, false, false, true, true, false, false]);
    });

    test('довільний: лише обрані дні, кінець графіка і наступний дозволений день', () {
      final s = NotifySchedule(mode: NotifyMode.custom, custom: {DateTime(2026, 11, 3), DateTime(2026, 11, 10)});
      expect(s.allows(DateTime(2026, 11, 3, 15)), isTrue);
      expect(s.allows(DateTime(2026, 11, 4)), isFalse);
      expect(s.nextAllowed(DateTime(2026, 11, 4)), DateTime(2026, 11, 10));
      expect(s.customEnded(DateTime(2026, 11, 10)), isFalse);
      expect(s.customEnded(DateTime(2026, 11, 11)), isTrue);
      expect(s.endNoticeDay, DateTime(2026, 11, 11));
    });

    test('вимкнено: жодного дня', () {
      expect(const NotifySchedule(enabled: false).allows(DateTime(2026, 11, 3)), isFalse);
    });
  });
}
