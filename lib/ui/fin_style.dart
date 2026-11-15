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

/// Значки рахунків (гаманців).
const Map<String, IconData> kFinAccountIcons = {
  'payments': Icons.payments_outlined,
  'card': Icons.credit_card,
  'bank': Icons.account_balance_outlined,
  'savings': Icons.savings_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'safe': Icons.lock_outline,
};

/// Каталог значків за групами (назви груп - `tr.finIconGroups`, у тому ж
/// порядку). Ключ зберігається в базі, тож наявні ключі не змінюємо.
const List<Map<String, IconData>> kFinIconGroups = [
  // Гроші й банки
  {
    'payments': Icons.payments_outlined,
    'card': Icons.credit_card,
    'bank': Icons.account_balance_outlined,
    'savings': Icons.savings_outlined,
    'wallet': Icons.account_balance_wallet_outlined,
    'safe': Icons.lock_outline,
    'dollar': Icons.attach_money,
    'euro': Icons.euro,
    'exchange': Icons.currency_exchange,
    'phone_pay': Icons.phone_iphone,
    'contactless': Icons.contactless_outlined,
    'invest': Icons.trending_up,
    'percent': Icons.percent,
    'shield': Icons.shield_outlined,
    'star': Icons.star_outline,
    'group': Icons.group_outlined,
    'gift_money': Icons.volunteer_activism_outlined,
    'calc': Icons.calculate_outlined,
  },
  // Пасіка
  {
    'honey': Icons.hexagon_outlined,
    'frame': Icons.grid_view,
    'jar': Icons.science_outlined,
    'feed': Icons.shopping_basket_outlined,
    'medicine': Icons.medication_outlined,
    'flower': Icons.local_florist_outlined,
    'drop': Icons.water_drop_outlined,
    'scale': Icons.scale_outlined,
    'tool': Icons.build_outlined,
  },
  // Ферма
  {
    'tractor': Icons.agriculture_outlined,
    'tree': Icons.park_outlined,
    'sprout': Icons.eco_outlined,
    'grass': Icons.grass,
    'barn': Icons.warehouse_outlined,
    'fence': Icons.fence_outlined,
  },
  // Транспорт
  {
    'car': Icons.directions_car_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'truck': Icons.local_shipping_outlined,
    'train': Icons.train_outlined,
    'bus': Icons.directions_bus_outlined,
    'taxi': Icons.local_taxi_outlined,
    'bike': Icons.pedal_bike,
    'plane': Icons.flight_outlined,
    'parking': Icons.local_parking,
    'car_wash': Icons.local_car_wash_outlined,
  },
  // Дім і комуналка
  {
    'home': Icons.home_outlined,
    'light': Icons.lightbulb_outline,
    'water': Icons.water_outlined,
    'fire': Icons.local_fire_department_outlined,
    'wifi': Icons.wifi,
    'phone': Icons.phone_outlined,
    'heat': Icons.thermostat,
    'repair': Icons.hardware_outlined,
    'doc': Icons.receipt_long_outlined,
  },
  // Покупки й їжа
  {
    'cart': Icons.shopping_cart_outlined,
    'bag': Icons.shopping_bag_outlined,
    'store': Icons.storefront_outlined,
    'shirt': Icons.checkroom_outlined,
    'devices': Icons.devices_outlined,
    'food': Icons.restaurant_outlined,
    'coffee': Icons.local_cafe_outlined,
    'bakery': Icons.bakery_dining_outlined,
    'drink': Icons.local_bar_outlined,
    'gift': Icons.card_giftcard_outlined,
  },
  // Здоров'я й сім'я
  {
    'health': Icons.favorite_border,
    'doctor': Icons.local_hospital_outlined,
    'tooth': Icons.health_and_safety_outlined,
    'baby': Icons.child_care,
    'family': Icons.family_restroom,
    'pet': Icons.pets,
  },
  // Розваги й освіта
  {
    'school': Icons.school_outlined,
    'book': Icons.menu_book_outlined,
    'movie': Icons.movie_outlined,
    'music': Icons.music_note_outlined,
    'sport': Icons.sports_soccer_outlined,
    'travel': Icons.luggage_outlined,
    'camp': Icons.cabin_outlined,
  },
  // Інше
  {
    'other': Icons.more_horiz,
  },
];

IconData finIcon(String key) {
  final v = kFinIcons[key] ?? kFinAccountIcons[key];
  if (v != null) return v;
  for (final g in kFinIconGroups) {
    final i = g[key];
    if (i != null) return i;
  }
  return Icons.more_horiz;
}
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

/// Знак валюти: ₴, $, €; інші - кодом.
String currencySymbol(String code) => switch (code) {
      'UAH' => '₴',
      'USD' => '\$',
      'EUR' => '€',
      _ => code,
    };

/// Сума в валюті [currency]: «1 250,50 \$».
String money(double v, String currency) =>
    uah(v).replaceFirst(RegExp(r' ₴$'), ' ${currencySymbol(currency)}');

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

/// Вибір значка за групами: заголовок групи і сітка значків під ним.
class FinIconPicker extends StatelessWidget {
  final String selected;
  final Color color;
  final ValueChanged<String> onPick;
  const FinIconPicker(
      {super.key, required this.selected, required this.color, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final names = tr.finIconGroups;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var g = 0; g < kFinIconGroups.length; g++) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(g < names.length ? names[g] : '',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in kFinIconGroups[g].entries)
              GestureDetector(
                onTap: () => onPick(e.key),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: e.key == selected ? color : AppColors.typeBtn,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(e.value,
                      size: 22,
                      color: e.key == selected ? AppColors.bg : AppColors.textMuted),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}
