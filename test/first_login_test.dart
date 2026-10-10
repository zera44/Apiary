import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/first_login.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_api.dart';
import 'package:apiary/data/sync_engine.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/services/backups.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/first_login_dialog.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_sync_server.dart';

/// Перший вхід на телефоні: дані на телефоні й на сервері.
void main() {
  late FakeSyncServer server;
  late Directory dir;
  final opened = <Repository>[];

  setUpAll(sqfliteFfiInit);
  setUp(() {
    server = FakeSyncServer();
    dir = Directory.systemTemp.createTempSync('apiary_first_');
  });
  tearDown(() async {
    for (final r in opened) {
      await r.db.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  var k = 0;
  Future<Repository> phone() async {
    final r = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, p.join(dir.path, 'p${k++}.db')));
    await r.prepareLikeFreshInstall();
    opened.add(r);
    return r;
  }

  BackupService backupsOf(Repository r) =>
      BackupService(r, dir: p.join(dir.path, 'bk${r.hashCode}'), factory: databaseFactoryFfiNoIsolate);

  Future<FirstLoginState> login(Repository r, [String uid = 'u1']) => FirstLogin(r, server.as(uid)).prepare();
  Future<void> sync(Repository r, [String uid = 'u1']) => SyncEngine(r, server.as(uid)).run();
  Future<List<String>> names(Repository r) async => [for (final a in await r.listApiaries()) a.name]..sort();

  /// На сервері вже є дані акаунта (з іншого телефона).
  Future<Repository> serverHas(String name) async {
    final other = await phone();
    await other.addApiary(name);
    expect(await login(other), FirstLoginState.ready);
    await sync(other);
    return other;
  }

  test('новий телефон, на сервері дані - просто отримати все', () async {
    await serverHas('З сервера');
    final a = await phone();
    expect(await FirstLogin.localHasData(a), isFalse, reason: 'типові записи не рахуються');
    expect(await login(a), FirstLoginState.ready);
    await sync(a);
    expect(await names(a), ['З сервера']);
  });

  test('на сервері порожньо - дані телефона просто вгору', () async {
    final a = await phone();
    await a.addApiary('Моя');
    expect(await login(a), FirstLoginState.ready);
    await sync(a);
    expect(server.t('apiaries').values.map((r) => r['name']), contains('Моя'));
  });

  test('дані і тут, і там - питаємо; поки не вибрали, синхронізація чекає', () async {
    await serverHas('З сервера');
    final a = await phone();
    await a.addApiary('З телефона');
    expect(await login(a), FirstLoginState.ask);
    await expectLater(sync(a), throwsA(isA<SyncNeedsChoice>()));
    expect(server.t('apiaries').values.map((r) => r['name']), isNot(contains('З телефона')));
    // повторна перевірка (новий запуск) - те саме питання
    expect(await login(a), FirstLoginState.ask);
  });

  test('«Злити все разом» - усе з обох боків', () async {
    final other = await serverHas('З сервера');
    final a = await phone();
    await a.addApiary('З телефона');
    expect(await login(a), FirstLoginState.ask);
    await FirstLogin(a, server.as('u1')).apply(FirstLoginChoice.merge);
    await sync(a);
    await sync(other);
    expect(await names(a), ['З сервера', 'З телефона']);
    expect(await names(other), ['З сервера', 'З телефона']);
    // типові характеристики не подвоїлись
    final base = await a.db.query('parameters', where: "seed_key = 'base:hive:visit_start' AND deleted = 0");
    expect(base.length, 1);
  });

  test('«Залишити дані телефона» - чого на телефоні немає, видалено й на інших телефонах', () async {
    final other = await serverHas('З сервера');
    final a = await phone();
    await a.addApiary('З телефона');
    expect(await login(a), FirstLoginState.ask);
    await FirstLogin(a, server.as('u1')).apply(FirstLoginChoice.keepPhone);
    await sync(a);
    await sync(other);
    expect(await names(a), ['З телефона']);
    expect(await names(other), ['З телефона']);
  });

  test('«Залишити дані сервера» - дані телефона замінено (копія перед тим лишається)', () async {
    await serverHas('З сервера');
    final a = await phone();
    await a.addApiary('З телефона');
    final bk = backupsOf(a);
    expect(await login(a), FirstLoginState.ask);
    await FirstLogin(a, server.as('u1')).apply(FirstLoginChoice.keepServer, backups: (_) async => bk);
    expect(await names(a), isEmpty);
    // без мережі застосунок усе одно працює: базові характеристики на місці
    expect(await a.db.query('parameters', where: "seed_key = 'base:hive:visit_start'"), isNotEmpty);
    await sync(a);
    expect(await names(a), ['З сервера']);
    expect(server.t('apiaries').values.where((r) => r['name'] == 'З телефона'), isEmpty);
    final copies = await bk.list();
    expect(copies.single.kind, BackupKind.beforeRestore);
  });

  test('інший акаунт Google - питаємо; «Завантажити дані цього акаунта»', () async {
    final a = await phone();
    await a.addApiary('Першого акаунта');
    expect(await login(a, 'u1'), FirstLoginState.ready);
    await sync(a, 'u1');
    final b = await phone();
    await b.addApiary('Другого акаунта');
    expect(await login(b, 'u2'), FirstLoginState.ready);
    await sync(b, 'u2');

    expect(await login(a, 'u2'), FirstLoginState.otherAccount);
    await expectLater(sync(a, 'u2'), throwsA(isA<SyncNeedsChoice>()));
    await FirstLogin(a, server.as('u2'))
        .apply(FirstLoginChoice.keepServer, backups: (_) async => backupsOf(a));
    await sync(a, 'u2');
    expect(await names(a), ['Другого акаунта']);
    // дані першого акаунта на сервері не змішано
    expect(server.t('apiaries').values.where((r) => r['owner_id'] == 'u2').map((r) => r['name']),
        ['Другого акаунта']);
  });

  testWidgets('вікно: три варіанти; небезпечний - з підтвердженням, «Скасувати» - знову вибір',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FirstLoginAnswer? answer;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              answer = await showFirstLoginDialog(c, FirstLoginState.ask);
              done = true;
            },
            child: const Text('x'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('x'));
    await tester.pumpAndSettle();
    expect(find.text(tr.firstLoginMerge), findsOneWidget);
    expect(find.text(tr.firstLoginKeepPhone), findsOneWidget);
    expect(find.text(tr.firstLoginKeepServer), findsOneWidget);
    // поза вікном - не закривається
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(tr.firstLoginTitle), findsOneWidget);

    await tester.tap(find.text(tr.firstLoginKeepPhone));
    await tester.pumpAndSettle();
    expect(find.text(tr.firstLoginKeepPhoneConfirm), findsOneWidget);
    await tester.tap(find.text(tr.cancel));
    await tester.pumpAndSettle();
    expect(done, isFalse);
    expect(find.text(tr.firstLoginMerge), findsOneWidget); // знову вибір

    await tester.tap(find.text(tr.firstLoginKeepServer));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillButton, tr.firstLoginKeepServer).last);
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(answer?.choice, FirstLoginChoice.keepServer);
  });
}
