import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../logic/stock_format.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Значки категорій фінансів (ключ зберігається в базі).
const Map<String, IconData> kFinIcons = {
  'feed': Icons.shopping_basket_outlined,
  'medicine': Icons.medication_outlined,
  'frame': Icons.grid_view,
  'honey': Icons.hexagon_outlined,
  'jar': Icons.science_outlined,
  'car': Icons.directions_car_outlined,
  'tool': Icons.build_outlined,
  'drop': Icons.water_drop_outlined,
  'scale': Icons.scale_outlined,
  'home': Icons.home_outlined,
  'doc': Icons.receipt_long_outlined,
  'other': Icons.more_horiz,
};

/// Кольори категорій (ключ -> колір).
const Map<String, Color> kFinColors = {
  'honey': Color(0xFFED9D2F),
  'olive': Color(0xFF8E9D3D),
  'terra': Color(0xFFCD4C28),
  'light': Color(0xFFF3C969),
  'nut': Color(0xFF9C7A55),
  'sky': Color(0xFF6E9FB8),
  'plum': Color(0xFF9B6A9E),
};

IconData finIcon(String key) => kFinIcons[key] ?? Icons.more_horiz;
Color finColor(String key) => kFinColors[key] ?? kFinColors['honey']!;

/// Назва для запису без категорії - прихід, внесений прямо на складі.
String get kFinStockCategoryName => tr.finFromStock;

/// Гроші з пропусками між тисячами: 12500 -> «12 500 ₴».
String uah(double v) {
  final s = formatMoney(v.abs());
  final parts = s.split(',');
  final whole = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(' ');
    buf.write(whole[i]);
  }
  final sign = v < 0 ? '−' : '';
  return '$sign$buf${parts.length > 1 ? ',${parts[1]}' : ''} ₴';
}

String finMonthTitle(DateTime d) => '${tr.monthNames[d.month]} ${d.year}';

String finDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// Кружок із значком категорії.
class FinBadge extends StatelessWidget {
  final String icon;
  final String color;
  final double size;
  const FinBadge({super.key, required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: finColor(color), shape: BoxShape.circle),
        child: Icon(finIcon(icon), size: size * 0.52, color: const Color(0xFF1D1611)),
      );
}

/// Перемикач з двох половинок («Витрати | Дохід», «Вручну | З чека»).
class FinSegment extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const FinSegment(
      {super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: AppColors.darkBtn, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.create : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                        color: i == selected ? AppColors.bg : AppColors.textMuted,
                        fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14.5,
                      )),
                ),
              ),
            ),
        ]),
      );
}

/// Підпис суми операції: витрата червоно-теракотова з «−», дохід зелений з «+».
Color finAmountColor(FinEntry e) =>
    e.cancelled ? AppColors.textMuted : (e.isExpense ? AppColors.text : AppColors.grass);
