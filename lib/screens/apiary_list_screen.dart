import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/merge_layout.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/guide_bubble.dart';
import '../ui/theme.dart';
import 'helpers_screen.dart';
import 'map_screen.dart';
import 'qr_generate_screen.dart';

/// Список пасік застосунку: тап відкриває карту, "+" — створює нову.
class ApiaryListScreen extends StatefulWidget {
  final Repository repo;

  /// Урок «Базові поняття» (режим навчання): [repo] — пісочниця; поки
  /// пасік немає, пасічник підказує створити карту; «назад» — до уроків.
  final bool tutorial;

  /// Урок: що робити наприкінці (див. [MapScreen.onLessonDone]).
  final Future<void> Function(bool magic, String apiaryId)? onLessonDone;
  const ApiaryListScreen(
      {super.key, required this.repo, this.tutorial = false, this.onLessonDone});

  /// Перша підказка уроку «Базові поняття».
  static List<InlineSpan> get tutorialHello => [
    TextSpan(text: tr.apiaryListHello),
    GuideBubble.highlight(tr.createMapQuoted),
  ];
  @override
  State<ApiaryListScreen> createState() => _ApiaryListScreenState();
}

class _ApiaryListScreenState extends State<ApiaryListScreen> {
  List<Apiary>? apiaries;
  final Map<String, List<SceneCell>> _cells = {};

  @override
  void initState() {
    super.initState();
    widget.repo.mapChanges.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.repo.mapChanges.removeListener(_reload);
    super.dispose();
  }

  // пасіки, що видаляються (чекають кінця «Відмінити»): _reload їх не повертає
  final Set<String> _hiding = {};

  Future<void> _reload() async {
    // урок: пісочницю закривають, щойно урок скінчився, а екран ще може
    // доживати анімацію закриття — тоді просто нічого не читаємо
    if (!mounted || !widget.repo.db.isOpen) return;
    final List<Apiary> list;
    final Map<String, List<MapElement>> els;
    try {
      list = await widget.repo.listApiaries();
      // один запит на всі пасіки; клітинки для мініатюр рахуються тут раз,
      // а не при кожному перемальовуванні списку
      els = await widget.repo.listElementsByApiary([for (final a in list) a.id]);
    } catch (_) {
      if (!widget.repo.db.isOpen) return; // базу закрили під час читання
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      apiaries = [for (final a in list) if (!_hiding.contains(a.id)) a];
      _cells
        ..clear()
        ..addAll({for (final e in els.entries) e.key: _cellsOf(e.value)});
    });
  }

  Future<void> _open(Apiary a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(
          repo: widget.repo,
          apiary: a,
          tutorial: widget.tutorial,
          onLessonDone: widget.onLessonDone),
    ));
    await _reload();
  }

  bool _creating = false;

  /// «+ Створити карту»: одразу пасіка «Пасіка N» і її карта (без окремого
  /// екрана назви; перейменувати — олівцем на плитці).
  Future<void> _create() async {
    if (_creating) return;
    _creating = true;
    try {
      final id = await widget.repo.addApiaryQuick();
      final created = await widget.repo.getApiary(id);
      await _reload();
      if (created != null && mounted) await _open(created);
    } finally {
      _creating = false;
    }
  }

  /// Видалення пасіки — з підтвердженням (зникає вся карта з вуликами й
  /// записами), після «Видалити» — одразу й остаточно.
  Future<void> _delete(Apiary a) async {
    final ok = await showConfirm(context,
        title: tr.deleteApiaryTitle, text: tr.deleteApiaryText(a.name));
    if (!ok || !mounted) return;
    _hiding.add(a.id);
    setState(() => apiaries = [...?apiaries]..removeWhere((x) => x.id == a.id));
    // урок: пісочницю могли закрити, поки висіло підтвердження
    try {
      await widget.repo.deleteApiary(a.id);
    } catch (_) {
      if (widget.repo.db.isOpen) rethrow;
      return;
    }
    _hiding.remove(a.id);
    if (!mounted) return;
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr.apiaryDeleted(a.name))));
    }
  }


  @override
  Widget build(BuildContext context) {
    final list = apiaries;
    // урок: системне «назад» не працює — лише кнопка вгорі ліворуч
    return PopScope(
      canPop: !widget.tutorial,
      child: Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(
              title: tr.myApiaries,
              onBack: () => Navigator.of(context).pop(),
              // помічники: запросити, хто вже має доступ (в уроці - ні)
              trailing: widget.tutorial
                  ? null
                  : Tooltip(
                      message: tr.addHelper,
                      child: Material(
                        color: AppColors.roundBtn,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => HelpersScreen.open(context, widget.repo),
                          child: SizedBox.square(
                              dimension: 34,
                              child: Icon(Icons.person_add_alt_1, size: 20, color: AppColors.text)),
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty && widget.tutorial
                      ? Align(
                          alignment: Alignment.bottomCenter,
                          child: SingleChildScrollView(
                            child: GuideBubble(text: ApiaryListScreen.tutorialHello),
                          ),
                        )
                  : list.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            // ведмедик розгубився: пасіки ще немає
                            Image.asset('assets/guide/bear_surprised_mess.webp',
                                width: 200, filterQuality: FilterQuality.medium),
                            const SizedBox(height: 12),
                            Text(tr.noApiariesYet,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textMuted)),
                          ]),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _tile(list[i]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PillButton(
                text: tr.createMapButton,
                bg: AppColors.accent,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: _create,
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    ),
    );
  }

  Widget _tile(Apiary a) {
    final cells = _cells[a.id] ?? const <SceneCell>[];
    return Column(children: [
      Text(a.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Expanded(
        child: Tooltip(
          message: tr.open,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.darkBtn, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _open(a),
                  child: Stack(children: [
                    Positioned.fill(
                        child: IgnorePointer(
                            child: RepaintBoundary(child: SceneThumbnail(cells: cells)))),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: CircleIconButton(
                          icon: 'trash',
                          bg: AppColors.danger,
                          size: 28,
                          tooltip: tr.delete,
                          onPressed: () => _delete(a)),
                    ),
                    // QR-наліпки цієї пасіки — без відкриття карти
                    if (!widget.tutorial)
                      Positioned(
                        left: 3,
                        bottom: 3,
                        child: CircleIconButton(
                            icon: 'qr',
                            bg: AppColors.darkBtn,
                            size: 28,
                            tooltip: tr.qrLabels,
                            onPressed: () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => QrGenerateScreen(repo: widget.repo, apiary: a),
                              ));
                              await _reload();
                            }),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Клітинки для знімка: та сама логіка злиття, що й на карті.
  List<SceneCell> _cellsOf(List<MapElement> elements) {
    final items = [
      for (final e in elements)
        MergeItem<String>(
          e.id,
          e.x,
          e.y,
          '${e.groupId ?? e.id}|${e.type}|${e.isHive ? '' : (e.variant ?? '')}|${e.icon ?? ''}|${e.color ?? ''}',
        )
    ];
    final look = {
      for (final e in elements)
        e.id: (type: e.type, variant: e.variant, icon: e.icon, color: e.color)
    };
    return buildScene<String>(items: items, look: look, selected: const {});
  }
}
