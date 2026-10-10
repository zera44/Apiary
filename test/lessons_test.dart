import 'package:apiary/data/database.dart';
import 'package:apiary/data/models.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/screens/map_screen.dart';
import 'package:apiary/screens/parameters_screen.dart';
import 'package:apiary/screens/settings_screen.dart';
import 'package:apiary/screens/template_editor_screen.dart';
import 'package:apiary/screens/tutorial_screen.dart';
import 'package:apiary/screens/whats_new_screen.dart';
import 'package:apiary/screens/home_screen.dart';
import 'package:apiary/ui/common.dart';
import 'package:apiary/ui/first_hints.dart';
import 'package:apiary/ui/grid_view.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Уроки з «Навчання» (крок за кроком, як їх проходить людина) і нові дрібниці
/// таблиці параметрів: перейменування тапом, перемикач «Застосувати до», свайп.
void main() {
  late Repository repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    await AppIcons.load();
    Hints.enabled = false;
    WhatsNewScreen.enabled = false;
    HomeScreen.mapBackdrop = false;
  });

  setUp(() async {
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    repo = Repository(db);
    await repo.init();
  });

  tearDown(() async => repo.db.close());

  Future<void> settle(WidgetTester tester, [int n = 5]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      // довгі кроки - з переходами між екранами (анімація до ~0,8 с)
      await tester.pump(Duration(milliseconds: n >= 8 ? 200 : 50));
    }
  }

  Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  Future<Repository> sandbox() async {
    final r = Repository(await AppDatabase.openSandbox(databaseFactoryFfiNoIsolate));
    await r.prepareLikeFreshInstall();
    return r;
  }

  /// Екран як у телефона.
  Future<void> phone(WidgetTester tester, [Size size = const Size(412, 915)]) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> openTutorial(WidgetTester tester) async {
    await tester.pumpWidget(wrap(TutorialScreen(realRepo: repo, openSandbox: sandbox)));
    await settle(tester);
  }

  Future<void> startLesson(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await settle(tester, 2);
    await tester.tap(find.text(title));
    await settle(tester, 12);
  }

  /// Ціль у «вікні» затемнення (не притемнена).
  void expectLit(WidgetTester tester, Finder target) {
    final scrimF = find.byType(LessonScrim).last;
    final holes = tester.state<LessonScrimState>(scrimF).holes;
    final box = tester.renderObject<RenderBox>(scrimF);
    final c = box.globalToLocal(tester.getCenter(target));
    expect(holes.any((h) => h.contains(c)), isTrue, reason: 'ціль притемнена');
  }

  bool ringOn(WidgetTester tester, Finder target) => tester
      .widgetList<HoneyRing>(find.ancestor(of: target, matching: find.byType(HoneyRing)))
      .any((r) => r.on);

  Future<void> longDrag(WidgetTester tester, Finder from, Finder to) async {
    final g = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(0, -8));
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveTo(tester.getCenter(to));
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveBy(const Offset(0, 2));
    await tester.pump(const Duration(milliseconds: 20));
    await g.up();
    await settle(tester, 3);
  }

  /// Що зараз каже пасічник (для повідомлень про помилку).
  String said(WidgetTester tester) => [
        for (final e in find.byType(RichText).evaluate())
          (e.widget as RichText).text.toPlainText()
      ].where((t) => t.length > 25).join(' | ');

  Finder backArrow() =>
      find.byWidgetPredicate((w) => w is CircleIconButton && w.icon == 'back_arrow');

  testWidgets('навчання: плитки уроків, «скоро» - лише повідомлення', (tester) async {
    await phone(tester);
    await openTutorial(tester);
    expect(find.text('Базові поняття'), findsOneWidget);
    expect(find.text('Групи і параметри обходу'), findsOneWidget);
    expect(find.text('Шаблони'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Історія'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('скоро'), findsNWidgets(3));
    await tester.tap(find.text('QR-код'));
    await settle(tester);
    expect(find.textContaining('скоро з\'явиться'), findsOneWidget, reason: said(tester));
    expect(find.byType(MapScreen), findsNothing, reason: said(tester));
    expect(tester.takeException(), isNull);
  });

  testWidgets('урок «Групи і параметри обходу» - від вулика до ідеальної таблиці', (tester) async {
    await phone(tester);
    await openTutorial(tester);
    await startLesson(tester, 'Групи і параметри обходу');

    // 1. натисни на вулик
    expect(find.byType(MapScreen), findsOneWidget, reason: said(tester));
    expect(find.textContaining('натисни на вулик'), findsOneWidget, reason: said(tester));
    final glow = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lesson-pick-glow-'));
    expect(glow, findsWidgets);
    expectLit(tester, glow.first);
    // поза вулика - нічого не відкривається (завіса)
    await tester.tapAt(const Offset(40, 400));
    await settle(tester);
    expect(find.textContaining('натисни на вулик'), findsOneWidget, reason: said(tester));
    await tester.tapAt(tester.getCenter(glow.first));
    await settle(tester, 8);

    // 2. панель вулика, «Параметри» в ободку й не притемнені
    expect(find.textContaining('геть не густо'), findsOneWidget, reason: said(tester));
    final paramsBtn = find.widgetWithText(PillButton, 'Параметри');
    expect(ringOn(tester, paramsBtn), isTrue);
    expectLit(tester, paramsBtn);
    await tester.tap(paramsBtn);
    await settle(tester, 8);

    // 3. «Створити параметр»
    expect(find.byType(ParametersScreen), findsOneWidget, reason: said(tester));
    expect(find.text('Таблиця параметрів'), findsOneWidget);
    expect(find.textContaining('В цьому меню'), findsOneWidget, reason: said(tester));
    final create = find.byTooltip('Створити параметр');
    expectLit(tester, create);
    // перемикач «Застосувати до» з'являється лише на своєму кроці
    expect(find.byType(ApplyScopeSwitch), findsNothing, reason: said(tester));
    await tester.tap(create);
    await settle(tester);

    // 4. форма - пояснення з «Продовжити»
    expect(find.textContaining('Тут ти можеш назвати'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Продовжити'));
    await settle(tester);
    // 5. заповнити: «Скасувати» не працює
    expect(find.textContaining('Створи свій параметр'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Скасувати'), warnIfMissed: false);
    await settle(tester);
    expect(find.textContaining('Створи свій параметр'), findsOneWidget, reason: said(tester));
    await tester.enterText(find.byType(TextField).first, 'Сила сім\'ї');
    await settle(tester);
    // 6. «Не забудь зберегти»
    expect(find.textContaining('Не забудь'), findsOneWidget, reason: said(tester));
    await tester.tap(find.widgetWithText(PillButton, 'Зберегти').last);
    await settle(tester, 8);

    // 7. відкрий конструктор
    expect(find.textContaining('вже додано до конструктора'), findsOneWidget, reason: said(tester));
    expect(find.textContaining('«Сила сім\'ї»'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Конструктор'));
    await settle(tester);

    // 8. нова група
    expect(find.textContaining('який безлад'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('+ Нова група'));
    await settle(tester);
    // 9. назва - лише «Обходи»
    expect(find.textContaining('Назви її'), findsOneWidget, reason: said(tester));
    await tester.enterText(find.byType(TextField).first, 'Огляд');
    await tester.tap(find.widgetWithText(PillButton, 'Зберегти').last);
    await settle(tester);
    expect(find.textContaining('Назви групу «Обходи»'), findsOneWidget, reason: said(tester));
    await tester.enterText(find.byType(TextField).first, 'Обходи');
    await tester.tap(find.widgetWithText(PillButton, 'Зберегти').last);
    await settle(tester, 8);

    // 10. перетягнути три характеристики обходу в «Обходи»
    expect(find.textContaining('до нової групи'), findsOneWidget, reason: said(tester));
    for (final name in ['Періодичність обходу', 'Кількість днів до обходу', 'Дата останнього обходу']) {
      final chip = find.descendant(
          of: find.byType(LongPressDraggable<String>), matching: find.textContaining(name));
      await tester.ensureVisible(chip.first);
      await settle(tester, 2);
      await tester.ensureVisible(find.text('Обходи'));
      await settle(tester, 2);
      await longDrag(tester, chip.first, find.text('Обходи'));
    }
    await settle(tester, 4);
    final groups = (await tester.runAsync(() => repo.paramGroups()))!;
    expect(groups, isEmpty); // справжні дані не чіпаємо - усе в пісочниці

    // 11. «Застосувати до» - з «Продовжити»
    expect(find.textContaining('За потреби можна застосувати'), findsOneWidget, reason: said(tester));
    expect(find.byType(ApplyScopeSwitch), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Продовжити'));
    await settle(tester);

    // 12. вимкнути зайве - свій параметр
    expect(find.textContaining('Вимкни все зайве'), findsOneWidget, reason: said(tester));
    await tester.pump(const Duration(milliseconds: 500)); // список доїхав до параметра
    final check = find.descendant(
        of: find.widgetWithText(ListCard, 'Сила сім\'ї'), matching: find.byType(CheckToggle));
    expect(ringOn(tester, check), isTrue);
    await tester.tap(check);
    await settle(tester);

    // 13. назад до вулика
    expect(find.textContaining('Повернімось до'), findsOneWidget, reason: said(tester));
    await tester.tap(backArrow().first);
    await settle(tester, 10);

    // 14. таблиця на панелі - з групою «Обходи»; «Завершити»
    expect(find.byType(ParametersScreen), findsNothing, reason: said(tester));
    expect(find.textContaining('вона ідеальна'), findsOneWidget, reason: said(tester));
    expect(find.text('Обходи'), findsWidgets);
    expect(find.text('Сила сім\'ї'), findsNothing);
    await tester.tap(find.text('Завершити'));
    await settle(tester, 8);
    expect(find.byType(MapScreen), findsNothing, reason: said(tester));
    expect(find.text('Групи і параметри обходу'), findsOneWidget);
    // пройдено - наступного разу спочатку, без питання
    expect(await tester.runAsync(() => repo.getMeta('lesson_params')), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('урок перервали - «Продовжити» з того місця або «Спочатку»', (tester) async {
    await phone(tester);
    await openTutorial(tester);
    await startLesson(tester, 'Групи і параметри обходу');
    final glow = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lesson-pick-glow-'));
    await tester.tapAt(tester.getCenter(glow.first));
    await settle(tester, 8);
    await tester.tap(find.widgetWithText(PillButton, 'Параметри'));
    await settle(tester, 8);
    await tester.tap(find.byTooltip('Створити параметр'));
    await settle(tester);
    // системне «назад» у формі - знову крок «Створити параметр», а не глухий кут
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.textContaining('В цьому меню'), findsOneWidget, reason: said(tester));
    // «назад» на екрані - вихід з уроку
    await tester.binding.handlePopRoute();
    await settle(tester, 8);
    expect(find.byType(MapScreen), findsNothing, reason: said(tester));
    expect(await tester.runAsync(() => repo.getMeta('lesson_params')), isNotNull);

    // знову урок - питання
    await tester.tap(find.text('Групи і параметри обходу'));
    await settle(tester);
    expect(find.text('Продовжити'), findsOneWidget);
    expect(find.text('Спочатку'), findsOneWidget);
    await tester.tap(find.text('Продовжити'));
    await settle(tester, 15);
    // одразу «Таблиця параметрів» вулика уроку
    expect(find.byType(ParametersScreen), findsOneWidget, reason: said(tester));
    expect(find.textContaining('В цьому меню'), findsOneWidget, reason: said(tester));
    await tester.binding.handlePopRoute();
    await settle(tester, 8);

    await tester.tap(find.text('Групи і параметри обходу'));
    await settle(tester);
    await tester.tap(find.text('Спочатку'));
    await settle(tester, 12);
    expect(find.byType(ParametersScreen), findsNothing, reason: said(tester));
    expect(find.textContaining('натисни на вулик'), findsOneWidget, reason: said(tester));
    await tester.tap(backArrow().first);
    await settle(tester, 8);
    expect(find.byType(MapScreen), findsNothing, reason: said(tester));
    expect(tester.takeException(), isNull);
  });

  testWidgets('урок «Налаштування» - шаблон-перешкода 2×2 і він у своїх шаблонах', (tester) async {
    await phone(tester);
    await openTutorial(tester);
    await startLesson(tester, 'Шаблони');

    expect(find.textContaining('це знову ти'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Продовжити'));
    await settle(tester);
    expect(find.textContaining('Натисни на шестерню'), findsOneWidget, reason: said(tester));
    expectLit(tester, find.byTooltip('Налаштування'));
    await tester.tap(find.byTooltip('Налаштування'));
    await settle(tester, 8);

    expect(find.byType(SettingsScreen), findsOneWidget, reason: said(tester));
    expect(find.text('Характеристики'), findsNothing);
    expect(find.textContaining('загальні налаштування застосунку'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Продовжити'));
    await settle(tester);
    expect(find.textContaining('Те, що треба'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Створити шаблон'));
    await settle(tester, 8);

    expect(find.byType(TemplateEditorScreen), findsOneWidget, reason: said(tester));
    expect(find.textContaining('Час малювати'), findsOneWidget, reason: said(tester));
    await tester.tap(find.byTooltip('Додати'));
    await settle(tester);
    expect(find.textContaining('свайпни картку'), findsOneWidget, reason: said(tester));
    // за замовчуванням - іконки вуликів; вулик зараз не можна - лише перешкоду
    expect(find.byTooltip('Стільник'), findsOneWidget);
    await tester.tap(find.byTooltip('Вулик'), warnIfMissed: false);
    await settle(tester);
    expect(find.textContaining('свайпни картку'), findsOneWidget, reason: said(tester));
    // свайп картки вліво - перешкоди
    await tester.drag(find.byType(PageView), const Offset(-250, 0));
    await settle(tester);
    expect(find.textContaining('Обери будь-яку'), findsOneWidget, reason: said(tester));
    await tester.pump(const Duration(milliseconds: 500)); // вікно доїхало до перешкод
    await tester.tap(find.byTooltip(AppIcons.obstacleVariants.first.$2).last);
    await settle(tester);

    expect(find.textContaining('постав одну плитку'), findsOneWidget, reason: said(tester));
    // у режимі додавання «+» - червоний хрестик
    expect(find.byTooltip('Завершити додавання'), findsOneWidget);
    final gridRect = tester.getRect(find.byType(InfiniteGrid));
    final first = gridRect.topLeft + Offset(gridRect.width * 0.3, gridRect.height * 0.25);
    await tester.tapAt(first);
    await settle(tester);
    expect(find.textContaining('заповни квадрат'), findsOneWidget, reason: said(tester));
    // квадрат у медовій рамці - ще три порожні клітинки
    final square = find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).border is Border &&
        ((w.decoration as BoxDecoration).border! as Border).top.color == AppColors.create &&
        ((w.decoration as BoxDecoration).border! as Border).top.width == 3);
    final r = tester.getRect(square.last).deflate(3);
    expect(r.contains(first), isTrue);
    expectLit(tester, square.last);
    for (final c in [
      r.topLeft + Offset(r.width / 4, r.height / 4),
      r.topLeft + Offset(r.width * 3 / 4, r.height / 4),
      r.topLeft + Offset(r.width / 4, r.height * 3 / 4),
      r.topLeft + Offset(r.width * 3 / 4, r.height * 3 / 4),
    ]) {
      if ((c - first).distance < r.width / 4) continue; // перша плитка вже стоїть
      await tester.tapAt(c);
      await settle(tester, 2);
    }
    expect(find.textContaining('закінчити малювання'), findsOneWidget, reason: said(tester));
    await tester.tap(find.byTooltip('Завершити додавання'));
    await settle(tester);
    expect(find.textContaining('можна пересунути'), findsOneWidget, reason: said(tester));
    await tester.tap(find.byTooltip('Переміщення'));
    await settle(tester);
    expect(find.textContaining('Стрілки навколо'), findsOneWidget, reason: said(tester));
    // перетягуємо квадрат на клітинку вниз
    final from = r.center;
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(Offset(0, r.height));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await settle(tester);
    expect(find.textContaining('Готово! Тепер'), findsOneWidget, reason: said(tester));
    await tester.tap(find.byTooltip('Зберегти'));
    await settle(tester);
    expect(find.textContaining('Дай шаблону назву'), findsOneWidget, reason: said(tester));
    // системне «назад» - знову крок «зберегти»
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.textContaining('Готово! Тепер'), findsOneWidget, reason: said(tester));
    await tester.tap(find.byTooltip('Зберегти'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Скеля');
    await tester.tap(find.widgetWithText(PillButton, 'Зберегти').last);
    await settle(tester, 8);

    expect(find.byType(TemplateEditorScreen), findsNothing, reason: said(tester));
    expect(find.textContaining('швидко вчишся'), findsOneWidget, reason: said(tester));
    expect(find.textContaining('«Скеля»'), findsOneWidget, reason: said(tester));
    await tester.tap(find.text('Завершити'));
    await settle(tester, 8);
    expect(find.byType(SettingsScreen), findsNothing, reason: said(tester));
    final real = (await tester.runAsync(() => repo.listTemplates()))!;
    final t = real.where((t) => t.name == 'Скеля').single;
    expect(t.cells.length, 4);
    expect(await tester.runAsync(() => repo.getMeta('lesson_templates')), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('уроки на малому екрані (360×640): без переповнень, вікна вміщуються', (tester) async {
    await phone(tester, const Size(360, 640));
    await openTutorial(tester);
    await startLesson(tester, 'Групи і параметри обходу');
    final glow = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lesson-pick-glow-'));
    await tester.tapAt(tester.getCenter(glow.first));
    await settle(tester, 8);
    expect(find.textContaining('геть не густо'), findsOneWidget, reason: said(tester));
    await tester.tap(find.widgetWithText(PillButton, 'Параметри'));
    await settle(tester, 8);
    await tester.tap(find.byTooltip('Створити параметр'));
    await settle(tester);
    await tester.tap(find.text('Продовжити'));
    await settle(tester);
    // «Зберегти» форми видно (не під пасічником)
    final save = find.widgetWithText(PillButton, 'Зберегти').last;
    expect(tester.getRect(save).bottom, lessThan(640 - 200));
    await tester.enterText(find.byType(TextField).first, 'Сила');
    await settle(tester);
    await tester.tap(save);
    await settle(tester, 8);
    await tester.tap(find.text('Конструктор'));
    await settle(tester);
    await tester.tap(find.text('+ Нова група'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Обходи');
    await tester.tap(find.widgetWithText(PillButton, 'Зберегти').last);
    await settle(tester, 8);
    expect(find.textContaining('до нової групи'), findsOneWidget, reason: said(tester));
    // параметр унизу, група вгорі: тягнемо до верхнього краю - список сам гортається
    final scroll = find
        .descendant(of: find.byType(ParametersScreen), matching: find.byType(Scrollable))
        .first;
    final chip = find.descendant(
        of: find.byType(LongPressDraggable<String>), matching: find.textContaining('Мітка матки'));
    await tester.ensureVisible(chip.first);
    await settle(tester, 2);
    final before = tester.state<ScrollableState>(scroll).position.pixels;
    if (before > 0) {
      final top = tester.getRect(scroll).top;
      final d = await tester.startGesture(tester.getCenter(chip.first));
      await tester.pump(const Duration(milliseconds: 400));
      await d.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
      await d.moveTo(Offset(tester.getCenter(scroll).dx, top + 6));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final after = tester.state<ScrollableState>(scroll).position.pixels;
      await d.up();
      await settle(tester);
      expect(after, lessThan(before));
    }
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await settle(tester, 8);

    await startLesson(tester, 'Шаблони');
    await tester.tap(find.text('Продовжити'));
    await settle(tester);
    await tester.tap(find.byTooltip('Налаштування'));
    await settle(tester, 8);
    await tester.tap(find.text('Продовжити'));
    await settle(tester);
    await tester.tap(find.text('Створити шаблон'));
    await settle(tester, 8);
    await tester.tap(find.byTooltip('Додати'));
    await settle(tester);
    await tester.tap(find.text('Перешкоди'));
    await settle(tester);
    expect(find.textContaining('Обери будь-яку'), findsOneWidget, reason: said(tester));
    await tester.pump(const Duration(milliseconds: 500)); // вікно доїхало до перешкод
    await tester.tap(find.byTooltip(AppIcons.obstacleVariants.first.$2).last);
    await settle(tester);
    expect(find.textContaining('постав одну плитку'), findsOneWidget, reason: said(tester));
    expect(tester.takeException(), isNull);
  });

  testWidgets('таблиця параметрів: тап по назві - перейменувати, поки немає записів', (tester) async {
    await phone(tester);
    final aid = (await tester.runAsync(() => repo.addApiary('П')))!;
    final gid = (await tester.runAsync(
        () => repo.addGroup(aid, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1')))!;
    final (used, free) = (await tester.runAsync(() async {
      final a = await repo.addParameter('Вага', unit: 'кг', dataType: DataTypes.float_);
      await repo.addParameterRecord(a, '12', EntityRef.group(gid));
      final b = await repo.addParameter('Настрій');
      return (a, b);
    }))!;
    final hive = (await tester.runAsync(() => repo.getGroupElements(gid)))!.first;
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: hive)));
    await settle(tester);
    await tester.tap(find.text('Вага'));
    await settle(tester);
    expect(find.text('Не можна перейменувати'), findsOneWidget);
    await tester.tap(find.text('Гаразд'));
    await settle(tester);
    await tester.tap(find.text('Настрій'));
    await settle(tester);
    expect(find.text('Редагувати параметр'), findsOneWidget);
    expect(find.text('Видалити параметр'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Настрій бджіл');
    await tester.tap(find.widgetWithText(PillButton, 'Зберегти').last);
    await settle(tester);
    expect(find.text('Настрій бджіл'), findsOneWidget);
    expect((await tester.runAsync(() => repo.getParameter(free)))!.name, 'Настрій бджіл');
    expect((await tester.runAsync(() => repo.getParameter(used)))!.name, 'Вага');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Застосувати до»: лише такі самі вулики (той самий клас)', (tester) async {
    await phone(tester);
    final (hive, lezhak2, vulyk) = (await tester.runAsync(() async {
      final aid = await repo.addApiary('П');
      final g1 = await repo.addGroup(aid, {'0,0': 'hive'}, 0, 0, groupLabel: 'Лежак 1');
      final g2 = await repo.addGroup(aid, {'0,0': 'hive'}, 3, 0, groupLabel: 'Лежак 2');
      final g3 = await repo.addGroup(aid, {'0,0': 'hive'}, 6, 0, groupLabel: 'Вулик 1');
      final h = (await repo.getGroupElements(g1)).first;
      return (h, g2, g3);
    }))!;
    final p = (await tester.runAsync(() => repo.addParameter('Сила')))!;
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: hive)));
    await settle(tester);
    await tester.tap(find.descendant(
        of: find.widgetWithText(ListCard, 'Сила'), matching: find.byType(CheckToggle)));
    await settle(tester);
    expect(find.text('Усі «Лежак»'), findsOneWidget);
    await tester.tap(find.text('Усі «Лежак»'));
    await settle(tester);
    await tester.tap(backArrow().first);
    await settle(tester);
    final a = (await tester.runAsync(() => repo.attachedParameterIds(EntityRef.group(lezhak2), elType: 'hive')))!;
    final b = (await tester.runAsync(() => repo.attachedParameterIds(EntityRef.group(vulyk), elType: 'hive')))!;
    expect(a, contains(p));
    expect(b, isNot(contains(p)));
  });

  testWidgets('вкладки свайпом: «Список» ↔ «Конструктор»', (tester) async {
    await phone(tester);
    final hive = (await tester.runAsync(() async {
      final aid = await repo.addApiary('П');
      final g = await repo.addGroup(aid, {'0,0': 'hive'}, 0, 0, groupLabel: 'Вулик 1');
      return (await repo.getGroupElements(g)).first;
    }))!;
    await tester.pumpWidget(wrap(ParametersScreen.forElement(repo: repo, element: hive)));
    await settle(tester);
    expect(find.text('+ Нова група'), findsNothing);
    await tester.fling(find.byType(TabSwipe), const Offset(-300, 0), 1200);
    await settle(tester);
    expect(find.text('+ Нова група'), findsOneWidget);
    await tester.fling(find.byType(TabSwipe), const Offset(300, 0), 1200);
    await settle(tester);
    expect(find.text('+ Нова група'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
