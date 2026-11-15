import 'dart:convert';
import 'dart:math';

import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/telegram_login_screen.dart';
import 'package:apiary/services/auth.dart';
import 'package:apiary/services/telegram_login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Фейкова функція `telegram-auth`: стан заявки задає тест.
class _Fn {
  String state = 'new';
  String next = 'pin_setup';
  int retryIn = 0;
  String finishError = '';
  String? recovery = 'ABCDE-FGHJK-LMNPQ-RSTUV';
  final calls = <Map<String, Object?>>[];
  final headers = <Map<String, String>>[];

  http.Client get client => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        calls.add(body);
        headers.add(req.headers);
        Map<String, Object?> ok(Map<String, Object?> j) => j;
        http.Response json(Object j, [int status = 200]) => http.Response(jsonEncode(j), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        switch (body['action']) {
          case 'start':
            return json(ok({'id': 'ID' * 11, 'match': 42, 'url': 'https://t.me/vulyk_bot?start=${'ID' * 11}', 'expires_in': 300}));
          case 'poll':
            if (state == 'unknown') return json({'state': 'unknown'}, 404);
            return json({'state': state, if (state == 'approved') 'next': next, if (retryIn > 0) 'retry_in': retryIn});
          case 'finish':
            if (finishError == 'wrong_pin') return json({'error': 'wrong_pin'}, 401);
            if (finishError == 'locked') return json({'error': 'locked', 'retry_in': 900}, 429);
            if (finishError == 'bad_pin') return json({'error': 'bad_pin', 'message': 'Надто простий PIN'}, 400);
            return json({
              'session': {
                'access_token': 'at',
                'refresh_token': 'rt',
                'expires_in': 3600,
                'user': {
                  'id': '00000000-0000-0000-0000-000000000001',
                  'email': 'tg-501@tg.vulyk.invalid',
                  'user_metadata': {'full_name': 'Марія'},
                },
              },
              if (recovery != null) 'recovery_code': recovery,
            });
        }
        return json({'error': 'unknown_action'}, 400);
      });
}

TelegramAuthApi _api(_Fn fn) => TelegramAuthApi(Uri.parse('https://x.supabase.co/functions/v1/telegram-auth'), 'anon', client: fn.client);

void main() {
  group('клієнт', () {
    test('секрет довгий і щоразу інший; на сервер іде лише його відбиток', () async {
      final a = newLoginSecret(), b = newLoginSecret();
      expect(a.length, 43);
      expect(a, isNot(b));
      expect(newLoginSecret(Random(1)), newLoginSecret(Random(1)), reason: 'залежить лише від джерела випадковості');
      expect(loginSecretHash('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');

      final fn = _Fn();
      final r = await _api(fn).start(secret: a, device: 'Android');
      expect(r.match, 42);
      expect(r.url.host, 't.me');
      final sent = jsonEncode(fn.calls.single);
      expect(sent.contains(a), false, reason: 'секрет не залишає телефон');
      expect(fn.calls.single['secret_hash'], loginSecretHash(a));
      expect(fn.headers.single.containsKey('Authorization'), false, reason: 'без входу - без заголовка');
    });

    test('прив\'язка: токен входу іде заголовком', () async {
      final fn = _Fn();
      await _api(fn).start(secret: newLoginSecret(), device: 'Android', accessToken: 'tok');
      expect(fn.headers.single['Authorization'], 'Bearer tok');
    });

    test('опитування: стани, наступний крок, невідома заявка', () async {
      final fn = _Fn()..state = 'approved'..next = 'pin';
      final p = await _api(fn).poll('ID' * 11, newLoginSecret());
      expect(p.approved, true);
      expect(p.next, TelegramNext.pin);
      fn
        ..state = 'approved'
        ..next = 'locked'
        ..retryIn = 840;
      final l = await _api(fn).poll('ID' * 11, 'x' * 43);
      expect(l.next, TelegramNext.locked);
      expect(l.retryIn, 840);
      fn.state = 'unknown';
      expect((await _api(fn).poll('ID' * 11, 'x' * 43)).dead, true);
    });

    test('вхід: сесія, ім\'я й код відновлення', () async {
      final fn = _Fn();
      final r = await _api(fn).finish('ID' * 11, 'x' * 43, pin: 'k7-Quartz-91');
      expect(r.session.accessToken, 'at');
      expect(r.session.email, 'tg-501@tg.vulyk.invalid');
      expect(r.name, 'Марія');
      expect(r.recoveryCode, 'ABCDE-FGHJK-LMNPQ-RSTUV');
      expect(fn.calls.single['pin'], 'k7-Quartz-91');
      expect(fn.calls.single.containsKey('recovery'), false);
    });

    test('помилки сервера - зрозумілі коди', () async {
      final fn = _Fn()..finishError = 'locked';
      await expectLater(_api(fn).finish('i', 'x' * 43, pin: 'p'),
          throwsA(isA<TelegramApiError>().having((e) => e.retryIn, 'retryIn', 900).having((e) => e.code, 'code', 'locked')));
      fn.finishError = 'wrong_pin';
      await expectLater(_api(fn).finish('i', 'x' * 43, pin: 'p'), throwsA(isA<TelegramApiError>().having((e) => e.code, 'code', 'wrong_pin')));
      final offline = TelegramAuthApi(Uri.parse('https://x/f'), 'anon', client: MockClient((_) async => throw http.ClientException('no net')));
      await expectLater(offline.start(secret: 's' * 43, device: 'd'), throwsA(isA<TelegramApiError>().having((e) => e.offline, 'offline', true)));
    });

    test('технічна пошта Telegram', () {
      expect(isTelegramEmail('tg-501@tg.vulyk.invalid'), true);
      expect(isTelegramEmail('TG-5@TG.VULYK.INVALID'), true);
      expect(isTelegramEmail('olena@gmail.com'), false);
      expect(const AppUser(id: '1', email: 'tg-1@tg.vulyk.invalid', name: 'М').viaTelegram, true);
    });
  });

  group('екран входу', () {
    Future<TelegramLoginResult?> open(WidgetTester t, _Fn fn, {List<Uri>? opened}) async {
      TelegramLoginResult? result;
      var closed = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(c).push<TelegramLoginResult>(MaterialPageRoute(
                    builder: (_) => TelegramLoginScreen(
                      api: _api(fn),
                      pollEvery: const Duration(milliseconds: 100),
                      openUrl: (u) async {
                        opened?.add(u);
                        return true;
                      },
                    ),
                  ));
                  closed = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 10));
      expect(closed, false);
      return result;
    }

    tearDown(() => L10n.debugOverride(null));

    testWidgets('новий акаунт: число, Telegram, PIN двічі, код відновлення, готово', (t) async {
      final fn = _Fn();
      final opened = <Uri>[];
      await open(t, fn, opened: opened);

      expect(find.byKey(const Key('tg-match')), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      await t.tap(find.text(tr.tgOpenTelegram));
      await t.pump();
      expect(opened.single.host, 't.me');

      // підтвердили в Telegram
      fn.state = 'approved';
      await t.pump(const Duration(milliseconds: 150));
      await t.pump();
      expect(find.text(tr.pinSetupTitle), findsOneWidget);

      // різні PIN - помилка, і сервер ще не кликали
      await t.enterText(find.byType(TextField).at(0), 'k7-Quartz-91');
      await t.enterText(find.byType(TextField).at(1), 'k7-Quartz-92');
      await t.tap(find.text(tr.pinSave));
      await t.pump();
      expect(find.text(tr.pinMismatch), findsOneWidget);
      expect(fn.calls.where((c) => c['action'] == 'finish'), isEmpty);

      // сервер не прийняв простий PIN - його повідомлення видно
      fn.finishError = 'bad_pin';
      await t.enterText(find.byType(TextField).at(1), 'k7-Quartz-91');
      await t.tap(find.text(tr.pinSave));
      await t.pump();
      await t.pump();
      expect(find.text('Надто простий PIN'), findsOneWidget);

      fn.finishError = '';
      await t.tap(find.text(tr.pinSave));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('tg-recovery')), findsOneWidget);
      expect(find.text('ABCDE-FGHJK-LMNPQ-RSTUV'), findsOneWidget);
      // назад не можна, доки код не записано
      expect(find.byType(CircleAvatar), findsNothing);
      await t.tap(find.text(tr.recoveryWritten));
      await t.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('наявний акаунт: невірний PIN, потім правильний - без коду відновлення', (t) async {
      final fn = _Fn()
        ..state = 'approved'
        ..next = 'pin'
        ..recovery = null;
      await open(t, fn);
      await t.pump(const Duration(milliseconds: 150));
      await t.pump();
      expect(find.text(tr.pinEnterTitle), findsOneWidget);

      fn.finishError = 'wrong_pin';
      await t.enterText(find.byType(TextField).first, 'wrong-pin-1');
      await t.tap(find.text(tr.pinContinue));
      await t.pump();
      await t.pump();
      expect(find.text(tr.pinWrong), findsOneWidget);

      fn.finishError = '';
      await t.tap(find.text(tr.pinContinue));
      await t.pumpAndSettle();
      expect(find.text('go'), findsOneWidget, reason: 'вхід завершено, екран закрито');
    });

    testWidgets('блокування: видно, через скільки спробувати; PIN не питаємо', (t) async {
      final fn = _Fn()
        ..state = 'approved'
        ..next = 'locked'
        ..retryIn = 840;
      await open(t, fn);
      await t.pump(const Duration(milliseconds: 150));
      await t.pump();
      expect(find.text(tr.pinLocked('14:00')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('скасовано в Telegram: повідомлення й «Спробувати знову»', (t) async {
      final fn = _Fn();
      await open(t, fn);
      fn.state = 'cancelled';
      await t.pump(const Duration(milliseconds: 150));
      await t.pump();
      expect(find.text(tr.tgCancelled), findsOneWidget);
      fn.state = 'new';
      await t.tap(find.text(tr.tgTryAgain));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('tg-match')), findsOneWidget);
    });

    testWidgets('відновлення: код і новий PIN', (t) async {
      final fn = _Fn()
        ..state = 'approved'
        ..next = 'pin';
      await open(t, fn);
      await t.pump(const Duration(milliseconds: 150));
      await t.pump();
      await t.tap(find.text(tr.pinForgot));
      await t.pump();
      expect(find.text(tr.pinRecoveryTitle), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), 'abcde fghjk lmnpq rstuv');
      await t.enterText(find.byType(TextField).at(1), 'zz-New-Pin-55');
      await t.tap(find.text(tr.pinContinue));
      await t.pump();
      await t.pump();
      final fin = fn.calls.lastWhere((c) => c['action'] == 'finish');
      expect(fin['recovery'], 'abcde fghjk lmnpq rstuv');
      expect(fin['new_pin'], 'zz-New-Pin-55');
      expect(fin.containsKey('pin'), false);
      // новий код відновлення показано
      expect(find.byKey(const Key('tg-recovery')), findsOneWidget);
    });
  });
}
