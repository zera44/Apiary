import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/guide_bubble.dart';
import '../ui/theme.dart';
import 'lesson.dart';

/// Уроки «з екскурсією»: пасічник веде по СПРАВЖНІХ екранах застосунку (у
/// пісочниці), а не по спеціально підготовлених. Екрану досить позначити
/// кнопку [TourTarget] з назвою - урок сам її знайде, підсвітить медовим
/// ободком і пропустить до неї дотик. Решта екрана - під «завісою».
///
/// Урок іде у власному [Navigator] під шаром пасічника: усі екрани, що
/// відкриваються з уроку, лежать під ним (а сам урок - один маршрут, який
/// закривається цілком).
class GuideStep {
  /// Текст хмарки: [виділено] - назва кнопки, {завдання} - що зробити.
  final String text;
  final LessonPic pic;

  /// Ціль у медовому ободку (див. [TourTarget]).
  final String? target;

  /// Натиснути ціль - і далі.
  final bool tap;

  /// Можна натискати все (форму заповнюють); далі - коли з'явиться [waitFor].
  final bool free;
  final String? waitFor;

  /// Останній крок: «Завершити ✓».
  final bool done;

  const GuideStep.tap(this.target, this.text, {this.pic = LessonPic.smile})
    : tap = true,
      free = false,
      waitFor = null,
      done = false;

  /// Пасічник розповідає (ціль, якщо є, - лише підсвічена), «Продовжити».
  const GuideStep.look(this.text, {this.target, this.pic = LessonPic.smile})
    : tap = false,
      free = false,
      waitFor = null,
      done = false;

  /// Вільний крок: натискати можна все, далі - коли на екрані з'явиться [waitFor].
  const GuideStep.free(
    this.text, {
    required String this.waitFor,
    this.target,
    this.pic = LessonPic.smile,
  }) : tap = false,
       free = true,
       done = false;

  const GuideStep.done(this.text, {this.target, this.pic = LessonPic.smile})
    : tap = false,
      free = false,
      waitFor = null,
      done = true;
}

/// Текст хмарки з розміткою: [кнопка] - виділено, {завдання} - напівжирно.
List<InlineSpan> guideSpans(String s) {
  final out = <InlineSpan>[];
  final re = RegExp(r'\[([^\]]+)\]|\{([^}]+)\}');
  var at = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > at) out.add(TextSpan(text: s.substring(at, m.start)));
    out.add(
      m.group(1) != null
          ? GuideBubble.highlight(m.group(1)!)
          : GuideBubble.task(m.group(2)!),
    );
    at = m.end;
  }
  if (at < s.length) out.add(TextSpan(text: s.substring(at)));
  return out;
}

/// Позначка цілі уроку-екскурсії. Без уроку нічого не змінює.
class TourTarget extends StatefulWidget {
  final String name;
  final Widget child;
  const TourTarget(this.name, {super.key, required this.child});

  /// Показані зараз цілі.
  static final _all = <_TourTargetState>{};

  /// Ціль [name] на верхньому екрані (або null).
  static Rect? rectOf(String name) {
    Rect? best;
    for (final t in _all) {
      if (t.widget.name != name || !t.mounted) continue;
      final route = ModalRoute.of(t.context);
      if (route != null && !route.isCurrent) continue;
      final box = t.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      best = box.localToGlobal(Offset.zero) & box.size;
    }
    return best;
  }

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  @override
  void initState() {
    super.initState();
    TourTarget._all.add(this);
  }

  @override
  void dispose() {
    TourTarget._all.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Урок-екскурсія з плиток «Навчання».
class GuidedLesson {
  final String id;
  final String Function() title;
  final String image;

  /// Кроки (тексти - з l10n, тож функція).
  final List<GuideStep> Function() steps;

  /// Наповнити пісочницю й повернути перший екран уроку.
  final Future<Widget> Function(Repository sandbox) start;

  const GuidedLesson({
    required this.id,
    required this.title,
    required this.image,
    required this.steps,
    required this.start,
  });
}

/// Маршрут уроку: власний навігатор з першим екраном і шар пасічника над ним.
class GuideHost extends StatefulWidget {
  final List<GuideStep> steps;
  final Widget first;
  final VoidCallback onExit;
  final VoidCallback onDone;
  const GuideHost({
    super.key,
    required this.steps,
    required this.first,
    required this.onExit,
    required this.onDone,
  });

  @override
  State<GuideHost> createState() => GuideHostState();
}

class GuideHostState extends State<GuideHost>
    with SingleTickerProviderStateMixin {
  final _nav = GlobalKey<NavigatorState>();
  final _self = GlobalKey();
  late final Ticker _ticker;
  int _step = 0;
  Rect? _target;
  bool _finished = false;

  int get step => _step;
  GuideStep get _cur => widget.steps[_step];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _tick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Ціль у координатах шару.
  Rect? _local(String? name) {
    if (name == null) return null;
    final g = TourTarget.rectOf(name);
    final self = _self.currentContext?.findRenderObject();
    if (g == null || self is! RenderBox || !self.hasSize) return null;
    return self.globalToLocal(g.topLeft) & g.size;
  }

  void _tick() {
    if (_finished) return;
    final s = _cur;
    if (s.free && s.waitFor != null && _local(s.waitFor) != null) {
      _go(_step + 1);
      return;
    }
    final r = _local(s.target);
    if (r != _target) setState(() => _target = r);
  }

  void _go(int i) {
    if (_finished) return;
    if (i >= widget.steps.length) return _done();
    setState(() {
      _step = i;
      _target = null;
    });
  }

  void _done() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  void _exit() {
    if (_finished) return;
    _finished = true;
    widget.onExit();
  }

  bool _allows(Offset p) {
    final s = _cur;
    if (s.free) return true;
    return s.tap && (_target?.contains(p) ?? false);
  }

  void _onUp(PointerUpEvent e) {
    final s = _cur;
    if (!s.tap || !(_target?.contains(e.localPosition) ?? false)) return;
    final from = _step;
    // спершу відпрацює сама кнопка, потім - наступний крок
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == from) _go(from + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _cur;
    final cue = LessonCue(
      screen: '',
      text: guideSpans(s.text),
      pic: s.pic,
      onContinue: !s.tap && !s.free && !s.done ? () => _go(_step + 1) : null,
      onDone: s.done ? _done : null,
    );
    final pad = MediaQuery.paddingOf(context);
    final scene = SizedBox(
      height: kLessonReserve,
      child: Stack(
        clipBehavior: Clip.none,
        children: lessonPicScene(cue, onFinish: _exit),
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _nav.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else {
          _exit();
        }
      },
      child: LayoutBuilder(
        builder: (context, box) {
          // ціль унизу - пасічник із хмаркою переходить нагору, щоб її не закривати
          final top = (_target?.bottom ?? 0) > box.maxHeight - kLessonReserve;
          return Stack(
            key: _self,
            children: [
              Positioned.fill(
                child: Navigator(
                  key: _nav,
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: (_) => widget.first),
                ),
              ),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerUp: _onUp,
                ),
              ),
              Positioned.fill(child: LessonGate(allow: _allows)),
              if (!s.free)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _ScrimPainter(_target)),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: top ? pad.top + 8 : null,
                bottom: top ? null : pad.bottom,
                child: scene,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Затемнення з «вікном» навколо цілі й медовим ободком.
class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  _ScrimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(
        all,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      return;
    }
    final rr = RRect.fromRectAndRadius(h.inflate(6), const Radius.circular(16));
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, Path()..addRRect(rr)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = AppColors.create.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = AppColors.create
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}

/// Пісочниця для уроків-екскурсій: пасіка з вуликами (двоє чекають огляду).
Future<Apiary> seedGuideApiary(Repository repo) async {
  final existing = await repo.listApiaries();
  if (existing.isNotEmpty) return existing.first;
  final aid = await repo.addApiary('Пасіка');
  final ts = await repo.listTemplates();
  final hiveT =
      ts.where((t) => t.name == 'Вулик').firstOrNull ?? ts.firstOrNull;
  if (hiveT != null) {
    for (final x in [0, 2, 4]) {
      await repo.placeTemplate(aid, hiveT.cells, x, 0, name: hiveT.name);
    }
  }
  return (await repo.getApiary(aid))!;
}
