import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Імпорт фінансів з Excel: аркуші «Витрати», «Дохід» і «Перекази» з
/// шапкою «Дата і час | Категорія | Рахунок | Сума у валюті за замовчуванням
/// | … | Коментувати» (для переказів - «Вихідні | Вхідні | Сума у вихідній
/// валюті | Вихідна валюта | Сума у валюті надходження | Вхідна валюта»).

class ImpOp {
  final bool expense;
  final String category;
  final String account;
  final double amount;
  final DateTime date;
  final String comment;

  /// Стабільний ключ рядка (для повторного імпорту без дублів).
  final String key;
  const ImpOp(this.expense, this.category, this.account, this.amount, this.date, this.comment, this.key);
}

class ImpTransfer {
  final String from;
  final String to;
  final double amount;
  final DateTime date;
  final String comment;
  final String key;
  const ImpTransfer(this.from, this.to, this.amount, this.date, this.comment, this.key);
}

class FinImportData {
  final List<ImpOp> ops;
  final List<ImpTransfer> transfers;

  /// Рядки, які не вдалося взяти: порожня дата чи сума, переказ між валютами.
  final int skipped;
  const FinImportData(this.ops, this.transfers, this.skipped);

  int get expenses => ops.where((o) => o.expense).length;
  int get incomes => ops.length - expenses;
  bool get isEmpty => ops.isEmpty && transfers.isEmpty;
}

/// Читає книгу [bytes]; кидає [FormatException], якщо файл не схожий на
/// потрібний (немає жодного з трьох аркушів).
FinImportData parseFinWorkbook(Uint8List bytes) {
  final Excel book;
  try {
    book = Excel.decodeBytes(bytes);
  } catch (e) {
    throw FormatException('$e');
  }
  final ops = <ImpOp>[];
  final transfers = <ImpTransfer>[];
  var skipped = 0;
  var found = false;
  for (final name in book.tables.keys) {
    final low = name.trim().toLowerCase();
    final kind = switch (low) {
      'витрати' => 0,
      'дохід' || 'доходи' => 1,
      'перекази' => 2,
      _ => -1,
    };
    if (kind < 0) continue;
    found = true;
    final rows = [
      for (final r in book.tables[name]!.rows) [for (final c in r) c?.value]
    ];
    final h = rows.indexWhere((r) => r.isNotEmpty && _text(r[0]).toLowerCase() == 'дата і час');
    if (h < 0) continue;
    final head = [for (final c in rows[h]) _text(c).toLowerCase()];
    int col(String title) => head.indexOf(title.toLowerCase());
    final cDate = col('Дата і час'), cComment = col('Коментувати');
    String cell(List<CellValue?> r, int i) => i < 0 || i >= r.length ? '' : _text(r[i]);
    if (kind == 2) {
      final cFrom = col('Вихідні'),
          cTo = col('Вхідні'),
          cOut = col('Сума у вихідній валюті'),
          cOutCur = col('Вихідна валюта'),
          cInCur = col('Вхідна валюта');
      for (var i = h + 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.every((c) => _text(c).isEmpty)) continue;
        final date = _date(r.isEmpty ? null : r[cDate < 0 ? 0 : cDate]);
        final amount = cOut < 0 || cOut >= r.length ? null : _number(r[cOut]);
        final from = cell(r, cFrom), to = cell(r, cTo);
        final outCur = cell(r, cOutCur), inCur = cell(r, cInCur);
        final crossCurrency = inCur.isNotEmpty && outCur.isNotEmpty && inCur != outCur;
        if (date == null || amount == null || !(amount > 0) || from.isEmpty || to.isEmpty ||
            from == to || crossCurrency) {
          skipped++;
          continue;
        }
        final note = cell(r, cComment);
        transfers.add(ImpTransfer(from, to, amount, date, note,
            'T|${i - h}|${_day(date)}|$amount|$from|$to|$note'));
      }
    } else {
      final cCat = col('Категорія'),
          cAcc = col('Рахунок'),
          cSum = col('Сума у валюті за замовчуванням');
      for (var i = h + 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.every((c) => _text(c).isEmpty)) continue;
        final date = _date(r.isEmpty ? null : r[cDate < 0 ? 0 : cDate]);
        final amount = cSum < 0 || cSum >= r.length ? null : _number(r[cSum]);
        final account = cell(r, cAcc);
        var category = cell(r, cCat);
        if (date == null || amount == null || !(amount > 0) || account.isEmpty) {
          skipped++;
          continue;
        }
        if (category.isEmpty) category = 'Інше';
        final note = cell(r, cComment);
        ops.add(ImpOp(kind == 0, category, account, amount, date, note,
            '${kind == 0 ? 'E' : 'I'}|${i - h}|${_day(date)}|$amount|$category|$account|$note'));
      }
    }
  }
  if (!found) throw const FormatException('немає аркушів «Витрати», «Дохід», «Перекази»');
  return FinImportData(ops, transfers, skipped);
}

String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

String _text(CellValue? v) => v == null ? '' : v.toString().trim();

double? _number(CellValue? v) {
  switch (v) {
    case IntCellValue():
      return v.value.toDouble();
    case DoubleCellValue():
      return v.value;
    case null:
      return null;
    default:
      final t = v.toString().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
      final d = double.tryParse(t);
      return d != null && d.isFinite ? d : null;
  }
}

DateTime? _date(CellValue? v) {
  switch (v) {
    case DateTimeCellValue():
      return DateTime(v.year, v.month, v.day);
    case DateCellValue():
      return DateTime(v.year, v.month, v.day);
    case null:
      return null;
    default:
      final m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(v.toString().trim());
      if (m != null) return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
      final iso = DateTime.tryParse(v.toString().trim());
      return iso == null ? null : DateTime(iso.year, iso.month, iso.day);
  }
}
