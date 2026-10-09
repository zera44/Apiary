import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/notes.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/ui/hive_notes.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Repository repo;
  late String apiaryId;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
    apiaryId = await repo.addApiary('Пасіка');
  });

  tearDown(() async => repo.db.close());

  test('нотатки: найновіші зверху, заднім числом, фільтр за міткою', () async {
    final hive = EntityRef.element(await repo.addElement(apiaryId, 0, 0));
    final other = EntityRef.element(await repo.addElement(apiaryId, 1, 0));
    final mood = await repo.addNoteLabel('Настрій');
    await repo.addHiveNote(hive, 'Спокійні', labelId: mood);
    await repo.addHiveNote(hive, 'Давнє', date: DateTime(2024, 5, 1));
    await repo.addHiveNote(other, 'Чужа');
    final notes = await repo.listHiveNotes(hive);
    expect(notes.map((n) => n.text), ['Спокійні', 'Давнє']);
    expect(notes.last.day.year, 2024);
    expect((await repo.listHiveNotes(hive, labelId: mood)).single.text, 'Спокійні');
    expect(await repo.countHiveNotes(hive), 2);
    expect(await repo.countHiveNotes(other), 1);
    expect(() => repo.addHiveNote(hive, '   '), throwsArgumentError);
  });

  test('зміна й видалення нотатки', () async {
    final hive = EntityRef.element(await repo.addElement(apiaryId, 0, 0));
    final id = await repo.addHiveNote(hive, 'Перше');
    final l = await repo.addNoteLabel('Хвороби');
    await repo.updateHiveNote(id, text: 'Друге', date: DateTime(2025, 1, 2), labelId: l);
    final n = (await repo.listHiveNotes(hive)).single;
    expect((n.text, n.labelId, n.day.day), ('Друге', l, 2));
    await repo.deleteHiveNote(id);
    expect(await repo.listHiveNotes(hive), isEmpty);
  });

  test('мітки: без дублів за назвою; видалення лишає нотатки без мітки', () async {
    final hive = EntityRef.element(await repo.addElement(apiaryId, 0, 0));
    final a = await repo.addNoteLabel('Матка');
    expect(await repo.addNoteLabel(' матка '), a);
    await repo.addHiveNote(hive, 'Сіє', labelId: a);
    await repo.renameNoteLabel(a, 'Матка й черва');
    expect((await repo.listNoteLabels()).single.name, 'Матка й черва');
    await repo.deleteNoteLabel(a);
    expect(await repo.listNoteLabels(), isEmpty);
    expect((await repo.listHiveNotes(hive)).single.labelId, isNull);
  });

  test('нотатка з огляду отримує мітку «Огляд», порожня - не пишеться', () async {
    final hive = EntityRef.element(await repo.addElement(apiaryId, 0, 0));
    expect(await repo.addInspectionNote(hive, '  '), isNull);
    await repo.addInspectionNote(hive, 'Мало корму');
    await repo.addInspectionNote(hive, 'Додав рамку');
    final labels = await repo.listNoteLabels();
    expect(labels.single.name, kInspectionNoteLabel);
    expect((await repo.listHiveNotes(hive, labelId: labels.single.id)).length, 2);
  });

  test('нотатки групи копіюються кожному вулику при поділі старої групи', () async {
    final gid = await repo.addGroup(apiaryId, {'0,0': 'hive', '2,0': 'hive'}, 0, 0, groupLabel: 'Л');
    await repo.addHiveNote(EntityRef.group(gid), 'Спільна');
    await repo.splitMultiObjectGroups();
    final hives = (await repo.listElements(apiaryId)).where((e) => e.isHive).toList();
    expect(hives.map((e) => e.groupId).toSet().length, 2);
    for (final h in hives) {
      expect((await repo.listHiveNotes(h.entity)).single.text, 'Спільна');
    }
  });

  test('видалений вулик: нотатки лишаються в базі', () async {
    final el = await repo.addElement(apiaryId, 0, 0);
    await repo.addHiveNote(EntityRef.element(el), 'Пам\'ять');
    await repo.updateElement(el, {'deleted': 1});
    expect((await repo.listHiveNotes(EntityRef.element(el))).single.text, 'Пам\'ять');
  });

  testWidgets('вкладка нотаток: додати через вікно', (tester) async {
    late EntityRef hive;
    await tester.runAsync(() async {
      hive = EntityRef.element(await repo.addElement(apiaryId, 0, 0));
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(width: 240, child: HiveNotesView(repo: repo, entity: hive)),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.textContaining('Нотаток ще немає'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-text')), 'Злі бджоли');
    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Злі бджоли'), findsOneWidget);
    expect(find.text('Сьогодні'), findsOneWidget);
  });
}
