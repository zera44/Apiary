import 'package:flutter_test/flutter_test.dart';

import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/logic/fz2/receipt_rows.dart';
import 'package:apiary/logic/fz2/recover.dart';

Frag f(String t, {double x = 500, double y = 100, double h = 30, double w = 120, double conf = 0.99}) =>
    Frag(text: t, conf: conf, x: x, y: y, w: w, h: h, xLeft: x - w / 2, xRight: x + w / 2, imgW: 1000, imgH: 2000);

/// Відповідає на читання за списком; усе інше - порожнє читання.
class _Fake implements OcrBackend {
  final List<ReadRes> Function(List<ReadReq>) answer;
  final reqs = <ReadReq>[];

  _Fake([this.answer = _empty]);

  static List<ReadRes> _empty(List<ReadReq> r) => [for (final _ in r) const ReadRes('', 0)];

  @override
  Future<List<ReadRes>> read(double angle, List<ReadReq> r) async {
    reqs.addAll(r);
    return answer(r);
  }

  @override
  Future<void> degen(Frag fr, double angle) async {}

  @override
  Future<List<Frag>> hand(List<Frag> fr) async => [];
}

/// Плагін, у якого падають рукописні рядки (як UNICODE_CHARACTER_CLASS на Android).
class _HandFails extends _Fake {
  @override
  Future<List<Frag>> hand(List<Frag> fr) async => throw Exception('flag not supported');
}

void main() {
  test('збій кроку дочитування не зупиняє решту й повертає причину', () async {
    final a = f('--12,50');
    final errors = await recoverAll([a], _HandFails());
    expect(a.text, '-12,50');
    expect(errors, hasLength(1));
    expect(errors.single, startsWith('hand: '));
  });

  test('без збоїв причин немає', () async {
    expect(await recoverAll([f('12,50')], _Fake()), isEmpty);
  });

  test('stripQty: «1 х 34,00» у вузькій рамці лишає ціну', () {
    final a = f('1 х 34,00', w: 40, h: 30);
    stripQty([a]);
    expect(a.text, '34,00');
  });

  test('подвійний мінус перед числом стає одним', () async {
    final a = f('--12,50');
    await recoverAll([a], _Fake());
    expect(a.text, '-12,50');
  });

  test('невпевнене число без копійок перечитується й приймається чисте читання', () async {
    final a = f('12 50', conf: 0.5);
    final b = _Fake((r) => [for (var i = 0; i < r.length; i++) i == 2 ? const ReadRes('12,50', 0.95) : const ReadRes('', 0)]);
    await reread([a], b);
    expect(a.text, '12,50');
    expect(a.conf, 0.95);
    expect(b.reqs.length, 6); // 2 рамки x 3 розтягнення
  });

  test('впевнений чистий фрагмент не читається вдруге', () async {
    final a = f('12,50');
    final b = _Fake();
    await recoverAll([a], b);
    expect(b.reqs, isEmpty);
    expect(a.text, '12,50');
  });

  test('reread3: «ціна х 1=» перечитується без множення, лише коли ліворуч той самий запис', () async {
    final left = f('5,00 x 2', x: 300);
    final sum = f('5,00 x 1 =', x: 600);
    final b = _Fake((r) => [for (final _ in r) const ReadRes('5,00', 0.97)]);
    await reread3([left, sum], b);
    expect(sum.text, '5,00');
  });

  group('reconcileSums: звірка з підсумком', () {
    Labeled l(String cls, String text, double y, double x) =>
        Labeled(Frag(text: text, conf: 0.99, x: x, y: y, w: 100, h: 30, xLeft: x - 50, xRight: x + 50), cls);

    /// Чек з двох позицій; друга сума прочитана хибно.
    List<Labeled> receipt(String second, String total) => [
          l('NAME', 'Вощина', 100, 200),
          l('ITEM', '37,80', 100, 700),
          l('NAME', 'Мед', 200, 200),
          l('ITEM', second, 200, 700),
          l('TOTAL', 'СУМА', 300, 200),
          l('TOTAL', total, 300, 700),
        ];

    /// Плагін, що відповідає залежно від кута й розтягнення запиту.
    _Smart smart(ReadRes Function(double angle, ReadReq q) answer) => _Smart(answer);

    test('злита подвоєна цифра: «22,90» читається лише з розтягненням', () async {
      final lab = receipt('2,90', '60,70');
      final fr = [for (final x in lab) x.f];
      final b = smart((a, q) => q.st.first >= 1.5 ? const ReadRes('22,90', 0.95) : const ReadRes('2,90', 0.99));
      expect(await reconcileSums(fr, assemble(lab), b), isTrue);
      expect(fr[3].text, '22,90');
      expect(fr[3].conf, 0.95);
      expect(fr[1].text, '37,80');
    });

    test('позиція - частина фрагмента («2,90» з «2,90 А»): перечитується весь фрагмент', () async {
      final lab = receipt('2,90', '60,70');
      // у розмітці сума вужча (літера ПДВ відділена), а у фрагментах чека - ціла «2,90 А»
      final whole = Frag(text: '2,90 А', conf: 0.915, x: 760, y: 200, w: 120, h: 30, xLeft: 650, xRight: 770);
      final fr = [lab[0].f, lab[1].f, lab[2].f, whole, lab[4].f, lab[5].f];
      final b = smart((a, q) => q.st.first >= 1.5 ? const ReadRes('22,90 А', 0.96) : const ReadRes('2,90 А', 0.9));
      expect(await reconcileSums(fr, assemble(lab), b), isTrue);
      expect(whole.text, '22,90 А');
    });

    test('відрізана старша цифра: ширша ліворуч рамка', () async {
      final lab = receipt('2,90', '60,70');
      final fr = [for (final x in lab) x.f];
      final b = smart((a, q) => q.x1 < fr[3].xLeft - 10 ? const ReadRes('22,90', 0.9) : const ReadRes('2,90', 0.99));
      expect(await reconcileSums(fr, assemble(lab), b), isTrue);
      expect(fr[3].text, '22,90');
    });

    test('сума читається правильно лише під нахилом: поворот рамки', () async {
      final lab = receipt('20,90', '60,70'); // має бути 22,90
      final fr = [for (final x in lab) x.f];
      final b = smart((a, q) => a != fr.first.angle ? const ReadRes('22,90', 0.9) : const ReadRes('20,90', 0.99));
      expect(await reconcileSums(fr, assemble(lab), b), isTrue);
      expect(fr[3].text, '22,90');
    });

    test('читання, що не дає підсумок, не приймається', () async {
      final lab = receipt('2,90', '60,70');
      final fr = [for (final x in lab) x.f];
      final b = smart((a, q) => const ReadRes('12,90', 0.99));
      expect(await reconcileSums(fr, assemble(lab), b), isFalse);
      expect(fr[3].text, '2,90');
    });

    test('сума збігається з підсумком - нічого не читається', () async {
      final lab = receipt('22,90', '60,70');
      final fr = [for (final x in lab) x.f];
      final b = smart((a, q) => const ReadRes('', 0));
      expect(await reconcileSums(fr, assemble(lab), b), isFalse);
      expect(b.reqs, 0);
    });

    test('рамка під нульовим кутом збігається з рамкою фрагмента', () async {
      final lab = receipt('2,90', '60,70');
      final fr = [for (final x in lab) x.f];
      final seen = <ReadReq>[];
      final b = smart((a, q) {
        if (q.st.first == 2.0 && a == fr.first.angle) seen.add(q);
        return const ReadRes('', 0);
      });
      await reconcileSums(fr, assemble(lab), b);
      expect(seen, isNotEmpty);
      expect(seen.first.x1, closeTo(fr[3].xLeft, 1e-6));
      expect(seen.first.x2, closeTo(fr[3].xRight, 1e-6));
      expect(seen.first.y1, lessThan(fr[3].y));
    });
  });
}

/// Плагін, що відповідає залежно від кута й запиту; рахує запити.
class _Smart implements OcrBackend {
  final ReadRes Function(double angle, ReadReq q) answer;
  int reqs = 0;

  _Smart(this.answer);

  @override
  Future<List<ReadRes>> read(double angle, List<ReadReq> r) async {
    reqs += r.length;
    return [for (final q in r) answer(angle, q)];
  }

  @override
  Future<void> degen(Frag fr, double angle) async {}

  @override
  Future<List<Frag>> hand(List<Frag> fr) async => [];
}
