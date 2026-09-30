import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/cell_value.dart';
import '../logic/merge_layout.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/theme.dart';
import 'template_editor_screen.dart';

/// Екран "Шаблони": плитки-мініатюри збережених конфігурацій + "Створити шаблон".
class TemplatesScreen extends StatefulWidget {
  final Repository repo;
  const TemplatesScreen({super.key, required this.repo});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<ApiaryTemplate>? templates;
  final Map<String, List<SceneCell>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.listTemplates();
    if (mounted) {
      setState(() {
        templates = list;
        _thumbs.clear();
      });
    }
  }

  Future<void> _open(String? id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemplateEditorScreen(repo: widget.repo, templateId: id),
    ));
    await _reload();
  }

  Future<void> _rename(ApiaryTemplate t) async {
    final name = await showTextPrompt(context, title: 'Перейменувати шаблон', initial: t.name);
    if (name == null) return;
    await widget.repo.updateTemplate(t.id, name: name);
    await _reload();
  }

  Future<void> _delete(ApiaryTemplate t) async {
    final ok = await showConfirm(context, text: 'Видалити шаблон «${t.name}»?');
    if (!ok) return;
    await widget.repo.deleteTemplate(t.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = templates;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Шаблони', onBack: () => Navigator.pop(context)),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодного шаблону',
                              style: TextStyle(color: AppColors.textMuted)))
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
                text: 'Створити шаблон',
                bg: AppColors.accent,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: () => _open(null),
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  /// Плитка шаблону — шматок карти з ним, як мініатюри пасік на головному
  /// екрані. Тап — відкрити, олівець — перейменувати, кошик — видалити.
  Widget _tile(ApiaryTemplate t) {
    final cells = _thumbs[t.id] ??= templateSceneCells(t);
    return Column(children: [
      Text(t.name,
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
                  onTap: () => _open(t.id),
                  onLongPress: () => _rename(t),
                  child: Stack(children: [
                    Positioned.fill(
                        child: IgnorePointer(
                            child: RepaintBoundary(child: SceneThumbnail(cells: cells)))),
                    Positioned(
                      left: 6,
                      bottom: 4,
                      child: Text('${t.width}×${t.height}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 3)])),
                    ),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: CircleIconButton(
                          icon: 'trash',
                          bg: AppColors.danger,
                          size: 28,
                          tooltip: 'Видалити',
                          onPressed: () => _delete(t)),
                    ),
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: CircleIconButton(
                          icon: 'pencil',
                          bg: AppColors.rename,
                          size: 28,
                          tooltip: 'Перейменувати',
                          onPressed: () => _rename(t)),
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
}

/// Клітинки мініатюри шаблону: та сама логіка злиття, що й у редакторі.
List<SceneCell> templateSceneCells(ApiaryTemplate t) {
  final h = t.height <= 0 ? 1 : t.height;
  final cells = <(int, int), CellValue>{};
  for (final e in t.cells.entries) {
    final pos = parseCellKey(e.key);
    if (pos == null) continue;
    // рядок 0 у збереженому шаблоні — верхній
    cells[(pos.$1, h - 1 - pos.$2)] = CellValue.parse(e.value);
  }
  return buildScene<(int, int)>(
    items: [for (final e in cells.entries) MergeItem<(int, int)>(e.key, e.key.$1, e.key.$2, e.value.mergeKey)],
    look: {
      for (final e in cells.entries)
        e.key: (type: e.value.type, variant: e.value.effectiveVariant, icon: e.value.icon, color: e.value.color)
    },
    selected: const {},
  );
}
