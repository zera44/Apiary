import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  /// є кнопка "Заповнити".
  final bool placed;
  final double? lastUpdated;

  /// Прив'язаний QR-код (для розміщених об'єктів), або null.
  final String? qrCode;

  /// Номер наліпки прив'язаного коду (якщо відомий).
  final int? qrNumber;

  const PanelData({
    required this.type,
    this.variant,
    this.icon,
    this.color,
    required this.title,
    this.params = const [],
    this.placed = false,
    this.lastUpdated,
    this.qrCode,
    this.qrNumber,
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

  /// «Оглянуто, змін немає» — лише дата огляду (для вуликів).
  final VoidCallback? onVisited;
  final VoidCallback? onFill;

  /// Урок: підсвітити «Оглянути» медовим ободком.
  final bool highlightFill;

  /// Урок: ключ кнопки «Оглянути» (її дозволено натиснути).
  final Key? fillKey;
  final void Function(String parameterId)? onHistory;
  final VoidCallback? onQr;

  const CharacteristicsPanel({
    super.key,
    required this.data,
    required this.onClose,
    this.onRename,
    this.onIcon,
    this.onColor,
    this.onEditParams,
    this.onVisited,
    this.onFill,
    this.highlightFill = false,
    this.fillKey,
    this.onHistory,
    this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    final color = fillColor(data.type, data.color);
    final typeText = data.type == 'hive'
        ? 'Вулик'
        : () {
            final v = obstacleVariantLabel(data.variant);
            return v.isEmpty ? 'Перешкода' : 'Перешкода - $v';
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
                // у перешкод немає параметрів, історії й QR-кодів — лише назва й вигляд
                if (data.type == 'hive') ...[
                const SizedBox(height: 14),
                Text('Значення', style: muted),
                const SizedBox(height: 6),
                if (data.params.isEmpty && !(data.placed && onQr != null))
                  Text('-', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                else
                  _paramTable(context),
                const SizedBox(height: 18),
                PillButton(
                  text: 'Параметри',
                  bg: AppColors.accent,
                  height: 38,
                  fontSize: 13,
                  onPressed: onEditParams,
                ),
                if (data.placed) ...[
                  const SizedBox(height: 10),
                  HoneyRing(
                    key: fillKey,
                    on: highlightFill,
                    radius: 16,
                    child: PillButton(
                      text: 'Оглянути',
                      bg: AppColors.roundBtn,
                      fg: AppColors.text,
                      height: 38,
                      fontSize: 13,
                      onPressed: onFill,
                    ),
                  ),
                  if (onVisited != null) ...[
                    const SizedBox(height: 8),
                    PillButton(
                      text: 'Оглянуто, змін немає',
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 38,
                      fontSize: 13,
                      onPressed: onVisited,
                    ),
                  ],
                  if (onQr != null) ...[
                    const SizedBox(height: 10),
                    PillButton(
                      text: data.qrCode == null ? 'Прив\'язати QR-код' : 'QR-код…',
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 38,
                      fontSize: 13,
                      onPressed: onQr,
                    ),
                  ],
                ],
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

  /// Таблиця «параметр — значення» з медовою сіткою. Тап по рядку — історія
  /// значень цього параметра (для розміщеного об'єкта).
  Widget _paramTable(BuildContext context) {
    final grid = AppColors.hive.withValues(alpha: 0.55);
    final tappable = data.placed && onHistory != null;
    Widget cell(Parameter p, Widget child) {
      final c = Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9), child: child);
      return tappable ? TableRowInkWell(onTap: () => onHistory!(p.id), child: c) : c;
    }

    return Table(
      border: TableBorder.all(color: grid, width: 1, borderRadius: BorderRadius.circular(10)),
      columnWidths: const {0: FlexColumnWidth(1.25), 1: FlexColumnWidth(1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        if (data.placed && onQr != null)
          TableRow(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Text('QR-код',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.25))),
            _qrCell(context),
          ]),
        for (final (p, value) in data.params)
          TableRow(children: [
            cell(
                p,
                Text(p.nameWithUnit,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.25))),
            cell(p, _valueView(p, value)),
          ]),
      ],
    );
  }

  /// Значення QR-коду: порожньо, якщо не прив'язано; інакше номер — по тапу
  /// відкривається сам код.
  Widget _qrCell(BuildContext context) {
    final code = data.qrCode;
    if (code == null) return const SizedBox(height: 38);
    final label = data.qrNumber != null ? '№ ${data.qrNumber}' : code;
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 220,
            height: 220,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: code, backgroundColor: Colors.white),
            ),
          ),
          actions: [
            PillButton(
                text: 'Закрити',
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                onPressed: () => Navigator.pop(ctx)),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline)),
      ),
    );
  }

  /// Колір (мітка матки) — кружечком потрібного кольору, решта — текстом.
  Widget _valueView(Parameter p, String? value) {
    if (p.dataType == DataTypes.color && value != null && value.isNotEmpty) {
      final c = queenTagChoices.where((e) => e.$1 == value).firstOrNull;
      if (c != null) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: value,
            child: ColorTagSwatch(fill: c.$2, size: 30),
          ),
        );
      }
    }
    return Text((value == null || value.isEmpty) ? '-' : value,
                    style: TextStyle(
                        color: (value == null || value.isEmpty) ? AppColors.textMuted : AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600));
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
