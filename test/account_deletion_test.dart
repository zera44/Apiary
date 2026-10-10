import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_api.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/settings_main_tab.dart';
import 'package:apiary/services/account_deletion.dart';
import 'package:apiary/services/backups.dart';
import 'package:apiary/services/server.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show FakeAuth;

/// «Видалити акаунт і всі дані» (Google Play) і «Політика конфіденційності».
void main() {
  late Directory dir;
  late Repository repo;
  late BackupService backups;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('apiary_delete_');
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, p.join(dir.path, 'a.db')));
    await repo.prepareLikeFreshInstall();
    backups = BackupService(repo, dir: p.join(dir.path, 'bk'), factory: databaseFactoryFfiNoIsolate);
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
    Server.debugAuth = null;
  });

  test('сервер видалив - на телефоні як після нової інсталяції, копій немає', () async {
    await repo.addApiary('Моя');
    final item = await repo.addStockItem('Цукор', 'кг');
    await repo.setMeta('sync_user', 'u1');
    await backups.create();
    var called = 0;
    await deleteAccountAndData(repo: repo, deleteOnServer: () async => called++, backups: (_) async => backups);
    expect(called, 1);
    expect(await repo.listApiaries(), isEmpty);
    expect(await repo.db.query('stock_items', where: 'id = ?', whereArgs: [item]), isEmpty);
    expect(await repo.getMeta('sync_user'), isNull);
    expect(Directory(backups.dir).existsSync(), isFalse);
    // застосунок працює далі: базові характеристики й шаблони на місці
    expect(await repo.db.query('parameters', where: "seed_key = 'base:hive:visit_start'"), isNotEmpty);
    expect(await repo.db.query('templates', where: 'deleted = 0'), isNotEmpty);
  });

  test('сервер не відповів - на телефоні нічого не чіпаємо', () async {
    await repo.addApiary('Моя');
    await expectLater(
        deleteAccountAndData(
            repo: repo, deleteOnServer: () async => throw const SyncOffline(), backups: (_) async => backups),
        throwsA(isA<SyncOffline>()));
    expect((await repo.listApiaries()).single.name, 'Моя');
  });

  testWidgets('кнопка - лише після входу; два підтвердження, друге - написати слово', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // без входу - лише політика
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: MainSettingsTab(repo: repo))));
    await settle();
    expect(find.text(tr.privacyPolicy), findsOneWidget);
    expect(find.text(tr.accountDelete), findsNothing);
    await tester.tap(find.text(tr.privacyPolicy));
    await settle();
    expect(find.text(tr.privacySoon), findsOneWidget);
    await tester.tap(find.text(tr.close));
    await settle();

    Server.debugAuth = FakeAuth(signedIn: true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: MainSettingsTab(repo: repo))));
    await settle();
    expect(find.text(tr.accountSignedInAs('pasichnyk@example.com')), findsOneWidget);
    await tester.tap(find.text(tr.accountDelete));
    await settle();
    expect(find.text(tr.accountDeleteText), findsOneWidget);
    await tester.tap(find.widgetWithText(PillButton, tr.accountDeleteContinue));
    await settle();
    expect(find.text(tr.accountDeleteFinalText), findsOneWidget);
    // поки слово не написано - кнопка вимкнена
    final btn = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(PillButton, tr.accountDelete));
    expect(tester.widget<PillButton>(btn).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'видалити');
    await settle();
    expect(tester.widget<PillButton>(btn).onPressed, isNotNull);
    await tester.tap(btn);
    await settle();
    // сервера в тесті немає - зрозуміла помилка, дані на місці
    expect(find.textContaining(tr.accountDeleteFailed('')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
