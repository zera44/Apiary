import 'dart:typed_data';

import 'package:apiary/logic/receipt_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Знімок із дрібним контрастним «текстом» (смужки) - різкий і розмитий.
Uint8List _photo({required bool blur}) {
  final im = img.Image(width: 600, height: 800);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  for (var y = 20; y < 780; y += 8) {
    for (var x = 20; x < 580; x += 4) {
      if ((x ~/ 4 + y) % 3 != 0) im.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  final out = blur ? img.gaussianBlur(im, radius: 6) : im;
  return img.encodePng(out);
}

void main() {
  test('різкість: чітке фото вище межі, розмите - нижче', () {
    final sharp = receiptSharpness(_photo(blur: false))!;
    final blurry = receiptSharpness(_photo(blur: true))!;
    expect(sharp, greaterThan(receiptBlurLimit));
    expect(blurry, lessThan(receiptBlurLimit));
    expect(sharp, greaterThan(blurry));
  });

  test('різкість: не зображення - null', () {
    expect(receiptSharpness(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
