import 'package:flutter/material.dart';

import '../ui/common.dart';
import '../ui/guide_bubble.dart';
import '../ui/mode_toggle.dart';
import '../ui/theme.dart';

/// Малюнки пасічника для уроків (assets/guide). Усі в одному масштабі з
/// beekeeper_on_toggle.webp: голова на тому самому місці, змінюється лише поза.
/// [headX] / [headUp] - де центр голови в пікселях малюнка (від лівого краю /
/// від низу), [toggleOnTop] - тулуб іде нижче перемикача, тож перемикач
/// малюється поверх (у «smile» руки лежать НА перемикачі).
enum LessonPic {
  smile('assets/guide/beekeeper_on_toggle.webp', 500, 709, 250, 446.7, false),
  blueprint('assets/guide/beekeeper_blueprint.webp', 506, 802, 247, 538.7, true),
  scheming('assets/guide/beekeeper_scheming.webp', 480, 802, 240, 538.7, true),
  surprised('assets/guide/beekeeper_surprised.webp', 606, 737, 273, 452.8, true),
  thinking('assets/guide/beekeeper_thinking.webp', 669, 802, 240, 538.7, true);

  final String asset;
  final double w, h, headX, headUp;
  final bool toggleOnTop;
  const LessonPic(this.asset, this.w, this.h, this.headX, this.headUp, this.toggleOnTop);
}

/// Що відбувається на кроці уроку: репліка пасічника, що підсвічено і що
/// можна натиснути (решта екрана - під «завісою»).
class LessonCue {
  /// На якому екрані цей крок (кожен екран показує лише свої кроки).
  final String screen;
  final List<InlineSpan> text;
  final LessonPic pic;

  /// Цілі в медовому ободку (їх і можна натиснути).
  final List<String> highlight;

  /// Ще можна натиснути (без ободка).
  final List<String> allow;

  /// Можна натискати все, крім [deny] (форма, яку треба заповнити).
  final bool allowAll;
  final List<String> deny;

  /// «Продовжити» з табличкою «завершити» під хмаркою.
  final VoidCallback? onContinue;

  /// Фінал уроку: широка кнопка «Завершити».
  final VoidCallback? onDone;

  const LessonCue({
    required this.screen,
    required this.text,
    this.pic = LessonPic.smile,
    this.highlight = const [],
    this.allow = const [],
    this.allowAll = false,
    this.deny = const [],
    this.onContinue,
    this.onDone,
  });
}

typedef LessonScript = LessonCue? Function(LessonController c);

/// Хід уроку: номер кроку, дані (назва створеного параметра, шаблону…) і
/// ключі віджетів, які урок підсвічує. Один на весь урок - передається
/// кожному екрану, через який іде урок.
class LessonController extends ChangeNotifier {
  final String id;
  final LessonScript script;

  /// Зберегти поступ (щоб наступного разу запропонувати «Продовжити»).
  final void Function(LessonController c) onSave;

  /// «завершити» - вийти з уроку (поступ лишається).
  final VoidCallback onExit;

  /// Урок пройдено до кінця.
  final Future<void> Function(LessonController c) onComplete;

  int _step;
  final Map<String, String> data;

  LessonController({
    required this.id,
    required this.script,
    required int step,
    required this.onSave,
    required this.onExit,
    required this.onComplete,
    Map<String, String>? data,
  })  : _step = step,
        data = data ?? {};

  int get step => _step;

  void go(int s) {
    if (s == _step) return;
    _step = s;
    onSave(this);
    notifyListeners();
  }

  /// Перейти на [to], лише якщо зараз саме крок [from].
  bool advance(int from, int to) {
    if (_step != from) return false;
    go(to);
    return true;
  }

  void setData(String key, String value) {
    data[key] = value;
    onSave(this);
  }

  bool _finishing = false;

  void exit() {
    if (_finishing) return;
    _finishing = true;
    onExit();
  }

  Future<void> complete() async {
    if (_finishing) return;
    _finishing = true;
    await onComplete(this);
  }

  final _keys = <String, GlobalKey>{};
  GlobalKey key(String name) =>
      _keys.putIfAbsent(name, () => GlobalKey(debugLabel: 'lesson-$name'));

  LessonCue? get cue => script(this);

  LessonCue? cueFor(String screen) {
    final c = cue;
    return c != null && c.screen == screen ? c : null;
  }

  bool highlights(String name) => cue?.highlight.contains(name) ?? false;
}

/// Ціль уроку: віджет із ключем [name]; коли урок його підсвічує - медовий
/// ободок (і прокрутка в поле зору). Без уроку - просто [child].
class LessonTarget extends StatelessWidget {
  final LessonController? lesson;
  final String name;
  final double radius;
  final Widget child;
  const LessonTarget(
      {super.key, required this.lesson, required this.name, this.radius = 999, required this.child});

  @override
  Widget build(BuildContext context) {
    final l = lesson;
    if (l == null) return child;
    return ListenableBuilder(
      listenable: l,
      builder: (context, _) => HoneyRing(
        key: l.key(name),
        on: l.highlights(name),
        radius: radius,
        child: child,
      ),
    );
  }
}

/// Шар уроку на екрані [screen]: «завіса» (натиснути можна лише дозволене),
/// пасічник на перемикачі режимів і хмарка з реплікою. На чужих кроках -
/// нічого не показує й нічому не заважає.
class LessonLayer extends StatefulWidget {
  final LessonController lesson;
  final String screen;

  /// Цілі, які екран рахує сам (у координатах шару [ref]): вулик на карті тощо.
  final Map<String, Rect? Function(RenderBox ref)> regions;

  /// Підняти пасічника (над нижньою панеллю кнопок).
  final double bottomInset;

  /// Чи малювати перемикач режимів під пасічником (на карті він справжній).
  final bool drawToggle;

  const LessonLayer({
    super.key,
    required this.lesson,
    required this.screen,
    this.regions = const {},
    this.bottomInset = 0,
    this.drawToggle = true,
  });

  @override
  State<LessonLayer> createState() => _LessonLayerState();
}

class _LessonLayerState extends State<LessonLayer> {
  final _self = GlobalKey();

  Rect? _rect(String name) {
    final ref = _self.currentContext?.findRenderObject();
    if (ref is! RenderBox || !ref.hasSize) return null;
    final r = widget.regions[name];
    if (r != null) return r(ref);
    return rectOfKey(widget.lesson.key(name), ref);
  }

  bool _allows(LessonCue cue, Offset p) {
    if (cue.allowAll) return !cue.deny.any((n) => _rect(n)?.contains(p) ?? false);
    for (final n in [...cue.highlight, ...cue.allow, 'exit']) {
      if (_rect(n)?.contains(p) ?? false) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.lesson,
      builder: (context, _) {
        final cue = widget.lesson.cueFor(widget.screen);
        if (cue == null) return SizedBox.shrink(key: _self);
        return Stack(key: _self, children: [
          Positioned.fill(child: LessonGate(allow: (p) => _allows(cue, p))),
          // решта екрана притемнена; ціль (у медовому ободку), пасічник і
          // хмарка - яскраві. Форму, яку заповнюють, не затемнюємо.
          if (!cue.allowAll)
            Positioned.fill(
              child: LessonScrim(
                extra: (ref) => [
                  for (final n in cue.highlight)
                    if (widget.regions[n]?.call(ref) case final r?) r
                ],
              ),
            ),
          ...lessonPicScene(
            cue,
            bottomInset: widget.bottomInset,
            drawToggle: widget.drawToggle,
            onFinish: widget.lesson.exit,
          ),
        ]);
      },
    );
  }
}

/// Пасічник [cue.pic] на перемикачі режимів і хмарка праворуч від нього.
List<Widget> lessonPicScene(LessonCue cue,
    {double bottomInset = 0, bool drawToggle = true, VoidCallback? onFinish}) {
  final pic = cue.pic;
  // масштаб - як у пасічника на перемикачі (beekeeper_on_toggle.webp)
  const s = kLessonLeaningHeight / 709;
  const left0 = kToggleLeft + (kToggleW - 500 * s) / 2;
  final bottom0 = kToggleLessonBottom + kToggleH - 10 + bottomInset;
  final toggle = drawToggle
      ? Positioned(
          left: kToggleLeft,
          bottom: kToggleLessonBottom + bottomInset,
          child: const IgnorePointer(child: ModeToggle(editing: false, decorative: true)),
        )
      : null;
  final image = Positioned(
    left: left0 + (250 - pic.headX) * s,
    bottom: bottom0 + (446.7 - pic.headUp) * s,
    child: IgnorePointer(
      child: Image.asset(pic.asset, height: pic.h * s, filterQuality: FilterQuality.medium),
    ),
  );
  Widget? below;
  double gap = LessonFinishLink.heightFor(180) + 4;
  if (cue.onContinue != null) {
    below = LessonContinue(onContinue: cue.onContinue!, onFinish: onFinish);
    gap = 0; // висота - за шириною (див. LessonContinue)
  } else if (cue.onDone != null) {
    below = LessonDoneButton(onPressed: cue.onDone!);
    gap = 0;
  }
  final bubble = GuideBubble(
    text: cue.text,
    image: null,
    imageLeft: 0,
    below: below,
    gap: gap,
  );
  return [
    if (toggle != null && !pic.toggleOnTop) toggle,
    image,
    if (toggle != null && pic.toggleOnTop) toggle,
    Positioned(
      left: kLessonBubbleLeft,
      right: 0,
      bottom: kLessonOnButtonBottom + bottomInset,
      child: Material(
        type: MaterialType.transparency,
        child: below == null ? IgnorePointer(child: bubble) : bubble,
      ),
    ),
  ];
}

/// «Продовжити» з дерев'яною табличкою «завершити», прибитою під нею
/// (малюнок автора, assets/guide/continue_with_sign.webp; написи - текстом).
class LessonContinue extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback? onFinish;
  final String label;
  const LessonContinue(
      {super.key, required this.onContinue, this.onFinish, this.label = 'Продовжити'});

  static const asset = 'assets/guide/continue_with_sign.webp';
  static const aspect = 700 / 353;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 240.0;
      final h = w / aspect;
      const shadow = [Shadow(color: Color(0xAA3B1F0B), blurRadius: 2, offset: Offset(0, 1))];
      return SizedBox(
        width: w,
        height: h,
        child: Stack(children: [
          Positioned.fill(
              child: Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
          // кнопка - верхні ~42% малюнка
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: h * 0.42,
            child: Semantics(
              button: true,
              label: label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onContinue,
                child: Align(
                  alignment: const Alignment(0.1, -0.05),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(label,
                          style: TextStyle(
                              color: const Color(0xFFFFF3DC),
                              fontSize: w * 0.075,
                              fontWeight: FontWeight.w800,
                              shadows: shadow)),
                      Icon(Icons.chevron_right, color: const Color(0xFFFFF3DC), size: w * 0.09),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          // табличка «завершити» - середня дошка між мотузками
          if (onFinish != null)
            Positioned(
              left: w * 0.24,
              right: w * 0.24,
              top: h * 0.5,
              bottom: 0,
              child: Semantics(
                button: true,
                label: 'завершити навчання',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onFinish,
                  child: Align(
                    alignment: const Alignment(0, 0.12),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.05),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('завершити',
                            style: TextStyle(
                                color: const Color(0xFFFFF3DC),
                                fontSize: w * 0.06,
                                fontWeight: FontWeight.w800,
                                shadows: shadow)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

/// Фінал уроку: широка медова кнопка «Завершити» (assets/guide/button_wide.webp).
class LessonDoneButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  const LessonDoneButton({super.key, required this.onPressed, this.label = 'Завершити'});

  static const asset = 'assets/guide/button_wide.webp';
  static const aspect = 700 / 142;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 240.0;
      final h = w / aspect;
      return Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(
                  child: Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
              Align(
                alignment: const Alignment(0.12, -0.1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: TextStyle(
                          color: const Color(0xFFFFF3DC),
                          fontSize: w * 0.075,
                          fontWeight: FontWeight.w800,
                          shadows: const [
                            Shadow(color: Color(0xAA3B1F0B), blurRadius: 2, offset: Offset(0, 1))
                          ])),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

/// Вікно (діалог) під час уроку: вікно вище, щоб пасічник унизу його не
/// закривав, і шар уроку зі своїм кроком [screen].
Widget lessonDialog(LessonController? lesson, String screen, Widget dialog) {
  if (lesson == null) return dialog;
  return Stack(children: [
    Positioned.fill(child: Padding(padding: const EdgeInsets.only(bottom: 300), child: dialog)),
    Positioned.fill(child: LessonLayer(lesson: lesson, screen: screen)),
  ]);
}

/// Місце внизу екрана під пасічника з хмаркою (щоб його кнопки не ховались).
const kLessonReserve = 300.0;
