// Бенчмарк швидкості (запуск: flutter test test_bench/bench_test.dart).
// Друкує рядки "BENCH|назва|мс" — CI збирає їх у звіт. Це JIT-режим на
// сервері, тож важливі не абсолютні числа, а порівняння до/після.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apiary/data/database.dart';
import 'package:apiary/data/repository.dart';
import 'package:apiary/data/sync_service.dart';
import 'package:apiary/logic/merge_layout.dart';
import 'package:apiary/ui/grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Медіана з [runs] запусків, мілісекунди.
Future<double> timeIt(Future<void> Function() body, {int runs = 5}) async {
  final t = <double>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    t.add(sw.elapsedMicroseconds / 1000);
  }
  t.sort();
  return t[t.length ~/ 2];
}

void report(String name, double ms) => print('BENCH|$name|${ms.toStringAsFixed(2)}');

Future<Repository> openRepo(String path) async {
  final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, path);
  final repo = Repository(db);
  await repo.init();
  return repo;
}

List<SceneCell> makeScene(int cols, int rows) {
  final items = <MergeItem<String>>[];
  final look = <String, ({String type, String? variant, String? icon, String? color})>{};
  var n = 0;
  for (var x = 0; x < cols; x++) {
    for (var y = 0; y < rows; y++) {
      final id = 'e${n++}';
      final hive = (x + y) % 3 != 0;
      items.add(MergeItem<String>(id, x, y, '${x ~/ 2}|${hive ? 'hive' : 'obstacle'}'));
      look[id] = (type: hive ? 'hive' : 'obstacle', variant: hive ? null : 'trees', icon: null, color: null);
    }
  }
  return buildScene<String>(items: items, look: look, selected: const {});
}

double paintMs(List<SceneCell> cells, double cs, Size size) {
  final painter = debugScenePainter(camera: Offset.zero - Offset(0, size.height), cs: cs, cells: cells);
  final sw = Stopwatch()..start();
  final rec = ui.PictureRecorder();
  painter.paint(Canvas(rec), size);
  rec.endRecording().dispose();
  sw.stop();
  return sw.elapsedMicroseconds / 1000;
}

void main() {
  setUpAll(sqfliteFfiInit);
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apiary_bench'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('bench: база', () async {
    var i = 0;
    String fresh() => p.join(tmp.path, 'b${i++}.db');

    // холодний старт бази (нова база: створення схеми + init)
    report('db_open_fresh', await timeIt(() async {
      final r = await openRepo(fresh());
      await r.db.close();
    }));

    // наповнення: 20 пасік x 100 елементів (25 груп по 4 клітинки)
    final path = fresh();
    var repo = await openRepo(path);
    final ids = <String>[];
    report('addGroup_x500', await timeIt(() async {
      for (var a = 0; a < 20; a++) {
        final id = await repo.addApiary('Пасіка $a');
        ids.add(id);
        for (var g = 0; g < 25; g++) {
          await repo.addGroup(id, {'0,0': 'hive', '1,0': 'hive', '0,1': 'hive', '1,1': 'obstacle:trees'},
              (g % 5) * 3, (g ~/ 5) * 3);
        }
      }
    }, runs: 1));

    report('listElements_100', await timeIt(() async {
      await repo.listElements(ids.first);
    }));

    // як завантажує екран "Мої пасіки"
    report('list_screen_load_20x100', await timeIt(() async {
      final list = await repo.listApiaries();
      for (final a in list) {
        await repo.listElements(a.id);
      }
    }));
    report('list_screen_load_20x100_single_query', await timeIt(() async {
      final list = await repo.listApiaries();
      await repo.listElementsByApiary([for (final a in list) a.id]);
    }));
    await repo.db.close();

    // повторний старт на заповненій базі
    report('db_open_populated', await timeIt(() async {
      final r = await openRepo(path);
      await r.db.close();
    }));

    // синхронізація-заглушка: 2000 несинхронізованих рядків
    repo = await openRepo(path);
    final sync = SyncService(repo);
    final sw = Stopwatch()..start();
    final res = await sync.syncOnce();
    sw.stop();
    print('BENCH|sync_stub_rows_${res.$2}|${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)}');
    // друга синхронізація без змін (порожня черга)
    report('sync_stub_idle', await timeIt(() async => sync.syncOnce()));
    await repo.db.close();
  });

  test('bench: сцена й малювання', () async {
    final items = <MergeItem<String>>[];
    final look = <String, ({String type, String? variant, String? icon, String? color})>{};
    for (var n = 0; n < 5000; n++) {
      final x = n % 100, y = n ~/ 100;
      items.add(MergeItem<String>('e$n', x, y, '${x ~/ 2}|hive'));
      look['e$n'] = (type: 'hive', variant: null, icon: null, color: null);
    }
    report('buildScene_5000', await timeIt(() async {
      buildScene<String>(items: items, look: look, selected: const {});
    }));

    final cells = makeScene(100, 50);
    // ~400 видимих клітинок (звичайний масштаб) і ~5000 (сильно віддалено)
    // (нижче — медіана з 7 кадрів)
    final a = <double>[], b = <double>[];
    for (var i = 0; i < 7; i++) {
      a.add(paintMs(cells, 28, const Size(400, 800)));
      b.add(paintMs(cells, 8, const Size(800, 1000)));
    }
    a.sort();
    b.sort();
    report('paint_frame_cs28', a[3]);
    report('paint_frame_cs8_5000cells', b[3]);
  });
}
