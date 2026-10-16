import 'dart:convert';
import 'dart:io';

import 'package:apiary/assistant/assistant_model.dart';
import 'package:apiary/assistant/assistant_session.dart';
import 'package:apiary/assistant/assistant_tools.dart';
import 'package:apiary/data/database.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/notes.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/user_reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final today = DateTime(2026, 5, 10, 12);

void main() {
  late Repository repo;
  late String apiary, apiary2, hive5, hive7, force;
  late List<PendingWrite> cards;
  late List<NavTarget> opened;
  Map<String, String>? Function(PendingWrite) answer = (w) => {for (final f in w.fields) f.key: f.value};

  AssistantTools tools({bool canNavigate = true}) => AssistantTools(
        repo,
        now: () => today,
        navigate: canNavigate
            ? (t) async {
                opened.add(t);
                return true;
              }
            : null,
        confirm: (w) async {
          cards.add(w);
          return answer(w);
        },
      );

  Future<Map<String, dynamic>> ok(AssistantTools t, String name, [Map<String, dynamic> input = const {}]) async {
    final r = await t.run(name, input);
    expect(r.isError, isFalse, reason: r.content);
    return jsonDecode(r.content) as Map<String, dynamic>;
  }

  Future<String> bad(AssistantTools t, String name, [Map<String, dynamic> input = const {}]) async {
    final r = await t.run(name, input);
    expect(r.isError, isTrue, reason: r.content);
    return r.content;
  }

  setUpAll(sqfliteFfiInit);
  tearDown(() => repo.db.close());

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
    cards = [];
    opened = [];
    answer = (w) => {for (final f in w.fields) f.key: f.value};
    apiary = await repo.addApiary('Біля хати');
    apiary2 = await repo.addApiary('Лісова');
    hive5 = await repo.addElement(apiary, 0, 0, label: 'Вулик 5');
    hive7 = await repo.addElement(apiary, 1, 0, label: 'Вулик 7');
    await repo.addElement(apiary2, 0, 0, label: 'Вулик 1');
    await repo.addElement(apiary, 3, 3, type: 'obstacle');
    force = await repo.addParameter('Сила', unit: 'вуличок', dataType: DataTypes.int_);
    for (final h in [hive5, hive7]) {
      await repo.setAttachedParameters([force], EntityRef.element(h));
    }
    final period = (await repo.baseParameterId('hive', 'visit_period'))!;
    for (final h in [hive5, hive7]) {
      await repo.addParameterRecord(period, '7', EntityRef.element(h));
    }
    await repo.markVisited(EntityRef.element(hive5), when: DateTime(2026, 5, 1)); // прострочено
    await repo.markVisited(EntityRef.element(hive7), when: DateTime(2026, 5, 8)); // за 5 днів
  });

  group('без підтвердження', () {
    test('apiaries_list - пасіки з кількістю вуликів (без перешкод)', () async {
      final r = await ok(tools(), 'apiaries_list');
      final list = r['apiaries'] as List;
      expect([for (final a in list) '${a['name']}:${a['hives']}'],
          containsAll(['Біля хати:2', 'Лісова:1']));
    });

    test('find_hives - за пасікою, терміном огляду і назвою', () async {
      final t = tools();
      expect((await ok(t, 'find_hives', {'apiary': 'Біля'}))['count'], 2);
      final due = await ok(t, 'find_hives', {'due': 'overdue'});
      expect([for (final h in due['hives']) h['name']], ['Вулик 5']);
      expect(due['hives'][0]['days_to_visit'], 0);
      expect(due['hives'][0]['id'], 'e:$hive5');
      final week = await ok(t, 'find_hives', {'due': 'week', 'apiary': apiary});
      expect([for (final h in week['hives']) h['name']], ['Вулик 5', 'Вулик 7']);
      expect((await ok(t, 'find_hives', {'name': '7'}))['count'], 1);
    });

    test('find_hives - за значенням параметра', () async {
      await repo.addParameterRecord(force, '9', EntityRef.element(hive7));
      final r = await ok(tools(), 'find_hives', {'parameter': 'сила'});
      expect(r['count'], 1);
      expect(r['hives'][0]['Сила'], '9');
      expect((await ok(tools(), 'find_hives', {'parameter': 'Сила', 'value': '5'}))['count'], 0);
    });

    test('група вуликів (лежак) - один вулик і в apiaries_list, і в find_hives', () async {
      await repo.addElement(apiary, 5, 5, label: 'Лежак 1', groupId: 'lezhak');
      await repo.addElement(apiary, 6, 5, label: 'Лежак 1', groupId: 'lezhak');
      final list = await ok(tools(), 'apiaries_list');
      final mine = (list['apiaries'] as List).firstWhere((a) => a['id'] == apiary);
      final found = await ok(tools(), 'find_hives', {'apiary': apiary});
      expect(mine['hives'], 3);
      expect(found['count'], mine['hives']);
    });

    test('find_hives - з QR-кодом і без', () async {
      await repo.linkQr('https://vulyk.app/h/1', EntityRef.element(hive5));
      final withQr = await ok(tools(), 'find_hives', {'has_qr': true});
      expect([for (final h in withQr['hives']) h['name']], ['Вулик 5']);
      final without = await ok(tools(), 'find_hives', {'has_qr': false, 'apiary': apiary});
      expect([for (final h in without['hives']) h['name']], ['Вулик 7']);
    });

    test('find_hives - невідома пасіка чи неправильний due - помилка для моделі', () async {
      expect(await bad(tools(), 'find_hives', {'apiary': 'Степова'}), contains('Біля хати'));
      await bad(tools(), 'find_hives', {'due': 'soon'});
    });

    test('hive_history - значення й нотатки за період, вулик за назвою', () async {
      await repo.addParameterRecord(force, '8', EntityRef.element(hive5));
      await repo.addHiveNote(EntityRef.element(hive5), 'Бачив матку');
      final r = await ok(tools(), 'hive_history', {'hive_id': '5'});
      expect(r['hive']['name'], 'Вулик 5');
      expect([for (final x in r['records']) x['parameter']], contains('Сила'));
      expect([for (final x in r['records']) x['value']], contains('8 вуличок'));
      expect(r['notes'][0]['text'], 'Бачив матку');
      // назва є в кількох пасіках - просить уточнити; немає - помилка
      await repo.addElement(apiary2, 1, 1, label: 'Вулик 5');
      expect(await bad(tools(), 'hive_history', {'hive_id': '5'}), contains('кількох'));
      expect(await bad(tools(), 'hive_history', {'hive_id': '99'}), contains('не знайдено'));
    });

    test('stock_list - залишки, пошук, low', () async {
      final sugar = await repo.addStockItem('Цукор', 'кг');
      await repo.receiveStock(sugar, 20, total: 900);
      await repo.addStockItem('Вощина', 'аркуш');
      await repo.updateStockItem(sugar, minQuantity: (50,));
      final all = await ok(tools(), 'stock_list');
      expect((all['items'] as List).length, 2);
      final s = await ok(tools(), 'stock_list', {'query': 'цук'});
      expect(s['items'], [
        {'name': 'Цукор', 'quantity': '20', 'unit': 'кг', 'low': true}
      ]);
    });

    test('finance_summary - з початку місяця, за категоріями', () async {
      final cats = await repo.listFinCategories(kind: kFinExpense);
      await repo.addFinOp(kind: kFinExpense, categoryId: cats.first.id, amount: 300, date: DateTime(2026, 5, 3));
      await repo.addFinOp(kind: kFinIncome, categoryId: null, amount: 1000, date: DateTime(2026, 5, 4));
      await repo.addFinOp(kind: kFinExpense, categoryId: null, amount: 50, date: DateTime(2026, 4, 30));
      final r = await ok(tools(), 'finance_summary');
      expect(r['income'], '1000');
      expect(r['expense'], '300');
      expect(r['balance'], '700');
      expect(r['expense_by_category'], {cats.first.name: '300'});
      expect((await ok(tools(), 'finance_summary', {'from': '2026-04-01'}))['expense'], '350');
      await bad(tools(), 'finance_summary', {'from': 'вчора'});
    });

    test('open_screen - відкриває вулик на його пасіці', () async {
      final r = await ok(tools(), 'open_screen', {'screen': 'hive', 'id': 'e:$hive7'});
      expect(r['status'], 'відкрито');
      expect(opened.single.apiaryId, apiary);
      expect(opened.single.elementId, hive7);
    });

    test('open_screen - карта: за назвою пасіки; кілька пасік без id - просить уточнити', () async {
      await ok(tools(), 'open_screen', {'screen': 'map', 'id': 'Лісова'});
      expect(opened.single.apiaryId, apiary2);
      expect(await bad(tools(), 'open_screen', {'screen': 'map'}), contains('кілька'));
      await ok(tools(), 'open_screen', {'screen': 'stock'});
      expect(opened.last.screen, 'stock');
      expect(await bad(tools(), 'open_screen', {'screen': 'garage'}), contains('Немає екрана'));
    });

    test('open_screen для відповіді з черги - не відкриває, а пропонує', () async {
      final t = tools(canNavigate: false);
      final r = await ok(t, 'open_screen', {'screen': 'stock'});
      expect(r['status'], 'запропоновано');
      expect(opened, isEmpty);
      expect(t.offeredNav.single.screen, 'stock');
    });
  });

  group('з підтвердженням', () {
    test('record_inspection: картка з усіма полями, «Так» - записано, «Скасувати» - як було', () async {
      final t = tools();
      final r = await ok(t, 'record_inspection', {
        'hive_id': 'e:$hive5',
        'values': {'сила': '9'},
        'note': 'Спокійні',
      });
      expect(r['status'], 'підтверджено');
      final card = cards.single;
      expect(card.title, contains('Вулик 5'));
      expect([for (final f in card.fields) f.label], ['Сила (вуличок)', 'Нотатка', 'Дата обходу']);
      final e = EntityRef.element(hive5);
      final visit = (await repo.baseParameterId('hive', 'visit_start'))!;
      expect((await repo.latestParameterValues(e))[force], '9');
      expect((await repo.latestParameterValues(e))[visit], '10.05.2026');
      expect((await repo.listHiveNotes(e)).single.text, 'Спокійні');

      await t.undoable.single.undo();
      final after = await repo.latestParameterValues(e);
      expect(after[force], isNull);
      expect(after[visit], '01.05.2026');
      expect(await repo.listHiveNotes(e), isEmpty);
    });

    test('record_inspection: «внеси синю матку» - Мітка матки = Синій', () async {
      final t = tools();
      for (final (said, stored) in [('синю', 'Синій'), ('Жовта', 'Жовтий'), ('без кольору', 'Без кольору')]) {
        final r = await ok(t, 'record_inspection', {
          'hive_id': '5',
          'values': {'мітка матки': said},
          'mark_visited': false,
        });
        expect(r['status'], 'підтверджено');
        final mark = (await repo.baseParameterId('hive', 'queen_mark'))!;
        expect((await repo.latestParameterValues(EntityRef.element(hive5)))[mark], stored);
      }
      expect(await bad(t, 'record_inspection', {'hive_id': '5', 'values': {'мітка матки': 'фіолетова'}}),
          contains('Синій'));
    });

    test('record_inspection: «Ні» - нічого не змінюється', () async {
      answer = (_) => null;
      final before = await repo.db.query('parameter_records');
      final r = await ok(tools(), 'record_inspection', {'hive_id': 'e:$hive5', 'values': {'Сила': '9'}});
      expect(r, {'status': 'відхилено'});
      expect((await repo.db.query('parameter_records')).length, before.length);
    });

    test('record_inspection: виправлене в картці значення - записується воно', () async {
      answer = (w) => {for (final f in w.fields) f.key: f.key.startsWith('p:') ? '11' : f.value};
      await ok(tools(), 'record_inspection', {'hive_id': '5', 'values': {'Сила': '9'}});
      expect((await repo.latestParameterValues(EntityRef.element(hive5)))[force], '11');
    });

    test('record_inspection: неправильне значення чи параметр - помилка, картки немає', () async {
      expect(await bad(tools(), 'record_inspection', {'hive_id': '5', 'values': {'Сила': 'багато'}}),
          contains('ціле число'));
      expect(await bad(tools(), 'record_inspection', {'hive_id': '5', 'values': {'Мед': '3'}}),
          contains('Сила'));
      expect(cards, isEmpty);
    });

    test('record_inspection: уже надіслане на сервер «Скасувати» повертає попереднє значення', () async {
      final e = EntityRef.element(hive5);
      await repo.addParameterRecord(force, '6', e);
      final t = tools();
      await ok(t, 'record_inspection', {'hive_id': '5', 'values': {'Сила': '9'}, 'mark_visited': false});
      await repo.db.update('parameter_records', {'synced': 1});
      await t.undoable.single.undo();
      expect((await repo.latestParameterValues(e))[force], '6');
    });

    test('stock_receive / stock_issue: залишок, «Скасувати», не більше залишку', () async {
      final sugar = await repo.addStockItem('Цукор', 'кг');
      final t = tools();
      final r = await ok(t, 'stock_receive', {'item': 'цукор', 'amount': 25, 'total': 1100});
      expect(r['quantity_now'], '25');
      expect([for (final f in cards.single.fields) f.label], ['Кількість (кг)', 'Сума, грн']);
      final i = await ok(t, 'stock_issue', {'item': 'Цукор', 'amount': 5});
      expect(i['quantity_now'], '20');
      expect(await bad(t, 'stock_issue', {'item': 'Цукор', 'amount': 100}), contains('лише 20'));
      await t.undoable.last.undo();
      expect((await repo.getStockItem(sugar))!.quantity, 25);
    });

    test('add_finance_entry: категорія за назвою, «Ні» і «Скасувати»', () async {
      final t = tools();
      final r = await ok(t, 'add_finance_entry', {'kind': 'income', 'amount': 2400, 'category': 'продаж'});
      expect(r['status'], 'підтверджено');
      Future<FinSummary> sum() async =>
          FinSummary.of(await repo.listFinEntries(from: DateTime(2026, 5), to: DateTime(2026, 6)));
      expect((await sum()).income, 2400);
      await t.undoable.single.undo();
      expect((await sum()).income, 0);

      answer = (_) => null;
      expect((await ok(t, 'add_finance_entry', {'kind': 'expense', 'amount': 10}))['status'], 'відхилено');
      expect((await sum()).expense, 0);
      // нова категорія з «Ні» - не створюється
      expect((await ok(t, 'add_finance_entry', {'kind': 'income', 'amount': 5, 'category': 'Бензин'}))['status'],
          'відхилено');
      expect([for (final c in await repo.listFinCategories()) c.name], isNot(contains('Бензин')));
    });

    test('add_finance_entry: категорії немає - створюється (видно в картці); «Скасувати» прибирає й її',
        () async {
      final t = tools();
      final r = await ok(t, 'add_finance_entry', {'kind': 'expense', 'amount': 100, 'category': 'Вощина'});
      expect(r['new_category'], isTrue);
      final f = cards.last.fields.firstWhere((f) => f.key == 'category');
      expect(f.label, 'Нова категорія');
      expect(f.value, 'Вощина');
      expect([for (final c in await repo.listFinCategories(kind: kFinExpense)) c.name], contains('Вощина'));
      await t.undoable.last.undo();
      expect([for (final c in await repo.listFinCategories(kind: kFinExpense)) c.name],
          isNot(contains('Вощина')));
    });

    test('stock_receive: нової позиції немає - створюється з одиницею; списати чого немає - ні', () async {
      final t = tools();
      final r = await ok(t, 'stock_receive', {'item': 'Вощина', 'amount': 20, 'unit': 'аркуш', 'total': 600});
      expect(r['created'], isTrue);
      expect(cards.last.title, contains('нова позиція'));
      final item = (await repo.listStockItems()).singleWhere((i) => i.name == 'Вощина');
      expect(item.unit, 'аркуш');
      expect(item.quantity, 20);
      expect(await bad(t, 'stock_issue', {'item': 'Мед', 'amount': 1}), contains('немає'));
      await t.undoable.last.undo();
      expect([for (final i in await repo.listStockItems()) i.name], isNot(contains('Вощина')));
    });

    test('create_reminder: у майбутньому, з вулика; «Скасувати» - видалено', () async {
      final t = tools();
      final r = await ok(t, 'create_reminder', {'text': 'Підгодувати', 'date': '2026-05-15', 'hive_id': '7'});
      expect(r['when'], '15.05.2026 09:00');
      final list = await repo.listUserReminders();
      expect(list.single.text, 'Підгодувати');
      expect(list.single.hive, EntityRef.element(hive7));
      await t.undoable.single.undo();
      expect(await repo.listUserReminders(), isEmpty);
      expect(await bad(t, 'create_reminder', {'text': 'x', 'date': '2026-05-01'}), contains('минув'));
    });
  });

  test('цикл: модель викликає інструмент, людина підтверджує, модель отримує «підтверджено»', () async {
    final model = DemoAssistantModel([
      const ModelTurn([
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'record_inspection',
          'input': {'hive_id': '5', 'values': {'Сила': '9'}},
        }
      ], 'tool_use'),
      const ModelTurn([
        {'type': 'text', 'text': 'Записав огляд вулика 5.'}
      ], 'end_turn'),
    ]);
    final t = tools();
    final reply = await AssistantSession(model).ask('Запиши силу 9 у п\'ятий', tools: t.run, today: today);
    expect(reply.text, 'Записав огляд вулика 5.');
    final first = model.sent.first.first['content'] as String;
    expect(first, endsWith('[Сьогодні: 2026-05-10, неділя]'));
    final result = (model.sent[1].last['content'] as List).single as Map;
    expect(jsonDecode(result['content'] as String)['status'], 'підтверджено');
  });

  test('назви інструментів збігаються з описом для моделі (tools.ts)', () async {
    final ts = await File('supabase/functions/assistant/tools.ts').readAsString();
    final names = RegExp(r"name: '([a-z_]+)'").allMatches(ts).map((m) => m[1]).toSet();
    expect(names, {...AssistantTools.readTools, ...AssistantTools.writeTools});
    final prompt = await File('supabase/functions/assistant/prompt.ts').readAsString();
    final screens = RegExp(r"'([a-z_]+)'")
        .allMatches(prompt.split('SCREENS = [')[1].split(']')[0])
        .map((m) => m[1])
        .toList();
    expect(screens, kAssistantScreens);
  });
}
