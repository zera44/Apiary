import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/merge_layout.dart';
import '../ui/app_drawer.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/theme.dart';
import 'map_screen.dart';
import 'new_apiary_screen.dart';
import 'splash_screen.dart';

/// Список пасік застосунку: тап відкриває карту, "+" — створює нову.
class ApiaryListScreen extends StatefulWidget {
  final Repository repo;
  const ApiaryListScreen({super.key, required this.repo});
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

  Future<void> _reload() async {
    final list = await widget.repo.listApiaries();
    // один запит на всі пасіки; клітинки для мініатюр рахуються тут раз,
    // а не при кожному перемальовуванні списку
    final els = await widget.repo.listElementsByApiary([for (final a in list) a.id]);
    if (!mounted) return;
    setState(() {
      apiaries = list;
      _cells
        ..clear()
        ..addAll({for (final e in els.entries) e.key: _cellsOf(e.value)});
    });
  }

  Future<void> _open(Apiary a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(repo: widget.repo, apiary: a),
    ));
    await _reload();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Apiary>(MaterialPageRoute(
      builder: (_) => NewApiaryScreen(repo: widget.repo),
    ));
    await _reload();
    // нова пасіка одразу відкривається; _open оновить список після повернення
    if (created != null && mounted) await _open(created);
  }

  Future<void> _rename(Apiary a) async {
    final name = await showTextPrompt(context, title: 'Перейменувати пасіку', initial: a.name);
    if (name == null) return;
    await widget.repo.updateApiary(a.id, name: name);
    await _reload();
  }

  bool _deleting = false;

  Future<void> _delete(Apiary a) async {
    if (_deleting) return;
    final ok = await showConfirm(context,
        text: 'Видалити пасіку «${a.name}» разом з усіма її об\'єктами?');
    if (!ok || _deleting) return;
    _deleting = true;
    try {
      await widget.repo.deleteApiary(a.id);
      await _reload();
    } finally {
      _deleting = false;
    }
  }

  /// Назад із головної — на заставку In Riy (кнопка «назад» і системна).
  void _toSplash() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SplashScreen(repo: widget.repo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = apiaries;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toSplash();
      },
      child: Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Мої пасіки', onBack: _toSplash),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодної пасіки.\nСтвори її кнопкою нижче.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: PillButton(
                text: 'Сканувати QR-код',
                bg: AppColors.darkBtn,
                fg: AppColors.text,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: () => AppDrawer.openHiveByQr(Navigator.of(context), widget.repo),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PillButton(
                text: '+  Створити карту',
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Expanded(
        child: Tooltip(
          message: 'Відкрити',
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
                  onLongPress: () => _rename(a),
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
                          tooltip: 'Видалити',
                          onPressed: () => _delete(a)),
                    ),
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: CircleIconButton(
                          icon: 'pencil',
                          bg: AppColors.rename,
                          size: 28,
                          tooltip: 'Перейменувати',
                          onPressed: () => _rename(a)),
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
