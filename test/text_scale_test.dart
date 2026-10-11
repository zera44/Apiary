import 'dart:io';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/finance.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/notes.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/backups_screen.dart';
import 'package:apiary/screens/fin_add_screen.dart';
import 'package:apiary/screens/finance_screen.dart';
import 'package:apiary/screens/history_hub_screen.dart';
import 'package:apiary/screens/home_screen.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/parameters_screen.dart';
import 'package:apiary/screens/settings_screen.dart';
import 'package:apiary/screens/splash_screen.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:apiary/screens/templates_screen.dart';
import 'package:apiary/screens/whats_new_screen.dart';
import 'package:apiary/services/server.dart';
import 'package:apiary/ui/first_hints.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/text_scale.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'widget_test.dart' show FakeAuth;

/// «Розмір шрифту» в Налаштуваннях і те, що головні екрани не ламаються
/// на найбільшому розмірі на вузькому телефоні.
void main() {
  late Repository repo;
  late String apiaryId;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    await AppIcons.load();
    Hints.enabled = false;
    WhatsNewScreen.enabled = false;
    HomeScreen.mapBackdrop = false;
    await _loadRealFonts();
  });

  setUp(() async {
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    await repo.prepareLikeFreshInstall();
    apiaryId = await repo.addApiary('Пасіка біля лісу');
    final cells = {for (var i = 0; i < 6; i++) '$i,0': 'hive'};
    final g = await repo.addGroup(apiaryId, cells, 0, 0, groupLabel: 'Лежак');
    final weight = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.float_);
    await repo.addParameterRecord(weight, '44.3', EntityRef.group(g));
    await repo.addHiveNote(EntityRef.group(g), 'Матка сіє добре, розплід суцільний');
    final sugar = await repo.addStockItem('Цукор', 'кг');
    await repo.receiveStock(sugar, 50, total: 1500);
    await repo.addStockItem('Мед соняшниковий', 'кг');
    await repo.addFinOp(kind: kFinIncome, categoryId: null, amount: 12000, date: DateTime.now());
  });

  tearDown(() async {
    AppTextScale.value.value = AppTextScale.levels.first;
    Server.debugAuth = null;
    await repo.db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app(Widget home) =>
      MaterialApp(theme: buildAppTheme(), builder: (_, child) => AppTextScale.apply(child!), home: home);

  testWidgets('рівень обирається в Налаштуваннях, діє одразу й зберігається', (tester) async {
    // Налаштування відкрито поверх головного: зміна рівня їх не закриває
    await tester.pumpWidget(app(const Scaffold(body: Text('головний'))));
    Navigator.of(
      tester.element(find.text('головний')),
    ).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(repo: repo)));
    await settle(tester);
    expect(find.text(tr.textSizeSection), findsOneWidget);
    expect(find.text(tr.textSizeLevels.first), findsOneWidget); // типово - звичайний
    double scaleOf(Finder f) => MediaQuery.textScalerOf(tester.element(f)).scale(10);
    expect(scaleOf(find.text(tr.textSizePreview)), 10);

    await tester.tap(find.byKey(const ValueKey('text-size-3')));
    await settle(tester);
    expect(AppTextScale.value.value, 1.5);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text(tr.textSizeLevels.last), findsOneWidget);
    expect(scaleOf(find.text(tr.textSizePreview)), closeTo(15, 0.001));
    expect(await tester.runAsync(() => repo.getMeta(AppTextScale.key)), '1.5');

    // перезапуск: збережений рівень повертається; сміття - звичайний
    AppTextScale.value.value = 1.0;
    await tester.runAsync(() => AppTextScale.load(repo));
    expect(AppTextScale.value.value, 1.5);
    await tester.runAsync(() => repo.setMeta(AppTextScale.key, '7'));
    await tester.runAsync(() => AppTextScale.load(repo));
    expect(AppTextScale.value.value, 1.0);
  });

  // дисплеї: вузький телефон з найбільшим шрифтом, найменший телефон,
  // планшет вертикально й горизонтально
  const displays = {
    'телефон 360 dp, найбільший шрифт': (Size(360, 640), 1.5),
    'телефон 320 dp': (Size(320, 568), 1.0),
    'планшет вертикально, найбільший шрифт': (Size(800, 1280), 1.5),
    'планшет горизонтально': (Size(1280, 800), 1.0),
  };
  for (final d in displays.entries) {
    testWidgets('${d.key}: екрани без переповнень', (tester) async {
      final (size, scale) = d.value;
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      AppTextScale.value.value = scale;
      Server.debugAuth = FakeAuth(signedIn: true);
      final apiary = (await tester.runAsync(() => repo.getApiary(apiaryId)))!;
      final auth = FakeAuth(signedIn: true);

      final hive = (await tester.runAsync(() => repo.listElements(apiaryId)))!.firstWhere((e) => e.isHive);
      final screens = <String, Widget>{
        'вхід': SplashScreen(repo: repo, auth: FakeAuth()),
        'головний': HomeScreen(repo: repo, auth: auth),
        'карта': MapScreen(repo: repo, apiary: apiary),
        'панель вулика': MapScreen(repo: repo, apiary: apiary, focusElementId: hive.id),
        'огляд': MapScreen(repo: repo, apiary: apiary, focusElementId: hive.id, openFill: true),
        'характеристики': ParametersScreen.catalog(repo: repo),
        'нова витрата': FinAddScreen(repo: repo, kind: kFinExpense),
        'шаблони': TemplatesScreen(repo: repo),
        'склад': StockScreen(repo: repo),
        'фінанси': FinanceScreen(repo: repo),
        'історія': HistoryHubScreen(repo: repo),
        'налаштування': SettingsScreen(repo: repo),
        'копії': BackupsScreen(repo: repo),
      };
      final problems = <String>[];
      for (final e in screens.entries) {
        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('overflowed')) {
            errors.add(s.split('\n').first);
          } else if (!s.contains('MissingPluginException')) {
            old?.call(d);
          }
        };
        try {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(app(e.value));
          await settle(tester);
        } finally {
          FlutterError.onError = old;
        }
        if (errors.isNotEmpty) problems.add('${e.key}: ${errors.toSet().join('; ')}');
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  testWidgets('планшет: списки й форми - по центру, не на всю ширину', (tester) async {
    tester.view.physicalSize = const Size(1280, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(FinanceScreen(repo: repo)));
    await settle(tester);
    final box = tester.getRect(find.byType(TopBar));
    expect(box.width, lessThanOrEqualTo(kContentMaxWidth));
    expect(box.center.dx, closeTo(640, 1));
    // кнопка «+» - біля вмісту, не в кутку екрана
    expect(tester.getRect(find.byTooltip('Нова операція')).right, lessThan(640 + kContentMaxWidth / 2));
  });
}

/// Справжній шрифт Roboto (як на Android) замість тестового з квадратиків -
/// інакше ширина тексту не та й переповнення не ті.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf') && !name.contains('Italic')) {
      roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await roboto.load();
}
