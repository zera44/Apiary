import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Підготовка фото чека до розпізнавання: чорний текст на білому.
///
/// Фото з телефона - з тінню від руки, згинами й нерівним світлом; Tesseract
/// на такому плутає літери й губить цілі рядки. Тому:
///  1. повернути за EXIF (телефон часто зберігає знімок «боком»);
///  2. сірі тони й одна ширина [receiptOcrWidth] - тоді шрифт чека завжди
///     приблизно однакової висоти в пікселях, незалежно від камери;
///  3. адаптивний поріг: кожна точка порівнюється із середньою яскравістю
///     навколо себе (вікно [receiptOcrWindow]), тож тінь і згини зникають.
/// Значення підібрані на реальних фото чеків (див. test/receipt_image_test.dart).
const receiptOcrWidth = 1050;
const receiptOcrWindow = 41;
const receiptOcrOffset = 15;

/// Адаптивний поріг за середнім у вікні [window]x[window] (через інтегральне
/// зображення - швидко для будь-якого вікна). [gray] - яскравість 0..255 по
/// рядках. Точка темніша за середнє навколо більш ніж на [offset] - чорна (0).
Uint8List binarizeAdaptive(Uint8List gray, int width, int height,
    {int window = receiptOcrWindow, int offset = receiptOcrOffset}) {
  final w1 = width + 1;
  final integral = Float64List(w1 * (height + 1));
  for (var y = 0; y < height; y++) {
    var row = 0.0;
    for (var x = 0; x < width; x++) {
      row += gray[y * width + x];
      integral[(y + 1) * w1 + x + 1] = integral[y * w1 + x + 1] + row;
    }
  }
  final r = window ~/ 2;
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final y0 = y - r < 0 ? 0 : y - r;
    final y1 = y + r + 1 > height ? height : y + r + 1;
    for (var x = 0; x < width; x++) {
      final x0 = x - r < 0 ? 0 : x - r;
      final x1 = x + r + 1 > width ? width : x + r + 1;
      final sum = integral[y1 * w1 + x1] - integral[y0 * w1 + x1] - integral[y1 * w1 + x0] + integral[y0 * w1 + x0];
      final mean = sum / ((y1 - y0) * (x1 - x0));
      out[y * width + x] = gray[y * width + x] > mean - offset ? 255 : 0;
    }
  }
  return out;
}

/// Фото (байти jpg/png) → png, готовий для Tesseract. null - не вдалося прочитати.
Uint8List? prepareReceiptImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // пошкоджений чи невідомий файл
  }
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  if (image.width > receiptOcrWidth) {
    image = img.copyResize(image, width: receiptOcrWidth, interpolation: img.Interpolation.average);
  }
  final w = image.width, h = image.height;
  final gray = Uint8List(w * h);
  for (final p in image) {
    gray[p.y * w + p.x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
  }
  final bw = binarizeAdaptive(gray, w, h);
  final out = img.Image(width: w, height: h, numChannels: 1);
  for (final p in out) {
    p.r = bw[p.y * w + p.x];
  }
  return img.encodePng(out);
}
