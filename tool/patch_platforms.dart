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

/// Дозволи: інтернет (фонова синхронізація), камера (сканер QR вуликів),
/// сповіщення й автозапуск після перезавантаження (нагадування про обхід).
/// У release-маніфесті, що генерує flutter create, їх немає. Вставляються
/// перед <application> лише ті, яких бракує.
void _patchAndroidPermissions(String path) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  final missing = [
    for (final perm in ['INTERNET', 'CAMERA', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'VIBRATE'])
      if (!s.contains('android.permission.$perm"')) perm
  ];
  if (missing.isEmpty) return;
  final idx = s.indexOf('<application');
  if (idx < 0) return;
  // вставити з тим самим відступом, що й у <application>, незалежно від
  // конкретної кількості пробілів у шаблоні flutter create
  final lineStart = s.lastIndexOf('\n', idx) + 1;
  final indent = s.substring(lineStart, idx);
  final perms = [
    for (final perm in missing) '$indent<uses-permission android:name="android.permission.$perm"/>\n'
  ].join();
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

/// Сканер QR — ML Kit через Google Play Services (не вкладений у APK):
/// +~0,6 МБ замість 3–10 МБ.
void _patchGradleProperties() {
  final f = File('android/gradle.properties');
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  if (s.contains('mobile_scanner.useUnbundled')) return;
  f.writeAsStringSync('${s.trimRight()}\ndev.steenbakker.mobile_scanner.useUnbundled=true\n');
  stdout.writeln('✓ android/gradle.properties (сканер QR без вкладеного ML Kit)');
}

/// Нагадування про обхід (flutter_local_notifications): приймачі
/// відкладених сповіщень у маніфесті + десугаринг Java у gradle.
void _patchAndroidNotifications() {
  final mf = File('android/app/src/main/AndroidManifest.xml');
  if (mf.existsSync()) {
    final s = mf.readAsStringSync();
    if (!s.contains('ScheduledNotificationReceiver') && s.contains('</application>')) {
      const receivers = '''
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
''';
      mf.writeAsStringSync(s.replaceFirst('</application>', '$receivers    </application>'));
      stdout.writeln('✓ AndroidManifest.xml (приймачі сповіщень)');
    }
  }
  for (final name in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final f = File(name);
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    if (s.contains('oreLibraryDesugaring')) return;
    final kts = name.endsWith('.kts');
    final flag = kts ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
    final m = RegExp(r'compileOptions\s*\{\s*\n').firstMatch(s);
    if (m != null) {
      s = '${s.substring(0, m.end)}        $flag\n${s.substring(m.end)}';
    } else {
      final a = RegExp(r'^android\s*\{\s*\n', multiLine: true).firstMatch(s);
      if (a == null) return;
      final opts = kts
          ? '    compileOptions {\n        $flag\n        sourceCompatibility = JavaVersion.VERSION_17\n        targetCompatibility = JavaVersion.VERSION_17\n    }\n'
          : '    compileOptions {\n        $flag\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n    }\n';
      s = '${s.substring(0, a.end)}$opts${s.substring(a.end)}';
    }
    s += kts
        ? '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        : "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
    f.writeAsStringSync(s);
    stdout.writeln('✓ $name (десугаринг для сповіщень)');
    return;
  }
}

void main() {
  patch('android/app/src/main/AndroidManifest.xml', 'android:label="apiary"',
      'android:label="$appName"');
  _patchAndroidPermissions('android/app/src/main/AndroidManifest.xml');
  _patchAndroidCompressedLibs();
  _patchAndroidNotifications();
  _patchGradleProperties();
  // Windows: автозапущений (--autostart) застосунок стартує згорнутим,
  // без відбирання фокуса
  patch(
      'windows/runner/win32_window.cpp',
      'ShowWindow(window_handle_, SW_SHOWNORMAL)',
      'ShowWindow(window_handle_, wcsstr(GetCommandLineW(), L"--autostart") ? SW_SHOWMINNOACTIVE : SW_SHOWNORMAL)');
  patch('linux/runner/my_application.cc', '"apiary"', '"$appName"');
  patch('ios/Runner/Info.plist', '<string>Apiary</string>', '<string>$appName</string>');
  patch('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME = apiary', 'PRODUCT_NAME = $appName');
}
