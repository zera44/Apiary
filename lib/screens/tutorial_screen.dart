import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repository.dart';
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
      await nav.push(MaterialPageRoute(
        builder: (_) => ApiaryListScreen(
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
        ),
      ));
    } finally {
      await sandbox?.db.close();
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
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
  const _LessonTile({required this.title, required this.image, this.onTap});

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
            Expanded(child: Image.asset(image, filterQuality: FilterQuality.medium)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}
