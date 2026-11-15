import 'dart:convert';
import 'dart:io';

import 'package:apiary/services/supabase_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

SupabaseSession _session([String refresh = 'rt-1']) => SupabaseSession(
      accessToken: 'at',
      refreshToken: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(2000000000 * 1000),
      userId: '00000000-0000-0000-0000-000000000001',
      email: 'olena@gmail.com',
    );

void main() {
  late Directory dir;
  late FileSessionStore file;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('session_store');
    file = FileSessionStore(File('${dir.path}/supabase_session.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('вхід лежить у захищеному сховищі, у файлі його немає', () async {
    final store = SecureSessionStore(const FlutterSecureStorage(), file);
    expect(await store.read(), isNull);
    await store.write(_session());
    expect((await store.read())!.refreshToken, 'rt-1');
    expect(file.file.existsSync(), false, reason: 'відкритої копії немає');
    await store.write(_session('rt-2'));
    expect((await store.read())!.refreshToken, 'rt-2');
  });

  test('старий файл переноситься в сховище й стирається', () async {
    await file.write(_session('old'));
    expect(file.file.existsSync(), true);
    final store = SecureSessionStore(const FlutterSecureStorage(), file);
    expect((await store.read())!.refreshToken, 'old');
    expect(file.file.existsSync(), false);
    expect(await const FlutterSecureStorage().read(key: SecureSessionStore.key), isNotNull);
    expect((await store.read())!.refreshToken, 'old', reason: 'тепер читається зі сховища');
  });

  test('вихід стирає і сховище, і старий файл', () async {
    final store = SecureSessionStore(const FlutterSecureStorage(), file);
    await store.write(_session());
    await file.write(_session('left-over'));
    await store.write(null);
    expect(await store.read(), isNull);
    expect(file.file.existsSync(), false);
  });

  test('пошкоджений запис у сховищі - як «не входили»', () async {
    FlutterSecureStorage.setMockInitialValues({SecureSessionStore.key: 'це не json'});
    final store = SecureSessionStore(const FlutterSecureStorage(), file);
    expect(await store.read(), isNull);
    // а запис із коректним JSON без токенів - теж
    FlutterSecureStorage.setMockInitialValues({SecureSessionStore.key: jsonEncode({'user': {}})});
    expect(await store.read(), isNull);
  });
}
