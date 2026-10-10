import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/cell_value.dart';
import '../logic/merge_layout.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/theme.dart';
import '../tutorial/lesson.dart';
import 'template_editor_screen.dart';

/// Екран "Шаблони": плитки-мініатюри збережених конфігурацій + "Створити шаблон".
class TemplatesScreen extends StatefulWidget {
  final Repository repo;

  /// Вкладка в «Налаштуваннях»: без власної верхньої панелі й рамки.
  final bool embedded;

  /// Урок «Налаштування»: «Створити шаблон» - ціль уроку.
  final LessonController? lesson;
  const TemplatesScreen({super.key, required this.repo, this.embedded = false, this.lesson});
  @override
  State<TemplatesScreen> createState() => TemplatesScreenState();
}

class TemplatesScreenState extends State<TemplatesScreen> {
  List<ApiaryTemplate>? templates;
  final Map<String, List<SceneCell>> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // шаблони, що видаляються (чекають кінця «Відмінити»): _reload їх не повертає
  final Set<String> _hiding = {};

  Future<void> _reload() async {
    final list = await widget.repo.listTemplates();
    if (mounted) {
      setState(() {
        templates = [for (final t in list) if (!_hiding.contains(t.id)) t];
        _thumbs.clear();
      });
    }
  }

  Future<void> _open(String? id) async {
    final l = widget.lesson;
    if (id == null) l?.advance(4, 5);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemplateEditorScreen(repo: widget.repo, templateId: id, lesson: l),
    ));
    // з уроку вийшли - пісочницю вже закривають
    if (!mounted || (l?.finished ?? false)) return;
    await _reload();
  }

  /// «Створити шаблон» (урок відкриває редактор сам, коли продовжують).
  Future<void> openNew() => _open(null);

  Future<void> _rename(ApiaryTemplate t) async {
    final name = await showTextPrompt(context, title: 'Перейменувати шаблон', initial: t.name);
    if (name == null) return;
    await widget.repo.updateTemplate(t.id, name: name);
    await _reload();
  }

  /// Видалення без підтвердження: шаблон зникає одразу, внизу «Відмінити».
  Future<void> _delete(ApiaryTemplate t) => deleteWithUndo(
        context,
        message: 'Шаблон «${t.name}» видалено',
        hide: () {
          _hiding.add(t.id);
          setState(() => templates = [...?templates]..removeWhere((x) => x.id == t.id));
        },
        restore: () {
          _hiding.remove(t.id);
          _reload();
        },
        commit: () async {
          await widget.repo.deleteTemplate(t.id);
          _hiding.remove(t.id);
          if (mounted) await _reload();
        },
      );

  @override
  Widget build(BuildContext context) {
    final list = templates;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            if (!widget.embedded) TopBar(title: 'Шаблони', onBack: () => Navigator.pop(context)),
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
              child: LessonTarget(
                lesson: widget.lesson,
                name: 'template-create',
                radius: 16,
                child: PillButton(
                  text: 'Створити шаблон',
                  bg: AppColors.accent,
                  height: 48,
                  radius: 16,
                  width: double.infinity,
                  onPressed: () => _open(null),
                ),
              ),
            ),
          ]),
          if (!widget.embedded) const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  /// Плитка шаблону. Тап — відкрити, олівець — перейменувати, кошик — видалити.
  Widget _tile(ApiaryTemplate t) => TemplateTile(
        template: t,
        cells: _thumbs[t.id] ??= templateSceneCells(t),
        tooltip: 'Відкрити',
        onTap: () => _open(t.id),
        onLongPress: () => _rename(t),
        onRename: () => _rename(t),
        onDelete: () => _delete(t),
      );
}

/// Плитка шаблону — шматок карти з ним (як мініатюри пасік): назва, мініатюра,
/// розмір. Одна на весь застосунок: список шаблонів і вибір «Оберіть шаблон».
class TemplateTile extends StatelessWidget {
  final ApiaryTemplate template;
  final List<SceneCell>? cells;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  const TemplateTile({
    super.key,
    required this.template,
    this.cells,
    this.tooltip,
    this.onTap,
    this.onLongPress,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = template;
    final scene = cells ?? templateSceneCells(t);
    return Column(children: [
      Text(t.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Expanded(
        child: Tooltip(
          message: tooltip ?? '${t.name} (${t.width}×${t.height})',
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
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Stack(children: [
                    Positioned.fill(
                        child: IgnorePointer(
                            child: RepaintBoundary(child: SceneThumbnail(cells: scene)))),
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
                    if (onDelete != null)
                      Positioned(
                        right: 3,
                        top: 3,
                        child: CircleIconButton(
                            icon: 'trash',
                            bg: AppColors.danger,
                            size: 28,
                            tooltip: 'Видалити',
                            onPressed: onDelete),
                      ),
                    if (onRename != null)
                      Positioned(
                        right: 3,
                        bottom: 3,
                        child: CircleIconButton(
                            icon: 'pencil',
                            bg: AppColors.rename,
                            size: 28,
                            tooltip: 'Перейменувати',
                            onPressed: onRename),
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
