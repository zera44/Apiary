// Перевірка Dart-версії дочитування (lib/logic/fz2/recover.dart) на записах еталона: tool/oracle/OcrRecover.java
// записує у файл кожне читання рамки моделлю, зміну виродженої рамки й рукописні рядки; тут правила
// програються на тих самих відповідях, а підсумкові фрагменти порівнюються з еталонними бітами.
// Записи робляться з чужих фото чеків, тож у репозиторії їх немає: каталог задає APIARY_RECOVER_FX
// (запуск без нього пропускається). Як зробити записи: packages/paddle_ocr_flutter/tool/OcrV2Main.java, FX_DIR.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/logic/fz2/recover.dart';

String _hex(double d) {
  final b = ByteData(8)..setFloat64(0, d);
  return BigInt.parse([for (var i = 0; i < 8; i++) b.getUint8(i).toRadixString(16).padLeft(2, '0')].join(), radix: 16)
      .toRadixString(16);
}

double _dbl(String h) {
  final v = BigInt.parse(h, radix: 16);
  final b = ByteData(8);
  for (var i = 0; i < 8; i++) {
    b.setUint8(7 - i, ((v >> (8 * i)) & BigInt.from(255)).toInt());
  }
  return b.getFloat64(0);
}

String _unesc(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final n = s[++i];
      b.write(n == 't' ? '\t' : n == 'n' ? '\n' : n);
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

Frag _frag(List<String> p) => Frag(
      boxId: int.parse(p[0]),
      text: _unesc(p[1]),
      conf: _dbl(p[2]),
      x: _dbl(p[3]),
      y: _dbl(p[4]),
      w: _dbl(p[5]),
      h: _dbl(p[6]),
      xLeft: _dbl(p[7]),
      xRight: _dbl(p[8]),
      angle: _dbl(p[9]),
      imgW: double.parse(p[10]),
      imgH: double.parse(p[11]),
      recovered: p[12] == '1',
      hand: p.length > 13 && p[13].isNotEmpty ? p[13] : null,
    );

class _Replay implements OcrBackend {
  final reads = <String, ReadRes>{};
  final degens = <String, List<double>>{};
  final hands = <Frag>[];
  int missing = 0;
  String? firstMissing;

  @override
  Future<List<ReadRes>> read(double angle, List<ReadReq> reqs) async => [
        for (final q in reqs)
          reads['${_hex(q.x1)}|${_hex(q.x2)}|${_hex(q.y1)}|${_hex(q.y2)}|${_hex(angle)}|${q.st.map(_hex).join(',')}'] ??
              (() {
                missing++;
                firstMissing ??= 'read ${q.x1} ${q.x2} ${q.y1} ${q.y2} st=${q.st}';
                return const ReadRes('', 0);
              })()
      ];

  @override
  Future<void> degen(Frag f, double angle) async {
    final r = degens['${_hex(f.x)}|${_hex(f.y)}|${_hex(f.h)}|${_hex(angle)}'];
    if (r == null) {
      missing++;
      firstMissing ??= 'degen ${f.x} ${f.y} ${f.h}';
      return;
    }
    f
      ..x = r[0]
      ..y = r[1]
      ..w = r[2]
      ..h = r[3]
      ..xLeft = r[4]
      ..xRight = r[5];
  }

  @override
  Future<List<Frag>> hand(List<Frag> fr) async => [for (final h in hands) h.copy()];
}

String _same(Frag a, Frag b) {
  bool eq(double p, double q) => _hex(p) == _hex(q);
  if (a.boxId != b.boxId) return 'boxId ${a.boxId} != ${b.boxId}';
  if (a.text != b.text) return 'text "${a.text}" != "${b.text}"';
  if (!eq(a.conf, b.conf)) return 'conf ${a.conf} != ${b.conf}';
  for (final e in {
    'x': [a.x, b.x],
    'y': [a.y, b.y],
    'w': [a.w, b.w],
    'h': [a.h, b.h],
    'xLeft': [a.xLeft, b.xLeft],
    'xRight': [a.xRight, b.xRight],
  }.entries) {
    if (!eq(e.value[0], e.value[1])) return '${e.key} ${e.value[0]} != ${e.value[1]}';
  }
  if (a.hand != b.hand) return 'hand';
  if (a.recovered != b.recovered) return 'recovered';
  return '';
}

void main() {
  final dir = Platform.environment['APIARY_RECOVER_FX'];
  test('дочитування в Dart дає ті самі фрагменти, що й еталон (записи читань моделі)', () async {
    final files = Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.fx')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    final bad = <String>[];
    for (final file in files) {
      final rp = _Replay();
      final init = <Frag>[], want = <Frag>[];
      for (final line in file.readAsLinesSync()) {
        final p = line.split('\t');
        switch (p[0]) {
          case 'I':
            init.add(_frag(p.sublist(1)));
          case 'E':
            want.add(_frag(p.sublist(1)));
          case 'H':
            rp.hands.add(_frag(p.sublist(1)));
          case 'R':
            rp.reads['${p[2]}|${p[3]}|${p[4]}|${p[5]}|${p[1]}|${p[6]}'] = ReadRes(_unesc(p.length > 8 ? p[8] : ''), _dbl(p[7]));
          case 'G':
            rp.degens['${p[1]}|${p[2]}|${p[3]}|${p[4]}'] = [for (var i = 5; i < 11; i++) _dbl(p[i])];
        }
      }
      final name = file.uri.pathSegments.last;
      if (init.isEmpty) {
        bad.add('$name: порожній запис');
        continue;
      }
      try {
        await recoverAll(init, rp);
      } catch (e) {
        bad.add('$name: $e');
        continue;
      }
      if (rp.missing > 0) {
        bad.add('$name: немає запису читання (${rp.missing}): ${rp.firstMissing}');
        continue;
      }
      if (init.length != want.length) {
        bad.add('$name: фрагментів ${init.length}, очікувалось ${want.length}');
        continue;
      }
      for (var i = 0; i < init.length; i++) {
        final d = _same(init[i], want[i]);
        if (d.isNotEmpty) {
          bad.add('$name #$i: $d');
          break;
        }
      }
    }
    expect(bad, isEmpty, reason: '${bad.length} з ${files.length} чеків відрізняються:\n${bad.take(20).join('\n')}');
  }, skip: dir == null ? 'APIARY_RECOVER_FX не задано' : false);
}
