import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../tutorial/lesson.dart';
import '../tutorial/lessons.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'apiary_list_screen.dart';
import 'map_screen.dart';

/// Відкриває порожню «пісочницю» для уроку (див. [AppDatabase.openSandbox]).
typedef SandboxOpener = Future<Repository> Function();

/// Пісочниця = щойно встановлений застосунок: порожня база з усім, що дає
/// перший запуск поточної версії (шаблони, базові характеристики). Екрани
/// уроку — ті самі, що й у роботі, тож навчання завжди показує актуальну
/// версію.
Future<Repository> openSandboxRepository() async {
  final repo = Repository(await AppDatabase.openSandbox());
  await repo.prepareLikeFreshInstall();
  return repo;
}

/// Режим навчання: плитки з уроками. Кожен урок проходить у «пісочниці» —
/// тимчасовій порожній базі, тож справжні пасіки не змінюються.
class TutorialScreen extends StatefulWidget {
  /// Підміняється в тестах.
  final SandboxOpener openSandbox;

  /// Справжня база: «Я сам собі маг пасіки» переносить у неї пасіку з уроку.
  final Repository? realRepo;

  /// Одразу почати урок «Базові поняття» (після червоної пігулки).
  final bool autoStart;
  const TutorialScreen(
      {super.key,
      this.openSandbox = openSandboxRepository,
      this.realRepo,
      this.autoStart = false});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _basics();
      });
    }
  }

  /// Закрити пісочницю уроку. `nav.push` повертається одразу, як урок
  /// прибрали з навігатора, але його екрани ще живуть до кінця анімації: при
  /// знищенні карта збільшує `mapChanges`, а слухачі (список пасік, нотатки)
  /// перечитують базу. Закрита раніше база давала «database_closed».
  static Future<void> _closeSandbox(Repository? sandbox) async {
    if (sandbox == null) return;
    // чекаємо кадрами, а не таймером: анімація переходу - теж кадри, а
    // віджет-тести не лишаються з таймером після кінця тесту
    final sw = Stopwatch()..start();
    while (sw.elapsed < _sandboxCloseDelay) {
      await SchedulerBinding.instance.endOfFrame;
    }
    await sandbox.db.close();
  }

  /// Довше за анімацію переходу (300 мс) з запасом на останні запити.
  static const _sandboxCloseDelay = Duration(seconds: 1);

  /// «Базові поняття»: починаємо з порожнього списку «Мої пасіки», де
  /// пасічник підказує створити першу карту.
  Future<void> _basics() async {
    if (_opening) return;
    setState(() => _opening = true);
    Repository? sandbox;
    try {
      sandbox = await widget.openSandbox();
      if (!mounted) return;
      final repo = sandbox;
      final nav = Navigator.of(context);
      final lessonsRoute = ModalRoute.of(context);
      var finishing = false; // подвійний тап по фіналу не імпортує пасіку двічі
      // одразу після вибору пігулки — без анімації переходу: екран «Мої пасіки»
      // уроку стає на місце такого самого порожнього, нічого не смикається
      Widget lessonPage(BuildContext _) => ApiaryListScreen(
          repo: repo,
          tutorial: true,
          onLessonDone: (magic, apiaryId) async {
            if (finishing) return;
            // Кінець уроку: пасіка з уроку стає справжньою, далі —
            // справжня карта (пасічник уже не веде)
            final real = widget.realRepo;
            if (real == null) {
              nav.popUntil((r) => r == lessonsRoute);
              return;
            }
            finishing = true;
            // початкове навчання пройдено — більше не пропонувати з нуля
            await real.setMeta('intro_done', '1');
            final String id;
            try {
              id = await real.importApiaryFrom(repo, apiaryId);
            } catch (_) {
              finishing = false;
              rethrow;
            }
            final a = await real.getApiary(id);
            if (a == null || !nav.mounted) return;
            nav.popUntil((r) => r.isFirst);
            // «синя пігулка» (magic=false): пасічник ще покаже меню; після повного
            // огляду меню (magic=true) - одразу справжня карта зі своїм вуликом
            nav.push(MaterialPageRoute(
                builder: (_) => MapScreen(repo: real, apiary: a, menuTour: !magic)));
          },
        );
      await nav.push(widget.autoStart
          ? PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (ctx, _, __) => lessonPage(ctx))
          : MaterialPageRoute<void>(builder: lessonPage));
      // вийшли з уроку, що почався з пігулки, — назад на головний, а не до плиток
      if (widget.autoStart && mounted) nav.pop();
    } finally {
      if (mounted) setState(() => _opening = false);
      // окрема база в пам'яті - закривається у фоні, наступний урок можна
      // відкривати одразу
      unawaited(_closeSandbox(sandbox));
    }
  }

  /// Чи продовжити перерваний урок: true - продовжити, false - спочатку,
  /// null - передумали.
  Future<bool?> _askResume(LessonDef def) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(def.title),
          content: Text('Ти вже починав цей урок. Продовжити з місця, де зупинився, '
              'чи почати спочатку?',
              style: TextStyle(color: AppColors.text)),
          actions: [
            Row(children: [
              Expanded(
                child: PillButton(
                    text: 'Спочатку',
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    onPressed: () => Navigator.pop(ctx, false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(
                    text: 'Продовжити',
                    bg: AppColors.accent,
                    onPressed: () => Navigator.pop(ctx, true)),
              ),
            ]),
          ],
        ),
      );

  /// Урок із [kLessons]: пісочниця, карта уроку, пасічник веде крок за кроком.
  /// Перерваний урок («завершити» чи вихід) запам'ятовується - наступного
  /// разу пропонуємо продовжити або почати спочатку.
  Future<void> _startLesson(LessonDef def) async {
    if (def.soon) {
      await showInfo(context, 'Цей урок ще готується - скоро з\'явиться.', title: def.title);
      return;
    }
    if (_opening || def.script == null || def.setup == null) return;
    final real = widget.realRepo;
    final metaKey = 'lesson_${def.id}';
    var step = 1;
    var data = <String, String>{};
    final saved = real == null ? null : await real.getMeta(metaKey);
    if (saved != null) {
      try {
        final j = jsonDecode(saved) as Map;
        step = (j['step'] as num).toInt();
        data = {
          for (final e in (j['data'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'
        };
      } catch (_) {
        step = 1;
      }
      if (step > 1) {
        if (!mounted) return;
        final cont = await _askResume(def);
        if (cont == null) return;
        if (!cont) {
          step = 1;
          data = {};
        }
      }
    }
    if (!mounted) return;
    setState(() => _opening = true);
    Repository? sandbox;
    try {
      sandbox = await widget.openSandbox();
      if (!mounted) return;
      final sb = sandbox;
      final nav = Navigator.of(context);
      final lessonsRoute = ModalRoute.of(context);
      final lesson = LessonController(
        id: def.id,
        script: def.script!,
        step: def.checkpoint(step),
        data: data,
        onSave: (c) => real?.setMeta(metaKey, jsonEncode({'step': c.step, 'data': c.data})),
        onExit: () => nav.popUntil((r) => r == lessonsRoute),
        onComplete: (c) async {
          // урок пройдено - наступного разу почнеться спочатку
          await real?.setMeta(metaKey, null);
          if (def.id == 'templates') {
            // створений шаблон лишається у справжніх шаблонах - розміщувати сам
            final name = c.data['template'];
            final t = (await sb.listTemplates()).where((t) => t.name == name).firstOrNull;
            if (t != null && real != null) {
              // така назва вже є у своїх шаблонах - додаємо номер
              final taken = {for (final x in await real.listTemplates()) x.name};
              var name = t.name;
              for (var n = 2; taken.contains(name); n++) {
                name = '${t.name} $n';
              }
              await real.addTemplate(name, t.width, t.height, t.cells);
            }
            // і назад на свою карту (туди, звідки відкривали «Навчання»)
            nav.popUntil((r) => r == lessonsRoute);
            if (nav.canPop()) nav.pop();
            return;
          }
          nav.popUntil((r) => r == lessonsRoute);
        },
      );
      final apiary = await def.setup!(sb, lesson);
      if (!mounted) return;
      lesson.onSave(lesson);
      await nav.push(MaterialPageRoute<void>(
          builder: (_) => MapScreen(repo: sb, apiary: apiary, lesson: lesson)));
    } finally {
      if (mounted) setState(() => _opening = false);
      // окрема база в пам'яті - закривається у фоні, наступний урок можна
      // відкривати одразу
      unawaited(_closeSandbox(sandbox));
    }
  }

  @override
  Widget build(BuildContext context) {
    // після червоної пігулки: поки відкривається урок — той самий порожній
    // екран «Мої пасіки», що й під пасічником із пігулками
    if (widget.autoStart) {
      return Scaffold(
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(title: 'Мої пасіки', onBack: () => Navigator.of(context).pop()),
            ]),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: 'Навчання', onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(16),
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.9,
                children: [
                  _LessonTile(
                    title: 'Базові поняття',
                    image: 'assets/guide/beekeeper.webp',
                    onTap: _opening ? null : _basics,
                  ),
                  for (final def in kLessons)
                    _LessonTile(
                      title: def.title,
                      image: def.image,
                      soon: def.soon,
                      onTap: _opening ? null : () => _startLesson(def),
                    ),
                ],
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}

/// Плитка уроку: малюнок і назва.
class _LessonTile extends StatelessWidget {
  final String title;
  final String image;
  final VoidCallback? onTap;

  /// Урок ще готується: плитка бліда, з позначкою «скоро».
  final bool soon;
  const _LessonTile({required this.title, required this.image, this.onTap, this.soon = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.darkBtn, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Expanded(
              child: Stack(alignment: Alignment.topRight, children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: soon ? 0.4 : 1,
                    child: Image.asset(image, filterQuality: FilterQuality.medium),
                  ),
                ),
                if (soon)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                    child: const Text('скоро',
                        style: TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}
