import 'package:apiary/logic/fz2/frag_text.dart';
import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/logic/receipt_pick.dart';
import 'package:flutter_test/flutter_test.dart';

Frag _f(String t, double x, double y, double w, {double h = 20}) =>
    Frag(text: t, x: x, y: y, w: w, h: h, xLeft: x - w / 2, xRight: x + w / 2);

void main() {
  test('fragLines: назва й ціна на одній висоті - один рядок, рядки згори донизу', () {
    final fr = [_f('Молоко', 100, 100, 160), _f('45.00', 400, 102, 80), _f('Хліб', 100, 140, 100), _f('20.00', 400, 141, 80)];
    expect(fragLines(fr), ['Молоко   45.00', 'Хліб   20.00']);
  });

  test('fragLinesAnchored: ціна пристає до рядка своєї назви при зсуві по висоті', () {
    final fr = [
      _f('Молоко', 100, 100, 160),
      _f('45.00', 400, 108, 80, h: 14),
      _f('Хліб', 100, 130, 100),
      _f('20.00', 400, 138, 80, h: 14),
    ];
    final l = fragLinesAnchored(fr);
    expect(l.length, 2);
    expect(l[0], contains('45.00'));
    expect(l[1], contains('20.00'));
  });

  test('fragLinesDeskewed без нахилу - не падає і не губить фрагменти', () {
    final fr = [_f('Молоко', 100, 100, 160), _f('45.00', 400, 100, 80), _f('Хліб', 100, 140, 100)];
    final l = fragLinesDeskewed(fr);
    expect(l.join(' '), allOf(contains('Молоко'), contains('45.00'), contains('Хліб')));
    expect(fragLinesDeskewed([]), isEmpty);
  });

  test('pickReading без розмітки і з порожніми текстами - порожньо', () {
    final r = pickReading(null, const []);
    expect(r.rows, isEmpty);
    expect(r.verified, false);
  });

  test('pickReading: розбір тексту, що сам себе підтверджує, береться без розмітки', () {
    final r = pickReading(null, ['Молоко 45.00\nХліб 20.00\nРАЗОМ 65.00']);
    expect(r.rows, isNotEmpty);
    expect(r.source, 'text');
  });
}
