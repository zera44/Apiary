// Нечітка розмітка fz2 на Dart має збігатися з Python (coursework/fuzzy_v2/fz2.py)
// на кожному фрагменті розмічених чеків. Еталон (тексти OCR чеків і класи з
// Python) у публічний репозиторій не кладеться: шлях до нього - у змінній
// оточення FZ2_FIXTURE (див. tool/fz2/README.md); без неї тест пропускається.
import 'dart:convert';
import 'dart:io';

import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/logic/fz2/py.dart';
import 'package:flutter_test/flutter_test.dart';

double _d(Object? v) => v == null ? double.nan : (v as num).toDouble();

Frag fragFromJson(Map<String, dynamic> m) => Frag(
      receipt: '${m['receipt']}',
      boxId: (m['box_id'] as num?)?.toInt(),
      lineId: (m['line_id'] as num?)?.toInt() ?? 0,
      text: m['text'] as String,
      conf: _d(m['conf']),
      x: _d(m['x']),
      y: _d(m['y']),
      w: _d(m['w']),
      h: _d(m['h']),
      xLeft: _d(m['x_left']),
      xRight: _d(m['x_right']),
      imgW: (m['img_w'] as num?)?.toDouble(),
      imgH: (m['img_h'] as num?)?.toDouble(),
      angle: _d(m['angle']),
      hand: m['hand'] as String?,
    );

void main() {
  test('регулярні вирази Python перекладаються', () {
    expect(has(r'\bСУМА\b', 'СУМА 12'), isTrue);
    expect(has(r'\bСУМА\b', 'ПІДСУМА'), isFalse);
    expect(has(r'[^\W\d_]{2,}', 'аб'), isTrue);
    expect(has(r'[^\W\d_]{2,}', '12'), isFalse);
    expect(pyRound(2.5), 2);
    expect(pyRound(3.5), 4);
    expect(kop('12,345'), 1234); // 1234.5 -> до парного
  });

  final path = Platform.environment['FZ2_FIXTURE'];
  test('розмітка збігається з Python на всіх розмічених чеках', () {
    final data = jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;
    var ok = 0, frags = 0, bad = 0;
    final fails = <String>[];
    final sw = Stopwatch()..start();
    for (final e in data.entries) {
      final r = e.value as Map<String, dynamic>;
      final input = [for (final f in r['frags'] as List) fragFromJson(f as Map<String, dynamic>)];
      final exp = r['expected'] as List;
      final got = label(input);
      var same = got.length == exp.length;
      final diffs = <String>[];
      for (var i = 0; i < exp.length; i++) {
        final x = exp[i] as Map<String, dynamic>;
        final g = i < got.length ? got[i] : null;
        frags++;
        final eq = g != null &&
            g.cls == x['cls'] &&
            g.f.text == x['text'] &&
            g.f.virtual == x['virtual'] &&
            (x['virtual'] == true
                ? (g.f.value! - (x['value'] as num)).abs() < 1e-9
                : (g.f.xLeft - _d(x['xl'])).abs() < 1e-6 && (g.f.xRight - _d(x['xr'])).abs() < 1e-6);
        if (!eq) {
          same = false;
          bad++;
          if (diffs.length < 6) {
            diffs.add('  #$i очікується ${x['cls']} «${x['text']}», є ${g?.cls} «${g?.f.text}»');
          }
        }
      }
      if (same) {
        ok++;
      } else {
        fails.add('${e.key}: ${got.length}/${exp.length}\n${diffs.join('\n')}');
      }
    }
    // ignore: avoid_print
    print('чеків збіглося $ok з ${data.length}, фрагментів не збіглося $bad з $frags, ${sw.elapsedMilliseconds} мс');
    if (fails.isNotEmpty) fail(fails.take(15).join('\n'));
  }, skip: path == null ? 'немає FZ2_FIXTURE' : false, timeout: const Timeout(Duration(minutes: 5)));
}
