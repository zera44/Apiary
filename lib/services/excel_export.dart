import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../ui/date_picker.dart';
import '../l10n/l10n.dart';

/// Експорт історії параметра у .xlsx. Показує системний діалог
/// "Зберегти як…" (на Android — вибір теки, зокрема "Завантаження", без
/// жодних дозволів на сховище). Повертає текст для користувача.
Future<String> exportHistoryToExcel({
  required Parameter parameter,
  required List<ParameterRecord> rows,
  String? scopeName,
}) async {
  final Uint8List bytes;
  try {
    bytes = buildHistoryWorkbook(parameter: parameter, rows: rows);
  } catch (e) {
    return tr.fileBuildFailed('$e');
  }

  final fileName = historyFileName(parameter.name, scopeName, DateTime.now());

  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      dialogTitle: tr.saveHistory,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (uri == null) return tr.saveCancelled;
    if (uri.scheme == 'file') {
      // на комп'ютері — підстраховуємось: якщо файл не записано, пишемо самі
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() == 0) {
        await f.writeAsBytes(bytes, flush: true);
      }
      return tr.savedAt(f.path);
    }
    // Android: адреса — внутрішній код документа (наприклад, 1361), не показуємо
    return tr.saved;
  } catch (_) {
    // запасний варіант — власна тека застосунку
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, fileName));
      await f.writeAsBytes(bytes, flush: true);
      return tr.savedFallback(f.path);
    } catch (e) {
      return tr.fileSaveFailed('$e');
    }
  }
}

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// «Звіт по пасіці» (P14) одним файлом: зберегти у вибрану теку.
Future<String> saveApiaryReport(ApiaryReport report, String apiaryName) async {
  final Uint8List bytes;
  try {
    bytes = buildApiaryWorkbook(report);
  } catch (e) {
    return tr.fileBuildFailed('$e');
  }
  final fileName = apiaryReportFileName(apiaryName, DateTime.now());
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: _xlsxMime,
      dialogTitle: tr.saveReport,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (uri == null) return tr.saveCancelled;
    if (uri.scheme == 'file') {
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() == 0) {
        await f.writeAsBytes(bytes, flush: true);
      }
      return tr.savedAt(f.path);
    }
    return tr.saved;
  } catch (_) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, fileName));
      await f.writeAsBytes(bytes, flush: true);
      return tr.savedFallback(f.path);
    } catch (e) {
      return tr.fileSaveFailed('$e');
    }
  }
}

/// «Звіт по пасіці»: одразу поділитися (месенджер, пошта, диск…).
/// Повертає текст помилки або null.
Future<String?> shareApiaryReport(ApiaryReport report, String apiaryName) async {
  try {
    final bytes = buildApiaryWorkbook(report);
    final fileName = apiaryReportFileName(apiaryName, DateTime.now());
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: _xlsxMime, name: fileName)],
      fileNameOverrides: [fileName],
      subject: tr.apiaryReportOf(apiaryName),
    ));
    return null;
  } catch (e) {
    return tr.shareFailed('$e');
  }
}

String apiaryReportFileName(String apiaryName, DateTime now) {
  final safe = apiaryName
      .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  return 'zvit_${safe.isEmpty ? 'pasika' : safe}_$stamp.xlsx';
}

/// Книга «Звіту по пасіці»: аркуш «Останні значення» (рядки — вулики,
/// колонки — параметри) і аркуш «Історія» (дата, вулик, параметр, значення).
Uint8List buildApiaryWorkbook(ApiaryReport report) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  final lastName = tr.sheetLatest;
  final histName = tr.history;
  excel.rename(defaultName, lastName);
  final bold = CellStyle(bold: true);
  final dateStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd.mm.yyyy'));
  final dateTimeStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd.mm.yyyy hh:mm'));
  final byId = {for (final p in report.parameters) p.id: p};

  final last = excel[lastName];
  last.appendRow([
    TextCellValue(tr.hive),
    for (final p in report.parameters) TextCellValue(p.nameWithUnit),
  ]);
  for (var c = 0; c <= report.parameters.length; c++) {
    last.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
  }
  for (final h in report.hives) {
    final values = report.latest[h.ref] ?? const <String, String?>{};
    final cells = [
      for (final p in report.parameters) historyValueCell(values[p.id], p.dataType),
    ];
    last.appendRow([TextCellValue(h.label), ...cells]);
    final row = last.maxRows - 1;
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] is DateCellValue) {
        last.cell(CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: row)).cellStyle =
            dateStyle;
      }
    }
  }
  last.setColumnWidth(0, 22);
  for (var c = 1; c <= report.parameters.length; c++) {
    last.setColumnWidth(c, 18);
  }

  final hist = excel[histName];
  hist.appendRow([
    TextCellValue(tr.dateTime),
    TextCellValue(tr.hive),
    TextCellValue(tr.parameter),
    TextCellValue(tr.value),
  ]);
  for (var c = 0; c < 4; c++) {
    hist.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
  }
  for (final r in report.history) {
    final p = byId[r.parameterId];
    if (p == null) continue;
    final at = DateTime.fromMicrosecondsSinceEpoch((r.createdAt * 1e6).round());
    final value = historyValueCell(r.value, p.dataType);
    hist.appendRow([
      DateTimeCellValue(
          year: at.year, month: at.month, day: at.day, hour: at.hour, minute: at.minute),
      TextCellValue(r.hive),
      TextCellValue(p.nameWithUnit),
      value,
    ]);
    final row = hist.maxRows - 1;
    hist.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = dateTimeStyle;
    if (value is DateCellValue) {
      hist.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = dateStyle;
    }
  }
  hist.setColumnWidth(0, 18);
  hist.setColumnWidth(1, 22);
  hist.setColumnWidth(2, 24);
  hist.setColumnWidth(3, 18);

  final data = excel.encode();
  if (data == null) throw StateError('encode() повернув null');
  return Uint8List.fromList(data);
}

/// Сама книга Excel (окремо — щоб можна було перевірити тестом).
Uint8List buildHistoryWorkbook({
  required Parameter parameter,
  required List<ParameterRecord> rows,
}) {
  final excel = Excel.createExcel();
  final sheetName = safeSheetTitle(parameter.name);
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultName, sheetName);
  final sheet = excel[sheetName];

  sheet.appendRow([
    TextCellValue(tr.objectOrGroup),
    TextCellValue(parameter.nameWithUnit),
    TextCellValue(tr.dateTime),
  ]);
  final bold = CellStyle(bold: true);
  for (var c = 0; c < 3; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
  }
  // числа — числами, дати — датами: у Excel працюють суми, графіки й
  // сортування за часом (раніше все було текстом)
  final dateStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd.mm.yyyy'));
  final dateTimeStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd.mm.yyyy hh:mm'));
  for (final r in rows) {
    final value = historyValueCell(r.value, parameter.dataType);
    final at = DateTime.fromMicrosecondsSinceEpoch((r.createdAt * 1e6).round());
    sheet.appendRow([
      TextCellValue(r.entityLabel.isEmpty ? '-' : r.entityLabel),
      value,
      DateTimeCellValue(
          year: at.year, month: at.month, day: at.day, hour: at.hour, minute: at.minute),
    ]);
    final row = sheet.maxRows - 1;
    if (value is DateCellValue) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = dateStyle;
    }
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle =
        dateTimeStyle;
  }
  sheet.setColumnWidth(0, 28);
  sheet.setColumnWidth(1, 22);
  sheet.setColumnWidth(2, 18);

  final data = excel.encode();
  if (data == null) throw StateError('encode() повернув null');
  return Uint8List.fromList(data);
}

/// Клітинка значення за типом параметра: ціле/дробове число, дата або текст
/// (якщо значення не відповідає типу — лишається текстом, як є).
CellValue historyValueCell(String? raw, String dataType) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return TextCellValue('');
  switch (dataType) {
    case DataTypes.int_:
      final i = int.tryParse(s);
      if (i != null) return IntCellValue(i);
    case DataTypes.float_:
      final d = double.tryParse(s.replaceAll(',', '.'));
      if (d != null && d.isFinite) return DoubleCellValue(d);
    case DataTypes.date:
      final dt = parseDdMmYyyy(s);
      if (dt != null) return DateCellValue(year: dt.year, month: dt.month, day: dt.day);
  }
  return TextCellValue(s);
}

String historyFileName(String paramName, String? scopeName, DateTime now) {
  String safe(String s) {
    // літери будь-якої абетки (зокрема кирилиця), цифри, "_" і "-"
    final r = s.replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_');
    return r.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final name = safe(paramName).isEmpty ? 'parameter' : safe(paramName);
  if (scopeName != null && safe(scopeName).isNotEmpty) {
    return 'istoriya_${name}_${safe(scopeName)}_$stamp.xlsx';
  }
  return 'istoriya_${name}_$stamp.xlsx';
}

/// Обмеження Excel: назва листа до 31 символу, без []:*?/\
String safeSheetTitle(String name) {
  var s = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_');
  if (s.length > 31) {
    // не розрізати суррогатну пару (емодзі)
    var cut = 31;
    final last = s.codeUnitAt(cut - 1);
    if (last >= 0xD800 && last <= 0xDBFF) cut--;
    s = s.substring(0, cut);
  }
  // Excel не приймає апостроф на початку чи в кінці назви листа
  s = s.replaceAll(RegExp(r"^'+|'+$"), '');
  return s.isEmpty ? tr.history : s;
}
