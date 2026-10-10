import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sharing.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/helpers_screen.dart';
import 'package:apiary/services/sharing.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/invitations_sheet.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_sharing_server.dart';

/// Спільний доступ: власник (Олена) запрошує помічника (Петра). Два
/// «телефони» (дві бази) і фейковий сервер між ними.
void main() {
  late FakeSharingServer server;
  late Repository olenaPhone, petroPhone;
  late SharingService olena, petro;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    server = FakeSharingServer()
      ..register('u-olena', 'olena@gmail.com')
      ..register('u-petro', 'Petro@Gmail.com');
    Future<Repository> phone() async {
      final r = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
          singleInstance: false));
      await r.init();
      return r;
    }

    olenaPhone = await phone();
    petroPhone = await phone();
    olena = SharingService(server.as('olena@gmail.com'), olenaPhone);
    petro = SharingService(server.as('petro@gmail.com'), petroPhone);
  });
  tearDown(() async {
    await olenaPhone.db.close();
    await petroPhone.db.close();
    SharingService.current = SharingService(null, null);
  });

  test('запрошення до всіх пасік: надіслано, прийнято - помічник у власника', () async {
    final (out, _) = await olena.invite(' PETRO@gmail.com ');
    expect(out, InviteOutcome.sent);
    // у помічника - у скриньці
    final inbox = await petro.incoming();
    expect(inbox.single.fromEmail, 'olena@gmail.com');
    expect(inbox.single.allApiaries, isTrue);
    expect(petro.pending.value, 1);
    // власник бачить, що чекає відповіді
    expect((await olena.sent()).single.toEmail, 'petro@gmail.com');

    await petro.respond(inbox.single, accept: true);
    expect(petro.pending.value, 0);
    expect(await petro.incoming(), isEmpty);
    final helpers = await olena.helpers();
    expect(helpers.single.email, 'petro@gmail.com');
    expect(helpers.single.apiaryId, isNull); // усі пасіки, зокрема майбутні
    expect(helpers.single.stockAccess, isFalse);
    expect(await olena.sent(), isEmpty);
    // помічник чужих помічників не бачить
    expect(await petro.helpers(), isEmpty);
  });

  test('лише до однієї пасіки, зі складом; потім без складу; забрати доступ', () async {
    final a = await olenaPhone.addApiary('Біля річки');
    final (out, _) = await olena.invite('petro@gmail.com',
        apiaryIds: [a], apiaryNames: ['Біля річки'], stockAccess: true);
    expect(out, InviteOutcome.sent);
    final inv = (await petro.incoming()).single;
    expect(inv.apiaryNames, ['Біля річки']);
    expect(inv.stockAccess, isTrue);
    await petro.respond(inv, accept: true);

    var m = (await olena.helpers()).single;
    expect(m.apiaryId, a);
    expect(m.stockAccess, isTrue);
    await olena.setStockAccess(m, on: false);
    expect(server.members.values.single.stockAccess, isFalse);
    m = (await olena.helpers()).single;
    expect(m.stockAccess, isFalse);

    await olena.revoke(m);
    expect(server.members, isEmpty);
    expect(await olena.helpers(), isEmpty);
    expect(await olenaPhone.members(), isEmpty);
  });

  test('відхилили - доступу немає', () async {
    await olena.invite('petro@gmail.com');
    await petro.respond((await petro.incoming()).single, accept: false);
    expect(server.members, isEmpty);
    expect(server.invitations.values.single.status, InviteStatus.declined);
  });

  test('зрозумілі відмови: немає такого користувача, не пошта, сам собі, уже має доступ', () async {
    expect((await olena.invite('nobody@gmail.com')).$1, InviteOutcome.noSuchUser);
    expect((await olena.invite('не пошта')).$1, InviteOutcome.invalidEmail);
    expect((await olena.invite('Olena@gmail.com')).$1, InviteOutcome.self);
    await olena.invite('petro@gmail.com');
    await petro.respond((await petro.incoming()).single, accept: true);
    expect((await olena.invite('petro@gmail.com')).$1, InviteOutcome.alreadyHasAccess);
    expect(server.invitations.length, 1);
    // без сервера - ділитися неможливо
    expect((await SharingService(null, null).invite('petro@gmail.com')).$1,
        InviteOutcome.unavailable);
  });

  test('друге запрошення, поки перше чекає, - не надсилаємо; склад - перемикачем у списку',
      () async {
    await olena.invite('petro@gmail.com');
    expect((await olena.invite('petro@gmail.com')).$1, InviteOutcome.alreadyInvited);
    expect(server.invitations.length, 1);
    await petro.respond((await petro.incoming()).single, accept: true);
    // має всі пасіки без складу; просять склад - підказка, а не новий учасник
    final a = await olenaPhone.addApiary('Біля річки');
    expect((await olena.invite('petro@gmail.com', apiaryIds: [a], stockAccess: true)).$1,
        InviteOutcome.needsStockSwitch);
    expect((await olena.invite('petro@gmail.com', apiaryIds: [a])).$1,
        InviteOutcome.alreadyHasAccess);
    expect(server.members.length, 1);
  });

  test('одна пасіка зі складом не робить «уже має доступ» до іншої', () async {
    final a = await olenaPhone.addApiary('Біля річки');
    final b = await olenaPhone.addApiary('Лісова');
    await olena.invite('petro@gmail.com', apiaryIds: [a], stockAccess: true);
    await petro.respond((await petro.incoming()).single, accept: true);
    expect((await olena.invite('petro@gmail.com', apiaryIds: [b], stockAccess: true)).$1,
        InviteOutcome.sent);
  });

  testWidgets('скринька: відповісти не вдалося - помилка в самому вікні', (tester) async {
    SharingService.current = petro;
    await tester.runAsync(() => olena.invite('petro@gmail.com'));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
            builder: (c) => TextButton(onPressed: () => showInvitations(c), child: const Text('x'))),
      ),
    ));
    await tester.tap(find.text('x'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(tr.accept), findsOneWidget);
    server.offline = true;
    await tester.tap(find.text(tr.accept));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('зв\'язку'), findsOneWidget);
    expect(find.text(tr.accept), findsOneWidget); // вікно відкрите, можна ще раз
  });

  test('скасувати надіслане запрошення', () async {
    await olena.invite('petro@gmail.com');
    await olena.cancel((await olena.sent()).single);
    expect(await olena.sent(), isEmpty);
    expect(await petro.incoming(), isEmpty);
  });

  test('без зв\'язку: скринька - з копії на телефоні, запрошення - зрозуміла помилка', () async {
    await olena.invite('petro@gmail.com');
    expect((await petro.incoming()).length, 1);
    server.offline = true;
    expect((await petro.incoming()).length, 1); // з копії
    final (out, details) = await olena.invite('petro@gmail.com', apiaryIds: ['x']);
    expect(out, InviteOutcome.failed);
    expect(details, contains('зв\'язку'));
  });

  group('екран «Помічники»', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(), home: HelpersScreen(repo: olenaPhone)));
      await settle(tester);
    }

    testWidgets('запросити до однієї пасіки; помічник прийняв - у списку; забрати доступ',
        (tester) async {
      SharingService.current = olena;
      await tester.runAsync(() async {
        await olenaPhone.addApiary('Біля річки');
        await olenaPhone.addApiary('Лісова');
      });
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'nobody@gmail.com');
      await tester.tap(find.text(tr.sendInvite));
      await settle(tester);
      expect(find.text(tr.inviteNoSuchUser('nobody@gmail.com')), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'petro@gmail.com');
      await tester.tap(find.text(tr.accessOne));
      await settle(tester);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      await tester.tap(find.text(tr.accessStock));
      await settle(tester);
      await tester.tap(find.text(tr.sendInvite));
      await settle(tester);
      expect(find.text(tr.inviteSent('petro@gmail.com')), findsOneWidget);
      final inv = server.invitations.values.single;
      expect(inv.apiaryIds!.length, 1);
      expect(inv.stockAccess, isTrue);
      expect(find.text(tr.invitesSentTitle), findsOneWidget);

      // Петро прийняв
      await tester.runAsync(() async => petro.respond((await petro.incoming()).single, accept: true));
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(find.text('petro@gmail.com'), findsOneWidget);
      await tester.tap(find.text(tr.revokeAccess));
      await settle(tester);
      await tester.tap(find.widgetWithText(PillButton, tr.revokeAccess).last);
      await settle(tester);
      expect(server.members, isEmpty);
      expect(find.text(tr.helpersNone), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('без сервера: пояснення, форма вимкнена', (tester) async {
      SharingService.current = SharingService(null, null);
      await pump(tester);
      expect(find.text(tr.sharingUnavailable), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(tester.widget<PillButton>(find.widgetWithText(PillButton, tr.sendInvite)).onPressed,
          isNull);
    });
  });
}
