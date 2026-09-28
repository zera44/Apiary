import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../ui/date_picker.dart';

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
    return 'Не вдалось сформувати файл:\n$e';
  }

  final fileName = historyFileName(parameter.name, scopeName, DateTime.now());

  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Зберегти історію',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: bytes,
    );
    if (path == null) return 'Збереження скасовано.';
    // на комп'ютері плагін лише повертає шлях — файл записуємо самі
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final f = File(path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx');
      await f.writeAsBytes(bytes, flush: true);
      return 'Збережено:\n${f.path}';
    }
    return 'Збережено:\n${p.basename(path)}';
  } catch (_) {
    // запасний варіант — власна тека застосунку
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File(p.join(dir.path, fileName));
      await f.writeAsBytes(bytes, flush: true);
      return 'Не вдалось відкрити діалог збереження — файл збережено тут:\n${f.path}';
    } catch (e) {
      return 'Не вдалось зберегти файл:\n$e';
    }
  }
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
    TextCellValue("Об'єкт / група"),
    TextCellValue(parameter.nameWithUnit),
    TextCellValue('Дата й час'),
  ]);
  final bold = CellStyle(bold: true);
  for (var c = 0; c < 3; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
  }
  for (final r in rows) {
    sheet.appendRow([
      TextCellValue(r.entityLabel.isEmpty ? '—' : r.entityLabel),
      TextCellValue(r.value ?? ''),
      TextCellValue(formatDateTime(r.createdAt)),
    ]);
  }
  sheet.setColumnWidth(0, 28);
  sheet.setColumnWidth(1, 22);
  sheet.setColumnWidth(2, 18);

  final data = excel.encode();
  if (data == null) throw StateError('encode() повернув null');
  return Uint8List.fromList(data);
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
  if (s.length > 31) s = s.substring(0, 31);
  return s.isEmpty ? 'Історія' : s;
}
