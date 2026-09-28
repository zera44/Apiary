import 'package:flutter/material.dart';

import '../data/models.dart';
import '../logic/merge_layout.dart';
import 'cell_style.dart';
import 'common.dart';
import 'icons.dart';
import 'theme.dart';

/// Що показує панель "Характеристики".
class PanelData {
  final String type;
  final String? variant, icon, color;
  final String title;

  /// Параметри у порядку показу з останніми значеннями (null — ще немає).
  final List<(Parameter, String?)> params;

  /// true — об'єкт уже на карті: рядки параметрів тапаються (історія),
  /// є кнопка "Заповнити" і рядок "Дата оновлення".
  final bool placed;
  final double? lastUpdated;

  const PanelData({
    required this.type,
    this.variant,
    this.icon,
    this.color,
    required this.title,
    this.params = const [],
    this.placed = false,
    this.lastUpdated,
  });
}

const _typeColorNames = {'hive': 'Медовий оранжевий', 'obstacle': "Кам'яно-бежевий"};

String _colorName(String type, String? own) {
  if (own != null && own.isNotEmpty) {
    for (final (hex, name) in objectColorChoices) {
      if (hex.toUpperCase() == own.toUpperCase()) return name;
    }
    return 'Власний колір';
  }
  return _typeColorNames[type] ?? '';
}

/// Спільна панель "Характеристики", що висувається справа — і на карті, і в
/// редакторі шаблону (порт characteristics_panel.py).
class CharacteristicsPanel extends StatelessWidget {
  static const double width = 240;

  final PanelData data;
  final VoidCallback onClose;
  final VoidCallback? onRename;
  final VoidCallback? onIcon;
  final VoidCallback? onColor;
  final VoidCallback? onEditParams;
  final VoidCallback? onFill;
  final void Function(String parameterId)? onHistory;

  const CharacteristicsPanel({
    super.key,
    required this.data,
    required this.onClose,
    this.onRename,
    this.onIcon,
    this.onColor,
    this.onEditParams,
    this.onFill,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final color = fillColor(data.type, data.color);
    final typeText = data.type == 'hive'
        ? 'Вулик'
        : () {
            final v = obstacleVariantLabel(data.variant);
            return v.isEmpty ? 'Перешкода' : 'Перешкода — $v';
          }();
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold);

    return Material(
      color: AppColors.panel,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Stack(children: [
          Positioned.fill(
            top: 48,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 14, 18),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: onIcon,
                    child: SizedBox.square(
                      dimension: 72,
                      child: CustomPaint(
                        painter: _IconBoxPainter(data.type, data.variant, data.icon, color),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onRename,
                  child: Text(data.title,
                      style: TextStyle(
                          color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 2),
                Text(typeText, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 14),
                Text('Колір', style: muted),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onColor,
                  borderRadius: BorderRadius.circular(6),
                  child: Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_colorName(data.type, data.color)}  ${colorToHex(color)}',
                        style: TextStyle(color: AppColors.text, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('Параметри', style: muted),
                const SizedBox(height: 6),
                if (data.params.isEmpty)
                  Text('—', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                else
                  for (final (p, value) in data.params) _paramRow(p, value),
                if (data.placed) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Дата оновлення: ${data.lastUpdated == null ? 'ще немає даних' : _date(data.lastUpdated!)}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                PillButton(
                  text: 'Редагувати',
                  bg: AppColors.accent,
                  height: 38,
                  fontSize: 13,
                  onPressed: onEditParams,
                ),
                if (data.placed) ...[
                  const SizedBox(height: 10),
                  PillButton(
                    text: 'Заповнити',
                    bg: AppColors.roundBtn,
                    fg: AppColors.text,
                    height: 38,
                    fontSize: 13,
                    onPressed: onFill,
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 10,
            child: CircleIconButton(
              icon: 'close',
              bg: AppColors.roundBtn,
              iconColor: AppColors.text,
              size: 34,
              onPressed: onClose,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _paramRow(Parameter p, String? value) {
    final text = '•  ${p.nameWithUnit}${(value != null && value.isNotEmpty) ? ': $value' : ''}';
    final style = TextStyle(
      color: AppColors.text,
      fontSize: 13,
      decoration: data.placed ? TextDecoration.underline : null,
      decorationColor: AppColors.textMuted,
    );
    final t = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(text, style: style),
    );
    if (!data.placed || onHistory == null) return t;
    return InkWell(onTap: () => onHistory!(p.id), child: t);
  }

  static String _date(double ts) {
    final d = DateTime.fromMicrosecondsSinceEpoch((ts * 1e6).round());
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}

class _IconBoxPainter extends CustomPainter {
  final String type;
  final String? variant, icon;
  final Color color;
  _IconBoxPainter(this.type, this.variant, this.icon, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    drawBody(canvas, r, Merge.none, color, radius: 8);
    paintAppIcon(canvas, iconNameFor(type, variant, icon), r.center, size.width, size.height,
        AppColors.iconMark);
    // значок-підказка "олівець": іконку можна змінити
    const br = 11.0;
    final b = Offset(size.width - br * 0.7, size.height - br * 0.7);
    canvas.drawCircle(b, br, Paint()..color = AppColors.roundBtn);
    paintAppIcon(canvas, 'pencil', b, br * 1.3, br * 1.3, AppColors.text);
  }

  @override
  bool shouldRepaint(_IconBoxPainter o) =>
      o.type != type || o.variant != variant || o.icon != icon || o.color != color;
}
