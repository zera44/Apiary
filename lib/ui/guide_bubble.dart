import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'mode_toggle.dart';
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
/// Пасічник по пояс, руки спираються на перемикач режимів унизу ліворуч.
const kLessonBeekeeperLeaning = 'assets/guide/beekeeper_on_toggle.webp';
const kLessonLeaningHeight = 170.0;

/// Помічник-ведмедик (покусаний, з рамкою) — урок, форма огляду.
const kLessonBeekeeperPills = 'assets/guide/beekeeper_pills.webp';
/// Покусаний пасічник по пояс - спирається на кнопку «Далі» в меню-огляді.
const kLessonBeekeeperStung = 'assets/guide/beekeeper_stung.webp';
/// Пасічник за ноутбуком - «Склад» в огляді меню.
const kLessonBeekeeperLaptop = 'assets/guide/beekeeper_laptop.webp';
/// Пасічник із газетою - «Історія» в огляді меню.
const kLessonBeekeeperNewspaper = 'assets/guide/beekeeper_newspaper.webp';
/// Пасічник із шаблонами - «Налаштування» в огляді меню.
const kLessonBeekeeperTemplates = 'assets/guide/beekeeper_templates.webp';
/// Пасічник-професор - «Навчання» в огляді меню.
const kLessonBeekeeperProfessor = 'assets/guide/beekeeper_professor.webp';
/// Пасічник із поштовою скринькою та бджолою - «Зворотний зв'язок» в огляді меню.
const kLessonBeekeeperMailbox = 'assets/guide/beekeeper_mailbox_bee.webp';
/// Покусаний ведмедик по пояс - лапи на перемикачі режимів (як і пасічник).
const kLessonBear = 'assets/guide/bear_on_toggle.webp';

/// Підказка режиму навчання: пасічник-провідник (малюнок автора,
/// assets/guide) зліва і «хмарка» з текстом справа.
class GuideBubble extends StatelessWidget {
  /// Текст підказки; виділені слова — через [GuideBubble.highlight].
  final List<InlineSpan> text;
  final String? image; // null — лише хмарка (пасічник стоїть окремо)

  /// Під хмаркою (у проміжку між нею й низом пасічника) — наприклад,
  /// «Пропустити».
  final Widget? below;

  /// Над хмаркою, праворуч (напр., «завершити навчання», коли під нею кнопка).
  final Widget? above;

  /// Висота пасічника (компактна підказка — менша).
  final double imageHeight;

  /// Висота проміжку під хмаркою (до низу пасічника).
  final double gap;
  const GuideBubble(
      {super.key,
      required this.text,
      this.image = 'assets/guide/beekeeper.webp',
      this.below,
      this.above,
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
            if (above != null) Align(alignment: Alignment.centerRight, child: above),
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
  bool? toggleEditing,
  VoidCallback? onFinish,
}) {
  final base = kLessonOnButtonBottom + bottomInset;
  // «завершити навчання» — посиланням під хмаркою; якщо там уже кнопка
  // («Продовжити», пігулки) — над хмаркою
  final finish = onFinish == null ? null : LessonFinishLink(onPressed: onFinish);
  // табличка - маленька, у правому нижньому куті (не заважає кнопкам хмарки)
  // з бджолами-пігулками малюнок ширший: менший і зсунутий вправо, щоб бджоли
  // не обрізались, а хмарка починалась після нього
  final pills = pose == LessonPose.pills;
  final (img, h, left, bottom) = switch (pose) {
    LessonPose.onButton => (kLessonBeekeeper, 170.0, kLessonOnButtonLeft, base),
    // «стійка» нижче рук: малюнок вищий і ширший, руки — там само
    // руки — на перемикачі режимів (унизу ліворуч)
    LessonPose.leaning => (
        kLessonBeekeeperLeaning,
        kLessonLeaningHeight,
        kToggleLeft + (kToggleW - kLessonLeaningHeight * 500 / 709) / 2,
        kToggleLessonBottom + kToggleH - 10 + bottomInset
      ),
    // той самий кадр, що «стійка», але пасічник із бджолами-пігулками
    LessonPose.pills => (
        kLessonBeekeeperPills,
        150.0,
        6.0,
        base - 17.4
      ),
    // та сама ширина, що й у пасічника: лапи — на перемикачі
    LessonPose.bear => (
        kLessonBear,
        kLessonLeaningHeight * 500 / 709 * 676 / 500,
        kToggleLeft + (kToggleW - kLessonLeaningHeight * 500 / 709) / 2,
        kToggleLessonBottom + kToggleH - 10 + bottomInset
      ),
  };
  final bubble = text == null
      ? null
      : GuideBubble(
          text: text,
          image: null,
          imageLeft: 0,
          below: below,
          gap: below == null ? LessonFinishLink.heightFor(180) + 4 : 70);
  return [
    // у вікнах уроку перемикача карти не видно — малюємо його копію під пасічником
    if (toggleEditing != null && (pose == LessonPose.leaning || pose == LessonPose.bear))
      Positioned(
        left: kToggleLeft,
        bottom: kToggleLessonBottom + bottomInset,
        child: IgnorePointer(child: ModeToggle(editing: toggleEditing, decorative: true)),
      ),
    Positioned(
      left: left,
      bottom: bottom,
      child: IgnorePointer(
        child: Image.asset(img, height: h, filterQuality: FilterQuality.medium),
      ),
    ),
    if (bubble != null)
      Positioned(
        left: pills ? 164.0 : kLessonBubbleLeft,
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
    if (finish != null)
      Positioned(
        right: 8,
        bottom: 4 + bottomInset,
        child: Material(type: MaterialType.transparency, child: finish),
      ),
  ];
}

/// «завершити навчання» — дерев'яна табличка на мотузках (малюнок автора,
/// assets/guide/sign_blank.webp; напис — текстом, щоб був чіткий).
const kSignBlank = 'assets/guide/sign_blank.webp';

class LessonFinishLink extends StatelessWidget {
  final VoidCallback onPressed;
  final double width;
  const LessonFinishLink({super.key, required this.onPressed, this.width = kSignWidth});

  /// Табличка 5:3; напис — на середній дошці.
  static const kSignWidth = 90.0;
  static double heightFor(double w) => w * 0.6;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'завершити навчання',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: width,
            height: heightFor(width),
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                  child: Image.asset(kSignBlank, fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium)),
              // середня дошка — трохи нижче центру малюнка
              Align(
                alignment: const Alignment(0, 0.16),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('завершити навчання',
                        style: TextStyle(
                            color: const Color(0xFFFFF3DC),
                            fontSize: width * 0.075,
                            fontWeight: FontWeight.w800,
                            shadows: const [Shadow(color: Color(0xAA3B1F0B), blurRadius: 2, offset: Offset(0, 1))])),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
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
