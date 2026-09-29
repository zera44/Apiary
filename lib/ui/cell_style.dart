import 'package:flutter/material.dart';

import '../logic/merge_layout.dart';
import 'icons.dart';
import 'theme.dart';

/// Спільне малювання клітинок-об'єктів для карти й редактора шаблону
/// (порт cell_style.py): заокруглена плашка з відступом від сітки,
/// злиття однакових сусідів, одна іконка на фігуру.

const double kInset = 0.075; // відступ плашки від лінії сітки (частка клітинки)
const double kBody = 0.85; // розмір плашки незлитої клітинки

Color hexToColor(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16) ?? 0xFFED9D2F;
  return Color(v);
}

String colorToHex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Колір плашки: власний (якщо задано) або типовий за типом.
Color fillColor(String type, String? color) {
  if (color != null && color.isNotEmpty) return hexToColor(color);
  return type == 'hive' ? AppColors.hive : AppColors.obstacle;
}

/// Прямокутник плашки клітинки у Flutter-координатах; [cellRect] — вся
/// клітинка сітки на екрані.
Rect bodyRect(Rect cellRect, Merge m) {
  final cs = cellRect.width;
  final inset = cs * kInset;
  final l = cellRect.left + inset - (m.left ? inset : 0);
  final t = cellRect.top + inset - (m.top ? inset : 0);
  final w = cs * kBody + (m.left ? inset : 0) + (m.right ? inset : 0);
  final h = cs * kBody + (m.top ? inset : 0) + (m.bottom ? inset : 0);
  return Rect.fromLTWH(l, t, w, h);
}

// Paint-и перевикористовуються між викликами (колір виставляється перед
// кожним малюванням) — так не створюється по 2 об'єкти на кожну клітинку
// щокадру. Canvas копіює параметри Paint у момент виклику draw*, тож це
// безпечно.
final Paint _fillPaint = Paint();
final Paint _borderPaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.8;

/// Плашка + темна межа: окрема клітинка — заокруглена рамка; злита —
/// межа лише по зовнішніх сторонах.
void drawBody(Canvas canvas, Rect r, Merge m, Color color, {double radius = 4}) {
  final rad = Radius.circular(radius);
  final rrect = RRect.fromRectAndCorners(
    r,
    topLeft: (m.top || m.left) ? Radius.zero : rad,
    topRight: (m.top || m.right) ? Radius.zero : rad,
    bottomRight: (m.bottom || m.right) ? Radius.zero : rad,
    bottomLeft: (m.bottom || m.left) ? Radius.zero : rad,
  );
  _fillPaint.color = color;
  canvas.drawRRect(rrect, _fillPaint);
  final border = _borderPaint..color = AppColors.objectBorder;
  if (!m.any) {
    canvas.drawRRect(RRect.fromRectAndRadius(r, rad), border);
    return;
  }
  if (!m.bottom) canvas.drawLine(r.bottomLeft, r.bottomRight, border);
  if (!m.top) canvas.drawLine(r.topLeft, r.topRight, border);
  if (!m.left) canvas.drawLine(r.topLeft, r.bottomLeft, border);
  if (!m.right) canvas.drawLine(r.topRight, r.bottomRight, border);
}

/// Назва іконки, яку малювати для об'єкта: власна або типова.
String iconNameFor(String type, String? variant, String? icon) {
  if (icon != null && hasAppIcon(icon)) return icon;
  if (type == 'hive') return 'beehive';
  final v = variant ?? 'mountain';
  return hasAppIcon(v) ? v : 'mountain';
}

void drawCellIcon(Canvas canvas, Offset center, double cs, String type, String? variant,
    String? icon) {
  final size = cs * kBody;
  paintAppIcon(canvas, iconNameFor(type, variant, icon), center, size, size, AppColors.iconMark);
}
