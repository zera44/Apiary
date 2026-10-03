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

  /// Тап по значенню: швидка правка одного параметра (інакше — [onHistory]).
  final void Function(String parameterId)? onValue;

  /// Тап по комірці QR-коду: порожня — прив'язати, з номером — код і дії.
  final VoidCallback? onQr;

  /// Можна міняти назву, значок і колір (режим редагування / редактор шаблону).
  /// У робочому режимі панель лише показує інформацію.
  final bool editable;

  /// Показувати огляд: значення (історія по тапу), «Оглянути», «Змін немає»,
  /// QR-код. У режимі редагування вони ховаються.
  final bool inspect;

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
    this.onValue,
    this.onQr,
    this.editable = true,
    this.inspect = true,
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
                    onTap: editable ? onIcon : null,
                    child: SizedBox.square(
                      dimension: 72,
                      child: CustomPaint(
                        painter: _IconBoxPainter(data.type, data.variant, data.icon, color, editable),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: editable ? onRename : null,
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
                  onTap: editable ? onColor : null,
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
                if (data.placed && inspect) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: HoneyRing(
                        key: fillKey,
                        on: highlightFill,
                        radius: 16,
                        child: PillButton(
                          text: 'Оглянути',
                          bg: AppColors.roundBtn,
                          fg: AppColors.text,
                          height: 38,
                          fontSize: 13,
                          width: double.infinity,
                          onPressed: onFill,
                        ),
                      ),
                    ),
                    if (onVisited != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillButton(
                          text: 'Змін немає',
                          bg: AppColors.darkBtn,
                          fg: AppColors.text,
                          height: 38,
                          fontSize: 13,
                          width: double.infinity,
                          onPressed: onVisited,
                        ),
                      ),
                    ],
                  ]),
                ],
                // набір параметрів вулика — у самому низу інформації
                const SizedBox(height: 18),
                PillButton(
                  text: 'Параметри',
                  bg: AppColors.accent,
                  height: 38,
                  fontSize: 13,
                  onPressed: onEditParams,
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

  /// Значення блоками: у рядку по два, у кожного - маленька назва зверху й
  /// значення під нею. Тап по блоку - швидка правка / історія значення
  /// (для розміщеного об'єкта); QR-код - прив'язка чи перегляд коду.
  Widget _paramTable(BuildContext context) {
    final tap = data.placed ? (onValue ?? onHistory) : null;
    final blocks = <Widget>[
      if (data.placed && onQr != null) _block('QR-код', _qrValue(), onQr),
      for (final (p, value) in data.params)
        _block(p.nameWithUnit, _valueView(p, value), tap == null ? null : () => tap(p.id)),
    ];
    return Column(children: [
      for (var i = 0; i < blocks.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: blocks[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < blocks.length ? blocks[i + 1] : const SizedBox()),
            ]),
          ),
        ),
    ]);
  }

  Widget _block(String label, Widget value, VoidCallback? onTap) => Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.hive.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.2)),
              const SizedBox(height: 5),
              value,
            ]),
          ),
        ),
      );

  /// Значення QR-коду: «-», якщо не прив'язано (тап по блоку - прив'язати),
  /// інакше номер наліпки (тап - сам код, «Інший» і «Відв'язати»).
  Widget _qrValue() {
    final code = data.qrCode;
    final label = code == null ? '-' : (data.qrNumber != null ? '№ ${data.qrNumber}' : code);
    return Text(label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: code == null
            ? TextStyle(color: AppColors.textMuted, fontSize: 15, fontWeight: FontWeight.w600)
            : TextStyle(color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w700));
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600));
  }
}

class _IconBoxPainter extends CustomPainter {
  final String type;
  final String? variant, icon;
  final Color color;
  final bool editable;
  _IconBoxPainter(this.type, this.variant, this.icon, this.color, this.editable);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    drawBody(canvas, r, Merge.none, color, radius: 8);
    paintAppIcon(canvas, iconNameFor(type, variant, icon), r.center, size.width, size.height,
        AppColors.iconMark);
    if (!editable) return;
    // значок-підказка "олівець": іконку можна змінити
    const br = 11.0;
    final b = Offset(size.width - br * 0.7, size.height - br * 0.7);
    canvas.drawCircle(b, br, Paint()..color = AppColors.roundBtn);
    paintAppIcon(canvas, 'pencil', b, br * 1.3, br * 1.3, AppColors.text);
  }

  @override
  bool shouldRepaint(_IconBoxPainter o) =>
      o.type != type || o.variant != variant || o.icon != icon || o.color != color || o.editable != editable;
}
