import 'package:apiary/data/sync_service.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/l10n/strings_uk.dart';
import 'package:apiary/ui/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Інша мова для перевірки перемикання (усі ключі - як у справжньої мови).
class _TestStrings extends AppStringsUk {
  const _TestStrings();
  @override
  String get languageCode => 'xx';
  @override
  String get settingsTabMain => 'Main';
  @override
  String get syncDisabled => 'Sync off';
  @override
  String todayAt(String hm) => 'today $hm';
}

void main() {
  tearDown(() => L10n.debugOverride(null));

  group('множина українською', () {
    String w(int n) => pluralUk(n, one: 'зміна', few: 'зміни', many: 'змін');

    test('1, 21, 101 - «зміна»; 2-4, 22-24 - «зміни»; решта - «змін»', () {
      for (final n in [1, 21, 31, 101, 1001]) {
        expect(w(n), 'зміна', reason: '$n');
      }
      for (final n in [2, 3, 4, 22, 23, 24, 102, 1004]) {
        expect(w(n), 'зміни', reason: '$n');
      }
      for (final n in [0, 5, 9, 10, 11, 12, 13, 14, 15, 19, 20, 25, 100, 111, 112, 114]) {
        expect(w(n), 'змін', reason: '$n');
      }
      expect(w(-2), 'зміни'); // знак не важить
    });

    test('у текстах: «Очікує відправки: 3 зміни»', () {
      expect(tr.syncPending(1), 'Очікує відправки: 1 зміна');
      expect(tr.syncPending(3), 'Очікує відправки: 3 зміни');
      expect(tr.syncPending(11), 'Очікує відправки: 11 змін');
    });
  });

  group('мова інтерфейсу', () {
    test('за замовчуванням - українська', () {
      expect(tr.languageCode, 'uk');
      expect(tr.settingsTabMain, 'Головне');
      expect(L10n.language.value, 'uk');
    });

    test('невідома мова не вмикається, відома - вмикається', () {
      expect(L10n.use('zz'), isFalse);
      expect(tr.languageCode, 'uk');
      expect(L10n.use('uk'), isTrue);
      expect(tr.languageCode, 'uk');
    });

    test('інша мова підміняє всі тексти, зокрема в рядку стану', () {
      L10n.debugOverride(const _TestStrings());
      expect(L10n.language.value, 'xx');
      expect(tr.settingsTabMain, 'Main');
      expect(syncStatusText(const SyncInfo(disabled: true)), 'Sync off');
      final now = DateTime(2026, 10, 10, 18);
      expect(formatWhen(DateTime(2026, 10, 10, 9, 5), now: now), 'today 09:05');
      L10n.debugOverride(null);
      expect(tr.settingsTabMain, 'Головне');
    });

    test('жоден текст української не порожній', () {
      const s = AppStringsUk();
      for (final t in [
        s.settingsTitle,
        s.settingsTabMain,
        s.settingsTabTemplates,
        s.syncSection,
        s.syncDisabled,
        s.syncOffline,
        s.syncPending(2),
        s.syncLastOk('x'),
        s.syncError('x'),
        s.todayAt('09:00'),
        s.dbTooNew(3, 2),
      ]) {
        expect(t.trim(), isNotEmpty);
      }
    });
  });

  group('рядок стану синхронізації', () {
    final now = DateTime(2026, 10, 10, 18, 30);

    test('вимкнена - про це й пише (навіть якщо щось чекає)', () {
      expect(syncStatusText(const SyncInfo(disabled: true, pending: 5)), tr.syncDisabled);
    });

    test('помилка, без зв\'язку, черга, остання синхронізація', () {
      expect(syncStatusText(const SyncInfo(error: 'тайм-аут')), 'Помилка синхронізації: тайм-аут');
      expect(syncStatusText(const SyncInfo(offline: true)), tr.syncOffline);
      expect(syncStatusText(const SyncInfo(pending: 2)), 'Очікує відправки: 2 зміни');
      expect(syncStatusText(SyncInfo(lastOk: DateTime(2026, 10, 10, 14, 5)), now: now),
          'Остання синхронізація: сьогодні 14:05');
      expect(syncStatusText(SyncInfo(lastOk: DateTime(2026, 10, 9, 23, 59)), now: now),
          'Остання синхронізація: 09.10 23:59');
      expect(syncStatusText(const SyncInfo()), isNull);
      // у Google увійшли, а сервер не прийняв - не «увійдіть через Google»
      const noServer = SyncInfo(disabled: true, needsSignIn: true);
      expect(syncStatusText(noServer), tr.syncNeedsSignIn);
      expect(syncStatusText(noServer, googleSignedIn: true), tr.serverNotConnected);
    });
  });
}
