import 'dart:convert';

import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_queue.dart';
import 'package:apiary/assistant/assistant_store.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ModelTurn say(String t) => ModelTurn([
      {'type': 'text', 'text': t}
    ], 'end_turn');

ModelTurn use(String name, Map<String, dynamic> input) => ModelTurn([
      {'type': 'tool_use', 'id': 't-$name', 'name': name, 'input': input}
    ], 'tool_use');

/// Модель зі сценарієм, що вміє й шукати в книгах.
class BookModel implements AssistantModel, BookSearch {
  final List<ModelTurn> script;
  BookModel(this.script);
  final sent = <List<Map<String, dynamic>>>[];
  final queries = <String>[];
  Map<String, dynamic> answer = {
    'books': true,
    'results': [
      {
        'book': 'Посібник пасічника',
        'author': 'Іваненко',
        'year': 2019,
        'chapter': 'Підгодівля',
        'page': 12,
        'text': 'Восени бджолам дають цукровий сироп два до одного.',
      }
    ],
  };
  @override
  bool get isRemote => true;
  @override
  Future<ModelTurn> send(List<Map<String, dynamic>> messages) async {
    sent.add(jsonDecode(jsonEncode(messages)).cast<Map<String, dynamic>>());
    return script.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> searchBooks(String query, {int limit = 5}) async {
    queries.add('$query|$limit');
    return answer;
  }
}

void main() {
  late Repository repo;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath,
        singleInstance: false));
    await repo.init();
  });
  tearDown(() async => repo.db.close());

  AssistantTools tools({Future<Map<String, dynamic>> Function(String, int)? search}) =>
      AssistantTools(repo, confirm: (_) async => null, searchBooks: search);

  test('search_books: уривки з книги, джерело й сторінка', () async {
    final asked = <String>[];
    final t = tools(search: (q, n) async {
      asked.add('$q|$n');
      return {
        'books': true,
        'results': [
          {'book': 'Посібник', 'page': 12, 'text': 'Сироп.'}
        ]
      };
    });
    final r = await t.run('search_books', {'query': 'підгодівля сироп восени', 'limit': 50});
    expect(r.isError, isFalse);
    final j = jsonDecode(r.content) as Map<String, dynamic>;
    expect((j['results'] as List).single['page'], 12);
    expect(asked, ['підгодівля сироп восени|8']); // не більше 8
  });

  test('search_books: книг немає / нічого не знайдено / немає пошуку - примітка, не поради', () async {
    final none = jsonDecode((await tools(search: (_, _) async => {'books': false, 'results': []})
            .run('search_books', {'query': 'рій'}))
        .content) as Map;
    expect(none['results'], isEmpty);
    expect(none['note'], contains('Книг у базі ще немає'));

    final empty = jsonDecode((await tools(search: (_, _) async => {'books': true, 'results': []})
            .run('search_books', {'query': 'рій'}))
        .content) as Map;
    expect(empty['note'], contains('нічого не знайдено'));

    final noSearch =
        jsonDecode((await tools().run('search_books', {'query': 'рій'})).content) as Map;
    expect(noSearch['note'], contains('Книг у базі ще немає'));

    final bad = await tools().run('search_books', {'query': '  '});
    expect(bad.isError, isTrue);
  });

  test('search_books є серед інструментів читання', () {
    expect(AssistantTools.readTools, contains('search_books'));
  });

  test('цикл: модель шукає в книгах, отримує уривки й відповідає з джерелом', () async {
    final model = BookModel([
      use('search_books', {'query': 'підгодівля восени'}),
      say('Восени дають сироп 2:1 («Посібник пасічника», с. 12).'),
    ]);
    final store = AssistantStore(repo.db);
    final q = AssistantQueue(repo, store, model,
        isOnline: () async => true, onlineChanges: const Stream.empty());
    await store.load();
    await q.submit('Чим підгодовувати восени?');
    expect(model.queries, ['підгодівля восени|5']);
    final result = (model.sent[1].last['content'] as List).single as Map;
    expect(result['content'] as String, contains('Посібник пасічника'));
    expect(result['content'] as String, contains('12'));
    final items = await store.items();
    expect(items.last.text, contains('с. 12'));
  });

  group('RemoteAssistantModel.searchBooks', () {
    RemoteAssistantModel remote(http.Client c) =>
        RemoteAssistantModel(Uri.parse('https://x/functions/v1/assistant'), 'code', client: c);

    test('POST {action: search_books} з кодом доступу; відповідь розбирається', () async {
      late http.Request seen;
      final m = remote(MockClient((r) async {
        seen = r;
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'books': true,
              'results': [
                {'book': 'Книга', 'text': 'Текст'}
              ]
            })),
            200);
      }));
      final r = await m.searchBooks('вощина', limit: 3);
      expect(seen.headers[RemoteAssistantModel.tokenHeader], 'code');
      expect(jsonDecode(seen.body), {'action': 'search_books', 'query': 'вощина', 'limit': 3});
      expect((r['results'] as List).length, 1);
    });

    test('помилки: 401 - не пустили, 503 - зайнято, мережі немає - offline', () async {
      Future<AssistantFailure> kind(MockClient c) async {
        try {
          await remote(c).searchBooks('x');
        } on AssistantException catch (e) {
          return e.kind;
        }
        fail('мало впасти');
      }

      expect(await kind(MockClient((_) async => http.Response('{}', 401))), AssistantFailure.unauthorized);
      expect(await kind(MockClient((_) async => http.Response('{}', 503))), AssistantFailure.busy);
      expect(await kind(MockClient((_) async => http.Response('{}', 500))), AssistantFailure.server);
      expect(await kind(MockClient((_) async => throw http.ClientException('offline'))),
          AssistantFailure.offline);
    });
  });
}
