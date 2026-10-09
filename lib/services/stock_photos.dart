import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Фото номенклатури: знімок камерою або вибір «з галереї». Фото копіюється в теку застосунку, щоб не зникло, коли
/// користувач прибере його з галереї.
class StockPhotos {
  StockPhotos._();

  /// Камера є лише на телефоні (на комп'ютері image_picker вміє тільки файли).
  static bool get cameraSupported => Platform.isAndroid || Platform.isIOS;

  /// Зробити/обрати фото й повернути шлях до копії (null — скасовано).
  static Future<String?> pick({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera && cameraSupported ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 82,
    );
    if (x == null) return null;
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'stock_photos'));
    await dir.create(recursive: true);
    var ext = p.extension(x.path).toLowerCase();
    if (ext.isEmpty) ext = '.jpg';
    final dest = p.join(dir.path, 'photo_${DateTime.now().microsecondsSinceEpoch}$ext');
    await File(x.path).copy(dest);
    return dest;
  }

  /// Прибрати старе фото (лише наше, з теки застосунку).
  static Future<void> remove(String? path) async {
    if (path == null || !path.contains('stock_photos')) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
