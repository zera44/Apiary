import 'dart:typed_data';

import 'package:apiary/logic/receipt_detect.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кадр [w] x [h] RGBA: тло [bg], а в прямокутнику [x0..x1] x [y0..y1] -
/// світлий папір з рядками «тексту» (темні штрихи).
Uint8List frame(int w, int h,
    {int bg = 60, int x0 = 30, int x1 = 90, int y0 = 20, int y1 = 170, bool text = true}) {
  final d = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = bg;
      if (x >= x0 && x < x1 && y >= y0 && y < y1) {
        v = 230;
        if (text && (y - y0) % 8 == 0 && x >= x0 + 8 && x < x0 + 38) v = 40;
      }
      final i = (y * w + x) * 4;
      d[i] = d[i + 1] = d[i + 2] = v;
      d[i + 3] = 255;
    }
  }
  return d;
}

void main() {
  test('світлий видовжений прямокутник із текстом на темному - це чек', () {
    final q = detectReceipt(frame(120, 200), 120, 200);
    expect(q, isNotNull);
    expect(q!.aspect, greaterThan(2));
    expect(q.area, greaterThan(0.25));
    // кути: ліво-верх, право-верх, право-низ, ліво-низ
    expect(q.corners.length, 4);
    expect(q.corners[0].dx, closeTo(30 / 120, 0.03));
    expect(q.corners[0].dy, closeTo(20 / 200, 0.03));
    expect(q.corners[2].dx, closeTo(90 / 120, 0.03));
    expect(q.corners[2].dy, closeTo(170 / 200, 0.03));
  });

  test('порожній стіл, однотонний кадр і чистий папір без тексту - не чек', () {
    expect(detectReceipt(frame(120, 200, x1: 30), 120, 200), isNull); // нічого світлого
    expect(detectReceipt(frame(120, 200, bg: 230, text: false), 120, 200), isNull); // однотонний
    expect(detectReceipt(frame(120, 200, text: false), 120, 200), isNull); // без друку
  });

  test('майже квадратна пляма - не чек', () {
    expect(detectReceipt(frame(120, 200, x0: 20, x1: 100, y0: 40, y1: 120), 120, 200), isNull);
  });

  test('той самий чек у сусідніх кадрах - «схожий», зсунутий далеко - ні', () {
    final a = detectReceipt(frame(120, 200), 120, 200)!;
    final b = detectReceipt(frame(120, 200, x0: 32, x1: 92, y0: 22, y1: 172), 120, 200)!;
    final c = detectReceipt(frame(120, 200, x0: 5, x1: 65, y0: 20, y1: 170), 120, 200)!;
    expect(a.similarTo(b), isTrue);
    expect(a.similarTo(c), isFalse);
  });
}
