import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/screens/receipt_markup_screen.dart';

Labeled _l(double x, double y) =>
    Labeled(Frag(text: 'т', x: x, y: y, w: 100, h: 20, xLeft: x - 50, xRight: x + 50), 'NAME');

void main() {
  const img = Size(1000, 2000);

  test('ділянка чека охоплює фрагменти з полем і не виходить за зображення', () {
    final r = markupCropRect([_l(400, 300), _l(500, 1500)], 0, img);
    expect(r.left, lessThan(350));
    expect(r.right, greaterThan(550));
    expect(r.top, lessThan(290));
    expect(r.bottom, greaterThan(1510));
    expect(r.width, lessThan(400)); // тло навколо чека відрізано
    expect(const Offset(0, 0) & img, containsRect(r));
  });

  test('без фрагментів - усе зображення', () {
    expect(markupCropRect([], 0, img), const Offset(0, 0) & img);
  });
}

Matcher containsRect(Rect r) => predicate<Rect>((o) => o.contains(r.topLeft) && o.contains(r.bottomRight - const Offset(0.001, 0.001)));
