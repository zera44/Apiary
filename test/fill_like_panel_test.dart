import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/whats_new_screen.dart';
import 'package:apiary/ui/first_hints.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Вікно «Оглянути» - як панель вулика: ті самі розділи («Обхід»), ті самі
/// назви, QR-код, «Кількість днів до обходу» лише для перегляду.
void main() {
  late Repository repo;
  late Apiary apiary;
  late MapElement hive;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    await AppIcons.load();
    Hints.enabled = false;
    WhatsNewScreen.enabled = false;
  });

  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    await repo.prepareLikeFreshInstall();
    final id = await repo.addApiary('Пасіка');
    final h = await repo.addElement(id, 0, 0, label: 'Вулик 1');
    // група «Обхід», як у користувача (її створює урок / «Конструктор»)
    final left = (await repo.baseParameterId('hive', 'visit_left'))!;
    final start = (await repo.baseParameterId('hive', 'visit_start'))!;
    await repo.setParamGroups([ParamGroup(id: 'g1', name: 'Обхід', ids: [left, start])]);
    apiary = (await repo.getApiary(id))!;
    hive = (await repo.getElement(h))!;
  });
  tearDown(() async => repo.db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('огляд: розділ «Обхід», QR-код і «Кількість днів до обходу» - як на панелі', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: MapScreen(repo: repo, apiary: apiary, focusElementId: hive.id, openFill: true),
    ));
    await settle(tester);
    expect(find.text('QR-код'), findsWidgets);
    expect(find.text('Обхід'), findsWidgets);
    expect(find.textContaining('Кількість днів до обходу'), findsWidgets);
    expect(find.text('Заповнити параметри'), findsOneWidget); // це вікно огляду
    expect(find.text('Мітка матки'), findsWidgets);
  });
}
