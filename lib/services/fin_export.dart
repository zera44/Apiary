import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import '../data/fin_accounts.dart';
import '../data/finance.dart';
import '../l10n/l10n.dart';
import '../ui/fin_style.dart';

/// Що виводити у файл: лише витрати, лише доходи чи все.
enum FinExportKind { expenses, income, all }

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Записи для файлу: скасовані не потрапляють, вид - за [kind]; від найдавніших.
List<FinEntry> finExportEntries(Iterable<FinEntry> entries, FinExportKind kind) {
  final out = [
    for (final e in entries)
      if (!e.cancelled &&
          switch (kind) {
            FinExportKind.expenses => e.isExpense,
            FinExportKind.income => !e.isExpense,
            FinExportKind.all => true,
          })
        e
  ]..sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// «operacii_2026-11-01_2026-11-30.xlsx» (+ _vytraty / _dohody).
String finExportFileName(DateTime from, DateTime lastDay, FinExportKind kind) {
  String two(int v) => v.toString().padLeft(2, '0');
  String d(DateTime x) => '${x.year}-${two(x.month)}-${two(x.day)}';
  final suffix = switch (kind) {
    FinExportKind.expenses => '_vytraty',
    FinExportKind.income => '_dohody',
    FinExportKind.all => '',
  };
  return 'operacii_${d(from)}_${d(lastDay)}$suffix.xlsx';
}

String _categoryName(FinEntry e, Map<String, FinCategory> cats) =>
    e.fromStock ? kFinStockCategoryName : (cats[e.categoryId]?.name ?? tr.noCategory);

String _accountName(FinEntry e, Map<String, FinAccount> accounts) {
  if (e.fromStock) return '';
  final a = accounts[e.accountId];
  if (a == null) return '';
  return a.foreign ? '${a.name} · ${a.currency}' : a.name;
}

/// Книга: аркуш «Операції» (дата, вид, категорія, [рахунок], опис, сума,
/// [коментар]) і за бажанням аркуш «Підсумки» (витрати й доходи за категоріями,
/// а з рахунком - ще й за рахунками). Витрата в сумі зі знаком «−», тож
/// `=СУМ(…)` у Excel одразу дає баланс.
Uint8List buildFinWorkbook({
  required List<FinEntry> entries,
  required Map<String, FinCategory> cats,
  required FinExportKind kind,
  Map<String, FinAccount> accounts = const {},
  bool includeSummary = true,
  bool includeComment = true,
  bool includeAccount = false,
}) {
  final rows = finExportEntries(entries, kind);
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  final opsName = tr.finOps;
  excel.rename(defaultName, opsName);
  final bold = CellStyle(bold: true);
  final dateStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd.mm.yyyy'));
  final moneyStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: '#,##0.00'));

  final ops = excel[opsName];
  final heads = [
    tr.date,
    tr.finColKind,
    tr.category,
    if (includeAccount) tr.finAccount,
    tr.finColDescription,
    tr.sum,
    if (includeComment) tr.comment,
  ];
  // номер колонки «Сума»: дата, вид, категорія, [рахунок], опис, сума
  final sumCol = includeAccount ? 5 : 4;
  ops.appendRow([for (final h in heads) TextCellValue(h)]);
  for (var c = 0; c < heads.length; c++) {
    ops.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
  }
  for (final e in rows) {
    ops.appendRow([
      DateCellValue(year: e.date.year, month: e.date.month, day: e.date.day),
      TextCellValue(e.isExpense ? tr.expense : tr.income),
      TextCellValue(_categoryName(e, cats)),
      if (includeAccount) TextCellValue(_accountName(e, accounts)),
      TextCellValue(e.title),
      DoubleCellValue(e.isExpense ? -e.amount : e.amount),
      if (includeComment) TextCellValue(e.comment ?? ''),
    ]);
    final r = ops.maxRows - 1;
    ops.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).cellStyle = dateStyle;
    ops.cell(CellIndex.indexByColumnRow(columnIndex: sumCol, rowIndex: r)).cellStyle = moneyStyle;
  }
  ops.setColumnWidth(0, 12);
  ops.setColumnWidth(1, 10);
  ops.setColumnWidth(2, 24);
  if (includeAccount) ops.setColumnWidth(3, 20);
  ops.setColumnWidth(sumCol - 1, 30);
  ops.setColumnWidth(sumCol, 14);
  if (includeComment) ops.setColumnWidth(sumCol + 1, 30);

  if (includeSummary) {
    final s = FinSummary.of(rows);
    final sum = excel[tr.finExportSummarySheet];
    sum.appendRow([
      TextCellValue(tr.category),
      if (kind != FinExportKind.income) TextCellValue(tr.expenses),
      if (kind != FinExportKind.expenses) TextCellValue(tr.incomes),
    ]);
    final cols = (kind == FinExportKind.all ? 2 : 1) + 1;
    for (var c = 0; c < cols; c++) {
      sum.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
    }
    final keys = <String?>{
      if (kind != FinExportKind.income) ...s.expenseByCategory.keys,
      if (kind != FinExportKind.expenses) ...s.incomeByCategory.keys,
    }.toList()
      ..sort((a, b) {
        final va = (s.expenseByCategory[a] ?? 0) + (s.incomeByCategory[a] ?? 0);
        final vb = (s.expenseByCategory[b] ?? 0) + (s.incomeByCategory[b] ?? 0);
        return vb.compareTo(va);
      });
    for (final k in keys) {
      final name = k == null ? kFinStockCategoryName : (cats[k]?.name ?? tr.noCategory);
      sum.appendRow([
        TextCellValue(name),
        if (kind != FinExportKind.income) DoubleCellValue(s.expenseByCategory[k] ?? 0),
        if (kind != FinExportKind.expenses) DoubleCellValue(s.incomeByCategory[k] ?? 0),
      ]);
      final r = sum.maxRows - 1;
      for (var c = 1; c < cols; c++) {
        sum.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = moneyStyle;
      }
    }
    sum.appendRow([
      TextCellValue(tr.finColTotal),
      if (kind != FinExportKind.income) DoubleCellValue(s.expense),
      if (kind != FinExportKind.expenses) DoubleCellValue(s.income),
    ]);
    final last = sum.maxRows - 1;
    for (var c = 0; c < cols; c++) {
      final cell = sum.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: last));
      cell.cellStyle = c == 0 ? bold : CellStyle(bold: true, numberFormat: NumFormat.custom(formatCode: '#,##0.00'));
    }
    if (includeAccount) {
      // другий блок: ті самі підсумки за рахунками
      final byExp = <String, double>{}, byInc = <String, double>{};
      for (final e in rows) {
        if (e.noStats) continue; // як і в підсумку за категоріями
        final n = e.fromStock ? kFinStockCategoryName : _accountName(e, accounts);
        final m = e.isExpense ? byExp : byInc;
        m[n] = (m[n] ?? 0) + e.amount;
      }
      final names = <String>{
        if (kind != FinExportKind.income) ...byExp.keys,
        if (kind != FinExportKind.expenses) ...byInc.keys,
      }.toList()
        ..sort((a, b) =>
            ((byExp[b] ?? 0) + (byInc[b] ?? 0)).compareTo((byExp[a] ?? 0) + (byInc[a] ?? 0)));
      sum.appendRow([TextCellValue('')]);
      sum.appendRow([
        TextCellValue(tr.finAccount),
        if (kind != FinExportKind.income) TextCellValue(tr.expenses),
        if (kind != FinExportKind.expenses) TextCellValue(tr.incomes),
      ]);
      final hr = sum.maxRows - 1;
      for (var c = 0; c < cols; c++) {
        sum.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: hr)).cellStyle = bold;
      }
      for (final n in names) {
        sum.appendRow([
          TextCellValue(n.isEmpty ? '—' : n),
          if (kind != FinExportKind.income) DoubleCellValue(byExp[n] ?? 0),
          if (kind != FinExportKind.expenses) DoubleCellValue(byInc[n] ?? 0),
        ]);
        final r = sum.maxRows - 1;
        for (var c = 1; c < cols; c++) {
          sum.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = moneyStyle;
        }
      }
      sum.appendRow([
        TextCellValue(tr.finColTotal),
        if (kind != FinExportKind.income) DoubleCellValue(s.expense),
        if (kind != FinExportKind.expenses) DoubleCellValue(s.income),
      ]);
      final lr = sum.maxRows - 1;
      for (var c = 0; c < cols; c++) {
        final cell = sum.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: lr));
        cell.cellStyle = c == 0
            ? bold
            : CellStyle(bold: true, numberFormat: NumFormat.custom(formatCode: '#,##0.00'));
      }
    }
    sum.setColumnWidth(0, 28);
    sum.setColumnWidth(1, 16);
    sum.setColumnWidth(2, 16);
  }

  final data = excel.encode();
  if (data == null) throw StateError('encode() повернув null');
  return Uint8List.fromList(data);
}

/// Збирає файл і відкриває «Поділитись» (месенджер, пошта, диск…).
/// Повертає текст помилки або null.
Future<String?> shareFinExport({
  required Uint8List bytes,
  required String fileName,
}) async {
  try {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: _xlsxMime, name: fileName)],
      fileNameOverrides: [fileName],
      subject: tr.finExportTitle,
    ));
    return null;
  } catch (e) {
    return tr.shareFailed('$e');
  }
}
