import 'package:flutter/material.dart';

import 'common.dart';
import 'guide_bubble.dart';

/// Кнопка-пігулка: капсула з двома півкулями кольору та бликом.
class PillChoice extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback? onPressed;
  const PillChoice({required this.text, required this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.35)!;
    return Semantics(
      button: true,
      label: text,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.55), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(alignment: Alignment.center, children: [
              Row(children: [
                Expanded(child: ColoredBox(color: color, child: const SizedBox.expand())),
                Expanded(child: ColoredBox(color: light, child: const SizedBox.expand())),
              ]),
              Positioned(
                top: 4,
                left: 12,
                right: 12,
                height: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 3)])),
            ]),
          ),
        ),
      ),
    );
  }
}


const kPillRed = Color(0xFFD64545);
const kPillBlue = Color(0xFF3B6FD6);

/// Репліка вибору «синя / червона пігулка» (завершити навчання / продовжити).
List<InlineSpan> pillChoiceSpans(String lead) => [
      TextSpan(text: lead),
      const TextSpan(
          text: 'Синя пігулка',
          style: TextStyle(color: Color(0xFF6F9BFF), fontWeight: FontWeight.w800)),
      const TextSpan(text: ' - ти власник свого життя ('),
      GuideBubble.task('завершити навчання'),
      const TextSpan(text: '), '),
      const TextSpan(
          text: 'червона',
          style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800)),
      const TextSpan(text: ' - я покажу, як глибока ця нора ('),
      GuideBubble.task('продовжити'),
      const TextSpan(text: ').'),
    ];

/// Пасічник «як Нео» при першому «Почати» - на тлі порожнього екрана «Мої
/// пасіки»: true - червона (навчання), false - синя (без навчання), null -
/// передумали («назад»).
Future<bool?> showPillChoice(NavigatorState nav) {
  return nav.push<bool>(MaterialPageRoute<bool>(
    builder: (ctx) => PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              TopBar(title: 'Мої пасіки', onBack: () => Navigator.of(ctx).pop()),
            ]),
            ...lessonScene(
              pose: LessonPose.pills,
              text: pillChoiceSpans('Здоров був, новачок. Укуси мене бджола. Пропоную тобі вибір. '),
              below: Row(children: [
                Expanded(
                    child: PillChoice(
                        text: 'Червона',
                        color: kPillRed,
                        onPressed: () => Navigator.of(ctx).pop(true))),
                const SizedBox(width: 8),
                Expanded(
                    child: PillChoice(
                        text: 'Синя',
                        color: kPillBlue,
                        onPressed: () => Navigator.of(ctx).pop(false))),
              ]),
            ),
          ]),
        ),
      ),
    ),
  ));
}
