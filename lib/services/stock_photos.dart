import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint, visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/repository.dart';
import '../logic/receipt_image.dart' show decodeReceiptPhoto;

/// Довша сторона повного фото складу, px (мета - 40-70 КБ у WebP).
const kPhotoFullSide = 800;

/// Довша сторона мініатюри для списків, px (5-10 КБ).
const kPhotoThumbSide = 200;

/// Фото, готове до запису: повне й мініатюра (уже закодовані) та їхні розміри.
class PhotoPair {
  final Uint8List full;
  final Uint8List thumb;
  final int width, height;
  final int thumbWidth, thumbHeight;
  const PhotoPair(this.full, this.thumb, this.width, this.height, this.thumbWidth, this.thumbHeight);
}

/// Як фото кодується у файл.
abstract class PhotoEncoder {
  /// Розширення файлів (webp, jpg).
  String get ext;

  /// Будь-яке фото (jpg/png/webp…) → зменшене повне й мініатюра; без EXIF
  /// (зокрема без GPS-координат), поворот за EXIF уже застосовано.
  Future<PhotoPair> encode(Uint8List source);
}

/// JPEG засобами Dart - там, де системного WebP немає (комп'ютер, тести).
class JpegPhotoEncoder implements PhotoEncoder {
  const JpegPhotoEncoder();

  @override
  String get ext => 'jpg';

  @override
  Future<PhotoPair> encode(Uint8List source) =>
      compute(preparePhoto, PhotoArgs(source, fullQuality: 82, thumbQuality: 78));
}

/// WebP системним кодувальником (Android/iOS). Dart готує зменшене фото без
/// EXIF і з правильним поворотом (як проміжний JPEG найвищої якості), а
/// система кодує його у WebP без зміни розміру.
class WebpPhotoEncoder implements PhotoEncoder {
  const WebpPhotoEncoder();

  @override
  String get ext => 'webp';

  @override
  Future<PhotoPair> encode(Uint8List source) async {
    final prep = await compute(preparePhoto, PhotoArgs(source, fullQuality: 95, thumbQuality: 92));
    Future<Uint8List> webp(Uint8List b, int w, int h, int q) => FlutterImageCompress.compressWithList(
        b,
        minWidth: w,
        minHeight: h,
        quality: q,
        format: CompressFormat.webp,
        keepExif: false);
    return PhotoPair(
      await webp(prep.full, prep.width, prep.height, 80),
      await webp(prep.thumb, prep.thumbWidth, prep.thumbHeight, 75),
      prep.width,
      prep.height,
      prep.thumbWidth,
      prep.thumbHeight,
    );
  }
}

/// Параметри [preparePhoto] (для окремого потоку).
class PhotoArgs {
  final Uint8List bytes;
  final int fullQuality, thumbQuality;
  const PhotoArgs(this.bytes, {required this.fullQuality, required this.thumbQuality});
}

/// Розібрати фото, повернути за EXIF, прибрати EXIF, зменшити до
/// [kPhotoFullSide] і [kPhotoThumbSide] (не збільшуючи) і закодувати в JPEG.
/// Окремий потік: велике фото розбирається довго.
PhotoPair preparePhoto(PhotoArgs a) {
  final src = decodeReceiptPhoto(a.bytes);
  if (src == null) throw const FormatException('файл не є фото');
  final upright = img.bakeOrientation(src);
  // жодних метаданих: ні GPS (де зроблено фото), ні моделі телефона
  upright.exif = img.ExifData();
  final full = _fit(upright, kPhotoFullSide);
  final thumb = _fit(full, kPhotoThumbSide);
  thumb.exif = img.ExifData();
  return PhotoPair(
    img.encodeJpg(full, quality: a.fullQuality),
    img.encodeJpg(thumb, quality: a.thumbQuality),
    full.width,
    full.height,
    thumb.width,
    thumb.height,
  );
}

img.Image _fit(img.Image im, int side) {
  if (math.max(im.width, im.height) <= side) return im;
  return im.width >= im.height
      ? img.copyResize(im, width: side, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: side, interpolation: img.Interpolation.average);
}

/// Розміри закодованого фото (null - файл зіпсований). Для перевірки, що
/// запис вдався.
(int, int)? photoSize(Uint8List bytes) {
  try {
    final im = decodeReceiptPhoto(bytes);
    return im == null ? null : (im.width, im.height);
  } catch (_) {
    return null;
  }
}

/// Фото номенклатури складу.
///
/// Файли - у теці застосунку `stock_photos/`: повне `<id>.webp` і мініатюра
/// `<id>_t.webp` (де WebP недоступний - `.jpg`). У базі - лише назва
/// повного файлу (вона ж - шлях у файловому сховищі сервера); старі записи
/// могли містити повний шлях до файлу - такі показуються як є, доки
/// [upgradeOld] їх не перетисне.
class StockPhotos {
  StockPhotos._();

  static String? _dir;

  /// Тека з фото (після [init]).
  static String? get dir => _dir;

  /// Тести: своя тека.
  @visibleForTesting
  static set debugDir(String? d) => _dir = d;

  /// Кодувальник: WebP на телефоні, JPEG деінде.
  static PhotoEncoder encoder =
      Platform.isAndroid || Platform.isIOS ? const WebpPhotoEncoder() : const JpegPhotoEncoder();

  /// Знайти теку з фото (один раз під час запуску).
  static Future<void> init() async {
    _dir ??= p.join((await getApplicationSupportDirectory()).path, 'stock_photos');
  }

  /// Камера є лише на телефоні (на комп'ютері image_picker вміє тільки файли).
  static bool get cameraSupported => Platform.isAndroid || Platform.isIOS;

  /// Старий запис: повний шлях до файлу (до перетискання).
  static bool isLegacy(String photo) => p.isAbsolute(photo);

  /// Назва мініатюри для фото [name]: `<id>_t.<ext>`.
  static String thumbName(String name) =>
      '${p.basenameWithoutExtension(name)}_t${p.extension(name)}';

  /// Повне фото на диску (null - фото немає або тека ще невідома).
  static String? fullPath(String? photo) {
    if (photo == null || photo.isEmpty) return null;
    if (isLegacy(photo)) return photo;
    final d = _dir;
    return d == null ? null : p.join(d, photo);
  }

  /// Мініатюра на диску (у старих записів - саме фото).
  static String? thumbPath(String? photo) {
    if (photo == null || photo.isEmpty) return null;
    if (isLegacy(photo)) return photo;
    final d = _dir;
    return d == null ? null : p.join(d, thumbName(photo));
  }

  /// Перетиснути фото [source] і записати повне й мініатюру. Повертає назву
  /// для бази. Записане перевіряється (розбирається назад); зіпсоване не
  /// зберігається - кидає [FormatException].
  static Future<String> save(Uint8List source) async {
    final d = _dir;
    if (d == null) throw StateError('тека фото невідома (StockPhotos.init)');
    final pair = await encoder.encode(source);
    _check(pair.full, pair.width, pair.height, kPhotoFullSide);
    _check(pair.thumb, pair.thumbWidth, pair.thumbHeight, kPhotoThumbSide);
    await Directory(d).create(recursive: true);
    final name = '${const Uuid().v4()}.${encoder.ext}';
    final full = File(p.join(d, name));
    final thumb = File(p.join(d, thumbName(name)));
    try {
      await _writeAtomic(thumb, pair.thumb);
      await _writeAtomic(full, pair.full);
    } catch (_) {
      for (final f in [full, thumb]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      rethrow;
    }
    return name;
  }

  static void _check(Uint8List bytes, int w, int h, int side) {
    final size = photoSize(bytes);
    if (bytes.isEmpty || size == null) throw const FormatException('фото не вдалося стиснути');
    if (size.$1 != w || size.$2 != h || math.max(w, h) > side || w <= 0 || h <= 0) {
      throw FormatException('неочікуваний розмір фото ${size.$1}×${size.$2}');
    }
  }

  /// Запис через тимчасовий файл: обірваний запис не лишає половину фото.
  static Future<void> _writeAtomic(File f, Uint8List bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  /// Зробити/обрати фото й зберегти (null - скасовано).
  static Future<String?> pick({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera && cameraSupported ? ImageSource.camera : ImageSource.gallery,
      // запас для якісного зменшення до 800 px
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 95,
    );
    if (x == null) return null;
    return save(await x.readAsBytes());
  }

  /// Прибрати фото (лише наше: з теки застосунку) - повне й мініатюру.
  static Future<void> remove(String? photo) async {
    if (photo == null || photo.isEmpty) return;
    final paths = isLegacy(photo)
        ? [if (photo.contains('stock_photos')) photo]
        : [fullPath(photo), thumbPath(photo)].whereType<String>();
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Позначка: старі фото вже перетиснуто.
  static const upgradedKey = 'stock_photos_v2';

  /// Один раз після оновлення: перетиснути старі фото (повний шлях у базі) у
  /// новий формат. Кожне перевіряється; запис у базі змінюється, лише якщо
  /// фото тим часом не міняли, і лише тоді старий файл видаляється. Зіпсоване
  /// чи нечитне фото лишається як було (воно й далі показується). Фото, якого
  /// вже немає на диску, прибирається із запису. Повертає скільки перетиснуто.
  static Future<int> upgradeOld(Repository repo) async {
    if (await repo.getMeta(upgradedKey) != null) return 0;
    var done = 0;
    for (final (id, photo) in await repo.stockPhotoRefs()) {
      if (!isLegacy(photo)) continue;
      final f = File(photo);
      try {
        if (!await f.exists()) {
          await repo.replaceStockPhoto(id, photo, null);
          continue;
        }
        final name = await save(await f.readAsBytes());
        if (await repo.replaceStockPhoto(id, photo, name)) {
          await remove(photo);
          done++;
        } else {
          await remove(name); // запис уже змінили - нове фото не знадобилось
        }
      } catch (e) {
        debugPrint('Фото складу $id не перетиснуто: $e');
      }
    }
    await repo.setMeta(upgradedKey, '1');
    return done;
  }

  /// Прибрати з теки файли, на які не посилається жоден запис (зокрема
  /// видалений: його фото знадобиться, якщо видалення скасують). Лише давні
  /// файли - щойно зроблене фото може ще не бути збережене в записі.
  static Future<int> sweepOrphans(Repository repo,
      {Duration olderThan = const Duration(days: 1)}) async {
    final d = _dir;
    if (d == null || !await Directory(d).exists()) return 0;
    final keep = <String>{};
    for (final (_, photo) in await repo.stockPhotoRefs()) {
      if (isLegacy(photo)) {
        keep.add(p.basename(photo));
      } else {
        keep
          ..add(photo)
          ..add(thumbName(photo));
      }
    }
    final cutoff = clock.now().subtract(olderThan);
    var removed = 0;
    await for (final e in Directory(d).list()) {
      if (e is! File || keep.contains(p.basename(e.path))) continue;
      try {
        if ((await e.lastModified()).isAfter(cutoff)) continue;
        await e.delete();
        removed++;
      } catch (_) {}
    }
    return removed;
  }
}
