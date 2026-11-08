// Позиції чеків із сирого CSV фрагментів (вихід ocr.py/recover.py чи tool/OcrV2Main.java):
// dart run tool/fz2/rows_dump.dart raw.csv > rows.json
// Для перевірки збирача позицій (lib/logic/fz2/receipt_rows.dart) на фото поза репозиторієм.
import 'dart:convert';
import 'dart:io';

import 'package:apiary/logic/fz2/fz2.dart';
import 'package:apiary/logic/fz2/receipt_rows.dart';

List<List<String>> parseCsv(String s) {
  final rows = <List<String>>[];
  var row = <String>[], cell = StringBuffer();
  var q = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') { cell.write('"'); i++; } else { q = false; }
      } else { cell.write(c); }
    } else if (c == '"') { q = true; }
    else if (c == ',') { row.add('$cell'); cell = StringBuffer(); }
    else if (c == '\n') { row.add('$cell'); cell = StringBuffer(); rows.add(row); row = []; }
    else if (c != '\r') { cell.write(c); }
  }
  if (cell.isNotEmpty || row.isNotEmpty) { row.add('$cell'); rows.add(row); }
  return rows;
}

void main(List<String> a) {
  final rows = parseCsv(File(a[0]).readAsStringSync());
  final hd = rows.first;
  int col(String n) => hd.indexOf(n);
  double d(List<String> r, String n) {
    final i = col(n);
    return i < 0 || i >= r.length || r[i].isEmpty ? double.nan : double.parse(r[i]);
  }
  final by = <String, List<Frag>>{};
  for (final r in rows.skip(1)) {
    if (r.length < 5) continue;
    final hi = col('hand');
    final hand = hi >= 0 && hi < r.length && r[hi].isNotEmpty ? r[hi] : null;
    by.putIfAbsent(r[col('receipt')], () => []).add(Frag(
          receipt: r[col('receipt')],
          boxId: int.tryParse(r[col('box_id')]) ?? double.parse(r[col('box_id')]).toInt(),
          text: r[col('text')],
          conf: d(r, 'conf'),
          x: d(r, 'x'), y: d(r, 'y'), w: d(r, 'w'), h: d(r, 'h'),
          xLeft: d(r, 'x_left'), xRight: d(r, 'x_right'),
          imgW: d(r, 'img_w'), imgH: d(r, 'img_h'), angle: d(r, 'angle'), hand: hand));
  }
  final out = <String, Object>{};
  for (final e in by.entries) {
    final m = markReceipt(e.value);
    out[e.key] = {
      'total': m.total,
      'rows': [for (final r in m.rows) {'name': r.name, 'qty': r.qty, 'unit': r.unit, 'price': r.price, 'sum': r.sum}],
    };
  }
  stdout.write(jsonEncode(out));
}
