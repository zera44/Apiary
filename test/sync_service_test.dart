import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_api.dart';
import 'package:apiary/data/sync_engine.dart';
import 'package:apiary/data/sync_schedule.dart';
import 'package:apiary/data/sync_service.dart';
import 'package:apiary/services/app_config.dart';
import 'package:apiary/services/backups.dart';
import 'package:apiary/services/server_backups.dart';
import 'package:apiary/services/supabase_api.dart';
import 'package:apiary/screens/settings_main_tab.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_sync_server.dart';

const _config = AppConfig(supabaseUrl: 'https://x.supabase.co', supabaseAnonKey: 'anon');

void main() {
  setUpAll(sqfliteFfiInit);

  group('розклад', () {
    final t = DateTime(2026, 10, 10, 14, 30);
    test('щогодини у свою хвилину', () {
      // хвилина телефона - 17: вікно почалось о 14:17
      expect(SyncSchedule.slotStart(t, 17), DateTime(2026, 10, 10, 14, 17));
      expect(SyncSchedule.slotStart(t, 45), DateTime(2026, 10, 10, 13, 45));
      expect(SyncSchedule.hourlyDue(null, t, 17), isTrue);
      expect(SyncSchedule.hourlyDue(DateTime(2026, 10, 10, 14, 20), t, 17), isFalse); // уже пробували
      expect(SyncSchedule.hourlyDue(DateTime(2026, 10, 10, 14, 10), t, 17), isTrue); // до 14:17
      expect(SyncSchedule.hourlyDue(DateTime(2026, 10, 10, 13, 50), t, 45), isFalse);
    });

    test('понад добу без зв\'язку - одразу (не частіше, ніж раз на 5 хв)', () {
      final day = t.subtract(const Duration(hours: 25));
      expect(SyncSchedule.catchUpDue(day, null, t), isTrue);
      expect(SyncSchedule.catchUpDue(day, t.subtract(const Duration(minutes: 2)), t), isFalse);
      expect(SyncSchedule.catchUpDue(day, t.subtract(const Duration(minutes: 6)), t), isTrue);
      expect(SyncSchedule.catchUpDue(t.subtract(const Duration(hours: 3)), null, t), isFalse);
      // годинник перевели назад - не застрягаємо
      expect(SyncSchedule.catchUpDue(day, t.add(const Duration(hours: 1)), t), isTrue);
    });

    test('нічна копія: 00:00-06:00, раз за ніч', () {
      final night = DateTime(2026, 10, 10, 2, 15);
      expect(SyncSchedule.nightlyDue(null, night), isTrue);
      expect(SyncSchedule.nightlyDue(DateTime(2026, 10, 10, 0, 40), night), isFalse);
      expect(SyncSchedule.nightlyDue(DateTime(2026, 10, 9, 1, 0), night), isTrue);
      expect(SyncSchedule.nightlyDue(null, DateTime(2026, 10, 10, 6, 0)), isFalse);
      expect(SyncSchedule.nightlyDue(null, DateTime(2026, 10, 10, 23, 0)), isFalse);
    });
  });

  group('SyncService', () {
    late Directory dir;
    late Repository repo;
    late FakeSyncServer server;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('apiary_syncsvc_');
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, p.join(dir.path, 'a.db')));
      await repo.init();
      server = FakeSyncServer();
    });
    tearDown(() async {
      await repo.db.close();
      dir.deleteSync(recursive: true);
      SyncService.info.value = const SyncInfo(disabled: true);
    });

    SyncService svc({bool mobileOnly = false, SyncApi? api}) => SyncService(repo,
        config: _config, api: api ?? server.as('u1'), mobileOnly: () async => mobileOnly);

    test('без входу - вимкнено, але видно, що треба увійти', () async {
      final s = SyncService(repo, config: _config);
      expect(s.enabled, isFalse);
      expect(await s.syncNow(), isNull);
      expect(SyncService.info.value.disabled, isTrue);
      expect(SyncService.info.value.needsSignIn, isTrue);
    });

    test('вхід на сервері відкликали - служба просить увійти знову', () async {
      await repo.addApiary('Перша');
      final s = svc(api: _SignedOutApi(server.as('u1')));
      var asked = 0;
      s.onSignedOut = () async => asked++;
      expect(await s.syncNow(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(asked, 1);
      expect(s.api, isNull);
      expect(SyncService.info.value.disabled, isTrue);
    });

    test('сервер налаштовано, а вхід не вдався - повтор не частіше, ніж раз на 5 хв', () async {
      final s = SyncService(repo, config: _config, mobileOnly: () async => false);
      var tries = 0;
      s.reconnect = () async => tries++;
      final t = DateTime(2026, 10, 10, 12);
      await withClock(Clock.fixed(t), s.tick);
      await withClock(Clock.fixed(t.add(const Duration(minutes: 1))), s.tick);
      await withClock(Clock.fixed(t.add(const Duration(minutes: 6))), s.tick);
      expect(tries, 2);
    });

    test('синхронізація: черга порожня, стан «остання синхронізація»', () async {
      await repo.addApiary('Перша');
      final s = svc();
      final r = await s.syncNow();
      expect(r, isNotNull);
      expect(await repo.countUnsynced(), 0);
      expect(SyncService.info.value.lastOk, isNotNull);
      expect(SyncService.info.value.pending, 0);
      expect(SyncService.info.value.error, isNull);
    });

    test('без зв\'язку - «немає зв\'язку», черга лишається', () async {
      await repo.addApiary('Перша');
      server.offline = true;
      final s = svc();
      expect(await s.syncNow(), isNull);
      expect(SyncService.info.value.offline, isTrue);
      expect(SyncService.info.value.pending, greaterThan(0));
    });

    test('мобільний інтернет вимкнено - на мобільному чекає Wi-Fi', () async {
      await repo.addApiary('Перша');
      final s = svc(mobileOnly: true);
      expect(await s.mobileAllowed(), isTrue, reason: 'за замовчуванням - можна');
      await s.setMobileAllowed(false);
      expect(await s.syncNow(), isNull);
      expect(SyncService.info.value.waitingWifi, isTrue);
      expect(await repo.countUnsynced(), greaterThan(0));
      await s.setMobileAllowed(true);
      expect(await s.syncNow(), isNotNull);
    });

    test('замок: поки синхронізує фонове завдання, застосунок пропускає хід', () async {
      await repo.setMeta(SyncService.lockKey,
          '${clock.now().add(const Duration(minutes: 5)).microsecondsSinceEpoch / 1e6}');
      expect(await svc().syncNow(), isNull);
      // покинутий замок (старший за 10 хв) не заважає
      await repo.setMeta(SyncService.lockKey,
          '${clock.now().subtract(const Duration(minutes: 1)).microsecondsSinceEpoch / 1e6}');
      expect(await svc().syncNow(), isNotNull);
      expect(await repo.getMeta(SyncService.lockKey), '');
    });

    test('за розкладом: щогодини у свою хвилину, не частіше', () async {
      final s = svc();
      await repo.setMeta(SyncService.minuteKey, '17');
      expect(await withClock(Clock.fixed(DateTime(2026, 10, 10, 14, 20)), s.maybeSync), isNotNull);
      expect(await withClock(Clock.fixed(DateTime(2026, 10, 10, 14, 50)), s.maybeSync), isNull);
      expect(await withClock(Clock.fixed(DateTime(2026, 10, 10, 15, 18)), s.maybeSync), isNotNull);
      // хвилина - своя назавжди
      expect(await s.minute(), 17);
    });

    test('нічна копія: сервер тримає 2 цілі; «Завантажити з сервера» повертає дані', () async {
      final backups = BackupService(repo, dir: p.join(dir.path, 'bk'), factory: databaseFactoryFfiNoIsolate);
      final s = svc();
      final a = await repo.addApiary('Перша ніч');
      // до першої синхронізації (поки не ясно, чиї дані на телефоні) - копії немає
      expect(await withClock(Clock.fixed(DateTime(2026, 10, 1, 1)), () => s.maybeNightly(backups: (_) async => backups)),
          isNull);
      await repo.setMeta(SyncEngine.userKey, 'u1');
      for (final (day, name) in [(1, 'Перша ніч'), (2, 'Друга ніч'), (3, 'Третя ніч')]) {
        await repo.updateApiary(a, name: name);
        final status =
            await withClock(Clock.fixed(DateTime(2026, 10, day, 2)), () => s.maybeNightly(backups: (_) async => backups));
        expect(status, 'ok');
        // тієї ж ночі - вдруге не треба
        expect(await withClock(Clock.fixed(DateTime(2026, 10, day, 3)),
            () => s.maybeNightly(backups: (_) async => backups)), isNull);
      }
      final list = await server.as('u1').listBackups();
      expect(list.length, 2);
      expect(server.backupFiles.length, 2);

      await repo.updateApiary(a, name: 'Зараз');
      final restore = ServerBackups(repo, server.as('u1'), backups);
      final oldest = list.last;
      final before = await restore.restore(oldest);
      expect((await repo.getApiary(a))!.name, 'Друга ніч');
      expect(before.kind, BackupKind.beforeRestore); // можна повернути
      await backups.restoreFrom(before.path);
      expect((await repo.getApiary(a))!.name, 'Зараз');
    });

    testWidgets('Налаштування → «Головне»: синхронізувати зараз; мобільний інтернет - '
        'попередження лише раз', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = svc();
      SyncService.current = s;
      addTearDown(() => SyncService.current = null);
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.runAsync(() => repo.addApiary('Перша'));
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(), home: Scaffold(body: MainSettingsTab(repo: repo))));
      await settle();
      expect(find.text(tr.syncNow), findsOneWidget);
      expect(find.text(tr.serverRestore), findsOneWidget);
      await tester.tap(find.text(tr.syncNow));
      for (var k = 0; k < 20 && find.text(tr.syncDone).evaluate().isEmpty; k++) {
        await settle();
      }
      expect(find.text(tr.syncDone), findsOneWidget);
      expect(await tester.runAsync(repo.countUnsynced), 0);

      // вимкнути - без питань; увімкнути вперше - пояснення про трафік
      await tester.tap(find.text(tr.syncMobile));
      await settle();
      expect(await tester.runAsync(s.mobileAllowed), isFalse);
      await tester.tap(find.text(tr.syncMobile));
      await settle();
      expect(find.text(tr.syncMobileWarnText), findsOneWidget);
      await tester.tap(find.widgetWithText(PillButton, tr.syncMobile));
      await settle();
      expect(await tester.runAsync(s.mobileAllowed), isTrue);
      // удруге - без пояснення
      await tester.tap(find.text(tr.syncMobile));
      await settle();
      await tester.tap(find.text(tr.syncMobile));
      await settle();
      expect(find.text(tr.syncMobileWarnText), findsNothing);
      expect(await tester.runAsync(s.mobileAllowed), isTrue);
      expect(tester.takeException(), isNull);
    });

    test('копія, що дійшла зіпсованою, не відновлюється', () async {
      final backups = BackupService(repo, dir: p.join(dir.path, 'bk'), factory: databaseFactoryFfiNoIsolate);
      final api = server.as('u1');
      expect(await ServerBackups(repo, api, backups).upload(), 'ok');
      final b = (await api.listBackups()).single;
      server.backupFiles[b.path] = server.backupFiles[b.path]!.sublist(0, 100);
      final a = await repo.addApiary('Як було');
      await expectLater(ServerBackups(repo, api, backups).restore(b), throwsA(isA<BackupException>()));
      expect((await repo.getApiary(a))!.name, 'Як було');
    });
  });

  group('клієнт Supabase', () {
    final requests = <http.Request>[];
    late MemorySessionStore store;

    SupabaseSession session({Duration left = const Duration(hours: 1), String token = 'at-1'}) =>
        SupabaseSession(
          accessToken: token,
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().add(left),
          userId: 'u1',
          email: 'olena@gmail.com',
        );

    Future<SupabaseApi> api(Future<http.Response> Function(http.Request) handler, {SupabaseSession? s}) async {
      requests.clear();
      store = MemorySessionStore(s ?? session());
      return (await SupabaseApi.restore(_config, store, client: MockClient((r) {
        requests.add(r);
        return handler(r);
      })))!;
    }

    test('вхід Google-токеном зберігає вхід', () async {
      store = MemorySessionStore();
      final c = MockClient((r) async {
        expect(r.url.path, '/auth/v1/token');
        expect(r.url.queryParameters['grant_type'], 'id_token');
        expect(r.headers['apikey'], 'anon');
        expect(jsonDecode(r.body), {'provider': 'google', 'id_token': 'google-token'});
        return http.Response(
            jsonEncode({
              'access_token': 'at',
              'refresh_token': 'rt',
              'expires_in': 3600,
              'user': {'id': 'u1', 'email': 'Olena@Gmail.com'},
            }),
            200);
      });
      final a = await SupabaseApi.signInWithGoogle(_config, store, 'google-token', client: c);
      expect(a.userId, 'u1');
      expect(a.myEmail, 'olena@gmail.com');
      expect(store.value!.refreshToken, 'rt');
    });

    test('відправка: upsert пакетом з правильними заголовками', () async {
      final a = await api((_) async => http.Response('', 201));
      await a.upsert('apiaries', [
        {'id': 'a1', 'name': 'П', 'owner_id': 'u1'},
      ]);
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://x.supabase.co/rest/v1/apiaries?on_conflict=id');
      expect(r.headers['Authorization'], 'Bearer at-1');
      expect(r.headers['Prefer'], contains('resolution=merge-duplicates'));
      expect(jsonDecode(r.body), [
        {'id': 'a1', 'name': 'П', 'owner_id': 'u1'},
      ]);
    });

    test('забирання змін - функцією sync_pull', () async {
      final a = await api((_) async => http.Response(
          jsonEncode({
            'rows': [
              {'id': 'a1', 'server_xid': '7', 'server_seq': 3},
            ],
            'next': '7:3',
            'more': false,
          }),
          200));
      final page = await a.pull('apiaries', '5:1');
      expect(requests.single.url.path, '/rest/v1/rpc/sync_pull');
      expect(jsonDecode(requests.single.body), {'p_table': 'apiaries', 'p_after': '5:1', 'p_limit': 500});
      expect(page.next, '7:3');
      expect(page.rows.single['id'], 'a1');
    });

    test('вхід скоро закінчиться - спершу оновлення, потім запит', () async {
      final a = await api((r) async {
        if (r.url.path == '/auth/v1/token') {
          expect(r.url.queryParameters['grant_type'], 'refresh_token');
          return http.Response(
              jsonEncode({
                'access_token': 'at-2',
                'refresh_token': 'rt-2',
                'expires_in': 3600,
                'user': {'id': 'u1', 'email': 'olena@gmail.com'},
              }),
              200);
        }
        expect(r.headers['Authorization'], 'Bearer at-2');
        return http.Response('[]', 200);
      }, s: session(left: const Duration(seconds: 30)));
      await a.listBackups();
      expect(requests.length, 2);
      expect(store.value!.refreshToken, 'rt-2');
    });

    test('відкликаний вхід - «потрібно знову увійти»; сервер упав - «без зв\'язку»; '
        'правила - «відхилено»', () async {
      var a = await api((r) async => r.url.path == '/auth/v1/token'
          ? http.Response('{"error":"invalid_grant"}', 400)
          : http.Response('{"message":"JWT expired"}', 401));
      await expectLater(a.upsert('apiaries', [{'id': 'x'}]), throwsA(isA<SyncSignedOut>()));

      a = await api((_) async => http.Response('bad gateway', 502));
      await expectLater(a.upsert('apiaries', [{'id': 'x'}]), throwsA(isA<SyncOffline>()));

      a = await api((_) async => throw const SocketException('no route'));
      await expectLater(a.upsert('apiaries', [{'id': 'x'}]), throwsA(isA<SyncOffline>()));

      a = await api((_) async =>
          http.Response('{"message":"new row violates row-level security policy"}', 403));
      await expectLater(
          a.upsert('apiaries', [{'id': 'x'}]),
          throwsA(isA<SyncRejected>()
              .having((e) => e.message, 'message', contains('row-level security'))));
    });

    test('фото: шлях власника, тип; немає фото - null', () async {
      final a = await api((r) async => r.method == 'GET' ? http.Response('{"error":"not found"}', 404) : http.Response('{}', 200));
      await a.putPhoto('owner-1', 'abc.webp', Uint8List.fromList([1, 2, 3]));
      expect(requests.single.url.path, '/storage/v1/object/stock-photos/owner-1/abc.webp');
      expect(requests.single.headers['Content-Type'], 'image/webp');
      expect(await a.getPhoto('owner-1', 'none.webp'), isNull);
    });
  });
}

/// Сервер, що вважає вхід відкликаним.
class _SignedOutApi implements SyncApi {
  final SyncApi inner;
  _SignedOutApi(this.inner);
  @override
  String get userId => inner.userId;
  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) => throw const SyncSignedOut();
  @override
  dynamic noSuchMethod(Invocation i) => throw const SyncSignedOut();
}
