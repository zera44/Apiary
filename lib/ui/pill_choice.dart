import 'package:flutter/material.dart';

import 'common.dart';
import 'guide_bubble.dart';
import '../l10n/l10n.dart';

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
/// [blue]/[red] — що означає кожна пігулка (у дужках, медовим).
List<InlineSpan> pillChoiceSpans(String lead,
{String? blue, String? red}) =>
    [
      TextSpan(text: lead),
TextSpan(
          text: tr.pillBlueLabel,
          style: TextStyle(color: Color(0xFF6F9BFF), fontWeight: FontWeight.w800)),
      TextSpan(text: tr.pillBlueText),
      GuideBubble.task(blue ?? tr.pillBlueDefault),
      const TextSpan(text: '), '),
TextSpan(
          text: tr.pillRedLabel,
          style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800)),
      TextSpan(text: tr.pillRedText),
      GuideBubble.task(red ?? tr.pillRedDefault),
      const TextSpan(text: ').'),
    ];

/// Пасічник «як Нео» при першому «Почати» - на тлі порожнього екрана «Мої
/// пасіки»: true - червона (навчання), false - синя (без навчання), null -
/// передумали («назад»).
/// [onLearn] — екран навчання: червона пігулка ставить його на місце цієї
/// сторінки миттєво (без мигання головного екрана між ними).
Future<bool?> showPillChoice(NavigatorState nav, {WidgetBuilder? onLearn}) {
  return nav.push<bool>(MaterialPageRoute<bool>(
    builder: (ctx) => PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              TopBar(title: tr.myApiaries, onBack: () => Navigator.of(ctx).pop()),
            ]),
            ...lessonScene(
              pose: LessonPose.pills,
              text: pillChoiceSpans(tr.pillLead,
                  blue: tr.pillNoTutorial, red: tr.pillTakeTutorial),
              below: Row(children: [
                Expanded(
                    child: PillChoice(
                        text: tr.pillBlue,
                        color: kPillBlue,
                        onPressed: () => Navigator.of(ctx).pop(false))),
                const SizedBox(width: 8),
                Expanded(
                    child: PillChoice(
                        text: tr.pillRed,
                        color: kPillRed,
                        onPressed: () => onLearn == null
                            ? Navigator.of(ctx).pop(true)
                            : Navigator.of(ctx).pushReplacement(
                                PageRouteBuilder<void>(
                                    transitionDuration: Duration.zero,
                                    reverseTransitionDuration: Duration.zero,
                                    pageBuilder: (c, _, __) => onLearn(c)),
                                result: true))),
              ]),
            ),
          ]),
        ),
      ),
    ),
  ));
}
