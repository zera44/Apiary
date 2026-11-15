import 'dart:convert';

import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/services/telegram_login.dart';
import 'package:apiary/ui/security_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Фейкова функція: стан PIN, Telegram і виклики.
class _Fn {
  String pin = 'off'; // none | on | off
  String? phone;
  String? disableAt;
  int failStatus = 0;
  String failCode = '';
  final calls = <Map<String, Object?>>[];
  final auth = <String?>[];

  TelegramAuthApi get api => TelegramAuthApi(Uri.parse('https://x/f'), 'anon',
      client: MockClient((req) async {
        final b = jsonDecode(req.body) as Map<String, Object?>;
        calls.add(b);
        auth.add(req.headers['Authorization']);
        http.Response j(Object o, [int s = 200]) =>
            http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json; charset=utf-8'});
        if (failStatus != 0 && b['action'] != 'pin_status') return j({'error': failCode}, failStatus);
        switch (b['action']) {
          case 'pin_status':
            return j({'state': pin, 'telegram_only': false, 'disable_at': disableAt, 'telegram': phone == null ? null : {'phone': phone}});
          case 'pin_set':
            pin = 'on';
            return j({'ok': true, 'recovery_code': 'ABCDE-FGHJK-LMNPQ-RSTUV'});
          case 'pin_disable':
            pin = 'off';
            return j({'ok': true, 'state': 'off'});
          case 'sign_out_everywhere':
            return j({'ok': true, 'sessions': 2});
        }
        return j({'error': 'unknown'}, 400);
      }));
}

var signedOut = 0;

Future<void> _show(WidgetTester t, _Fn fn) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SecurityControls(afterSignOutEverywhere: () async => signedOut++, api: fn.api, accessToken: () async => 'tok'),
      ),
    ),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('PIN вимкнено: пропонує увімкнути, показує код відновлення', (t) async {
    final fn = _Fn();
    await _show(t, fn);
    expect(find.text(tr.secPinOff), findsOneWidget);
    expect(find.text(tr.secTelegramNone), findsOneWidget);
    expect(fn.auth.first, 'Bearer tok');

    await t.ensureVisible(find.byKey(const Key('sec-enable')));
    await t.tap(find.byKey(const Key('sec-enable')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'k7-Quartz-91');
    await t.enterText(find.byType(TextField).at(1), 'k7-Quartz-92');
    await t.tap(find.text(tr.secSave));
    await t.pumpAndSettle();
    expect(find.text(tr.pinMismatch), findsOneWidget);
    expect(fn.calls.where((c) => c['action'] == 'pin_set'), isEmpty);

    await t.ensureVisible(find.byKey(const Key('sec-enable')));
    await t.tap(find.byKey(const Key('sec-enable')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'k7-Quartz-91');
    await t.enterText(find.byType(TextField).at(1), 'k7-Quartz-91');
    await t.tap(find.text(tr.secSave));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sec-recovery')), findsOneWidget);
    expect(fn.calls.lastWhere((c) => c['action'] == 'pin_set')['new_pin'], 'k7-Quartz-91');
    await t.tap(find.text(tr.recoveryWritten));
    await t.pumpAndSettle();
    expect(find.text(tr.secPinOn), findsOneWidget, reason: 'стан оновився');
    expect(find.byKey(const Key('sec-disable')), findsOneWidget);
  });

  testWidgets('вимкнення PIN: потрібен чинний PIN; невірний - зрозуміла помилка', (t) async {
    final fn = _Fn()
      ..pin = 'on'
      ..phone = '+380501112233';
    await _show(t, fn);
    expect(find.text(tr.secTelegramLinked('+380501112233')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('sec-disable')));

    fn
      ..failStatus = 401
      ..failCode = 'wrong_pin';
    await t.tap(find.byKey(const Key('sec-disable')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'nope-nope-1');
    await t.tap(find.text(tr.secSave));
    await t.pumpAndSettle();
    expect(find.text(tr.pinWrong), findsOneWidget);

    fn.failStatus = 0;
    await t.ensureVisible(find.byKey(const Key('sec-disable')));
    await t.tap(find.byKey(const Key('sec-disable')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'k7-Quartz-91');
    await t.tap(find.text(tr.secSave));
    await t.pumpAndSettle();
    expect(fn.calls.lastWhere((c) => c['action'] == 'pin_disable')['pin'], 'k7-Quartz-91');
    expect(find.text(tr.secPinOff), findsOneWidget);
  });

  testWidgets('вийти на всіх пристроях: сервер, потім цей телефон', (t) async {
    signedOut = 0;
    final fn = _Fn()..pin = 'on';
    await _show(t, fn);
    await t.ensureVisible(find.byKey(const Key('sec-signout')));
    await t.tap(find.byKey(const Key('sec-signout')));
    await t.pumpAndSettle();
    await t.tap(find.text(tr.secSignOutAll).last);
    await t.pumpAndSettle();
    expect(fn.calls.any((c) => c['action'] == 'sign_out_everywhere'), true);
    expect(signedOut, 1);
  });

  testWidgets('немає зв\'язку зі станом - повідомлення й повтор', (t) async {
    final api = TelegramAuthApi(Uri.parse('https://x/f'), 'anon', client: MockClient((_) async => throw http.ClientException('no net')));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SecurityControls(afterSignOutEverywhere: () async {}, api: api, accessToken: () async => 'tok')),
    ));
    await t.pump();
    await t.pump();
    expect(find.text(tr.secLoadFailed), findsOneWidget);
    expect(find.text(tr.tgTryAgain), findsOneWidget);
  });
}
