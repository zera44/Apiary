import 'package:flutter_test/flutter_test.dart';

import 'package:apiary/logic/fz2/fz2.dart';
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

void main() {
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
}
