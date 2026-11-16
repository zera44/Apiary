import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../logic/stock_format.dart';
import 'icons.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Значки категорій фінансів (ключ зберігається в базі). Значення: [IconData]
/// з Tabler або назва власного значка з реєстру (assets/icons).
const Map<String, Object> kFinIcons = {
  'feed': TablerIcons.basket,
  'medicine': TablerIcons.pill,
  'frame': 'frame',
  'honey': 'hexagon',
  'jar': 'honey_jar',
  'car': TablerIcons.car,
  'tool': TablerIcons.tool,
  'drop': TablerIcons.droplet,
  'scale': TablerIcons.scale,
  'home': TablerIcons.home,
  'doc': TablerIcons.receipt,
  'other': TablerIcons.dots,
};

/// Значки рахунків (гаманців).
const Map<String, Object> kFinAccountIcons = {
  'payments': TablerIcons.cash,
  'card': TablerIcons.credit_card,
  'bank': TablerIcons.building_bank,
  'savings': TablerIcons.pig_money,
  'wallet': TablerIcons.wallet,
  'safe': TablerIcons.lock,
};

/// Каталог значків за групами (назви груп - `tr.finIconGroups`, у тому ж
/// порядку). Ключ зберігається в базі, тож наявні ключі не змінюємо.
const List<Map<String, Object>> kFinIconGroups = [
  // Гроші й банки
  {
    'payments': TablerIcons.cash,
    'card': TablerIcons.credit_card,
    'bank': TablerIcons.building_bank,
    'savings': TablerIcons.pig_money,
    'wallet': TablerIcons.wallet,
    'safe': TablerIcons.lock,
    'dollar': TablerIcons.currency_dollar,
    'euro': TablerIcons.currency_euro,
    'hryvnia': TablerIcons.currency_hryvnia,
    'coin': TablerIcons.coin,
    'coins': TablerIcons.coins,
    'exchange': TablerIcons.arrows_left_right,
    'phone_pay': TablerIcons.device_mobile,
    'contactless': TablerIcons.credit_card_pay,
    'invest': TablerIcons.chart_line,
    'percent': TablerIcons.percentage,
    'shield': TablerIcons.shield,
    'briefcase': TablerIcons.briefcase,
    'gift_card': TablerIcons.gift_card,
    'group': TablerIcons.topology_star,
    'gift_money': TablerIcons.gift,
    'calc': TablerIcons.calculator,
  },
  // Пасіка
  {
    'hive': 'beehive',
    'skep': 'skep',
    'frame': 'frame',
    'extractor': 'extractor',
    'jar': 'honey_jar',
    'smoker': 'smoker',
    'queen_cell': 'queen_cell',
    'wax': 'wax',
    'sugar': 'sugar',
    'treatment': 'treatment',
    'barrel': 'barrel',
    'flower': 'honey_plants',
    'veil': 'veil',
    'bee': 'bee',
    'honey': 'hexagon',
    'feed': TablerIcons.basket,
    'medicine': TablerIcons.pill,
    'drop': TablerIcons.droplet,
    'scale': TablerIcons.scale,
    'tool': TablerIcons.tool,
  },
  // Ферма
  {
    'tractor': TablerIcons.tractor,
    'tree': TablerIcons.tree,
    'trees': TablerIcons.trees,
    'sprout': TablerIcons.seeding,
    'barn': TablerIcons.building_warehouse,
    'fence': TablerIcons.fence,
    'apple': TablerIcons.apple,
    'factory': TablerIcons.building_factory,
  },
  // Транспорт
  {
    'car': TablerIcons.car,
    'fuel': TablerIcons.gas_station,
    'truck': TablerIcons.truck,
    'train': TablerIcons.train,
    'bus': TablerIcons.bus,
    'moto': TablerIcons.motorbike,
    'bike': TablerIcons.bike,
    'plane': TablerIcons.plane,
    'parking': TablerIcons.parking,
    'garage': TablerIcons.car_garage,
    'ship': TablerIcons.ship,
  },
  // Дім і комуналка
  {
    'home': TablerIcons.home,
    'cottage': TablerIcons.building_cottage,
    'light': TablerIcons.bulb,
    'fire': TablerIcons.flame,
    'wifi': TablerIcons.wifi,
    'phone': TablerIcons.phone,
    'heat': TablerIcons.temperature,
    'repair': TablerIcons.hammer,
    'tools': TablerIcons.tools,
    'plug': TablerIcons.plug,
    'doc': TablerIcons.receipt,
  },
  // Покупки й їжа
  {
    'cart': TablerIcons.shopping_cart,
    'store': TablerIcons.building_store,
    'shirt': TablerIcons.shirt,
    'phone_buy': TablerIcons.device_mobile,
    'devices': TablerIcons.device_laptop,
    'food': TablerIcons.bread,
    'coffee': TablerIcons.coffee,
    'drink': TablerIcons.beer,
    'pizza': TablerIcons.pizza,
    'gift': TablerIcons.gift,
  },
  // Краса й здоров'я
  {
    'hair': TablerIcons.scissors,
    'shave': TablerIcons.razor,
    'makeup': TablerIcons.brush,
    'spray': TablerIcons.spray,
    'perfume': TablerIcons.perfume,
    'manicure': TablerIcons.hand_finger,
    'massage': TablerIcons.massage,
    'bath': TablerIcons.bath,
    'beauty': TablerIcons.sparkles,
    'smile': TablerIcons.mood_smile,
    'glasses': TablerIcons.eyeglass,
    'yoga': TablerIcons.yoga,
    'gym': TablerIcons.barbell,
    'health': TablerIcons.heart,
    'pulse': TablerIcons.heartbeat,
    'doctor': TablerIcons.stethoscope,
    'tooth': TablerIcons.dental,
    'vaccine': TablerIcons.vaccine,
    'first_aid': TablerIcons.first_aid_kit,
    'bandage': TablerIcons.bandage,
  },
  // Сім'я й тварини
  {
    'baby': TablerIcons.baby_carriage,
    'bottle': TablerIcons.baby_bottle,
    'family': TablerIcons.users,
    'pet': TablerIcons.paw,
    'dog': TablerIcons.dog,
    'cat': TablerIcons.cat,
  },
  // Розваги й освіта
  {
    'school': TablerIcons.school,
    'book': TablerIcons.book,
    'movie': TablerIcons.movie,
    'music': TablerIcons.music,
    'sport': TablerIcons.ball_football,
    'travel': TablerIcons.luggage,
    'camp': TablerIcons.tent,
    'ticket': TablerIcons.ticket,
    'trophy': TablerIcons.trophy,
    'swim': TablerIcons.swimming,
    'campfire': TablerIcons.campfire,
  },
  // Інше
  {
    'other': TablerIcons.dots,
  },
];

/// Значок за ключем: Tabler або власний SVG.
Widget finIconWidget(String key, {required double size, required Color color}) {
  Object? v = kFinIcons[key] ?? kFinAccountIcons[key];
  if (v == null) {
    for (final g in kFinIconGroups) {
      v = g[key];
      if (v != null) break;
    }
  }
  v ??= TablerIcons.dots;
  if (v is String) return AppIcon(v, size: size, color: color);
  return Icon(v as IconData, size: size, color: color);
}
/// Кольори категорій (ключ -> колір).
const Map<String, Color> kFinColors = {
  'honey': Color(0xFFED9D2F),
  'olive': Color(0xFF8E9D3D),
  'terra': Color(0xFFCD4C28),
  'light': Color(0xFFF3C969),
  'nut': Color(0xFF9C7A55),
  'sky': Color(0xFF6E9FB8),
  'plum': Color(0xFF9B6A9E),
  'coral': Color(0xFFE8795A),
  'rose': Color(0xFFD9708A),
  'lime': Color(0xFFB7C94A),
  'green': Color(0xFF4FA36A),
  'teal': Color(0xFF3E9C97),
  'cyan': Color(0xFF5BB8D0),
  'blue': Color(0xFF4A7FC1),
  'indigo': Color(0xFF6B6CC4),
  'violet': Color(0xFF8E5CC4),
  'magenta': Color(0xFFC25BA8),
  'stone': Color(0xFF9A9186),
  'crimson': Color(0xFFB8323F),
  'orange': Color(0xFFE8672A),
  'amber': Color(0xFFF5B82E),
  'sand': Color(0xFFD9C08A),
  'brown': Color(0xFF7A4E32),
  'moss': Color(0xFF5E7A32),
  'mint': Color(0xFF7CCBA2),
  'aqua': Color(0xFF2FA7A0),
  'navy': Color(0xFF2F5C8F),
  'lavender': Color(0xFFA99AD8),
  'purple': Color(0xFF6E3F8F),
  'pink': Color(0xFFE88FB4),
  'slate': Color(0xFF5E6B7A),
  'graphite': Color(0xFF4A423B),
};

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
        child: Center(
            child: finIconWidget(icon, size: size * 0.55, color: const Color(0xFF1D1611))),
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
                  child: Center(
                    child: finIconWidget(e.key,
                        size: 24,
                        color: e.key == selected ? AppColors.bg : AppColors.textMuted),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}
