import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// Чи є на цьому пристрої камера для знімка (телефон/планшет).
bool get photoCameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Єдиний вибір фото в усьому додатку: [camera] - знімок камерою (де вона є),
/// інакше - галерея (на комп'ютері - файл). Розмір і якість задає викликач:
/// чек потребує великої роздільності, фото складу - меншої. null - скасовано.
Future<XFile?> pickPhoto({
  required bool camera,
  required double maxWidth,
  required double maxHeight,
  required int quality,
}) =>
    ImagePicker().pickImage(
      source: camera && photoCameraAvailable ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: quality,
    );
