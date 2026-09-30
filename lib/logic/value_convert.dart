/// Перетворення збережених значень параметра в інший тип даних — для
/// "перенесення історії" зі старого параметра в новий (тип даних параметра
/// обирається один раз і потім не змінюється).
library;

import '../data/models.dart';
import '../ui/date_picker.dart' show parseDdMmYyyy;
import '../ui/icons.dart' show queenTagChoices;

/// Значення [value] у форматі типу [toType] або null, якщо воно цьому типу
/// не підходить. Порожнє значення ("значення прибрали") підходить будь-якому.
String? convertValue(String? value, String toType) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return '';
  switch (toType) {
    case DataTypes.int_:
      final i = int.tryParse(v);
      if (i != null) return '$i';
      final d = double.tryParse(v.replaceAll(',', '.'));
      if (d != null && d.isFinite && d == d.truncateToDouble() && d.abs() < 1e15) {
        return '${d.toInt()}';
      }
      return null;
    case DataTypes.float_:
      final d = double.tryParse(v.replaceAll(',', '.'));
      return (d == null || !d.isFinite) ? null : d.toString();
    case DataTypes.date:
      final dt = parseDdMmYyyy(v);
      if (dt == null) return null;
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    case DataTypes.color:
      for (final (label, _) in queenTagChoices) {
        if (label.toLowerCase() == v.toLowerCase()) return label;
      }
      return null;
    default:
      return v;
  }
}
