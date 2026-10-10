import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/cell_value.dart';
import '../logic/geometry.dart';
import '../logic/merge_layout.dart';
import '../ui/characteristics_panel.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/guide_bubble.dart' show rectOfKey;
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../tutorial/lesson.dart';
import 'parameters_screen.dart';

/// Редактор заготовки (порт TemplateEditorScreen / TemplateGridArea).
///
/// Три режими:
///  * "За замовчуванням" (інформація): тап по намальованій клітинці обирає
///    ВЕСЬ її злитий екземпляр і відкриває справа панель "Характеристики";
///    повторний тап по обраному чи тап по порожньому — зняти вибір.
///    Нічого не переміщується.
///  * "Переміщення" (кнопка зі стрілками): дотик до екземпляра обирає його
///    й тим самим дотиком його можна перетягувати; над обраним — плаваючі
///    кнопки "Повернути"/"Видалити". Панель не відкривається.
///  * "Додавання" (кнопка "+"): тап по порожній клітинці малює обраний тип,
///    по намальованій — стирає.
class TemplateEditorScreen extends StatefulWidget {
  final Repository repo;
  final String? templateId;

  /// Урок «Налаштування (шаблони і параметри)».
  final LessonController? lesson;
  const TemplateEditorScreen({super.key, required this.repo, this.templateId, this.lesson});
  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _Snapshot {
  final Map<Cell, CellValue> cells;
  final Set<Cell> selected;
  _Snapshot(this.cells, this.selected);
}

class _EditorDrag {
  final Set<Cell> targets;
  final Set<Cell> occupied;
  final bool wasSelected;
  Cell shown = (0, 0);
  _EditorDrag(this.targets, this.occupied, this.wasSelected);
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen>
    with SingleTickerProviderStateMixin {
  Repository get repo => widget.repo;

  final grid = GridController(cellSize: 32, minCell: 14, maxCell: 56);

  String title = 'Новий шаблон';
  Map<Cell, CellValue> cells = {};
  Set<Cell> selected = {};
  List<Set<Cell>> _components = [];
  bool addingMode = false;
  bool moveMode = false;
  String mode = 'hive';
  String obstacleVariant = 'mountain';
  final List<_Snapshot> _undo = [];
  // ВИПРАВЛЕНО: раніше це був прапорець, що виставлявся при першій зміні
  // й ніколи не знімався — навіть якщо "Скасувати" повертало шаблон
  // точно до збереженого стану. Тепер "незбережено" обчислюється
  // порівнянням з знімком, зробленим при завантаженні/збереженні.
  String? _savedSnapshot;
  bool get _dirty => _savedSnapshot != null && _snapshot() != _savedSnapshot;

  String _snapshot() {
    final (_, _, out) = _export();
    // порядок клітинок у мапі залежить від історії правок — сортуємо, щоб
    // "прибрав і повернув" не рахувалось незбереженою зміною
    final keys = out.keys.toList()..sort();
    return jsonEncode({
      'title': title,
      'cells': {for (final k in keys) k: out[k]},
    });
  }

  _EditorDrag? _drag;
  bool _blocked = false;
  Timer? _blockedTimer;
  late final AnimationController _shake;
  Set<Cell> _shakeTargets = {};

  String? _warning;
  Timer? _warnTimer;

  PanelData? _panelData;

  LessonController? get _lesson => widget.lesson;

  /// Урок: квадрат 2×2, який треба заповнити перешкодами (від першої плитки).
  Set<Cell> _lessonSquare = const {};
  final _gridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
      ..addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _shake.dispose();
    _blockedTimer?.cancel();
    _warnTimer?.cancel();
    grid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.templateId;
    if (id != null) {
      final t = await repo.getTemplate(id);
      if (t != null) {
        final h = t.height <= 0 ? 1 : t.height;
        final loaded = <Cell, CellValue>{};
        // поле нескінченне: лівий нижній кут шаблону — у клітинці (0, 0);
        // рядок 0 у збереженому шаблоні — ВЕРХНІЙ
        for (final e in t.cells.entries) {
          final pos = parseCellKey(e.key);
          if (pos == null) continue;
          loaded[(pos.$1, h - 1 - pos.$2)] = CellValue.parse(e.value);
        }
        title = t.name;
        cells = loaded;
      }
    }
    _savedSnapshot = _snapshot();
    if (!mounted) return;
    final (cx, cy) = _cellsCenter();
    grid.centerOnGrid(cx, cy);
    setState(() {});
  }

  (double, double) _cellsCenter() {
    if (cells.isEmpty) return (0.5, 0.5);
    final xs = cells.keys.map((c) => c.$1), ys = cells.keys.map((c) => c.$2);
    final minX = xs.reduce((a, b) => a < b ? a : b), maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b), maxY = ys.reduce((a, b) => a > b ? a : b);
    return ((minX + maxX + 1) / 2, (minY + maxY + 1) / 2);
  }

  // ---------------------------------------------------------------------
  // стан і undo
  // ---------------------------------------------------------------------

  void _pushUndo() {
    _undo.add(_Snapshot(Map.of(cells), Set.of(selected)));
    if (_undo.length > 50) _undo.removeAt(0);
  }

  void _onUndo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    setState(() {
      cells = s.cells;
      selected = {for (final p in s.selected) if (cells.containsKey(p)) p};
    });
    _afterChange();
  }

  Set<Cell> _componentAt(Cell c) {
    for (final comp in _components) {
      if (comp.contains(c)) return comp;
    }
    return {c};
  }

  List<Cell> get _selectedCells => [for (final p in selected) if (cells.containsKey(p)) p];

  /// Після будь-якої зміни клітинок/вибору — оновити панель.
  void _afterChange() {
    // у режимі переміщення панель не показується
    if (_selectedCells.isEmpty || moveMode) {
      setState(() => _panelData = null);
    } else {
      _refreshPanel();
    }
  }

  Future<void> _refreshPanel() async {
    final sel = _selectedCells;
    if (sel.isEmpty) return;
    final v = cells[sel.first]!;
    final base = await repo.baseParameterIds(v.type);
    final ids = [...base.where((id) => !v.parameters.contains(id)), ...v.parameters];
    final params = <Parameter>[];
    for (final id in ids) {
      final p = await repo.getParameter(id);
      if (p != null && !p.deleted) params.add(p);
    }
    final groups = await repo.paramGroups();
    if (!mounted) return;
    setState(() {
      _panelData = PanelData(
        type: v.type,
        variant: v.effectiveVariant,
        icon: v.icon,
        color: v.color,
        title: title,
        params: [
          for (final p in params)
            if (!(p.isBase && p.baseKey == 'visit_period')) (p, null)
        ],
        placed: false,
        groups: groups,
      );
    });
  }

  // ---------------------------------------------------------------------
  // дотики
  // ---------------------------------------------------------------------

  bool _onPressDown(GridPress p) {
    // перетягувати можна лише в режимі переміщення
    if (addingMode || !moveMode) return false;
    if (!cells.containsKey(p.cell)) return false;
    final comp = _componentAt(p.cell);
    final wasSelected = selected.length == comp.length && selected.containsAll(comp);
    setState(() => selected = Set.of(comp));
    _drag = _EditorDrag(Set.of(comp), cells.keys.toSet().difference(comp), wasSelected);
    _afterChange();
    return true;
  }

  void _onPressMove(Offset delta) {
    final d = _drag;
    if (d == null) return;
    var (cdx, cdy) = grid.screenDeltaToCells(delta);
    final blocked = d.targets.any((c) => d.occupied.contains((c.$1 + cdx, c.$2 + cdy)));
    if (blocked) {
      // заморожуємо на останній вільній позиції
      cdx = d.shown.$1;
      cdy = d.shown.$2;
    }
    setState(() => d.shown = (cdx, cdy));
    if (blocked != _blocked) {
      setState(() => _blocked = blocked);
      if (blocked) {
        _shakeTargets = d.targets;
        _shake.forward(from: 0);
      }
    }
  }

  void _onPressUp(Offset delta) {
    final d = _drag;
    _drag = null;
    setState(() => _blocked = false);
    if (d == null) return;
    final (cdx, cdy) = d.shown;
    if (cdx == 0 && cdy == 0) {
      // справжній тап (палець майже не рухався) по вже обраному — зняти вибір
      if (delta.distance <= InfiniteGrid.panThreshold && d.wasSelected) {
        setState(() => selected = {});
      }
      _afterChange();
      return;
    }
    _moveSelected(cdx, cdy);
  }

  void _onTap(GridPress p) {
    final key = p.cell;
    if (addingMode) {
      _pushUndo();
      setState(() {
        if (cells.containsKey(key)) {
          cells.remove(key);
        } else {
          cells[key] = mode == 'hive'
              ? const CellValue(type: 'hive')
              : CellValue(type: 'obstacle', variant: obstacleVariant);
        }
        selected = {};
      });
      _lessonAfterTap(key);
      _afterChange();
      return;
    }
    if (!moveMode && cells.containsKey(key)) {
      // режим інформації: тап обирає екземпляр і відкриває панель,
      // повторний тап по ньому ж — закриває
      final comp = _componentAt(key);
      final same = selected.length == comp.length && selected.containsAll(comp);
      setState(() => selected = same ? {} : Set.of(comp));
      _afterChange();
      return;
    }
    if (selected.isNotEmpty) {
      setState(() => selected = {});
      _afterChange();
    }
  }

  /// Урок: перша плитка перешкоди - далі квадрат 2×2 від неї; квадрат
  /// заповнено - «Червоною кнопкою» завершити додавання.
  void _lessonAfterTap(Cell key) {
    final l = _lesson;
    if (l == null) return;
    if (l.step == 7 && cells[key]?.type == 'obstacle') {
      // квадрат росте від плитки до середини поля: унизу пасічник, праворуч -
      // кнопки масштабу, тож туди не лізе
      final size = _gridKey.currentContext?.size;
      final c = grid.cellRect(key.$1, key.$2).center;
      final dx = size != null && c.dx > size.width / 2 ? -1 : 1;
      final dy = size != null && c.dy > size.height / 2 ? -1 : 1;
      setState(() => _lessonSquare = {
            key,
            (key.$1 + dx, key.$2),
            (key.$1, key.$2 + dy),
            (key.$1 + dx, key.$2 + dy),
          });
      l.go(8);
    } else if (l.step == 8 &&
        _lessonSquare.isNotEmpty &&
        _lessonSquare.every((c) => cells[c]?.type == 'obstacle')) {
      l.go(9);
    }
  }

  /// Урок: квадрат 2×2 у медовому ободку.
  List<Widget> _lessonSquareGlow() {
    if (_lesson?.step != 8 || _lessonSquare.isEmpty) return const [];
    return [
      AnimatedBuilder(
        animation: grid,
        builder: (context, _) {
          Rect? r;
          for (final c in _lessonSquare) {
            final cr = grid.cellRect(c.$1, c.$2);
            r = r == null ? cr : r.expandToInclude(cr);
          }
          return Positioned.fromRect(
            rect: r!.inflate(3),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.create, width: 3),
                  boxShadow: [
                    BoxShadow(color: AppColors.create.withValues(alpha: 0.6), blurRadius: 12)
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  /// Рамка квадрата уроку в координатах шару уроку [ref].
  Rect? _lessonSquareRect(RenderBox ref) {
    final g = rectOfKey(_gridKey, ref);
    if (g == null || _lessonSquare.isEmpty) return null;
    Rect? r;
    for (final c in _lessonSquare) {
      final cr = grid.cellRect(c.$1, c.$2).shift(g.topLeft);
      r = r == null ? cr : r.expandToInclude(cr);
    }
    return r;
  }

  /// Увімкнути/вимкнути режим переміщення (вимикає додавання).
  void _toggleMove() {
    setState(() {
      moveMode = !moveMode;
      addingMode = false;
      selected = {};
    });
    _afterChange();
  }

  // ---------------------------------------------------------------------
  // операції над екземпляром
  // ---------------------------------------------------------------------

  bool _moveSelected(int dx, int dy) {
    final targets = _selectedCells;
    if (targets.isEmpty || (dx == 0 && dy == 0)) return false;
    final newPos = {for (final p in targets) p: (p.$1 + dx, p.$2 + dy)};
    final others = cells.keys.toSet().difference(targets.toSet());
    if (newPos.values.any(others.contains)) return false;
    _pushUndo();
    final moved = {for (final p in targets) newPos[p]!: cells[p]!};
    setState(() {
      for (final p in targets) {
        cells.remove(p);
      }
      cells.addAll(moved);
      selected = moved.keys.toSet();
    });
    _afterChange();
    return true;
  }

  void _rotate() {
    if (cells.isEmpty) return;
    final targets = _selectedCells.isNotEmpty ? _selectedCells : cells.keys.toList();
    final newPos = rotatedPositions({for (final p in targets) p: p});
    final others = cells.keys.toSet().difference(targets.toSet());
    if (newPos.values.any(others.contains)) {
      _showWarning('Немає місця для повороту');
      _flashBlocked();
      return;
    }
    _pushUndo();
    final moved = {for (final p in targets) newPos[p]!: cells[p]!};
    setState(() {
      for (final p in targets) {
        cells.remove(p);
      }
      cells.addAll(moved);
      if (selected.isNotEmpty) selected = moved.keys.toSet();
    });
    _afterChange();
  }

  void _deleteSelected() {
    final targets = _selectedCells;
    if (targets.isEmpty) return;
    _pushUndo();
    setState(() {
      for (final p in targets) {
        cells.remove(p);
      }
      selected = {};
    });
    _afterChange();
  }

  void _applyToSelected(CellValue Function(CellValue v) f) {
    final targets = _selectedCells;
    if (targets.isEmpty) return;
    _pushUndo();
    setState(() {
      for (final p in targets) {
        cells[p] = f(cells[p]!);
      }
    });
    _afterChange();
  }

  void _flashBlocked() {
    _blockedTimer?.cancel();
    setState(() => _blocked = true);
    _shakeTargets = _selectedCells.isNotEmpty ? _selectedCells.toSet() : cells.keys.toSet();
    _shake.forward(from: 0);
    _blockedTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _blocked = false);
    });
  }

  void _showWarning(String text) {
    _warnTimer?.cancel();
    setState(() => _warning = text);
    _warnTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _warning = null);
    });
  }

  // ---------------------------------------------------------------------
  // кнопки
  // ---------------------------------------------------------------------

  Future<void> _onAddType() async {
    final l = _lesson;
    if (addingMode) {
      setState(() {
        addingMode = false;
        selected = {};
      });
      l?.advance(9, 10);
      _afterChange();
      return;
    }
    l?.advance(5, 6);
    final picked = await showDialog<(String, String?)>(
      context: context,
      barrierDismissible: l == null,
      builder: (ctx) {
        Widget section(String t, List<Widget> children) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: children),
              ],
            );
        return lessonDialog(l, 'editor-picker', AlertDialog(
          title: const Text('Тип для малювання'),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  section('Вулики', [
                    CircleIconButton(
                        icon: 'beehive',
                        bg: AppColors.hive,
                        size: 52,
                        tooltip: 'Вулик',
                        onPressed: () => Navigator.pop(ctx, ('hive', null))),
                  ]),
                  const SizedBox(height: 14),
                  LessonTarget(
                    lesson: l,
                    name: 'picker-obstacle',
                    radius: 14,
                    child: section('Перешкоди', [
                      for (final (key, label) in obstacleVariants)
                        CircleIconButton(
                            icon: key,
                            bg: AppColors.obstacle,
                            size: 52,
                            tooltip: label,
                            onPressed: () => Navigator.pop(ctx, ('obstacle', key))),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ));
      },
    );
    if (picked == null) {
      l?.advance(6, 5); // урок: вікно закрили - знову «+»
      return;
    }
    if (picked.$1 == 'obstacle') l?.advance(6, 7);
    setState(() {
      mode = picked.$1;
      if (picked.$2 != null) obstacleVariant = picked.$2!;
      addingMode = true;
      moveMode = false;
      selected = {};
    });
    _afterChange();
  }

  Future<void> _renameTemplate() async {
    final name = await showTextPrompt(context, title: 'Перейменувати шаблон', initial: title);
    if (name == null) return;
    setState(() {
      title = name;
    });
    _afterChange();
  }

  Future<void> _panelIcon() async {
    // обрано одного типу — лише його іконки; різне — обидві плитки
    final types = {for (final p in _selectedCells) cells[p]!.type};
    final r = await pickIcon(context,
        withReset: true, elType: types.length == 1 ? types.first : null);
    if (r == null) return;
    _applyToSelected((v) => v.copyWith(icon: r.$1));
  }

  Future<void> _panelColor() async {
    final r = await pickObjectColor(context, withReset: true);
    if (r == null) return;
    _applyToSelected((v) => v.copyWith(color: r.$1));
  }

  Future<void> _panelParams() async {
    final targets = _selectedCells;
    if (targets.isEmpty) return;
    final v = cells[targets.first]!;
    final result = await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => ParametersScreen.forTemplate(
        repo: repo,
        initialIds: v.parameters,
        elType: v.type,
      ),
    ));
    if (result == null) return;
    // порядок зі списку — для всіх майбутніх екземплярів шаблону; базові
    // характеристики лишаються в ньому (так зберігається їхнє місце).
    // id уже видаленого параметра прибираємо, щоб шаблон не носив
    // посилання на нього назавжди.
    final dead = await repo.deletedParameterIds();
    final ids = [for (final id in result) if (!dead.contains(id)) id];
    if (!mounted) return;
    // клітинки екземпляра не змінювались, поки був відкритий інший екран
    final still = [for (final p in targets) if (cells.containsKey(p)) p];
    if (still.isEmpty) return;
    _pushUndo();
    setState(() {
      for (final p in still) {
        cells[p] = cells[p]!.copyWith(parameters: ids);
      }
    });
    _afterChange();
  }

  /// Обрізати до мінімального прямокутника; ключі "col,row", рядок 0 — верхній.
  (int, int, Map<String, dynamic>) _export() {
    if (cells.isEmpty) return (1, 1, {});
    final xs = cells.keys.map((c) => c.$1), ys = cells.keys.map((c) => c.$2);
    final minX = xs.reduce((a, b) => a < b ? a : b), maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b), maxY = ys.reduce((a, b) => a > b ? a : b);
    return (
      maxX - minX + 1,
      maxY - minY + 1,
      {
        for (final e in cells.entries) '${e.key.$1 - minX},${maxY - e.key.$2}': e.value.toJson(),
      },
    );
  }

  bool _saving = false;

  Future<void> _save() async {
    // подвійний тап не має створювати два шаблони чи двічі закривати екран
    if (_saving) return;
    // порожній шаблон нічого не розмістить на карті — не зберігаємо
    if (cells.isEmpty) {
      _showWarning('Додайте хоча б одну клітинку');
      return;
    }
    // новий шаблон: перед збереженням одразу питаємо назву (скасували —
    // лишаємось у редакторі)
    if (widget.templateId == null) {
      _saving = true;
      final l = _lesson;
      l?.advance(10, 11);
      final asked = await showTextPrompt(context,
          title: 'Назва шаблону',
          initial: title.trim().isEmpty ? 'Новий шаблон' : title.trim(),
          dismissible: l == null,
          wrap: l == null ? null : (d) => lessonDialog(l, 'template-name', d),
          decorate: l == null
              ? null
              : (which, b) => LessonTarget(lesson: l, name: 'name-$which', radius: 14, child: b));
      _saving = false;
      if (asked == null) l?.advance(11, 10); // урок: вікно закрили - знову «зберегти»
      if (asked == null || !mounted) return;
      title = asked;
    }
    _saving = true;
    try {
      final name = title.trim().isEmpty ? 'Новий шаблон' : title.trim();
      final (w, h, out) = _export();
      if (widget.templateId != null) {
        final old = await repo.getTemplate(widget.templateId!);
        await repo.updateTemplate(widget.templateId!, name: name, width: w, height: h, cells: out);
        if (old != null && mounted) await _offerApplyToPlaced(old, out);
      } else {
        await repo.addTemplate(name, w, h, out);
        _lesson?.setData('template', name);
        _lesson?.advance(11, 12);
      }
      _savedSnapshot = _snapshot();
      if (mounted) Navigator.pop(context, true);
    } finally {
      _saving = false;
    }
  }

  /// Набір характеристик вулика в шаблоні (з першої клітинки-вулика).
  static List<String> _hiveParams(Map<String, dynamic> cells) {
    for (final v in cells.values) {
      final c = CellValue.parse(v);
      if (c.isHive) return c.parameters;
    }
    return const [];
  }

  /// Змінили набір характеристик шаблону: запропонувати застосувати його до
  /// вже поставлених з нього вуликів (інакше вони лишаються як були).
  Future<void> _offerApplyToPlaced(ApiaryTemplate old, Map<String, dynamic> newCells) async {
    final before = _hiveParams(old.cells), after = _hiveParams(newCells);
    if (before.join('|') == after.join('|')) return;
    final hives = await repo.hivesPlacedFrom(old.name);
    if (hives.isEmpty || !mounted) return;
    final ok = await showConfirm(context,
        title: 'Застосувати до вуликів?',
        text: 'З шаблону «${old.name}» уже поставлено вуликів: ${hives.length}. '
            'Застосувати до них новий набір характеристик? '
            'Історія значень збережеться.',
        confirmText: 'Застосувати',
        cancelText: 'Не змінювати',
        danger: false);
    if (!ok) return;
    for (final h in hives) {
      await repo.setAttachedParameters(after, h);
    }
  }

  Future<void> _back() async {
    if (_lesson != null) {
      _lesson!.exit();
      return;
    }
    if (_dirty) {
      final leave = await showConfirm(context,
          title: 'Вийти без збереження?',
          text: 'Зміни в шаблоні буде втрачено.',
          confirmText: 'Вийти');
      if (!leave) return;
    }
    if (mounted) Navigator.pop(context);
  }

  // ---------------------------------------------------------------------
  // побудова
  // ---------------------------------------------------------------------

  List<SceneCell> _scene() {
    final items = [for (final e in cells.entries) MergeItem<Cell>(e.key, e.key.$1, e.key.$2, e.value.mergeKey)];
    _components = [for (final c in mergeLayout(items).components) c.toSet()];
    final look = {
      for (final e in cells.entries)
        e.key: (
          type: e.value.type,
          variant: e.value.effectiveVariant,
          icon: e.value.icon,
          color: e.value.color
        )
    };
    final shifts = <Cell, Offset>{};
    final cs = grid.cellSize;
    final d = _drag;
    if (d != null && d.shown != (0, 0)) {
      for (final p in d.targets) {
        shifts[p] = Offset(d.shown.$1 * cs, -d.shown.$2 * cs);
      }
    }
    if (_shake.isAnimating) {
      final dx = shakeOffset(_shake.value * 0.32, 0.32);
      for (final p in _shakeTargets) {
        shifts[p] = (shifts[p] ?? Offset.zero) + Offset(dx, 0);
      }
    }
    // рамка "заборонено" для повороту всього шаблону, коли нічого не обрано
    final sel = selected.isEmpty && _blocked ? cells.keys.toSet() : selected;
    return buildScene<Cell>(items: items, look: look, selected: sel, shifts: shifts);
  }

  String get _modeText {
    if (addingMode) {
      final what = mode == 'hive'
          ? 'Вулик'
          : 'Перешкода - ${obstacleVariantLabel(obstacleVariant)}';
      return 'Додаємо: $what   ·   торкніться клітинки, щоб прибрати';
    }
    if (moveMode) {
      return _selectedCells.isNotEmpty
          ? 'Перетягніть, щоб перемістити · над ним - поворот і видалення'
          : 'Переміщення: торкніться екземпляра й тягніть';
    }
    if (_selectedCells.isNotEmpty) return 'Інформація про екземпляр - справа';
    return 'Торкніться екземпляра, щоб побачити інформацію';
  }

  @override
  Widget build(BuildContext context) {
    final panelOpen = _panelData != null && _selectedCells.isNotEmpty && !moveMode;
    return PopScope(
      canPop: !_dirty && _lesson == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              SizedBox(
                height: 50,
                child: Row(children: [
                  const SizedBox(width: 12),
                  CircleIconButton(
                    icon: 'back_arrow',
                    bg: AppColors.roundBtn,
                    iconColor: AppColors.text,
                    size: 34,
                    onPressed: _back,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _renameTemplate,
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  return Stack(children: [
                    Positioned.fill(
                      key: _gridKey,
                      child: InfiniteGrid(
                        controller: grid,
                        cells: _scene(),
                        blocked: _blocked,
                        maskSelected: false,
                        showMoveHints: moveMode, // стрілки — лише в режимі переміщення
                        onPressDown: _onPressDown,
                        onPressMove: _onPressMove,
                        onPressUp: _onPressUp,
                        onTap: _onTap,
                      ),
                    ),
                    const Positioned.fill(child: ScreenFrame()),
                    // масштаб - як на основній карті: праворуч по центру
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      child: Center(child: ZoomButtons(controller: grid)),
                    ),
                    Positioned(
                      top: 14,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: CapsuleLabel(_warning ?? '',
                              bg: AppColors.warning, fg: Colors.white),
                        ),
                      ),
                    ),
                    ..._overlayButtons(box.biggest),
                    ..._lessonSquareGlow(),
                  ]);
                }),
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 26),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                alignment: Alignment.center,
                child: Text(_modeText,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              Container(
                height: 70,
                color: AppColors.panel,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // у режимі додавання «+» стає червоним хрестиком - ним і вимикають
                  LessonTarget(
                    lesson: _lesson,
                    name: 'editor-add',
                    child: CircleIconButton(
                      icon: addingMode ? 'close' : 'plus_circle',
                      bg: addingMode ? AppColors.danger : AppColors.accent,
                      tooltip: addingMode ? 'Завершити додавання' : 'Додати',
                      onPressed: _onAddType,
                    ),
                  ),
                  const SizedBox(width: 16),
                  CircleIconButton(
                    icon: 'move',
                    bg: moveMode ? AppColors.modeActive : AppColors.darkBtn,
                    tooltip: moveMode ? 'Завершити переміщення' : 'Переміщення',
                    onPressed: _toggleMove,
                  ),
                  const SizedBox(width: 16),
                  CircleIconButton(
                    icon: 'back_arrow',
                    bg: AppColors.darkBtn,
                    tooltip: 'Скасувати',
                    onPressed: _undo.isEmpty ? null : _onUndo,
                  ),
                  const SizedBox(width: 16),
                  // дискета замість галочки
                  LessonTarget(
                    lesson: _lesson,
                    name: 'editor-save',
                    child: Tooltip(
                    message: 'Зберегти',
                    child: Material(
                      color: AppColors.accent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _save,
                        child: const SizedBox.square(
                            dimension: 46, child: Icon(Icons.save, color: Colors.white, size: 26)),
                      ),
                    ),
                  ),
                  ),
                ]),
              ),
            ]),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: panelOpen ? Curves.easeOutCubic : Curves.easeInCubic,
              top: 52,
              bottom: 100,
              right: panelOpen ? 0 : -(CharacteristicsPanel.width + 12),
              child: _panelData == null
                  ? const SizedBox(width: CharacteristicsPanel.width)
                  : CharacteristicsPanel(
                      data: _panelData!,
                      onClose: () {
                        setState(() => selected = {});
                        _afterChange();
                      },
                      onRename: _renameTemplate,
                      onIcon: _panelIcon,
                      onColor: _panelColor,
                      onEditParams: _panelParams,
                    ),
            ),
            // урок: пасічник над нижньою панеллю кнопок
            if (_lesson != null)
              Positioned.fill(
                child: LessonLayer(
                  lesson: _lesson!,
                  screen: 'editor',
                  bottomInset: 96,
                  // у редакторі шаблону перемикача «око / олівець» немає
                  drawToggle: false,
                  regions: {
                    'grid': (ref) => rectOfKey(_gridKey, ref),
                    'square': _lessonSquareRect,
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Плаваючі кнопки "Повернути"/"Видалити" над обраним екземпляром.
  /// Під час перетягування ховаються.
  List<Widget> _overlayButtons(Size area) {
    if (_drag != null || addingMode || !moveMode) return const [];
    final sel = _selectedCells;
    if (sel.isEmpty) return const [];
    return [
      AnimatedBuilder(
        animation: grid,
        builder: (context, _) {
          final r = cellsScreenBounds(grid, sel);
          if (r == null) return const SizedBox.shrink();
          const bs = 36.0;
          const gap = kHintGap + kHintSize + 8;
          var top = r.top - gap - bs;
          if (top < 4) top = r.bottom + gap; // не вміщається згори — під фігурою
          final maxLeft = area.width - 2 * bs - 10;
          final left = maxLeft <= 4 ? 4.0 : (r.center.dx - bs - 3).clamp(4.0, maxLeft).toDouble();
          return Positioned(
            left: left,
            top: top,
            child: Row(children: [
              CircleIconButton(
                  icon: 'rotate',
                  bg: AppColors.darkBtn,
                  size: bs,
                  tooltip: 'Повернути',
                  onPressed: _rotate),
              const SizedBox(width: 6),
              CircleIconButton(
                  icon: 'trash',
                  bg: AppColors.danger,
                  size: bs,
                  tooltip: 'Видалити',
                  onPressed: _deleteSelected),
            ]),
          );
        },
      ),
    ];
  }
}
