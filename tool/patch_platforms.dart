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

/// Дозволи, потрібні для карти вибору місця пасіки (завантаження тайлів
/// OpenStreetMap і геолокація) — вставляються перед <application>, якщо
/// їх ще немає у згенерованому файлі.
void _patchAndroidPermissions(String path) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  if (s.contains('ACCESS_FINE_LOCATION')) return;
  final idx = s.indexOf('<application');
  if (idx < 0) return;
  // вставити з тим самим відступом, що й у <application>, незалежно від
  // конкретної кількості пробілів у шаблоні flutter create
  final lineStart = s.lastIndexOf('\n', idx) + 1;
  final indent = s.substring(lineStart, idx);
  final perms = '$indent<uses-permission android:name="android.permission.INTERNET"/>\n'
      '$indent<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
      '$indent<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n';
  f.writeAsStringSync(s.substring(0, lineStart) + perms + s.substring(lineStart));
  stdout.writeln('✓ $path (дозволи)');
}

void main() {
  patch('android/app/src/main/AndroidManifest.xml', 'android:label="apiary"',
      'android:label="$appName"');
  _patchAndroidPermissions('android/app/src/main/AndroidManifest.xml');
  patch('linux/runner/my_application.cc', '"apiary"', '"$appName"');
  patch('ios/Runner/Info.plist', '<string>Apiary</string>', '<string>$appName</string>');
  patch('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME = apiary', 'PRODUCT_NAME = $appName');
}
