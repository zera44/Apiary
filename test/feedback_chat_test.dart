import 'dart:convert';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/screens/feedback_chat_screen.dart';
import 'package:apiary/services/app_config.dart';
import 'package:apiary/services/feedback_chat.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Підставний сервер feedback: зберігає розмову, віддає повідомлення за
/// after_seq (як supabase/functions/feedback).
class FakeServer {
  final msgs = <Map<String, dynamic>>[]; // seq, from_dev, body, at
  final calls = <Map<String, dynamic>>[];
  bool down = false;
  String? secret;

  void devReply(String body) => msgs.add(
      {'seq': msgs.length + 1, 'from_dev': true, 'body': body, 'at': '2026-10-17T12:00:00Z'});

  http.Client get client => MockClient((req) async {
        if (down) throw http.ClientException('no network');
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        calls.add(b);
        secret ??= b['secret'] as String;
        if (b['secret'] != secret) return http.Response('{"error":"forbidden"}', 403);
        switch (b['action']) {
          case 'send':
            final m = {
              'seq': msgs.length + 1,
              'from_dev': false,
              'body': b['body'],
              'at': '2026-10-17T11:00:00Z'
            };
            msgs.add(m);
            return http.Response.bytes(utf8.encode(jsonEncode({'message': m})), 200);
          case 'poll':
            final after = (b['after_seq'] as num?)?.toInt() ?? 0;
            return http.Response.bytes(
                utf8.encode(jsonEncode({'messages': [for (final m in msgs) if (m['seq'] > after) m]})), 200);
        }
        return http.Response('{}', 400);
      });
}

void main() {
  late Repository repo;
  late FakeServer server;
  late FeedbackChat chat;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false));
    await repo.init();
    server = FakeServer();
    chat = FeedbackChat(repo,
        client: server.client, endpoint: Uri.parse('https://x.supabase.co/functions/v1/feedback'));
  });
  tearDown(() async => repo.db.close());

  test('адреса функції - з адреси Supabase у збірці; без сервера - немає', () {
    final c = AppConfig(supabaseUrl: 'https://x.supabase.co', supabaseAnonKey: 'k');
    expect(FeedbackChat.serverEndpoint(c).toString(), 'https://x.supabase.co/functions/v1/feedback');
    expect(FeedbackChat.serverEndpoint(const AppConfig()), isNull);
  });

  test('відгук: надіслано, у стрічці, ключ пристрою створено один раз', () async {
    expect(await chat.hasThread(), isFalse);
    expect(await chat.send('  Додайте темну тему  '), FeedbackSend.sent);
    final m = await chat.messages();
    expect(m.single.body, 'Додайте темну тему');
    expect(m.single.fromDev, isFalse);
    expect(m.single.pending, isFalse);
    expect(m.single.remoteSeq, 1);
    expect(await chat.hasThread(), isTrue);
    final id = await repo.getMeta(FeedbackChat.idKey);
    await chat.send('Ще');
    expect(await repo.getMeta(FeedbackChat.idKey), id);
    expect(server.calls.first['device_id'], id);
    expect(server.calls.first['secret'], (await repo.getMeta(FeedbackChat.secretKey)));
    // ключі - лише на цьому телефоні (не в резервну копію)
    expect(FeedbackChat.idKey, startsWith('device_'));
    expect(FeedbackChat.secretKey, startsWith('device_'));
  });

  test('відповідь розробника: опитування приносить її, значок, «прочитано»', () async {
    await chat.send('Питання');
    server.devReply('Дякую, зробимо');
    final fresh = await chat.poll();
    expect([for (final m in fresh) m.body], ['Дякую, зробимо']);
    expect(chat.unread.value, 1);
    final all = await chat.messages();
    expect([for (final m in all) [m.fromDev, m.body]], [
      [false, 'Питання'],
      [true, 'Дякую, зробимо'],
    ]);
    // повторне опитування - нічого нового, власне повідомлення не дублюється
    expect(await chat.poll(), isEmpty);
    expect((await chat.messages()).length, 2);
    await chat.markRead();
    expect(chat.unread.value, 0);
  });

  test('без інтернету: збережено, «чекає»; з\'явився зв\'язок - піде саме', () async {
    server.down = true;
    expect(await chat.send('Пишу в лісі'), FeedbackSend.queued);
    expect((await chat.messages()).single.pending, isTrue);
    expect(await chat.poll(), isEmpty); // зв'язку немає - нічого не губиться
    expect((await chat.messages()).single.pending, isTrue);
    server.down = false;
    server.devReply('Бачу ваш відгук');
    final fresh = await chat.poll();
    expect([for (final m in fresh) m.body], ['Бачу ваш відгук']);
    final all = await chat.messages();
    expect([for (final m in all) [m.fromDev, m.pending]], [
      [false, false], // дослано
      [true, false],
    ]);
    expect(server.msgs.where((m) => m['body'] == 'Пишу в лісі').length, 1); // рівно раз
  });

  test('людина, яка не писала, нічого не опитує', () async {
    expect(await chat.poll(), isEmpty);
    expect(server.calls, isEmpty);
  });

  testWidgets('екран: пишу - з\'являється; відповідь розробника - «Розробник»; значок скидається',
      (tester) async {
    await tester.runAsync(() async {
      await chat.send('Перший відгук');
      server.devReply('Відповідаю на перший');
      await chat.poll();
    });
    expect(chat.unread.value, 1);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: FeedbackChatScreen(chat: chat)));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Перший відгук'), findsOneWidget);
    expect(find.text('Відповідаю на перший'), findsOneWidget);
    expect(find.text('Розробник'), findsOneWidget);
    expect(chat.unread.value, 0); // відкрили - прочитано

    await tester.enterText(find.byKey(const ValueKey('feedback-input')), 'Дякую!');
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Дякую!'), findsOneWidget);
    expect(server.msgs.last['body'], 'Дякую!');
    // знімаємо таймер екрана
    await tester.pumpWidget(const SizedBox());
  });
}
