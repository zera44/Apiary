// Після `flutter create` підставляє людську назву застосунку
// ("Vulyk") та іконку (tool/app_icon, див. tool/make_app_icon.py) у
// згенеровані платформні файли.
//
//   dart run tool/patch_platforms.dart
import 'dart:io';

const appName = 'Vulyk';

void patch(String path, String from, String to) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  if (!s.contains(from)) return;
  f.writeAsStringSync(s.replaceAll(from, to));
  stdout.writeln('✓ $path');
}

/// Дозволи: інтернет (фонова синхронізація), камера (сканер QR вуликів),
/// сповіщення й автозапуск після перезавантаження (нагадування про обхід),
/// мікрофон (голосовий ввід Vosk).
/// У release-маніфесті, що генерує flutter create, їх немає. Вставляються
/// перед <application> лише ті, яких бракує.
void _patchAndroidPermissions(String path) {
  final f = File(path);
  if (!f.existsSync()) return;
  final s = f.readAsStringSync();
  final missing = [
    for (final perm in ['INTERNET', 'CAMERA', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'VIBRATE', 'RECORD_AUDIO'])
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
    // плагіни (Tesseract, Vosk) приносять бібліотеки й для x86/x86_64, а
    // збірка CI - лише ARM (як і Flutter у ній): x86 не вкладаємо. Лише в CI:
    // локальний запуск на емуляторі x86_64 без них не працював би.
    const x86 = ['**/x86/**', '**/x86_64/**'];
    final ci = Platform.environment['CI'] == 'true';
    final excl = !ci
        ? ''
        : kts
            ? '            excludes += setOf(${x86.map((e) => '"$e"').join(', ')})\n'
            : '            excludes += [${x86.map((e) => "'$e'").join(', ')}]\n';
    final block = kts
        ? '    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n$excl        }\n    }\n'
        : '    packagingOptions {\n        jniLibs {\n            useLegacyPackaging true\n$excl        }\n    }\n';
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

/// Дані застосунку (координати пасік, історія) не йдуть у хмарні резервні
/// копії Google / adb backup. Перенесення на новий телефон напряму
/// (device-transfer) лишається дозволеним.
/// Запрошувальне посилання: схема vulyk://join?t=<код> відкриває Vulyk
/// (на неї перенаправляє функція join, див. supabase/functions/join).
void _patchAndroidInviteLink() {
  final mf = File('android/app/src/main/AndroidManifest.xml');
  if (!mf.existsSync()) return;
  final s = mf.readAsStringSync();
  if (s.contains('android:scheme="vulyk"')) return;
  final i = s.indexOf('</activity>');
  if (i < 0) {
    stderr.writeln('✗ AndroidManifest.xml: не знайдено <activity> для посилань');
    exit(1);
  }
  const filter = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="vulyk" android:host="join"/>
            </intent-filter>
        ''';
  mf.writeAsStringSync('${s.substring(0, i)}$filter${s.substring(i)}');
  stdout.writeln('✓ AndroidManifest.xml (посилання-запрошення vulyk://join)');
}

void _patchAndroidBackup() {
  final mf = File('android/app/src/main/AndroidManifest.xml');
  if (!mf.existsSync()) return;
  final s = mf.readAsStringSync();
  if (!s.contains('android:allowBackup')) {
    final m = RegExp(r'<application\b').firstMatch(s);
    if (m == null) return;
    mf.writeAsStringSync('${s.substring(0, m.end)}\n        android:allowBackup="false"'
        '\n        android:dataExtractionRules="@xml/data_extraction_rules"${s.substring(m.end)}');
    stdout.writeln('✓ AndroidManifest.xml (без хмарних резервних копій)');
  }
  final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
  if (!rules.existsSync()) {
    rules.createSync(recursive: true);
    rules.writeAsStringSync('<?xml version="1.0" encoding="utf-8"?>\n'
        '<data-extraction-rules>\n'
        '    <cloud-backup>\n'
        '        <exclude domain="root" />\n'
        '        <exclude domain="file" />\n'
        '        <exclude domain="database" />\n'
        '        <exclude domain="sharedpref" />\n'
        '        <exclude domain="external" />\n'
        '    </cloud-backup>\n'
        '</data-extraction-rules>\n');
  }
}

/// Підпис release-APK власним ключем із секретів CI (змінні середовища
/// APIARY_KEYSTORE_PATH / APIARY_KEYSTORE_PASSWORD / APIARY_KEY_ALIAS /
/// APIARY_KEY_PASSWORD під час збірки). Вмикається APIARY_SIGNING=1. Якщо
/// файл gradle змінити не вдалося, збірка ПАДАЄ — щоб APK з іншим підписом не
/// вийшов непомітно.
void _patchAndroidSigning() {
  // увімкнено лише в Android-збірці CI; сам ключ і паролі gradle бере зі
  // змінних середовища вже під час збірки
  if (Platform.environment['APIARY_SIGNING'] != '1') return;
  for (final name in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final f = File(name);
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    if (s.contains('apiaryRelease')) return;
    final kts = name.endsWith('.kts');
    final use = kts
        ? RegExp(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)')
        : RegExp(r'signingConfig\s+signingConfigs\.debug');
    final bt = RegExp(r'^[ \t]*buildTypes\s*\{', multiLine: true).firstMatch(s);
    if (!use.hasMatch(s) || bt == null) {
      stderr.writeln('✗ $name: не знайдено, куди вставити підпис release');
      exit(1);
    }
    const env = 'System.getenv';
    final block = kts
        ? '    signingConfigs {\n'
            '        create("apiaryRelease") {\n'
            '            storeFile = file($env("APIARY_KEYSTORE_PATH"))\n'
            '            storePassword = $env("APIARY_KEYSTORE_PASSWORD")\n'
            '            keyAlias = $env("APIARY_KEY_ALIAS")\n'
            '            keyPassword = $env("APIARY_KEY_PASSWORD")\n'
            '        }\n'
            '    }\n'
        : '    signingConfigs {\n'
            '        apiaryRelease {\n'
            '            storeFile file($env("APIARY_KEYSTORE_PATH"))\n'
            '            storePassword $env("APIARY_KEYSTORE_PASSWORD")\n'
            '            keyAlias $env("APIARY_KEY_ALIAS")\n'
            '            keyPassword $env("APIARY_KEY_PASSWORD")\n'
            '        }\n'
            '    }\n';
    s = s.substring(0, bt.start) + block + s.substring(bt.start);
    s = s.replaceFirst(
        use,
        kts
            ? 'signingConfig = signingConfigs.getByName("apiaryRelease")'
            : 'signingConfig signingConfigs.apiaryRelease');
    f.writeAsStringSync(s);
    stdout.writeln('✓ $name (підпис власним ключем)');
    return;
  }
  stderr.writeln('✗ не знайдено android/app/build.gradle(.kts)');
  exit(1);
}

/// Іконка застосунку: копіює готові файли з tool/app_icon (їх генерує
/// tool/make_app_icon.py з design/app_icon/app_icon.pdf) поверх типових
/// іконок Flutter. Для Android — ще й адаптивна іконка (Android 8+) і
/// окрема біла іконка сповіщень.
void _copyAppIcon() {
  void copyTree(String from, String to) {
    final src = Directory(from);
    if (!src.existsSync() || !Directory(to).existsSync()) return;
    var n = 0;
    for (final e in src.listSync(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.substring(src.path.length + 1);
      final dst = File('$to/$rel');
      dst.parent.createSync(recursive: true);
      e.copySync(dst.path);
      n++;
    }
    stdout.writeln('✓ $to (іконка: $n файлів)');
  }

  // Без готових файлів збірка тихо брала типову іконку Flutter (а сповіщення —
  // неіснуючу ic_notification), тож їх відсутність — помилка.
  if (!File('tool/app_icon/android/res/mipmap-anydpi-v26/ic_launcher.xml').existsSync()) {
    stderr.writeln('✗ немає файлів іконки в tool/app_icon — запустіть python3 tool/make_app_icon.py');
    exit(1);
  }
  copyTree('tool/app_icon/android/res', 'android/app/src/main/res');
}

/// Помічник «Пасічник»: розпізнавач мови Android (запасний, коли моделі
/// Vosk ще немає) і синтезатор (читання відповідей уголос). З Android 11
/// застосунок бачить ці служби, лише якщо назве їх у <queries>.
void _patchAndroidSpeechQueries() {
  final mf = File('android/app/src/main/AndroidManifest.xml');
  if (!mf.existsSync()) return;
  var s = mf.readAsStringSync();
  const actions = ['android.speech.RecognitionService', 'android.intent.action.TTS_SERVICE'];
  final missing = [for (final a in actions) if (!s.contains('"$a"')) a];
  if (missing.isEmpty) return;
  final intents = [
    for (final a in missing)
      '        <intent>\n            <action android:name="$a" />\n        </intent>\n'
  ].join();
  final q = s.indexOf('<queries>');
  if (q >= 0) {
    final at = q + '<queries>'.length;
    s = '${s.substring(0, at)}\n$intents${s.substring(at)}';
  } else {
    final end = s.lastIndexOf('</manifest>');
    if (end < 0) return;
    s = '${s.substring(0, end)}    <queries>\n$intents    </queries>\n${s.substring(end)}';
  }
  mf.writeAsStringSync(s);
  stdout.writeln('✓ AndroidManifest.xml (розпізнавання мови й синтезатор для помічника)');
}

/// Мінімальна версія Android - 7.0 (API 24): так вимагає ONNX Runtime, що
/// розпізнає чеки (плагін paddle_ocr_flutter). Старіших телефонів практично немає.
void _patchAndroidMinSdk() {
  for (final name in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final f = File(name);
    if (!f.existsSync()) continue;
    final s = f.readAsStringSync();
    final t = s.replaceAll('flutter.minSdkVersion', '24');
    if (t == s) {
      stdout.writeln('· $name: minSdk не змінено (немає flutter.minSdkVersion)');
      return;
    }
    f.writeAsStringSync(t);
    stdout.writeln('✓ $name (minSdk 24)');
    return;
  }
}

void main() {
  _copyAppIcon();
  patch('android/app/src/main/AndroidManifest.xml', 'android:label="apiary"',
      'android:label="$appName"');
  _patchAndroidPermissions('android/app/src/main/AndroidManifest.xml');
  _patchAndroidCompressedLibs();
  _patchAndroidNotifications();
  _patchAndroidBackup();
  _patchAndroidInviteLink();
  _patchAndroidSpeechQueries();
  _patchAndroidMinSdk();
  _patchAndroidSigning();
  _patchGradleProperties();
  patch('linux/runner/my_application.cc', '"apiary"', '"$appName"');
  patch('ios/Runner/Info.plist', '<string>Apiary</string>', '<string>$appName</string>');
  patch('macos/Runner/Configs/AppInfo.xcconfig', 'PRODUCT_NAME = apiary', 'PRODUCT_NAME = $appName');
}
