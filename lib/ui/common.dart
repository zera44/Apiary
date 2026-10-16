import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../icons/app_icons.dart';
import 'icons.dart';
import 'theme.dart';

/// Текст, що переноситься лише між словами. Якщо найдовше слово не
/// вміщується в ширину (великий шрифт, вузька колонка), зменшується весь
/// напис - замість «Навчан/ня» чи «15.10.2/026».
class WordSafeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextAlign textAlign;
  const WordSafeText(this.text,
      {super.key, required this.style, this.maxLines, this.textAlign = TextAlign.start});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        var st = DefaultTextStyle.of(context).style.merge(style);
        if (c.maxWidth.isFinite) {
          final scaler = MediaQuery.textScalerOf(context);
          var widest = 0.0;
          for (final w in text.split(RegExp(r'\s+'))) {
            if (w.isEmpty) continue;
            final tp = TextPainter(
                text: TextSpan(text: w, style: st),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1)
              ..layout();
            if (tp.width > widest) widest = tp.width;
            tp.dispose();
          }
          if (widest > c.maxWidth && widest > 0) {
            // з невеликим запасом на округлення ширини гліфів
            st = st.copyWith(fontSize: (st.fontSize ?? 14) * c.maxWidth / widest * 0.98);
          }
        }
        return Text(text,
            style: st,
            maxLines: maxLines,
            textAlign: textAlign,
            overflow: maxLines == null ? null : TextOverflow.ellipsis);
      });
}

/// Кругла кнопка з іконкою, намальованою лініями.
class CircleIconButton extends StatelessWidget {
  final String icon;
  final Color bg;
  final Color iconColor;
  final double size;
  final VoidCallback? onPressed;
  final Color? disabledBg;
  final String? tooltip;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.bg,
    this.iconColor = Colors.white,
    this.size = 46,
    this.onPressed,
    this.disabledBg,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? bg : (disabledBg ?? bg.withValues(alpha: 0.45));
    Widget btn = Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _IconPainter(icon, enabled ? iconColor : iconColor.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

class _IconPainter extends CustomPainter {
  final String icon;
  final Color color;
  _IconPainter(this.icon, this.color);
  @override
  void paint(Canvas canvas, Size size) =>
      paintAppIcon(canvas, icon, size.center(Offset.zero), size.width, size.height, color);
  @override
  bool shouldRepaint(_IconPainter o) => o.icon != icon || o.color != color;
}

/// Заокруглена кнопка-пігулка з текстом.
class PillButton extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final VoidCallback? onPressed;
  final double height;
  final double radius;
  final double fontSize;
  final double? width;

  /// Замість напису - зрозуміла іконка (напис стає підказкою).
  final IconData? icon;

  const PillButton({
    super.key,
    this.icon,
    required this.text,
    required this.bg,
    this.fg = Colors.white,
    this.onPressed,
    this.height = 42,
    this.radius = 14,
    this.fontSize = 14,
    this.width,
  });

  bool _twoLinesFit(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(fontSize) * 1.1 * 2 + 6 <= height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Material(
        color: onPressed == null ? bg.withValues(alpha: 0.45) : bg,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: icon != null
                  ? Tooltip(message: text, child: Icon(icon, color: fg, size: 26))
                  // вузька кнопка: кілька слів - переноситься на другий рядок, одне
                  // слово - стискається (без «…» і без розриву слова навпіл).
                  // Два рядки не вміщуються по висоті (великий шрифт) - один
                  // рядок, стиснутий, а не притиснутий до країв кнопки
                  : (text.trim().contains(RegExp(r'\s')) && _twoLinesFit(context)
                      ? Text(
                          text,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: fg,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w500,
                              height: 1.1),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            text,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                color: fg, fontSize: fontSize, fontWeight: FontWeight.w500),
                          ),
                        )),
            ),
          ),
        ),
      ),
    );
  }
}

/// Напівпрозора капсула з текстом (статус / попередження вгорі).
class CapsuleLabel extends StatelessWidget {
  final String text;
  final Color? bg;
  final Color? fg;
  const CapsuleLabel(this.text, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: text.isEmpty ? 0 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bg ?? AppColors.capsule,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg ?? AppColors.text, fontSize: 12)),
      ),
    );
  }
}

/// Товста заокруглена рамка навколо екрана (декоративна).
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _FramePainter(), size: Size.infinite),
      );
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const w = 6.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
    // кути поза заокругленням
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRRect(r);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => false;
}

/// Верхня панель екранів-списків: кнопка "назад", заголовок, дія праворуч.
class TopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// Якщо задано — зліва замість "назад" показується кнопка меню (три смужки).
  final VoidCallback? onMenu;

  /// Обгортка кнопки «назад» (урок: медовий ободок).
  final Widget Function(Widget back)? decorateBack;
  const TopBar(
      {super.key, required this.title, this.onBack, this.trailing, this.onMenu, this.decorateBack});

  @override
  Widget build(BuildContext context) {
    // меню навігації — як на карті: назва скраю, велика кнопка під нею ліворуч
    if (onBack == null && onMenu != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 14, 0),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 34),
            child: CircleIconButton(
          icon: 'menu',
          bg: AppColors.roundBtn,
          iconColor: AppColors.text,
          size: 48,
          tooltip: 'Меню',
          onPressed: onMenu,
        ),
          ),
        ),
      ]);
    }
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          if (onBack != null)
            (decorateBack ?? (w) => w)(CircleIconButton(
              icon: 'back_arrow',
              bg: AppColors.roundBtn,
              iconColor: AppColors.text,
              size: 34,
              onPressed: onBack,
            ))
          else if (onMenu != null)
            CircleIconButton(
              icon: 'menu',
              bg: AppColors.roundBtn,
              iconColor: AppColors.text,
              size: 34,
              tooltip: 'Меню',
              onPressed: onMenu,
            )
          else
            const SizedBox(width: 34),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          trailing ?? const SizedBox(width: 34),
        ]),
      ),
    );
  }
}

/// Картка списку (шаблон / параметр / запис історії).
/// Найбільша ширина вмісту екранів-списків і форм: на планшеті вони не
/// розтягуються на весь екран, а стоять по центру (карта - на всю ширину).
const double kContentMaxWidth = 720;

/// Вміст екрана (верхня смуга й решта) - колонкою не ширшою за
/// [kContentMaxWidth], по центру. На телефоні - як звичайна колонка.
class ScreenColumn extends StatelessWidget {
  final List<Widget> children;
  const ScreenColumn({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Column(children: children),
        ),
      );
}

class ListCard extends StatelessWidget {
  final Widget child;
  final double height;
  const ListCard({super.key, required this.child, this.height = 66});
  @override
  Widget build(BuildContext context) => Container(
        // не нижча за [height]; більший шрифт - росте разом із текстом
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// Власна квадратна позначка вибору (в стилі застосунку).
class CheckToggle extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool>? onChanged;
  const CheckToggle({super.key, required this.checked, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!checked) : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: checked ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: checked ? null : Border.all(color: const Color(0xFF807061), width: 1.8),
            ),
            child: checked ? const AppIcon('check', color: Colors.white, size: 26) : null,
          ),
        ),
      ),
    );
  }
}

/// "Замочок" замість чекбокса: характеристика обов'язкова й завжди обрана.
class LockMark extends StatelessWidget {
  const LockMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Tooltip(
          message: "Обов'язкова характеристика",
          child: AppIcon('lock', color: AppColors.textMuted, size: 26),
        ),
      ),
    );
  }
}

/// Кругла кнопка-зразок кольору (для типу даних "Колір").
class ColorTagSwatch extends StatelessWidget {
  final Color? fill; // null — "без кольору"
  final bool selected;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  const ColorTagSwatch(
      {super.key, this.fill, this.selected = false, this.onTap, this.tooltip, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final swatch = GestureDetector(
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _SwatchPainter(fill, selected)),
      ),
    );
    return tooltip == null ? swatch : Tooltip(message: tooltip!, child: swatch);
  }
}

class _SwatchPainter extends CustomPainter {
  final Color? fill;
  final bool selected;
  _SwatchPainter(this.fill, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final muted = Paint()
      ..color = AppColors.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (fill != null) {
      canvas.drawCircle(c, r * 0.78, Paint()..color = fill!);
      canvas.drawCircle(c, r * 0.78, muted);
    } else {
      canvas.drawCircle(c, r * 0.78, muted..strokeWidth = 2);
      canvas.drawLine(c + Offset(-r * 0.5, r * 0.5), c + Offset(r * 0.5, -r * 0.5), muted);
    }
    if (selected) {
      canvas.drawCircle(
        c,
        r * 0.96,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter o) => o.fill != fill || o.selected != selected;
}

// ---------------------------------------------------------------------------
// Діалоги
// ---------------------------------------------------------------------------

Widget _dialogButtons(List<Widget> buttons) => Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: buttons[i]),
        ]
      ],
    );

/// Підтвердження дії. Повертає true, якщо підтверджено.
Future<bool> showConfirm(
  BuildContext context, {
  required String text,
  String title = 'Підтвердження',
  String confirmText = 'Видалити',
  bool danger = true,
  String cancelText = 'Скасувати',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text, style: TextStyle(color: AppColors.text)),
      actions: [
        _dialogButtons([
          PillButton(
              text: cancelText,
              bg: AppColors.neutralBtn,
              fg: AppColors.text,
              onPressed: () => Navigator.pop(ctx, false)),
          PillButton(
              text: confirmText,
              bg: danger ? AppColors.danger : AppColors.accent,
              onPressed: () => Navigator.pop(ctx, true)),
        ]),
      ],
    ),
  );
  return res ?? false;
}

/// Повідомлення з кнопкою "Гаразд".
Future<void> showInfo(BuildContext context, String text, {String title = ''}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: title.isEmpty ? null : Text(title),
      content: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.text)),
      actions: [
        _dialogButtons([
          PillButton(text: 'Гаразд', bg: AppColors.accent, onPressed: () => Navigator.pop(ctx)),
        ]),
      ],
    ),
  );
}

/// Запит тексту (перейменування). Повертає новий текст або null.
///
/// [validate] - текст помилки (тоді вікно не закривається) або null.
/// [wrap] - обгортка вікна (урок малює під ним пасічника), [decorate] -
/// обгортка кнопок ('save' / 'cancel'), напр. медовий ободок уроку.
Future<String?> showTextPrompt(BuildContext context,
    {required String title,
    required String initial,
    String? Function(String text)? validate,
    Widget Function(Widget dialog)? wrap,
    Widget Function(String which, Widget button)? decorate,
    bool dismissible = true}) {
  // початкова назва виділена: перше ж натискання клавіші замінює її
  final ctrl = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  String? error;
  return showDialog<String>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      void save() {
        final v = ctrl.text.trim();
        final e = validate?.call(v);
        if (e != null) {
          setD(() => error = e);
          return;
        }
        Navigator.pop(ctx, v.isEmpty ? initial : v);
      }

      final dec = decorate;
      Widget deco(String which, Widget b) => dec == null ? b : dec(which, b);
      final dialog = AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: AppColors.text),
            onChanged: (_) {
              if (error != null) setD(() => error = null);
            },
            onSubmitted: (_) => save(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
        ]),
        actions: [
          _dialogButtons([
            deco(
                'cancel',
                PillButton(
                    text: 'Скасувати',
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    onPressed: () => Navigator.pop(ctx))),
            deco('save', PillButton(text: 'Зберегти', bg: AppColors.accent, onPressed: save)),
          ]),
        ],
      );
      final w = wrap;
      return w == null ? dialog : w(dialog);
    }),
  );
}

/// Діалог-сітка для вибору іконки. [withReset] — кнопка "Типова".
/// [elType] — тип об'єкта: 'hive' — лише іконки вуликів, 'obstacle' — лише
/// перешкод; null (обрано різне) — дві плитки: «Вулики» і «Перешкоди».
/// Повертає ('', null) для скидання, (key, key) для вибору, null — скасовано.
Future<(String?,)?> pickIcon(BuildContext context, {bool withReset = false, String? elType}) {
  Widget grid(BuildContext ctx, List<(String, String)> icons) =>
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (key, label) in icons)
          CircleIconButton(
            icon: key,
            bg: AppColors.roundBtn,
            iconColor: AppColors.text,
            size: 52,
            tooltip: label,
            onPressed: () => Navigator.pop(ctx, (key,)),
          ),
      ]);
  // плитка-розділ: заголовок і сітка іконок у рамці
  Widget tile(BuildContext ctx, String title, List<(String, String)> icons) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hive.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          grid(ctx, icons),
        ]),
      );
  final hives = AppIcons.pickableIn('objects');
  final obstacles = AppIcons.pickableIn('obstacles');
  return showDialog<(String?,)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(switch (elType) {
        'hive' => 'Іконка вулика',
        'obstacle' => 'Іконка перешкоди',
        _ => 'Обрати іконку',
      }),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (withReset) ...[
              PillButton(
                text: 'Типова',
                bg: AppColors.roundBtn,
                fg: AppColors.text,
                height: 36,
                width: double.infinity,
                fontSize: 12,
                onPressed: () => Navigator.pop(ctx, (null,)),
              ),
              const SizedBox(height: 12),
            ],
            if (elType == 'hive')
              grid(ctx, hives)
            else if (elType == 'obstacle')
              grid(ctx, obstacles)
            else ...[
              tile(ctx, 'Вулики', hives),
              const SizedBox(height: 10),
              tile(ctx, 'Перешкоди', obstacles),
            ],
          ]),
        ),
      ),
    ),
  );
}

/// Діалог вибору кольору об'єкта. Результат як у [pickIcon].
Future<(String?,)?> pickObjectColor(BuildContext context, {bool withReset = false}) {
  return showDialog<(String?,)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Обрати колір'),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (withReset) ...[
            PillButton(
              text: 'Типовий',
              bg: AppColors.roundBtn,
              fg: AppColors.text,
              height: 36,
              width: double.infinity,
              fontSize: 12,
              onPressed: () => Navigator.pop(ctx, (null,)),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (hex, name) in objectColorChoices)
              Tooltip(
                message: name,
                child: Material(
                  color: _hex(hex),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, (hex,)),
                    child: const SizedBox.square(dimension: 46),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    ),
  );
}

Color _hex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Видалення без «Точно видалити?»: [hide] одразу прибирає з екрана, внизу —
/// «[message]» з кнопкою «Відмінити». Відмінили — [restore]; повідомлення
/// зникло (час минув, нове повідомлення, перехід) — [commit], справжнє
/// видалення.
Future<void> deleteWithUndo(
  BuildContext context, {
  required String message,
  required VoidCallback hide,
  required VoidCallback restore,
  required Future<void> Function() commit,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  hide();
  messenger.hideCurrentSnackBar();
  final ctrl = messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 5),
    // з дією SnackBar інакше висить, доки не натиснуть — а видалення має
    // завершитись само через 5 с
    persist: false,
    action: SnackBarAction(label: 'Відмінити', onPressed: () {}),
  ));
  final reason = await ctrl.closed;
  if (reason == SnackBarClosedReason.action) {
    restore();
  } else {
    await commit();
  }
}

/// Урок: медовий ободок навколо кнопки, яку треба натиснути. Щойно ободок
/// з'являється, кнопку прокручує в поле зору (якщо вона у списку, що гортається).
class HoneyRing extends StatefulWidget {
  final bool on;
  final Widget child;
  final double radius;
  const HoneyRing({super.key, required this.on, required this.child, this.radius = 999});
  @override
  State<HoneyRing> createState() => _HoneyRingState();
}

class _HoneyRingState extends State<HoneyRing> {
  @override
  void initState() {
    super.initState();
    if (widget.on) _reveal();
  }

  @override
  void didUpdateWidget(HoneyRing old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(context,
              alignment: 0.5, duration: const Duration(milliseconds: 250));
        }
      });

  @override
  Widget build(BuildContext context) {
    // ободок малюється ПОЗА кнопкою й нічого не зсуває (розмір той самий);
    // увімкнений ободок - ще й «вікно» в затемненні уроку (див. LessonScrim)
    return Stack(clipBehavior: Clip.none, children: [
      SpotlightHole(on: widget.on, radius: widget.radius, child: widget.child),
      if (widget.on)
        Positioned(
          left: -5,
          top: -5,
          right: -5,
          bottom: -5,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius + 5),
                border: Border.all(color: AppColors.create, width: 3),
                boxShadow: [
                  BoxShadow(color: AppColors.create.withValues(alpha: 0.5), blurRadius: 12)
                ],
              ),
            ),
          ),
        ),
    ]);
  }
}


/// Вкладки змінюються ще й свайпом: провели пальцем вліво - наступна,
/// вправо - попередня. Вертикальне гортання списків усередині не заважає.
class TabSwipe extends StatelessWidget {
  final int index;
  final int count;
  final ValueChanged<int> onChanged;
  final Widget child;
  const TabSwipe(
      {super.key,
      required this.index,
      required this.count,
      required this.onChanged,
      required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250 && index < count - 1) {
            onChanged(index + 1);
          } else if (v > 250 && index > 0) {
            onChanged(index - 1);
          }
        },
        child: child,
      );
}


/// Ціль уроку, яку не затемнювати: [LessonScrim] на тому ж екрані вирізає
/// навколо неї «вікно».
class SpotlightHole extends StatefulWidget {
  final Widget child;
  final double radius;

  /// false - звичайний віджет (так дерево не перебудовується, коли ціль
  /// вмикається й вимикається).
  final bool on;
  const SpotlightHole({super.key, required this.child, this.radius = 16, this.on = true});

  /// Усі зараз показані цілі.
  static final active = <SpotlightHoleState>{};

  @override
  State<SpotlightHole> createState() => SpotlightHoleState();
}

class SpotlightHoleState extends State<SpotlightHole> {
  ModalRoute<dynamic>? route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    SpotlightHole.active.add(this);
  }

  @override
  void dispose() {
    SpotlightHole.active.remove(this);
    super.dispose();
  }

  /// Рамка в глобальних координатах (або null, поки не викладено).
  Rect? get globalRect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Урок: притемнює екран, крім цілей ([SpotlightHole] на тому ж екрані й
/// [extra]). Ставиться під пасічником із хмаркою - їх не затемнює.
/// Без цілей - нічого не малює.
class LessonScrim extends StatefulWidget {
  /// Ще цілі (у своїх координатах): клітинки карти тощо.
  final List<Rect> Function(RenderBox self)? extra;
  const LessonScrim({super.key, this.extra});

  @override
  State<LessonScrim> createState() => LessonScrimState();
}

class LessonScrimState extends State<LessonScrim> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  List<RRect> _holes = const [];

  /// «Вікна» в затемненні (у координатах завіси).
  List<RRect> get holes => _holes;

  @override
  void initState() {
    super.initState();
    // цілі рухаються разом із прокруткою й анімаціями - стежимо щокадру
    _ticker = createTicker((_) => _update())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _update() {
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize || !self.attached) return;
    final route = ModalRoute.of(context);
    final holes = <RRect>[];
    for (final h in SpotlightHole.active) {
      if (!h.mounted || !h.widget.on || h.route != route) continue;
      final g = h.globalRect;
      if (g == null) continue;
      final r = self.globalToLocal(g.topLeft) & g.size;
      holes.add(RRect.fromRectAndRadius(r.inflate(6), Radius.circular(h.widget.radius + 6)));
    }
    for (final r in widget.extra?.call(self) ?? const <Rect>[]) {
      holes.add(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(12)));
    }
    if (!_same(holes, _holes)) setState(() => _holes = holes);
  }

  static bool _same(List<RRect> a, List<RRect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _ScrimPainter(_holes), child: const SizedBox.expand()),
      );
}

class _ScrimPainter extends CustomPainter {
  final List<RRect> holes;
  _ScrimPainter(this.holes);

  @override
  void paint(Canvas canvas, Size size) {
    if (holes.isEmpty) return;
    // «вікна» об'єднуємо: ціль і її сяйво перекриваються, а з even-odd
    // перекриття знову ставало темним
    Path? cut;
    for (final h in holes) {
      final hp = Path()..addRRect(h);
      cut = cut == null ? hp : Path.combine(PathOperation.union, cut, hp);
    }
    final p = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), cut!);
    canvas.drawPath(p, Paint()..color = Colors.black.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.holes != holes;
}
