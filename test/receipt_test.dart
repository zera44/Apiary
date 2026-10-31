import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/logic/receipt_parser.dart';
import 'package:apiary/screens/receipt_screen.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:apiary/services/receipt_ocr.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOcr implements ReceiptOcr {
  final String text;
  _FakeOcr(this.text);
  @override
  bool get supported => true;
  @override
  Future<String> read(String imagePath) async => text;
}

const _receipt = '''
ТОВ "МЕДОВИЙ ДІМ"
м. Київ, вул. Садова 5
Чек № 4521  Дата 08.10.2026
Цукор білий 1кг
2.000 х 45.50  91.00 А
Вощина пасічна
5 шт x 120,00 = 600.00 Б
Мед липовий 0.5кг 150.00 А
Сироп 1л  3 x 80.00
СУМА 841.00
ГОТІВКА 1000.00
РЕШТА 159.00
ПДВ А 20% 15.17
''';

void main() {
  group('розпізнавання', () {
    test('PaddleOCR працює лише на Android (тут - ні), підміна в тестах діє', () async {
      expect(PaddleReceiptOcr().supported, isFalse);
      expect(() => PaddleReceiptOcr().read('/немає.jpg'), throwsStateError);
      expect(await _FakeOcr('Мед 1 x 100.00').read('/немає.jpg'), 'Мед 1 x 100.00');
    });
  });

  group('розбір чека', () {
    test('назва в одному рядку, «кількість x ціна» - у наступному', () {
      final rows = parseReceipt(_receipt);
      expect(rows.map((r) => r.name), ['Цукор білий 1кг', 'Вощина пасічна', 'Мед липовий 0.5кг', 'Сироп 1л']);
      expect(rows[0].qty, 2);
      expect(rows[0].price, 45.5);
      expect(rows[0].unit, 'шт');
      expect(rows[1].qty, 5);
      expect(rows[1].price, 120);
      // «Мед … 150.00» - одна позиція за ціною
      expect(rows[2].qty, 1);
      expect(rows[2].price, 150);
      expect(rows[3].qty, 3);
      expect(rows[3].price, 80);
    });

    test('службові рядки й усе після «СУМА» не стають товарами', () {
      final names = parseReceipt(_receipt).map((r) => r.name.toLowerCase()).join('|');
      for (final w in ['сума', 'готівка', 'решта', 'пдв', 'чек', 'київ']) {
        expect(names.contains(w), isFalse, reason: w);
      }
    });

    test('«кількість x ціна» і назва в одному рядку; вага; кома; літера О замість нуля', () {
      final rows = parseReceipt('Огірки 1.2О0 кг x 55,5О 66.60\nХліб 2 * 18.00');
      expect(rows.length, 2);
      expect(rows[0].name, 'Огірки');
      expect(rows[0].qty, 1.2);
      expect(rows[0].unit, 'кг');
      expect(rows[0].price, 55.5);
      expect(rows[1].qty, 2);
      expect(rows[1].price, 18);
    });

    test('нумерація позицій і сміття не потрапляють у назву', () {
      final rows = parseReceipt('1. Цукор | рафінад\n2 x 30.00');
      expect(rows.single.name, 'Цукор рафінад');
    });

    test('порожній чи нечитабельний текст - порожній результат', () {
      expect(parseReceipt(''), isEmpty);
      expect(parseReceipt('###\n12:30\n0.00'), isEmpty);
    });
  });

  group('екран чека', () {
    late Repository repo;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      await AppIcons.load();
    });

    setUp(() async {
      repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
      await repo.init();
    });

    tearDown(() async => repo.db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    testWidgets('таблиця «Товар / Кількість / Ціна» і запис у склад (нове й поповнення)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final known = (await tester.runAsync(() async {
        final id = await repo.addStockItem('Вощина пасічна', 'шт');
        await repo.receiveStock(id, 10, total: 100);
        return id;
      }))!;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ReceiptScreen(repo: repo, imagePath: '/x.jpg', ocr: _FakeOcr(_receipt)),
      ));
      await settle(tester);
      expect(find.text('Товар'), findsOneWidget);
      expect(find.text('Кількість'), findsOneWidget);
      expect(find.text('Ціна'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Цукор білий 1кг'), findsOneWidget);
      expect(find.textContaining('Разом: '), findsOneWidget);

      // зайву позицію знімаємо
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.tap(find.text('Додати на склад'));
      await settle(tester);
      await settle(tester);

      expect(find.byType(StockScreen), findsOneWidget);
      final items = (await tester.runAsync(() => repo.listStockItems()))!;
      final byName = {for (final i in items) i.name: i};
      expect(byName['Цукор білий 1кг']!.quantity, 2);
      expect(byName['Мед липовий 0.5кг']!.quantity, 1);
      expect(byName.containsKey('Сироп 1л'), isFalse); // знята галочка
      // наявну номенклатуру поповнено, а не продубльовано
      expect(items.where((i) => i.name == 'Вощина пасічна').length, 1);
      expect((await tester.runAsync(() => repo.getStockItem(known)))!.quantity, 15);
      expect(tester.takeException(), isNull);
    });

    testWidgets('невалідний рядок не записується, пояснення людською мовою', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ReceiptScreen(repo: repo, ocr: _FakeOcr('')),
      ));
      await settle(tester);
      await tester.tap(find.text('+ Додати рядок'));
      await tester.pump();
      await tester.tap(find.text('Додати на склад'));
      await settle(tester);
      expect(find.textContaining('не вистачає назви'), findsOneWidget);
      expect(await tester.runAsync(() => repo.listStockItems()), isEmpty);
    });

    testWidgets('там, де розпізнавання недоступне, - порожня таблиця й пояснення', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ReceiptScreen(repo: repo, imagePath: '/x.jpg', ocr: _NoOcr()),
      ));
      await settle(tester);
      expect(find.textContaining('працює на телефоні'), findsOneWidget);
      expect(find.text('+ Додати рядок'), findsOneWidget);
    });
  });

  test('службові рядки з номером картки й гарантією не стають товарами', () {
    final rows = parseReceipt('Гарантійний термін 14 днів 1 x 1134\n'
        'ЕПЗ 4412345678 x 4\n'
        'Мед липовий 1 x 134.00 134.00\n'
        'СУМА 134.00');
    expect(rows.map((r) => r.name), ['Мед липовий']);
    expect(rows.single.total, 134);
  });

  group('чеки зі штрихкодами (справжній текст PaddleOCR з фото)', () {
    test('«Вигідна покупка»: одна позиція, без гарантії, картки й реквізитів', () {
      final rows = parseReceipt('''
ТОВ ВИГІДНА ПОКУПКА"
магазин
ПН411303626599
Касир 35901
1X   134,00
Штрихкод 2099901024039
Арт №2 138807 Навушники
вакуум.дрот.гарн.Geliuз DailyB.GP-HP03С
Гарантійний термін 1рік   134,00 А
ЧЕК: 9240934314
КОО 1А 2136
ІДЕНТ. ЕКВАЙРА   51К809F1
ТЕРМІНА Л   51К809F1
Оплата
ЕПЗ   449135439*****4
ПЛАТІЖНА СИСТЕМА   VI5А
КОД АВТ.   328201
КОД ТРАНЗ.   118538265007
БЕЗГОТІВКОВА   134,00 гРн
Електронний плапіжний заоіб
СУМА   134,00 гРН
ПДВ А 20,00 %   2R,33
До сплати   134,00 гРН.
ЧЕК №9 8086453377
22.10.2026 08-40 44
''');
      expect(rows.length, 1);
      expect(rows.single.name, startsWith('Навушники'));
      expect(rows.single.qty, 1);
      expect(rows.single.price, 134);
    });

    test('АТБ: чотири позиції; знижка враховується; разом 121,84', () {
      final rows = parseReceipt('''
e mail: in@atbmarket.com
ГАРЯЧА ЛННЯ 0 800 500 415
ГОВ "оТЬ Маркет"
МагВзин  ПрОдукти-225"
Уернна Нмив. гомооіівоький р-м,
Пр. ГолоС іівський, 128
ПН 304872104175
Мооа Б ВАОо Перноакв з. П.   01
Т55202E10 7035047 ШЕК 20Е4380,  2406 Я
ШК 4820217000055
Вода 1,5 7 Морвннська мі
Нерал Н СиАНОГААОВБНА
2 Х 30,90   61,80 А
ЗНИНКА   -3,16 А
ЦІНА КГ/ 3І ЗНМЖКОЮ   29, 32 А А
СНМА ЗІ ЗНАК00   58,64
ШК 4523065734490
КогЧрт 23е г долЬче
Вишн чіа ,2% п/отакан   31,90 А
ШК 402020253455
СароК гААуРоВаНий ЗБ г
Своя лНія Ві омаком Шок 12,60 А
ШК 4820200534563
СироК глазурОвВНий Бо г
С80Я АН15 2 0 1 ВИШНЯ Т   18,70 А
634317102   101 84 гРН
ПОВ А 20, 00%   20, 31
БЕЗГОТІВКОВА   121,84 ГРН
КАРТКА
ГАЕНЕ. ЕМВАИРА   S1К30РF0
ГЕРМЯНАА   S1К30PFD
КОМІС459   0,00
ПЛАтІКНО СКСТЕМА   Wisa Credit
ВИД ОПЕРАШІ   оплатв
В3   ХХХХХХХХХХХХХКЖБ
К3 А01   250089
ККН   118342923466
ЗНИКИ З8 МОЯАБНіСтЮ 3. 16 гРН   А
3 НИХ 38 КВРТКОЮ АТБ 3.16 гРН   #
ШЯКУЕМО ЗА ПОКУПКУ П
01 0Н2В05
ЧКК М 2ВЗ1637   17-10-2026 08:59:26
0Н К600002733   ФН 3000760271
АВОАААУQAААААВYADaeТ
ААХntAIBLloКrW07eМ=
''');
      expect(rows.length, 4);
      expect(rows[0].name, startsWith('Вода'));
      expect(rows[0].qty, 2);
      expect(rows[0].price, 29.32); // 58,64 / 2: «сума зі знижкою»
      expect(rows[1].price, 31.9);
      expect(rows[2].price, 12.6);
      expect(rows[3].price, 18.7);
      final total = rows.fold<double>(0, (s, r) => s + r.qty * r.price);
      expect(total, closeTo(121.84, 0.011));
    });
  });

  group('чеки з фото користувача (текст відтворено з фото, не сирий OCR)', () {
    test('«Вигідна покупка»: назву «220х400мм» не прийнято за кількість і ціну', () {
      final text = '''
ТОВ "ВИГІДНА ПОКУПКА"
магазин
м. Київ, Дарницький район вул. Геннадія
Афанасьєва, буд. 13-А
ПН 411303626599
Касир 44162
1х 7,00
Штрихкод 2310000150871
Арт № 15087 Маркер перманентний
двосторон. в асорт. арт. 15087
7,00 А
1х 27,00
Штрихкод 4820091630780
Арт № 116162 Соломка солона VLADKA
200г
27,00 А
1х 3,00
Штрихкод 2900001210409
Арт № 121040 Пакет п/е Аврора
220х400мм
3,00 А
1х 29,00
Штрихкод 2900001229449
Арт № 122944 Набір резинок
д/волос текст.кольор.6шт арт. 122944
29,00 А
1х 18,00
Штрихкод 4820252125674
Арт № 129880 Напій соковм.б/а
сильног.Mojo М'ята-лайм ж/б 250мл
18,00 А
1х 20,00
Штрихкод 4820252126558
Арт № 137804 Напій соковм.б/а
сильног.Mojo Алое-лічі ж/б 330мл
20,00 А
ЧЕК: 11790382197
КСО 1 А 2430
ІДЕНТ. ЕКВАЙРА S1K90OLX
БЕЗГОТІВКОВА 104,00 грн
Електронний платіжний засіб
СУМА 104,00 грн
ПДВ А 20.00 % 17,33
До сплати 104,00 грн.
ЧЕК № 61830924.4.8621
27.10.2026 13-12-37
''';
      final rows = parseReceipt(text);
      expect(rows.length, 6);
      expect(rows[2].name, 'Пакет п/е Аврора');
      expect(rows[2].qty, 1);
      expect(rows[2].price, 3);
      final total = rows.fold<double>(0, (s, r) => s + r.total);
      expect(total, closeTo(104, 0.011));
      expect(receiptDeclaredTotal(text), 104);
    });

    test('«Київхліб»: «ШТРИХ-КОД», назва з кількох рядків і «ЗНИЖКА -9,40»', () {
      final text = '''
ТОВ "ФІРМОВА МЕРЕЖА "КИЇВХЛІБ"
ПАВІЛЬЙОН N172
м. Київ, Дарницький р-н
вул. Юрія Пасхаліна, 1
ПН407583026564
ФН3001138209
ОПЕРАТОР 1
ШТРИХ-КОД: 4820000199711
Хліб український фірмовий 95
Ог в пакеті ТМ Київхліб Ак
ція пл 47,00 А
ЗНИЖКА -9,40 А
ШТРИХ-КОД: 4820136405861
Хліб Оксамитовий 350г наріза
ний скибками ТМ Київхліб 35,00 А
СУМА 72,60
ПДВ А = 20,00% 12,10
БЕЗГОТІВКОВА 72,60 ГРН
КАРТКОЮ
ВИД ОПЕРАЦІЇ : ОПЛАТА
ПЛАТІЖНА СИСТЕМА: VISA
БАНК: Ощадбанк
ТЕРМІНАЛ: 50933836
ЕПЗ : 4119XXXXXXXX5684
RRN: 630056818693
КОД АВТ: 837189
ПІДПИС ДЕРЖАТЕЛЯ ЕПЗ НЕ ПОТРІБЕН
27-10-2026 18:14:56
ЧЕК N°08120189
''';
      final rows = parseReceipt(text);
      expect(rows.length, 2);
      expect(rows[0].name, startsWith('Хліб український'));
      expect(rows[0].price, 37.6); // 47,00 - 9,40
      expect(rows[1].price, 35);
      final total = rows.fold<double>(0, (s, r) => s + r.total);
      expect(total, closeTo(72.6, 0.011));
    });

    test('«Фора»: штрихкод без «ШК» і з пробілом усередині «Ш К»', () {
      final text = '''
Чек 34/1042/159
Ш К 4823130301757
Бул300київхлібМалят 29.90 А
4820000431026
М/в1.5Мирг/Лаг1дН/газ 28.70 А
ПІДСУМОК 58.60
СУМА 58.60 ГРН
''';
      final rows = parseReceipt(text);
      expect(rows.map((r) => r.price), [29.9, 28.7]);
    });

    test('без штрихкодів «СУМА … ПДВ …» не стає товаром', () {
      final text = '''
ТОВ "ФОРА"
Каса N 5 (Семенюта М.М.)
Чек 34/1042/158
Нап0.25SprКомбПерс 81.40 А
ПІДСУМОК 81.40
СУМА ПДВ А 20.00% 13.57
СУМА 81.40 ГРН
ДО СПЛАТИ: 81.40 ГРН
''';
      final rows = parseReceipt(text);
      expect(rows.length, 1);
      expect(rows.single.name, startsWith('Нап'));
      expect(rows.single.price, 81.4);
    });

    test('«Вигідна покупка»: три позиції з артикулами', () {
      final text = '''
ТОВ "ВИГІДНА ПОКУПКА"
магазин
м. Київ, Дніпровський район, вул. Сиваська, 1-А
(другий поверх)
ПН 411303626599
Касир 36509
1х 12,00
Штрихкод 4820043252176
Арт № 37193 Часник сушений Ласочка
15г
12,00 А
1х 7,00
Штрихкод 4820043250868
Арт № 44177 Приправа Хмелі-сунелі
Ласочка 30г
7,00 А
1х 29,00
Штрихкод 2900000864740
Арт № 86474 Ложка для морозива Almo
з візерунком арт.86474
29,00 А
ЧЕК: 9670900707
КСО 3 А 2219
ІДЕНТ. ЕКВАЙРА S1K60E2R
ТЕРМІНАЛ S1K60E2R
Оплата
ЕПЗ 533282446******7
ПЛАТІЖНА СИСТЕМА MASTERCARD
КОД АВТ. 346171
КОД ТРАНЗ. 118717174220
БЕЗГОТІВКОВА 48,00 грн
Електронний платіжний засіб
СУМА 48,00 грн
ПДВ А 20.00 % 8,00
До сплати 48,00 грн.
ЧЕК № 61608739.353.7847
26.10.2026 13-46-48
ОФЛАЙН
''';
      final rows = parseReceipt(text);
      expect(rows.map((r) => r.price), [12, 7, 29]);
      expect(rows[0].name, 'Часник сушений Ласочка');
    });
  });
}

class _NoOcr implements ReceiptOcr {
  @override
  bool get supported => false;
  @override
  Future<String> read(String imagePath) async => throw StateError('no');
}
