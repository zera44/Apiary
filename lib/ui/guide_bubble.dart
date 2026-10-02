import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'theme.dart';

/// Урок: де стоїть пасічник (над «Редагувати») і його малюнок — однакові
/// на всіх кроках.
/// Пасічник спирається руками на кнопку «Редагувати» (вона: ліворуч 16,
/// знизу 18, 150 × 50): руки трохи заходять на її верхній край, сам —
/// посередині кнопки.
const kLessonOnButtonBottom = 58.0;
const kLessonOnButtonLeft = 31.0;
const kLessonBeekeeper = 'assets/guide/beekeeper_nohive.webp';

/// Коли кнопки «Редагувати» немає (редагування, вибір шаблону, форма огляду)
/// — пасічник спирається на свою «стійку» (малюнок у тому ж масштабі, вищий).
const kLessonBeekeeperLeaning = 'assets/guide/beekeeper_hands.webp';
const kLessonLeaningHeight = 192.0;

/// Помічник-ведмедик (покусаний, з рамкою) — урок, форма огляду.
const kLessonBeekeeperPills = 'assets/guide/beekeeper_pills.webp';
const kLessonBear = 'assets/guide/bear_helper.webp';

/// Підказка режиму навчання: пасічник-провідник (малюнок автора,
/// assets/guide) зліва і «хмарка» з текстом справа.
class GuideBubble extends StatelessWidget {
  /// Текст підказки; виділені слова — через [GuideBubble.highlight].
  final List<InlineSpan> text;
  final String? image; // null — лише хмарка (пасічник стоїть окремо)

  /// Під хмаркою (у проміжку між нею й низом пасічника) — наприклад,
  /// «Пропустити».
  final Widget? below;

  /// Висота пасічника (компактна підказка — менша).
  final double imageHeight;

  /// Висота проміжку під хмаркою (до низу пасічника).
  final double gap;
  const GuideBubble(
      {super.key,
      required this.text,
      this.image = 'assets/guide/beekeeper.webp',
      this.below,
      this.imageHeight = 170,
      this.gap = 70,
      this.imageLeft = 12});

  /// Відступ пасічника від лівого краю.
  final double imageLeft;

  /// Назва кнопки в тексті підказки: іншим кольором і жирним.
  static TextSpan highlight(String s) => TextSpan(
        text: s,
        style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w800),
      );

  /// Те саме, але напівжирним — для завдання, а не назви кнопки.
  static TextSpan task(String s) => TextSpan(
        text: s,
        style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w600),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: imageLeft, right: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (image != null) ...[
          Image.asset(image!, height: imageHeight, filterQuality: FilterQuality.medium),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(
              painter: _BubblePainter(fill: AppColors.popupBg, border: AppColors.create),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
                child: Text.rich(
                  TextSpan(children: text),
                  style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.35),
                ),
              ),
            ),
            SizedBox(height: gap, child: Center(child: below)),
          ]),
        ),
      ]),
    );
  }
}

/// Заокруглена хмарка з «хвостиком» ліворуч (до пасічника).
class _BubblePainter extends CustomPainter {
  final Color fill;
  final Color border;
  _BubblePainter({required this.fill, required this.border});

  static const tail = 10.0;

  Path _shape(Size s) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(tail, 0, s.width - tail, s.height), const Radius.circular(16));
    final y = s.height * 0.62;
    final tip = Path()
      ..moveTo(tail + 1, y - 9)
      ..lineTo(0, y + 6)
      ..lineTo(tail + 1, y + 5)
      ..close();
    return Path.combine(PathOperation.union, Path()..addRRect(body), tip);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _shape(size);
    canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(
        p,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.fill != fill || old.border != border;
}

/// Хто стоїть в уроці: пасічник спирається на «Редагувати», на свою «стійку»
/// (кнопки немає) чи замість нього — ведмежа-помічник.
enum LessonPose { onButton, leaning, pills, bear }

/// Урок: персонаж на ОДНОМУ місці (не стрибає між кроками й вікнами) і хмарка
/// праворуч від нього. Обидва малюнки пасічника — в одному масштабі, тож
/// голова й руки лишаються там самі; змінюється лише те, на що він спирається.
/// [bottomInset] — нижній системний відступ (у вікнах, що на весь екран).
List<Widget> lessonScene({
  required LessonPose pose,
  List<InlineSpan>? text,
  Widget? below,
  VoidCallback? onTap,
  double bottomInset = 0,
}) {
  final base = kLessonOnButtonBottom + bottomInset;
  final (img, h, left, bottom) = switch (pose) {
    LessonPose.onButton => (kLessonBeekeeper, 170.0, kLessonOnButtonLeft, base),
    // «стійка» нижче рук: малюнок вищий і ширший, руки — там само
    LessonPose.leaning => (
        kLessonBeekeeperLeaning,
        kLessonLeaningHeight,
        kLessonOnButtonLeft - 37.6,
        base - 22.3
      ),
    // той самий кадр, що «стійка», але пасічник із бджолами-пігулками
    LessonPose.pills => (
        kLessonBeekeeperPills,
        kLessonLeaningHeight,
        kLessonOnButtonLeft - 37.6,
        base - 22.3
      ),
    LessonPose.bear => (kLessonBear, 150.0, 12.0, base),
  };
  final bubble = text == null
      ? null
      : GuideBubble(text: text, image: null, imageLeft: 0, below: below);
  return [
    Positioned(
      left: left,
      bottom: bottom,
      child: IgnorePointer(
        child: Image.asset(img, height: h, filterQuality: FilterQuality.medium),
      ),
    ),
    if (bubble != null)
      Positioned(
        left: kLessonBubbleLeft,
        right: 0,
        bottom: base,
        child: Material(
          type: MaterialType.transparency,
          child: onTap != null
              ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: bubble)
              : below != null
                  ? bubble // кнопки під хмаркою мають натискатися
                  : IgnorePointer(child: bubble),
        ),
      ),
  ];
}

/// Хмарка уроку починається одразу праворуч від пасічника.
const kLessonBubbleLeft = 150.0;

/// Урок: «завіса» на весь екран — поки навчання чекає певної дії, інше
/// натиснути не можна. Пропускає дотик лише там, де [allow] (у своїх
/// координатах) каже «так»: кнопка, яку треба натиснути, вулик тощо.
class LessonGate extends LeafRenderObjectWidget {
  final bool Function(Offset local) allow;
  const LessonGate({super.key, required this.allow});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLessonGate(allow);

  @override
  void updateRenderObject(BuildContext context, _RenderLessonGate renderObject) {
    renderObject.allow = allow;
  }
}

class _RenderLessonGate extends RenderBox {
  bool Function(Offset local) allow;
  _RenderLessonGate(this.allow);

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position) || allow(position)) return false; // пропустити
    result.add(BoxHitTestEntry(this, position)); // поглинути дотик
    return true;
  }
}

/// Прямокутник віджета з ключем [key] у координатах [ref] (або null).
Rect? rectOfKey(GlobalKey key, RenderBox ref) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final topLeft = ref.globalToLocal(box.localToGlobal(Offset.zero));
  return topLeft & box.size;
}
