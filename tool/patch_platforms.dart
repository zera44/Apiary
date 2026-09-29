// Після `flutter create` підставляє людську назву застосунку
// ("Моя пасіка") у згенеровані платформні файли.
//
//   dart run tool/patch_platforms.dart
import 'dart:io';

const appName = 'Моя пасіка';

void patch(String path, String from, String to) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  if (!s.contains(from)) return;
  f.writeAsStringSync(s.replaceAll(from, to));
  stdout.writeln('✓ $path');
}

/// Дозвіл на інтернет (фонова синхронізація) — у release-маніфесті, що
/// генерує flutter create, його немає. Вставляється перед <application>.
void _patchAndroidPermissions(String path) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  if (s.contains('android.permission.INTERNET')) return;
  final idx = s.indexOf('<application');
  if (idx < 0) return;
  // вставити з тим самим відступом, що й у <application>, незалежно від
  // конкретної кількості пробілів у шаблоні flutter create
  final lineStart = s.lastIndexOf('\n', idx) + 1;
  final indent = s.substring(lineStart, idx);
  final perms = '$indent<uses-permission android:name="android.permission.INTERNET"/>\n';
  f.writeAsStringSync(s.substring(0, lineStart) + perms + s.substring(lineStart));
  stdout.writeln('✓ $path (дозволи)');
}

/// Стискає нативні бібліотеки всередині APK (useLegacyPackaging): файл APK
/// значно менший; на телефоні бібліотеки розпаковуються під час
/// встановлення (займають трохи більше місця, швидкість роботи та сама).
void _patchAndroidCompressedLibs() {
  for (final name in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final f = File(name);
    if (!f.existsSync()) continue;
    final s = f.readAsStringSync();
    if (s.contains('useLegacyPackaging')) return;
    final kts = name.endsWith('.kts');
    final block = kts
        ? '    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n'
        : '    packagingOptions {\n        jniLibs {\n            useLegacyPackaging true\n        }\n    }\n';
    final m = RegExp(r'^android\s*\{\s*\n', multiLine: true).firstMatch(s);
    if (m == null) return;
    f.writeAsStringSync(s.substring(0, m.end) + block + s.substring(m.end));
    stdout.writeln('✓ $name (стиснення нативних бібліотек)');
    return;
  }
}

void main() {
  patch('android/app/src/main/AndroidManifest.xml', 'android:label="apiary"',
      'android:label="$appName"');
  _patchAndroidPermissions('android/app/src/main/AndroidManifest.xml');
  _patchAndroidCompressedLibs();
  patch('linux/runner/my_application.cc', '"apiary"', '"$appName"');
  patch('ios/Runner/Info.plist', '<string>Apiary</string>', '<string>$appName</string>');
  patch('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME = apiary', 'PRODUCT_NAME = $appName');
}
