import 'dart:io';
import 'dart:typed_data';

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/l10n/l10n.dart';
import 'package:apiary/screens/stock_screen.dart';
import 'package:apiary/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:apiary/services/stock_photos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Фото «з камери»: [w]×[h], з EXIF (поворот, GPS, модель телефона).
Uint8List cameraJpeg(int w, int h, {int orientation = 1}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 120);
    }
  }
  im.exif.imageIfd.orientation = orientation;
  im.exif.imageIfd[0x010F] = img.IfdValueAscii('PhoneMaker'); // Make
  im.exif.gpsIfd[0x0001] = img.IfdValueAscii('N'); // GPSLatitudeRef
  return img.encodeJpg(im, quality: 95);
}

bool noExif(img.Image im) =>
    im.exif.imageIfd.isEmpty && im.exif.gpsIfd.isEmpty && im.exif.exifIfd.isEmpty;

/// Кодувальник, що повертає зіпсоване фото.
class _BrokenEncoder implements PhotoEncoder {
  @override
  String get ext => 'webp';
  @override
  Future<PhotoPair> encode(Uint8List source) async =>
      PhotoPair(Uint8List(0), Uint8List(0), 800, 600, 200, 150);
}

/// «WebP»-кодувальник (у тестах системного WebP немає - підміна з тими самими
/// розмірами, щоб перевірити назви файлів і перевірку результату).
class _FakeWebpEncoder implements PhotoEncoder {
  @override
  String get ext => 'webp';
  @override
  Future<PhotoPair> encode(Uint8List source) async =>
      preparePhoto(PhotoArgs(source, fullQuality: 80, thumbQuality: 75));
}

void main() {
  late Directory dir;
  late Repository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('apiary_photos_');
    StockPhotos.debugDir = p.join(dir.path, 'stock_photos');
    StockPhotos.encoder = const JpegPhotoEncoder();
    repo = Repository(await AppDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    await repo.init();
  });
  tearDown(() async {
    await repo.db.close();
    StockPhotos.debugDir = null;
    dir.deleteSync(recursive: true);
  });

  group('підготовка фото', () {
    test('довша сторона - 800, мініатюра - 200, пропорції збережено', () {
      final r = preparePhoto(PhotoArgs(cameraJpeg(2000, 1000), fullQuality: 82, thumbQuality: 78));
      expect((r.width, r.height), (800, 400));
      expect((r.thumbWidth, r.thumbHeight), (200, 100));
      expect(photoSize(r.full), (800, 400));
      expect(photoSize(r.thumb), (200, 100));
    });

    test('поворот за EXIF застосовано, EXIF (зокрема GPS) прибрано', () {
      final src = cameraJpeg(1000, 500, orientation: 6);
      final decodedSrc = img.decodeJpg(src)!;
      expect(decodedSrc.exif.gpsIfd.isEmpty, isFalse); // GPS справді був
      final r = preparePhoto(PhotoArgs(src, fullQuality: 82, thumbQuality: 78));
      // повернуто на 90°: було 1000×500 «лежачи» - стало стоячи
      expect((r.width, r.height), (400, 800));
      expect(noExif(img.decodeJpg(r.full)!), isTrue);
      expect(noExif(img.decodeJpg(r.thumb)!), isTrue);
    });

    test('маленьке фото не збільшується', () {
      final r = preparePhoto(PhotoArgs(cameraJpeg(120, 90), fullQuality: 82, thumbQuality: 78));
      expect((r.width, r.height), (120, 90));
      expect((r.thumbWidth, r.thumbHeight), (120, 90));
    });

    test('не фото - зрозуміла помилка', () {
      expect(() => preparePhoto(PhotoArgs(Uint8List.fromList([1, 2, 3, 4, 5]),
          fullQuality: 82, thumbQuality: 78)), throwsFormatException);
    });

    test('розмір файлів - у межах цілі', () {
      final r = preparePhoto(PhotoArgs(cameraJpeg(3000, 2000), fullQuality: 82, thumbQuality: 78));
      expect(r.full.length, lessThan(120 * 1024));
      expect(r.thumb.length, lessThan(15 * 1024));
    });
  });

  group('збереження', () {
    test('JPEG там, де WebP недоступний: повне й мініатюра, у базі - лише назва', () async {
      final name = await StockPhotos.save(cameraJpeg(1600, 1200));
      expect(name, matches(RegExp(r'^[0-9a-f-]{36}\.jpg$')));
      expect(p.isAbsolute(name), isFalse);
      final full = File(StockPhotos.fullPath(name)!), thumb = File(StockPhotos.thumbPath(name)!);
      expect(photoSize(await full.readAsBytes()), (800, 600));
      expect(photoSize(await thumb.readAsBytes()), (200, 150));
      expect(p.basename(thumb.path), StockPhotos.thumbName(name));
      // жодних тимчасових файлів
      expect(Directory(StockPhotos.dir!).listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);

      await StockPhotos.remove(name);
      expect(await full.exists(), isFalse);
      expect(await thumb.exists(), isFalse);
    });

    test('на телефоні - WebP (назви .webp, мініатюра _t.webp)', () async {
      StockPhotos.encoder = _FakeWebpEncoder();
      final name = await StockPhotos.save(cameraJpeg(900, 900));
      expect(name, endsWith('.webp'));
      expect(StockPhotos.thumbPath(name), endsWith('_t.webp'));
      expect(await File(StockPhotos.thumbPath(name)!).exists(), isTrue);
    });

    test('зіпсований результат кодування не зберігається', () async {
      StockPhotos.encoder = _BrokenEncoder();
      await expectLater(StockPhotos.save(cameraJpeg(900, 600)), throwsFormatException);
      final d = Directory(StockPhotos.dir!);
      expect(d.existsSync() ? d.listSync() : const [], isEmpty);
    });

    test('старий запис (повний шлях) показується як є', () {
      const legacy = '/data/user/0/org.apiary.apiary/files/stock_photos/photo_1.jpg';
      expect(StockPhotos.isLegacy(legacy), isTrue);
      expect(StockPhotos.fullPath(legacy), legacy);
      expect(StockPhotos.thumbPath(legacy), legacy);
      expect(StockPhotos.fullPath(null), isNull);
    });
  });

  group('старі фото - один раз у новий формат', () {
    Future<String> legacyFile(String name, List<int> bytes) async {
      final f = File(p.join(StockPhotos.dir!, name));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      return f.path;
    }

    Future<Map<String, Object?>> row(String id) async =>
        (await repo.db.query('stock_items', where: 'id = ?', whereArgs: [id])).single;

    test('перетиснуто, перевірено, старий файл прибрано; повторно - нічого', () async {
      final ok = await repo.addStockItem('Цукор', 'кг');
      final okPath = await legacyFile('photo_1.jpg', cameraJpeg(1280, 960));
      await repo.updateStockItem(ok, photo: (okPath,));
      final gone = await repo.addStockItem('Рамки', 'шт');
      await repo.updateStockItem(gone, photo: (p.join(StockPhotos.dir!, 'photo_2.jpg'),));
      final bad = await repo.addStockItem('Ліки', 'уп');
      final badPath = await legacyFile('photo_3.jpg', [1, 2, 3]);
      await repo.updateStockItem(bad, photo: (badPath,));
      final deleted = await repo.addStockItem('Вощина', 'кг');
      final delPath = await legacyFile('photo_4.jpg', cameraJpeg(1000, 1000));
      await repo.updateStockItem(deleted, photo: (delPath,));
      await repo.deleteStockItem(deleted);
      final stamp = (await row(ok))['updated_at'];

      expect(await StockPhotos.upgradeOld(repo), 2);

      final okRow = await row(ok);
      final newName = okRow['photo'] as String;
      expect(StockPhotos.isLegacy(newName), isFalse);
      expect(photoSize(await File(StockPhotos.fullPath(newName)!).readAsBytes()), (800, 600));
      expect(await File(okPath).exists(), isFalse);
      // службова зміна: час зміни запису той самий
      expect(okRow['updated_at'], stamp);
      // файлу вже не було - запис без фото
      expect((await row(gone))['photo'], isNull);
      // зіпсоване лишається як було
      expect((await row(bad))['photo'], badPath);
      expect(await File(badPath).exists(), isTrue);
      // видалена позиція теж перетиснута (видалення можна скасувати)
      expect(StockPhotos.isLegacy((await row(deleted))['photo'] as String), isFalse);

      expect(await repo.getMeta(StockPhotos.upgradedKey), '1');
      expect(await StockPhotos.upgradeOld(repo), 0);
    });

    test('фото змінили, поки перетискали - чіпати не можна', () async {
      final id = await repo.addStockItem('Цукор', 'кг');
      await repo.updateStockItem(id, photo: ('нове.jpg',));
      expect(await repo.replaceStockPhoto(id, '/старий/шлях.jpg', 'інше.jpg'), isFalse);
      expect((await row(id))['photo'], 'нове.jpg');
    });
  });

  testWidgets('склад: у плитці - повне фото, у картці - мініатюра, дотик - на весь екран',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final name = (await tester.runAsync(() async {
      final n = await StockPhotos.save(cameraJpeg(1200, 900));
      final id = await repo.addStockItem('Цукор', 'кг');
      await repo.updateStockItem(id, photo: (n,));
      return n;
    }))!;
    String? shown(Finder f) {
      final img = tester.widget<Image>(find.descendant(of: f, matching: find.byType(Image)).first);
      final provider = img.image;
      final file = provider is ResizeImage ? provider.imageProvider : provider;
      return file is FileImage ? file.file.path : null;
    }

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: StockScreen(repo: repo)));
    await settle();
    // плитка складу (до 170 px) - повне фото
    expect(shown(find.byType(StockPhoto).first), StockPhotos.fullPath(name));
    await tester.tap(find.byType(StockPhoto).first);
    await settle();
    // картка позиції: фото 72×72 - мініатюра
    final small = find.descendant(of: find.byType(AlertDialog), matching: find.byType(StockPhoto));
    expect(tester.widget<StockPhoto>(small).thumb, isTrue);
    expect(shown(small), StockPhotos.thumbPath(name));
    await tester.tap(small);
    await settle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(shown(find.byType(InteractiveViewer)), StockPhotos.fullPath(name));
    await tester.tap(find.byTooltip(tr.close));
    await settle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('прибрати непотрібні файли: лише давні й ні на що не прив\'язані', () async {
    final keep = await StockPhotos.save(cameraJpeg(500, 400));
    final id = await repo.addStockItem('Цукор', 'кг');
    await repo.updateStockItem(id, photo: (keep,));
    final delKeep = await StockPhotos.save(cameraJpeg(500, 400));
    final del = await repo.addStockItem('Рамки', 'шт');
    await repo.updateStockItem(del, photo: (delKeep,));
    await repo.deleteStockItem(del);
    final oldOrphan = await StockPhotos.save(cameraJpeg(300, 300));
    final freshOrphan = await StockPhotos.save(cameraJpeg(300, 300));
    final longAgo = DateTime.now().subtract(const Duration(days: 3));
    for (final n in [keep, delKeep, oldOrphan]) {
      File(StockPhotos.fullPath(n)!).setLastModifiedSync(longAgo);
      File(StockPhotos.thumbPath(n)!).setLastModifiedSync(longAgo);
    }

    expect(await StockPhotos.sweepOrphans(repo), 2); // повне й мініатюра
    bool has(String n) =>
        File(StockPhotos.fullPath(n)!).existsSync() && File(StockPhotos.thumbPath(n)!).existsSync();
    expect(has(keep), isTrue);
    expect(has(delKeep), isTrue);
    expect(has(freshOrphan), isTrue); // щойно зроблене - може ще зберігатись
    expect(File(StockPhotos.fullPath(oldOrphan)!).existsSync(), isFalse);
  });
}
