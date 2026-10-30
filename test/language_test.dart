import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/l10n/strings_en.dart';
import 'package:apiary/main.dart';
import 'package:apiary/screens/home_screen.dart';
import 'package:apiary/screens/settings_screen.dart';
import 'package:apiary/screens/whats_new_screen.dart';
import 'package:apiary/ui/first_hints.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show FakeAuth;

/// Англійська мова: вибір у Налаштуваннях → «Головне», збереження вибору
/// й повнота перекладу.
void main() {
  late Repository repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    await AppIcons.load();
    Hints.enabled = false;
    WhatsNewScreen.enabled = false;
    HomeScreen.mapBackdrop = false;
    ApiaryApp.listenLinks = false;
  });

  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    await repo.prepareLikeFreshInstall();
  });

  tearDown(() async {
    L10n.debugOverride(null);
    await repo.db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  test('вибір мови зберігається; на старті - збережена, невідома - українська', () async {
    await L10n.set(repo, 'en');
    expect(tr.languageCode, 'en');
    expect(await repo.getMeta(L10n.key), 'en');

    L10n.use('uk');
    await L10n.load(repo);
    expect(tr.languageCode, 'en');
    expect(tr.settingsTitle, 'Settings');

    await repo.setMeta(L10n.key, 'zz');
    await L10n.load(repo);
    expect(tr.languageCode, 'uk');
  });

  test('мова - налаштування телефона: у резервну копію не переходить', () {
    expect(L10n.key, startsWith('device_'));
  });

  test('англійською: множина й прапор', () {
    const en = AppStringsEn();
    expect(en.syncPending(1), 'Waiting to be sent: 1 change');
    expect(en.syncPending(3), 'Waiting to be sent: 3 changes');
    expect(en.mapDueHives(2), 'Inspect: 2 hives (red)');
    expect(en.records(1), '1 record');
    expect(en.languageFlag, '🇬🇧');
    expect(L10n.supported['uk']!.languageFlag, '🇺🇦');
  });

  test('в англійських текстах немає українських літер', () {
    final cyr = RegExp(r'[А-Яа-яІіЇїЄєҐґ]');
    final lines = File('lib/l10n/strings_en.dart').readAsLinesSync();
    final bad = [
      for (var i = 0; i < lines.length; i++)
        // коментарі й ключі назв кольорів (дані з бази) - не тексти
        if (cyr.hasMatch(lines[i]) &&
            !lines[i].trimLeft().startsWith('//') &&
            !lines[i].contains("const {'Білий'"))
          '${i + 1}: ${lines[i].trim()}',
    ];
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  testWidgets('«Змінити мову»: прапор, вибір англійської, усі екрани - одразу англійською',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ApiaryApp(repo: repo, auth: FakeAuth(configured: false)));
    await settle(tester);
    expect(find.text('Почати'), findsOneWidget);

    // Налаштування поверх головного екрана
    Navigator.of(tester.element(find.text('Почати')))
        .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(repo: repo)));
    await settle(tester);
    expect(find.text('🇺🇦'), findsOneWidget);
    expect(find.text('Змінити мову'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('language-change')));
    await settle(tester);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Українська'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-en')));
    await settle(tester);

    // налаштування лишились відкритими, але вже англійською
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('🇬🇧'), findsOneWidget);
    expect(find.text('Change language'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(await tester.runAsync(() => repo.getMeta(L10n.key)), 'en');

    // головний екран під ними теж перебудувався
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await settle(tester);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Почати'), findsNothing);

    // і назад українською
    Navigator.of(tester.element(find.text('Start')))
        .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(repo: repo)));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('language-change')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('language-uk')));
    await settle(tester);
    expect(find.text('🇺🇦'), findsOneWidget);
    expect(find.text('Змінити мову'), findsOneWidget);
  });
}
