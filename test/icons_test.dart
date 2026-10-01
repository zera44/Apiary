import 'dart:io';
import 'dart:ui' as ui;

import 'package:apiary/icons/app_icons.dart';
import 'package:apiary/icons/svg_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Перевірка іконок: реєстр assets/icons/icons.json, усі SVG-файли й сам
/// розбір SVG. Цей тест ловить типові помилки при додаванні/зміні іконок
/// (забули записати в реєстр, непідтримувана можливість SVG, зіпсований файл).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => AppIcons.load());

  group('реєстр іконок (assets/icons)', () {
    test('усі іконки завантажуються без жодної проблеми', () {
      expect(AppIcons.problems, isEmpty, reason: AppIcons.problems.join('\n'));
      expect(AppIcons.entries.length, greaterThanOrEqualTo(22));
    });

    test('кожен SVG-файл у папці записаний у icons.json (і навпаки)', () {
      final onDisk = <String>{};
      for (final f in Directory('assets/icons').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.svg')) continue;
        final rel = f.path.replaceAll('\\', '/').split('assets/icons/').last;
        if (rel.split('/').last.startsWith('_')) continue; // _template.svg тощо
        onDisk.add(rel);
      }
      final registered = {for (final e in AppIcons.entries) e.file};
      expect(onDisk.difference(registered), isEmpty,
          reason: 'файли є, але їх немає в icons.json');
      expect(registered.difference(onDisk), isEmpty,
          reason: 'в icons.json є файли, яких немає');
    });

    test('підпапка кожної іконки оголошена в pubspec.yaml (assets)', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final e in AppIcons.entries) {
        final dir = e.file.contains('/') ? e.file.substring(0, e.file.lastIndexOf('/') + 1) : '';
        expect(pubspec.contains('assets/icons/$dir'), isTrue,
            reason: 'додайте "- assets/icons/$dir" у pubspec.yaml → flutter → assets');
      }
    });

    test('списки вибору: іконки об\'єкта й варіанти перешкоди - з реєстру', () {
      expect([for (final (k, _) in AppIcons.pickable) k],
          ['beehive', 'hexagon', 'mountain', 'river', 'lake', 'trees', 'houses', 'fence', 'road']);
      expect([for (final (k, _) in AppIcons.obstacleVariants) k],
          ['mountain', 'river', 'lake', 'trees', 'houses', 'fence', 'road']);
      expect(AppIcons.obstacleVariants.first.$2, 'Інше');
      // усі іконки, що використовує код, існують
      for (final id in [
        'beehive', 'hexagon', 'mountain', 'menu', 'qr', 'rotate', 'trash', 'back_arrow',
        'pencil', 'eye', 'plus_circle', 'check', 'close', 'arrow_left', 'arrow_right', 'history',
      ]) {
        expect(AppIcons.has(id), isTrue, reason: 'немає іконки "$id"');
      }
    });

    test('іконки не виходять за межі viewBox (з урахуванням товщини лінії)', () {
      for (final e in AppIcons.entries) {
        final text = File('assets/icons/${e.file}').readAsStringSync();
        final icon = parseSvgIcon(text);
        for (final s in icon.shapes) {
          final b = s.path.getBounds().inflate(s.stroke ? s.strokeWidth / 2 : 0);
          expect(icon.viewBox.inflate(1.5).contains(b.topLeft) &&
                  icon.viewBox.inflate(1.5).contains(b.bottomRight),
              isTrue,
              reason: '${e.id}: елемент виходить за межі viewBox ($b)');
        }
      }
    });

    testWidgets('іконка справді малюється, невідома - ні', (tester) async {
      Future<int> inkPixels(String name) async {
        return (await tester.runAsync(() async {
          final rec = ui.PictureRecorder();
          AppIcons.paint(ui.Canvas(rec), name, const Offset(32, 32), 64, 64, Colors.black);
          final img = await rec.endRecording().toImage(64, 64);
          final data = (await img.toByteData())!;
          var n = 0;
          for (var i = 3; i < data.lengthInBytes; i += 4) {
            if (data.getUint8(i) > 0) n++;
          }
          return n;
        }))!;
      }

      for (final e in AppIcons.entries) {
        expect(await inkPixels(e.id), greaterThan(30), reason: '${e.id} нічого не малює');
      }
      expect(await inkPixels('no_such_icon'), 0);
    });
  });

  group('розбір SVG', () {
    test('дані контуру: відносні команди, неявні повтори, дуги зі злитими прапорцями', () {
      expect(parseSvgPathData('M0 0h10v10z').getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
      expect(parseSvgPathData('m1 1 2 0 0 2').getBounds(), const Rect.fromLTRB(1, 1, 3, 3));
      expect(parseSvgPathData('M0,0L4-4').getBounds(), const Rect.fromLTRB(0, -4, 4, 0));
      final arc = parseSvgPathData('M0 0a5 5 0 0110 0').getBounds();
      expect(arc.left, closeTo(0, 0.1));
      expect(arc.right, closeTo(10, 0.1));
      expect(arc.height, closeTo(5, 0.1));
      expect(parseSvgPathData('M0 0C1 1 2 1 3 0S5-1 6 0').getBounds().right, closeTo(6, 0.01));
      expect(parseSvgPathData('M0 0Q1 2 2 0T4 0').getBounds().right, closeTo(4, 0.01));
      final tight = parseSvgPathData('M1.5.5 2.5.5').getBounds();
      expect(tight.left, closeTo(1.5, 0.001));
      expect(tight.right, closeTo(2.5, 0.001));
    });

    test('некоректні дані контуру - FormatException', () {
      expect(() => parseSvgPathData('L1 1'), throwsFormatException);
      expect(() => parseSvgPathData('M1'), throwsFormatException);
      expect(() => parseSvgPathData('M0 0 A1 1 0 2 1 5 5'), throwsFormatException);
    });

    test('заливка/лінія: за замовчуванням лінія; fill без stroke - лише заливка', () {
      const head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">';
      var i = parseSvgIcon('$head<path d="M1 1L5 5"/></svg>');
      expect(i.shapes.single.stroke, isTrue);
      expect(i.shapes.single.fill, isFalse);
      i = parseSvgIcon('$head<path d="M1 1L5 5L1 5Z" fill="#000"/></svg>');
      expect(i.shapes.single.fill, isTrue);
      expect(i.shapes.single.stroke, isFalse);
      i = parseSvgIcon('$head<g fill="none" stroke="#fff" stroke-width="3">'
          '<circle cx="5" cy="5" r="2"/></g></svg>');
      expect(i.shapes.single.stroke, isTrue);
      expect(i.shapes.single.strokeWidth, 3);
      i = parseSvgIcon('$head<path d="M1 1L5 5" style="fill:none;stroke:#000;stroke-width:2;opacity:.5"/></svg>');
      expect(i.shapes.single.strokeWidth, 2);
      expect(i.shapes.single.strokeOpacity, 0.5);
      i = parseSvgIcon('$head<rect x="1" y="1" width="4" height="4" rx="1" fill="none" stroke="#000"/>'
          '<line x1="0" y1="0" x2="3" y2="3" stroke="#000"/>'
          '<polygon points="0,0 4,0 4,4" fill="#000"/><ellipse cx="9" cy="9" rx="2" ry="1" fill="#000"/></svg>');
      expect(i.shapes.length, 4);
    });

    test('непідтримуване - попередження; зіпсований файл - помилка', () {
      final warnings = <String>[];
      parseSvgIcon(
          '<svg viewBox="0 0 24 24"><path d="M1 1L5 5" stroke="#000" transform="rotate(5)"/>'
          '<text>hi</text></svg>',
          onWarning: warnings.add);
      expect(warnings.length, 2);
      expect(() => parseSvgIcon('<svg viewBox="0 0 24 24"></svg>'), throwsFormatException);
      expect(() => parseSvgIcon('нема svg'), throwsFormatException);
      expect(() => parseSvgIcon('<svg viewBox="0 0 x 24"><path d="M0 0L1 1"/></svg>'),
          throwsFormatException);
    });

    test('реєстр: погані записи не ламають завантаження, а потрапляють у problems', () {
      const good = '<svg viewBox="0 0 24 24"><path d="M1 1L5 5"/></svg>';
      final set = buildIconSet('''
        {"categories": {"ui": "UI"}, "icons": [
          {"id": "ok", "file": "ok.svg", "label": "Ок", "category": "ui"},
          {"id": "ok", "file": "ok.svg", "label": "Дубль", "category": "ui"},
          {"id": "Bad Id", "file": "x.svg", "label": "X", "category": "ui"},
          {"id": "missing", "file": "nope.svg", "label": "X", "category": "ui"},
          {"id": "broken", "file": "broken.svg", "label": "X", "category": "ui"},
          {"id": "nocat", "file": "ok.svg", "label": "X", "category": "zzz"}
        ]}''', (f) => {'ok.svg': good, 'broken.svg': '<svg'}[f]);
      expect(set.icons.keys, containsAll(['ok', 'nocat']));
      expect(set.icons.containsKey('broken'), isFalse);
      expect(set.problems.length, 5);
      expect(buildIconSet('не json', (_) => null).problems, isNotEmpty);
    });
  });
}
