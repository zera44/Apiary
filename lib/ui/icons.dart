import 'package:flutter/material.dart';

import '../icons/app_icons.dart';
import '../l10n/l10n.dart';

export '../icons/app_icons.dart' show AppIcons;

/// Іконки застосунку — SVG-файли в `assets/icons/` (див. README там же):
/// їх можна змінювати й додавати, не чіпаючи код. Тут — зручні обгортки для
/// малювання й списки вибору (обидва списки беруться з реєстру icons.json).

/// Намалювати іконку [name] з центром у [center] у прямокутнику w×h.
void paintAppIcon(Canvas canvas, String name, Offset center, double w, double h, Color color) =>
    AppIcons.paint(canvas, name, center, w, h, color);

bool hasAppIcon(String name) => AppIcons.has(name);

/// Варіанти перешкоди: (ключ, назва) — з реєстру іконок (`variantLabel`).
List<(String, String)> get obstacleVariants => AppIcons.obstacleVariants;

String obstacleVariantLabel(String? key) {
  for (final (k, l) in obstacleVariants) {
    if (k == (key ?? 'mountain')) return l;
  }
  return '';
}

/// Іконки, які можна обрати для будь-якого об'єкта (`pickable` у реєстрі).
List<(String, String)> get objectIconChoices => AppIcons.pickable;

/// Кольори об'єкта (без службових кольорів карти).
const _objectColors = ['#ED9D2F', '#F2B705', '#CD6133', '#D64550', '#E0729C', '#9B4F96', '#C9A227', '#FF7A59', '#8C3B3B', '#F2A65A'];

/// Кольори об'єкта з назвами поточною мовою.
List<(String, String)> get objectColorChoices =>
    [for (var i = 0; i < _objectColors.length; i++) (_objectColors[i], tr.objectColorNames[i])];

/// Варіанти "Мітки матки" (тип даних "Колір"); null — без кольору.
const queenTagChoices = <(String, Color?)>[
  ('Без кольору', null),
  ('Білий', Color(0xFFF2F2F2)),
  ('Жовтий', Color(0xFFF2D926)),
  ('Червоний', Color(0xFFD93333)),
  ('Зелений', Color(0xFF40994D)),
  ('Синій', Color(0xFF3373D9)),
];

/// Віджет-іконка.
class AppIcon extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const AppIcon(this.name, {super.key, this.color = Colors.white, this.size = 46});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _AppIconPainter(name, color)),
      );
}

class _AppIconPainter extends CustomPainter {
  final String name;
  final Color color;
  _AppIconPainter(this.name, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    paintAppIcon(canvas, name, size.center(Offset.zero), size.width, size.height, color);
  }

  @override
  bool shouldRepaint(_AppIconPainter old) => old.name != name || old.color != color;
}
