import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/cell_value.dart' show parseCellKey;
import '../logic/geometry.dart';
import '../logic/hive_objects.dart';
import '../logic/merge_layout.dart';
import '../logic/visit_reminders.dart';
import '../services/reminders.dart';
import '../ui/app_drawer.dart';
import '../ui/characteristics_panel.dart';
import '../ui/common.dart';
import '../ui/fill_values_dialog.dart';
import '../ui/grid_view.dart';
import '../ui/theme.dart';
import 'history_screen.dart';
import 'parameters_screen.dart';
import 'qr_scan_screen.dart';
import 'template_editor_screen.dart';

/// Головний екран: карта пасіки (порт map_screen.py).
///
///  * Зліва внизу: «Додати» (одразу вибір шаблону й розміщення) і
///    «Редагувати». Список шаблонів — у меню ☰ → «Шаблони».
///  * "Редагувати": натиснути на об'єкт — обрати його (разом з усією групою)
///    і тим самим дотиком перетягувати; знизу — панель дій: додати об'єкт
///    із шаблону, повернути, перейменувати, крок назад, видалити, готово.
///  * Поза режимом редагування тап по об'єкту відкриває панель
///    "Характеристики".
/// Куди веде «Зберегти й далі» у формі вулика (обхід ланцюжком).
enum NextHive {
  /// наступний вулик на карті за розташуванням (зверху вниз, зліва направо)
  order,

  /// знову камера — наступна наліпка
  qr,

  /// наступний вулик із простроченим оглядом (з нагадування чи «Сьогодні оглянути»)
  overdue,
}

/// Ключ власника значень: група вуликів чи окремий вулик (як у VisitTarget).
String ownerKeyOf(MapElement e) => e.groupId != null ? 'g:${e.groupId}' : 'e:${e.id}';

class MapScreen extends StatefulWidget {
  final Repository repo;
  final Apiary apiary;

  /// Одразу показати цей об'єкт і відкрити його панель (після сканування
  /// QR-коду вулика).
  final String? focusElementId;

  /// Разом із [focusElementId]: одразу відкрити форму «Заповнити» цього
  /// вулика (після сканування QR чи натискання на нагадування — людина
  /// прийшла саме заповнити).
  final bool openFill;

  /// Куди веде «Зберегти й далі».
  final NextHive next;
  const MapScreen(
      {super.key,
      required this.repo,
      required this.apiary,
      this.focusElementId,
      this.openFill = false,
      this.next = NextHive.order});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _Undo {
  final List<MapElement>? restore;
  // ВИПРАВЛЕНО: знімок прив'язок параметрів на момент видалення — без
  // нього "крок назад" після видалення міг повернути об'єкт без
  // призначених йому (не базових) параметрів.
  final List<Map<String, Object?>>? paramRows;
  /// Прибрати ці групи (крок назад після розміщення шаблону — він дає
  /// кілька окремих об'єктів).
  final List<String>? deleteGroupIds;
  const _Undo.restore(this.restore, {this.paramRows}) : deleteGroupIds = null;
  const _Undo.deleteGroups(this.deleteGroupIds)
      : restore = null,
        paramRows = null;
}

class _Drag {
  final List<Cell> cells;
  final Set<Cell> occupied;
  Cell shown = (0, 0);
  _Drag(this.cells, this.occupied);
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  Repository get repo => widget.repo;

  final grid = GridController(cellSize: 34, minCell: 18, maxCell: 56);
  List<MapElement> elements = [];

  bool selectMode = false;
  ApiaryTemplate? pendingTemplate;
  String? selectedId;
  String? selectedGroupId;
  // щойно поставлений шаблон: поки його не відпустили, усі його вулики й
  // перешкоди тягнуться/повертаються/видаляються разом. Це лише на час
  // розміщення — після цього кожен об'єкт вибирається окремо.
  Set<String> _placedGids = const {};
  final List<_Undo> undoStack = [];
  // ВИПРАВЛЕНО: захищає від гонки при швидких повторних діях (два тапи
  // "Повернути" чи два тапи розміщення шаблону підряд) — без цього друга
  // дія стартувала на застарілому [elements], ще до того, як перша
  // встигала оновити стан, і губила крок undo або дозволяла накладання
  // об'єктів.
  bool _busy = false;

  _Drag? _drag;
  bool _blocked = false;
  late final AnimationController _shake;
  Timer? _blockedFlash;

  String? _warning;
  Timer? _warnTimer;

  // панель "Характеристики"
  bool panelOpen = false;
  MapElement? panelElement;
  PanelData? panelData;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
      ..addListener(() => setState(() {}));
    _init();
  }

  Future<void> _init() async {
    // «Почати» на головному екрані відкриватиме цю пасіку
    unawaited(repo.setMeta('last_apiary', widget.apiary.id));
    await _reload();
    if (elements.isNotEmpty) {
      var minX = elements.first.x, maxX = minX, minY = elements.first.y, maxY = minY;
      for (final e in elements) {
        if (e.x < minX) minX = e.x;
        if (e.x > maxX) maxX = e.x;
        if (e.y < minY) minY = e.y;
        if (e.y > maxY) maxY = e.y;
      }
      grid.centerOnGrid((minX + maxX + 1) / 2, (minY + maxY + 1) / 2);
    }
    final focusId = widget.focusElementId;
    if (focusId != null && mounted) {
      final el = elements.where((e) => e.id == focusId).firstOrNull;
      if (el != null) {
        grid.centerOnGrid(el.x + 0.5, el.y + 0.5);
        await _onInfoRequest(el);
        if (widget.openFill && el.isHive && mounted && panelElement != null) await _panelFill();
      }
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _warnTimer?.cancel();
    _blockedFlash?.cancel();
    grid.dispose();
    // список пасік оновить мініатюру цієї карти
    repo.mapChanges.value++;
    super.dispose();
  }

  Future<void> _reload() async {
    final els = await repo.listElements(widget.apiary.id);
    final overdue = await _loadOverdue();
    if (!mounted) return;
    setState(() {
      elements = els;
      _overdue = overdue;
      _blocked = false;
    });
  }

  /// Вулики (ключі власників) із простроченим оглядом — червоний ободок.
  Set<String> _overdue = const {};

  Future<Set<String>> _loadOverdue() async {
    final now = DateTime.now();
    return {
      for (final t in await repo.visitTargets())
        if (dueReminder(t, now: now) != null) t.key
    };
  }

  Future<void> _refreshOverdue() async {
    final o = await _loadOverdue();
    if (!mounted) return;
    setState(() {
      _overdue = o;
      _sceneBase = null; // перебудувати сцену з новими ободками
    });
  }

  // ---------------------------------------------------------------------
  // вибір
  // ---------------------------------------------------------------------

  List<MapElement> get selection {
    if (selectedGroupId != null) {
      final gids = _selGids;
      return elements.where((e) => gids.contains(e.groupId)).toList();
    }
    if (selectedId != null) return elements.where((e) => e.id == selectedId).toList();
    return const [];
  }

  Set<String> get _selGids => selectedGroupId == null
      ? const {}
      : (_placedGids.contains(selectedGroupId) ? _placedGids : {selectedGroupId!});

  bool get hasSelection => selectedGroupId != null || selectedId != null;

  MapElement? _elementAt((int, int) cell) {
    for (final e in elements) {
      if (e.x == cell.$1 && e.y == cell.$2) return e;
    }
    return null;
  }

  void _select(MapElement el) {
    if (el.groupId == null || !_placedGids.contains(el.groupId)) _placedGids = const {};
    if (el.groupId != null) {
      selectedGroupId = el.groupId;
      selectedId = null;
    } else {
      selectedId = el.id;
      selectedGroupId = null;
    }
  }

  // ---------------------------------------------------------------------
  // дотики по карті
  // ---------------------------------------------------------------------

  /// Довгий дотик до об'єкта: одразу режим редагування, об'єкт обрано й
  /// його можна тягнути тим самим дотиком (без «Редагувати» й вибору шаблону).
  bool _onLongPress(GridPress p) {
    if (_busy || _elementAt(p.cell) == null) return false;
    if (!selectMode) _enterEdit();
    return _onPressDown(p);
  }

  bool _onPressDown(GridPress p) {
    // поки триває інша дія (запис у базу), нове перетягування не починаємо —
    // воно спиралось би на застарілий список об'єктів
    // у режимі розміщення шаблону теж: щойно поставлений (чи будь-який
    // інший) об'єкт можна одразу перетягнути; тап по порожньому — новий
    if (!selectMode || _busy) return false;
    final match = _elementAt(p.cell);
    if (match == null) return false;
    // вибір і початок перетягування — одним дотиком
    setState(() => _select(match));
    final sel = selection;
    final ids = {for (final e in sel) e.id};
    _drag = _Drag(
      [for (final e in sel) (e.x, e.y)],
      {for (final e in elements) if (!ids.contains(e.id)) (e.x, e.y)},
    );
    return true;
  }

  /// Куди стане об'єкт: найближча клітинка, якщо там вільно; інакше
  /// лишається в останній вільній позиції.
  (Cell, bool) _dragTarget(Offset delta) {
    final d = _drag!;
    final cand = grid.screenDeltaToCells(delta);
    final hit = d.cells.any((c) => d.occupied.contains((c.$1 + cand.$1, c.$2 + cand.$2)));
    return hit ? (d.shown, true) : (cand, false);
  }

  void _onPressMove(Offset delta) {
    if (_drag == null) return;
    final (target, blocked) = _dragTarget(delta);
    setState(() => _drag!.shown = target);
    if (blocked != _blocked) {
      setState(() => _blocked = blocked);
      if (blocked) {
        _shake.forward(from: 0);
        _showWarning("Тут уже є інший об'єкт");
      } else {
        _clearWarning();
      }
    }
  }

  Future<void> _onPressUp(Offset delta) async {
    final d = _drag;
    if (d == null) return;
    if (_busy) {
      setState(() {
        _drag = null;
        _blocked = false;
      });
      _clearWarning();
      return;
    }
    final (target, _) = _dragTarget(delta);
    final releasedBlocked = _blocked;
    // _drag лишається, поки база не оновиться: об'єкт показується на новому
    // місці без "стрибка" назад на кілька кадрів
    setState(() => _busy = true);
    try {
      final (dx, dy) = target;
      if (dx != 0 || dy != 0) {
        final sel = selection;
        final ids = {for (final e in sel) e.id};
        // перевірка по СВІЖОМУ стану: поки один палець тягнув, другим могли
        // повернути фігуру чи "кроком назад" відновити інший об'єкт
        final occupied = {for (final e in elements) if (!ids.contains(e.id)) (e.x, e.y)};
        final sameShape = sel.length == d.cells.length && sel.every((e) => d.cells.contains((e.x, e.y)));
        final free = sel.isNotEmpty &&
            sameShape &&
            !sel.any((e) => occupied.contains((e.x + dx, e.y + dy)));
        if (!free) {
          _showWarning("Тут уже є інший об'єкт", duration: const Duration(seconds: 1));
        } else if (selectedGroupId != null) {
          _pushUndo(_Undo.restore(sel));
          for (final gid in _selGids) {
            await repo.moveGroup(gid, dx, dy);
          }
        } else if (selectedId != null) {
          final el = sel.first;
          _pushUndo(_Undo.restore([el]));
          await repo.moveElement(el.id, el.x + dx, el.y + dy);
        }
      }
      final els = await repo.listElements(widget.apiary.id);
      if (!mounted) return;
      // нові позиції й зняття зсуву — одним кадром
      setState(() {
        elements = els;
        _drag = null;
        _blocked = false;
      });
      if (releasedBlocked) {
        _showWarning("Тут уже є інший об'єкт", duration: const Duration(seconds: 1));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _drag = null;
        });
      }
    }
  }

  Future<void> _onTap(GridPress p) async {
    if (!selectMode) {
      await _onInfoRequest(_elementAt(p.cell));
      return;
    }
    final tpl = pendingTemplate;
    if (tpl == null || _busy) return;
    // порожній шаблон (без жодної клітинки) не має що розміщувати
    if (!tpl.cells.keys.any((k) => parseCellKey(k) != null)) {
      _showWarning('Шаблон порожній', duration: const Duration(seconds: 1));
      return;
    }
    setState(() => _busy = true);
    try {
      final (gx, gy) = p.cell;
      // заборонити розміщення поверх існуючого об'єкта
      final occupied = {for (final e in elements) (e.x, e.y)};
      for (final key in tpl.cells.keys) {
        final parts = key.split(',');
        if (parts.length != 2) continue;
        final col = int.tryParse(parts[0]) ?? 0, row = int.tryParse(parts[1]) ?? 0;
        if (occupied.contains((gx + col, gy - row))) {
          _showWarning('Клітинка зайнята', duration: const Duration(seconds: 1));
          return;
        }
      }
      // одна дія — кілька окремих об'єктів (кожен вулик і перешкода окремо)
      final gids = await repo.placeTemplate(widget.apiary.id, tpl.cells, gx, gy, name: tpl.name);
      if (gids.isEmpty) return;
      _pushUndo(_Undo.deleteGroups(gids));
      selectedId = null;
      selectedGroupId = gids.first; // щойно поставлений шаблон обраний цілим
      _placedGids = {...gids};
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // попередження / статус
  // ---------------------------------------------------------------------

  void _showWarning(String text, {Duration? duration}) {
    _warnTimer?.cancel();
    setState(() => _warning = text);
    if (duration != null) {
      _warnTimer = Timer(duration, _clearWarning);
    }
  }

  void _clearWarning() {
    _warnTimer?.cancel();
    if (mounted) setState(() => _warning = null);
  }

  String get _statusText {
    if (!selectMode) return '';
    if (pendingTemplate != null) {
      return 'Тапай — ставити «${pendingTemplate!.name}», тягни — перемістити';
    }
    if (selectedGroupId != null) {
      final sel = selection;
      final label = sel.map((e) => e.label).firstWhere((l) => l != null && l.isNotEmpty,
          orElse: () => null);
      return label ?? 'Група (${sel.length})';
    }
    if (selectedId != null) {
      final el = selection.firstOrNull;
      if (el == null) return '';
      return (el.label?.isNotEmpty ?? false) ? el.label! : (el.isHive ? 'Вулик' : 'Перешкода');
    }
    return 'Оберіть вулик';
  }

  void _flashBlocked() {
    _blockedFlash?.cancel();
    setState(() => _blocked = true);
    _shake.forward(from: 0);
    _blockedFlash = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _blocked = false);
    });
  }

  // ---------------------------------------------------------------------
  // undo
  // ---------------------------------------------------------------------

  void _pushUndo(_Undo u) {
    undoStack.add(u);
    if (undoStack.length > 30) undoStack.removeAt(0);
  }

  Future<void> _onUndo() async {
    if (undoStack.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final u = undoStack.removeLast();
      if (u.restore != null) {
        await repo.restoreElements(u.restore!);
        if (u.paramRows != null && u.paramRows!.isNotEmpty) {
          await repo.restoreParameterBindings(u.paramRows!);
        }
      } else if (u.deleteGroupIds != null) {
        for (final gid in u.deleteGroupIds!) {
          await repo.deleteGroup(gid);
        }
        if (u.deleteGroupIds!.contains(selectedGroupId)) selectedGroupId = null;
      }
      _placedGids = const {};
      await _reload();
      // вибір міг зникнути (об'єкта більше немає)
      if (selectedId != null && !elements.any((e) => e.id == selectedId)) selectedId = null;
      if (selectedGroupId != null && !elements.any((e) => e.groupId == selectedGroupId)) {
        selectedGroupId = null;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // режим редагування і дії
  // ---------------------------------------------------------------------

  void _enterEdit() {
    setState(() {
      panelOpen = false;
      selectMode = true;
      selectedId = null;
      selectedGroupId = null;
      _placedGids = const {};
    });
  }

  void _exitEdit() {
    setState(() {
      selectMode = false;
      pendingTemplate = null;
      selectedId = null;
      selectedGroupId = null;
      _placedGids = const {};
      undoStack.clear();
    });
    _clearWarning();
  }

  /// Позначка "користувач натиснув «Створити шаблон»" у діалозі вибору.
  static final ApiaryTemplate _createTemplate =
      ApiaryTemplate(id: '', name: '', width: 0, height: 0, cells: const {});

  Future<void> _onAddObject() async {
    final templates = await repo.listTemplates();
    if (!mounted) return;
    final picked = await showDialog<ApiaryTemplate>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Оберіть шаблон'),
        content: SizedBox(
          width: 320,
          child: templates.isEmpty
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Ще немає жодного шаблону.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.text)),
                  const SizedBox(height: 16),
                  PillButton(
                    text: 'Створити шаблон',
                    bg: AppColors.accent,
                    height: 44,
                    width: double.infinity,
                    onPressed: () => Navigator.pop(ctx, _createTemplate),
                  ),
                ])
              : SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final t in templates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: PillButton(
                          text: '${t.name} (${t.width}×${t.height})',
                          bg: AppColors.darkBtn,
                          fg: AppColors.text,
                          height: 44,
                          width: double.infinity,
                          onPressed: () => Navigator.pop(ctx, t),
                        ),
                      ),
                  ]),
                ),
        ),
      ),
    );
    if (picked == null) return;
    if (identical(picked, _createTemplate)) {
      // "Створити шаблон" → екран "Новий шаблон"; якщо шаблон з'явився —
      // одразу знову показуємо вибір, щоб його можна було поставити на карту
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TemplateEditorScreen(repo: repo),
      ));
      if (!mounted) return;
      if ((await repo.listTemplates()).isNotEmpty && mounted) await _onAddObject();
      return;
    }
    setState(() {
      pendingTemplate = picked;
      selectedId = null;
      selectedGroupId = null;
      _placedGids = const {};
    });
  }

  Future<void> _onRotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (selectedGroupId != null) {
        final els = selection;
        if (els.isEmpty) return;
        // спершу перевіряємо, чи повернута фігура не накладеться на інший об'єкт
        final newPos = rotatedPositions({for (final e in els) e.id: (e.x, e.y)});
        final ids = {for (final e in els) e.id};
        final occupied = {for (final e in elements) if (!ids.contains(e.id)) (e.x, e.y)};
        if (newPos.values.any(occupied.contains)) {
          _showWarning('Немає місця для повороту', duration: const Duration(seconds: 1));
          _flashBlocked();
          return;
        }
        _pushUndo(_Undo.restore(els));
        await repo.rotateGroups(_selGids.toList());
      } else if (selectedId != null) {
        final el = selection.firstOrNull;
        if (el == null) return;
        _pushUndo(_Undo.restore([el]));
        await repo.rotateElement(el.id);
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    final sel = selection;
    if (sel.isEmpty || _busy) return;
    final isGroup = selectedGroupId != null;
    // без «Точно видалити?»: одразу, а внизу «Відмінити» (= «Крок назад»)
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // ВИПРАВЛЕНО: знімок прив'язок параметрів ПЕРЕД видаленням, щоб
      // "крок назад" міг відновити їх, навіть якщо фонова синхронізація
      // встигне остаточно прибрати їх із бази до натискання undo.
      final paramRows = [
        for (final e in sel) ...await repo.attachedParameterRows(e.entity),
      ];
      _pushUndo(_Undo.restore(sel, paramRows: paramRows));
      if (isGroup) {
        for (final gid in _selGids) {
          await repo.deleteGroup(gid);
        }
      } else {
        await repo.deleteElement(sel.first.id);
      }
      selectedId = null;
      selectedGroupId = null;
      _placedGids = const {};
      await _reload();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(isGroup ? "Групу об'єктів видалено" : "Об'єкт видалено"),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Відмінити',
          onPressed: () {
            if (mounted) _onUndo();
          },
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // панель "Характеристики"
  // ---------------------------------------------------------------------

  Future<void> _onInfoRequest(MapElement? el) async {
    if (el == null) {
      if (panelOpen) setState(() => panelOpen = false);
      return;
    }
    // той самий об'єкт (будь-яка його клітинка) — закрити; інший вулик тієї ж
    // групи — показати його (QR-код у панелі — свій для кожного вулика)
    if (panelOpen &&
        panelElement != null &&
        mergedObjectOf(panelElement!, elements).any((e) => e.id == el.id)) {
      setState(() => panelOpen = false);
      return;
    }
    await _loadPanel(el);
    if (!mounted) return;
    setState(() => panelOpen = true);
    _revealBesidePanel(el);
  }

  /// Панель «Характеристики» праворуч не повинна закривати обраний об'єкт:
  /// якщо він під панеллю чи біля краю — зсунути карту, щоб він став
  /// посередині вільної частини ліворуч від панелі.
  void _revealBesidePanel(MapElement el) {
    final view = grid.viewSize;
    if (view.isEmpty) return;
    Rect? r;
    for (final c in mergedObjectOf(el, elements)) {
      final cr = grid.cellRect(c.x, c.y);
      r = r == null ? cr : r.expandToInclude(cr);
    }
    if (r == null) return;
    const margin = 12.0;
    final freeRight = view.width - CharacteristicsPanel.width - margin;
    if (freeRight < 60) return; // вузьке вікно — місця ліворуч немає
    const top = 60.0; // під назвою пасіки
    final bottom = view.height - 90; // над кнопками внизу
    var dx = 0.0, dy = 0.0;
    if (r.right > freeRight || r.left < margin) dx = freeRight / 2 - r.center.dx;
    if (r.top < top || r.bottom > bottom) dy = (top + bottom) / 2 - r.center.dy;
    if (dx != 0 || dy != 0) grid.panBy(Offset(dx, dy));
  }

  Future<void> _loadPanel(MapElement el) async {
    final fresh = await repo.getElement(el.id) ?? el;
    final entity = fresh.entity;
    String title;
    if (fresh.groupId != null) {
      final members = await repo.getGroupElements(fresh.groupId!);
      title = members.map((e) => e.label).firstWhere((l) => l != null && l.isNotEmpty,
              orElse: () => null) ??
          (fresh.isHive ? 'Вулик' : 'Перешкода');
    } else {
      title = (fresh.label?.isNotEmpty ?? false) ? fresh.label! : (fresh.isHive ? 'Вулик' : 'Перешкода');
    }
    final params = await repo.attachedParameters(entity, elType: fresh.type);
    final latest = await repo.latestParameterValues(entity);
    final last = await repo.lastUpdated(entity);
    // вулик на кілька клітинок — один код на весь вулик
    final qr = fresh.isHive
        ? await repo.qrForObject(hiveObjectOf(fresh, elements))
        : await repo.qrForElement(fresh);
    if (!mounted) return;
    setState(() {
      panelElement = fresh;
      panelData = PanelData(
        type: fresh.type,
        variant: fresh.variant,
        icon: fresh.icon,
        color: fresh.color,
        title: title,
        params: [for (final p in params) (p, latest[p.id])],
        placed: true,
        lastUpdated: last,
        qrCode: qr,
      );
    });
  }

  bool _panelBusy = false;

  /// Дія панелі, яка не запускається вдруге, поки перша не завершилась.
  Future<void> _panelGuard(Future<void> Function() action) async {
    if (_panelBusy) return;
    _panelBusy = true;
    try {
      await action();
    } finally {
      _panelBusy = false;
    }
  }

  /// Повернення з екранів, відкритих через меню ☰ (шаблони, характеристики,
  /// генератор QR): дані могли змінитись — оновити карту, панель і шаблон,
  /// обраний для розміщення.
  Future<void> _afterExternalChange() async {
    if (!mounted) return;
    final tpl = pendingTemplate;
    if (tpl != null) {
      final fresh = (await repo.listTemplates()).where((t) => t.id == tpl.id).firstOrNull;
      if (!mounted) return;
      setState(() => pendingTemplate = fresh);
      if (fresh == null) _showWarning('Шаблон видалено', duration: const Duration(seconds: 1));
    }
    if (panelOpen && panelElement != null) {
      await _refreshPanel();
    } else {
      await _reload();
    }
  }

  Future<void> _refreshPanel() async {
    await _reload();
    final el = panelElement;
    if (el != null) await _loadPanel(el);
  }

  Future<void> _panelRename() async {
    final el = panelElement;
    if (el == null) return;
    final name = await showTextPrompt(context,
        title: "Перейменувати об'єкт", initial: panelData?.title ?? '');
    if (name == null) return;
    if (el.groupId != null) {
      await repo.renameGroup(el.groupId!, name);
    } else {
      await repo.updateElement(el.id, {'label': name});
    }
    await _refreshPanel();
  }

  Future<void> _panelIcon() async {
    final el = panelElement;
    if (el == null) return;
    final r = await pickIcon(context);
    if (r == null) return;
    // лише цей об'єкт (усі його злиті клітинки), а не вся група: інші вулики
    // й перешкоди шаблону зберігають свій вигляд
    await repo.updateElements(
        [for (final e in mergedObjectOf(el, elements)) e.id], {'icon': r.$1});
    await _refreshPanel();
  }

  Future<void> _panelColor() async {
    final el = panelElement;
    if (el == null) return;
    final r = await pickObjectColor(context);
    if (r == null) return;
    await repo.updateElements(
        [for (final e in mergedObjectOf(el, elements)) e.id], {'color': r.$1});
    await _refreshPanel();
  }

  Future<void> _panelEditParams() async {
    final el = panelElement;
    if (el == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ParametersScreen.forElement(repo: repo, element: el),
    ));
    await _refreshPanel();
  }

  Future<void> _panelFill() async {
    final el = panelElement;
    if (el == null) return;
    final entity = el.entity;
    final params = await repo.attachedParameters(entity, elType: el.type);
    if (!mounted) return;
    if (params.isEmpty) {
      _showWarning("Спершу прив'яжіть хоча б один параметр",
          duration: const Duration(milliseconds: 1200));
      return;
    }
    final latest = await repo.latestParameterValues(entity);
    if (!mounted) return;
    final stock = el.isHive ? await repo.listStockItems() : const <StockItem>[];
    if (!mounted) return;
    final result = await showFillValuesDialog(context,
        params: params, latest: latest, offerNext: el.isHive, stock: stock);
    if (result == null) return;
    final values = result.values;
    for (final e in values.entries) {
      await repo.addParameterRecord(e.key, e.value, entity);
    }
    // підгодівля: списати зі складу з назвою вулика в коментарі
    final feed = result.feed;
    if (feed != null) {
      try {
        await repo.writeOffStock(feed.itemId, feed.amount,
            reason: 'Підгодівля', comment: panelData?.title ?? el.label ?? 'Вулик');
      } on StateError catch (e) {
        if (mounted) await showInfo(context, e.message, title: 'Не списано');
      }
    }
    if (el.isHive) {
      // обхід зроблено: дата останнього обходу = сьогодні, якщо її самі
      // не змінювали в цій формі
      final visitId = await repo.baseParameterId(el.type, 'visit_start');
      if (visitId != null && !values.containsKey(visitId)) {
        await repo.markVisited(entity, elType: el.type);
      }
    }
    unawaited(ReminderService.instance.reschedule());
    await _refreshPanel();
    await _refreshOverdue();
    if (result.next && mounted) await _goNext(el);
  }

  /// «Оглянуто, змін немає»: лише дата огляду = сьогодні, без форми.
  Future<void> _panelVisited() async {
    final el = panelElement;
    if (el == null || !el.isHive) return;
    await repo.markVisited(el.entity, elType: el.type);
    unawaited(ReminderService.instance.reschedule());
    await _refreshPanel();
    await _refreshOverdue();
    _showWarning('Огляд відмічено: сьогодні', duration: const Duration(milliseconds: 1200));
  }

  /// Показати вулик на цій карті й одразу відкрити його форму.
  Future<void> _focusAndFill(MapElement el) async {
    grid.centerOnGrid(el.x + 0.5, el.y + 0.5);
    await _loadPanel(el);
    if (!mounted) return;
    setState(() => panelOpen = true);
    _revealBesidePanel(el);
    await _panelFill();
  }

  /// «Зберегти й далі»: наступний вулик за [MapScreen.next].
  Future<void> _goNext(MapElement cur) async {
    final nav = Navigator.of(context);
    switch (widget.next) {
      case NextHive.order:
        // один представник на вулик/групу: верхня-ліва клітинка
        final reps = <String, MapElement>{};
        for (final e in elements.where((e) => e.isHive)) {
          final k = ownerKeyOf(e);
          final r = reps[k];
          if (r == null || e.y > r.y || (e.y == r.y && e.x < r.x)) reps[k] = e;
        }
        final list = reps.values.toList()
          ..sort((a, b) => a.y != b.y ? b.y.compareTo(a.y) : a.x.compareTo(b.x));
        final i = list.indexWhere((e) => ownerKeyOf(e) == ownerKeyOf(cur));
        if (i < 0 || i + 1 >= list.length) {
          _showWarning('Це останній вулик на карті', duration: const Duration(milliseconds: 1500));
          return;
        }
        await _focusAndFill(list[i + 1]);
      case NextHive.qr:
        final code = await scanQrCode(context, title: 'Наступний вулик');
        if (code == null || !mounted) return;
        final found = await repo.findByQr(code);
        if (!mounted) return;
        if (found == null) {
          await showInfo(context, 'Цей QR-код ще не прив\'язаний до жодного вулика.\n\nКод: $code',
              title: 'Вулик не знайдено');
          return;
        }
        if (found.apiary.id == widget.apiary.id) {
          final el = elements.where((e) => e.id == found.element.id).firstOrNull ?? found.element;
          await _focusAndFill(el);
        } else {
          AppDrawer.openHive(nav, repo, found.apiary, found.element.id, fill: true, next: NextHive.qr);
        }
      case NextHive.overdue:
        final now = DateTime.now();
        final due = [
          for (final t in await repo.visitTargets())
            if (t.key != ownerKeyOf(cur))
              if (dueReminder(t, now: now) case final d?) (t: t, at: d.when)
        ]..sort((a, b) => a.at.compareTo(b.at));
        if (!mounted) return;
        if (due.isEmpty) {
          await showInfo(context, 'Прострочених оглядів більше немає.', title: 'Готово');
          return;
        }
        final el = await repo.getElement(due.first.t.elementId);
        final aid = el?.apiaryId;
        if (el == null || aid == null || !mounted) return;
        if (aid == widget.apiary.id) {
          await _focusAndFill(elements.where((e) => e.id == el.id).firstOrNull ?? el);
        } else {
          final a = await repo.getApiary(aid);
          if (a == null || !mounted) return;
          AppDrawer.openHive(nav, repo, a, el.id, fill: true, next: NextHive.overdue);
        }
    }
  }

  Future<void> _panelHistory(String parameterId) async {
    final el = panelElement;
    if (el == null) return;
    final p = await repo.getParameter(parameterId);
    if (p == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistoryScreen(repo: repo, parameter: p, entity: el.entity),
    ));
    await _refreshPanel();
  }

  bool _qrBusy = false;

  /// Прив'язати / замінити / відв'язати QR-код вулика з панелі.
  /// «Прив'язати наліпки підряд»: застосунок по черзі виділяє вулики без
  /// коду (зверху вниз, зліва направо), пасічник лише сканує наліпки.
  /// Закрили камеру — зупинились.
  Future<void> _bindQrInRow() async {
    if (_qrBusy || _busy) return;
    _qrBusy = true;
    var linked = 0;
    try {
      if (selectMode) _exitEdit();
      setState(() => panelOpen = false);
      while (mounted) {
        List<MapElement>? members;
        for (final o in hiveObjects(elements)) {
          if (await repo.qrForObject(o) == null) {
            members = o;
            break;
          }
        }
        if (!mounted) return;
        if (members == null) {
          await showInfo(
              context,
              linked == 0
                  ? 'У всіх вуликів цієї пасіки вже є QR-коди.'
                  : 'Прив\'язано наліпок: $linked. Тепер у всіх вуликів є QR-коди.',
              title: 'QR-коди');
          return;
        }
        final hive = members.first;
        final name = (hive.label ?? '').trim().isEmpty ? 'вулик' : hive.label!.trim();
        grid.centerOnGrid(hive.x + 0.5, hive.y + 0.5);
        setState(() => _select(hive)); // підсвітити, для якого вулика наліпка
        final scanned = await scanQrCode(context, title: 'Наліпка для: $name');
        if (scanned == null || !mounted) break;
        final code = await repo.resolveTypedQr(scanned);
        final other = await repo.findByQr(code);
        if (!mounted) return;
        if (other != null) {
          final otherName = await repo.entityLabel(other.element.entity);
          if (!mounted) return;
          final move = await showConfirm(context,
              title: 'Код уже використовується',
              text: 'Цей QR-код прив\'язаний до «$otherName» (пасіка «${other.apiary.name}»). '
                  'Перенести його на «$name»?',
              confirmText: 'Перенести',
              danger: false);
          if (!move) continue; // той самий вулик — сканувати іншу наліпку
        }
        for (final m in members.skip(1)) {
          await repo.unlinkQr(EntityRef.element(m.id));
        }
        await repo.linkQr(code, EntityRef.element(hive.id));
        linked++;
        _showWarning('Прив\'язано: $name', duration: const Duration(milliseconds: 900));
      }
    } finally {
      _qrBusy = false;
      if (mounted) {
        setState(() {
          selectedId = null;
          selectedGroupId = null;
        });
      }
    }
  }

  Future<void> _panelQr() async {
    final el = panelElement;
    if (el == null || _qrBusy) return;
    _qrBusy = true;
    try {
      // код прив'язується до КОНКРЕТНОГО вулика (навіть у групі); вулик на
      // кілька клітинок — до його першої клітинки
      final members = hiveObjectOf(el, elements);
      final target = EntityRef.element(members.first.id);
      final current = await repo.qrForObject(members);
      if (!mounted) return;
      if (current != null) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('QR-код вулика'),
            content: Text(current, style: TextStyle(color: AppColors.text)),
            actions: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                PillButton(
                    text: 'Сканувати інший',
                    bg: AppColors.accent,
                    width: double.infinity,
                    onPressed: () => Navigator.pop(ctx, 'scan')),
                const SizedBox(height: 8),
                PillButton(
                    text: 'Відв\'язати',
                    bg: AppColors.danger,
                    width: double.infinity,
                    onPressed: () => Navigator.pop(ctx, 'unlink')),
                const SizedBox(height: 8),
                PillButton(
                    text: 'Скасувати',
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    width: double.infinity,
                    onPressed: () => Navigator.pop(ctx)),
              ]),
            ],
          ),
        );
        if (action == null || !mounted) return;
        if (action == 'unlink') {
          for (final m in members) {
            await repo.unlinkQr(EntityRef.element(m.id));
          }
          if (el.groupId != null) await repo.unlinkQr(EntityRef.group(el.groupId!));
          await _refreshPanel();
          return;
        }
      }
      final scanned = await scanQrCode(context, title: 'QR-код для вулика');
      if (scanned == null || !mounted) return;
      // введений вручну номер -> справжній код наліпки з цим номером
      final code = await repo.resolveTypedQr(scanned);
      final other = await repo.findByQr(code);
      if (!mounted) return;
      // "той самий вулик" — лише клітинки ЦЬОГО вулика, не вся група
      final sameHive = other != null && members.any((m) => m.id == other.element.id);
      if (other != null && !sameHive) {
        final name = await repo.entityLabel(other.element.entity);
        if (!mounted) return;
        final move = await showConfirm(context,
            title: 'Код уже використовується',
            text: 'Цей QR-код прив\'язаний до «$name» (пасіка «${other.apiary.name}»). '
                'Перенести його на цей вулик?',
            confirmText: 'Перенести',
            danger: false);
        if (!move) return;
      }
      // старі коди інших клітинок цього вулика вимикаються
      for (final m in members.skip(1)) {
        await repo.unlinkQr(EntityRef.element(m.id));
      }
      await repo.linkQr(code, target);
      await _refreshPanel();
      _showWarning('QR-код прив\'язано', duration: const Duration(seconds: 1));
    } finally {
      _qrBusy = false;
    }
  }

  // ---------------------------------------------------------------------
  // побудова
  // ---------------------------------------------------------------------

  // Кеш сцени: злиття клітинок (mergeLayout) не залежить від зсувів під час
  // перетягування/"трусіння", тож перераховується лише коли змінився список
  // елементів або вибір — а не на кожному кадрі анімації.
  List<MapElement>? _sceneEls;
  String? _sceneSelId, _sceneSelGid;
  Set<String>? _scenePlaced;
  List<SceneCell>? _sceneBase;
  Set<String> _sceneSel = const {};

  List<SceneCell> _scene() {
    if (_sceneBase == null ||
        !identical(_sceneEls, elements) ||
        _sceneSelId != selectedId ||
        _sceneSelGid != selectedGroupId ||
        !identical(_scenePlaced, _placedGids)) {
      _sceneSel = {for (final e in selection) e.id};
      _sceneBase = _buildBaseScene(_sceneSel);
      _sceneEls = elements;
      _sceneSelId = selectedId;
      _sceneSelGid = selectedGroupId;
      _scenePlaced = _placedGids;
    }
    final base = _sceneBase!;
    final sel = _sceneSel;
    final shakeX = _shake.isAnimating ? shakeOffset(_shake.value * 0.32, 0.32) : 0.0;
    final d = _drag;
    if (d == null && shakeX == 0) return base;
    final cs = grid.cellSize;
    final off = (d == null ? Offset.zero : Offset(d.shown.$1 * cs, -d.shown.$2 * cs)) +
        Offset(shakeX, 0);
    return [for (final c in base) sel.contains(c.id) ? c.withShift(off) : c];
  }

  List<SceneCell> _buildBaseScene(Set<String> sel) {
    final items = [
      for (final e in elements)
        MergeItem<String>(
          e.id,
          e.x,
          e.y,
          mergeKeyOf(e), // зливаються лише однакові клітинки ОДНІЄЇ групи
        )
    ];
    final look = {
      for (final e in elements)
        e.id: (type: e.type, variant: e.variant, icon: e.icon, color: e.color)
    };
    return buildScene<String>(
      items: items,
      look: look,
      selected: sel,
      // червоний ободок — давно не оглядали (час огляду настав)
      outlined: {for (final e in elements) if (e.isHive && _overdue.contains(ownerKeyOf(e))) e.id},
      outlineColor: AppColors.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _warning ?? _statusText;
    final isWarn = _warning != null;
    return Scaffold(
      drawer: AppDrawer(
          repo: repo,
          currentApiary: widget.apiary,
          onReturn: _afterExternalChange,
          onBindQrRow: _bindQrInRow),
      // свайп від лівого краю конфліктував би з панорамуванням карти —
      // меню відкривається лише кнопкою
      drawerEnableOpenDragGesture: false,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          return Stack(children: [
            Positioned.fill(
              child: InfiniteGrid(
                controller: grid,
                cells: _scene(),
                blocked: _blocked,
                onPressDown: _onPressDown,
                onPressMove: _onPressMove,
                onPressUp: _onPressUp,
                onTap: _onTap,
                onLongPress: _onLongPress,
              ),
            ),
            // над обраним об'єктом у редагуванні — "Повернути"/"Видалити"
            // (як у редакторі шаблону); кнопки внизу теж лишаються
            ..._selectionButtons(box.biggest),
            // верхня панель: назва + статус
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 48,
              child: IgnorePointer(
                ignoring: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Builder(
                      builder: (ctx) => CircleIconButton(
                        icon: 'menu',
                        bg: AppColors.roundBtn,
                        iconColor: AppColors.text,
                        size: 34,
                        tooltip: 'Меню',
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // довга назва пасіки/статус більше не дають переповнення
                    // рядка: обидва стискаються з "…"
                    Expanded(
                      flex: 2,
                      child: Text(widget.apiary.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: CapsuleLabel(status,
                            bg: isWarn ? AppColors.warning : null,
                            fg: isWarn ? Colors.white : null),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const Positioned.fill(child: ScreenFrame()),
            // зум
            Positioned(
              right: 14,
              top: box.maxHeight / 2 - 46,
              child: Column(children: [
                PillButton(
                    text: '+',
                    bg: AppColors.roundBtn,
                    fg: AppColors.text,
                    width: 42,
                    height: 42,
                    radius: 21,
                    fontSize: 20,
                    onPressed: () => grid.zoomBy(4)),
                const SizedBox(height: 8),
                PillButton(
                    text: '−',
                    bg: AppColors.roundBtn,
                    fg: AppColors.text,
                    width: 42,
                    height: 42,
                    radius: 21,
                    fontSize: 20,
                    onPressed: () => grid.zoomBy(-4)),
              ]),
            ),
            // розміщення шаблону завершує те саме «Готово», що й редагування
            if (selectMode) Positioned(left: 0, right: 0, bottom: 0, child: _actionBar()),
            if (!selectMode) ..._fab(),
            // панель "Характеристики"
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: panelOpen ? Curves.easeOutCubic : Curves.easeInCubic,
              top: 52,
              bottom: 12,
              right: panelOpen ? 0 : -(CharacteristicsPanel.width + 12),
              child: panelData == null
                  ? const SizedBox(width: CharacteristicsPanel.width)
                  : CharacteristicsPanel(
                      data: panelData!,
                      onClose: () => setState(() => panelOpen = false),
                      // подвійний тап не відкриває два вікна
                      onRename: () => _panelGuard(_panelRename),
                      onIcon: () => _panelGuard(_panelIcon),
                      onColor: () => _panelGuard(_panelColor),
                      onEditParams: () => _panelGuard(_panelEditParams),
                      onFill: () => _panelGuard(_panelFill),
                      onVisited: (panelElement?.isHive ?? false)
                          ? () => _panelGuard(_panelVisited)
                          : null,
                      onHistory: (id) => _panelGuard(() => _panelHistory(id)),
                      // QR-коди — лише для вуликів
                      onQr: (panelElement?.isHive ?? false) ? _panelQr : null,
                    ),
            ),
          ]);
        }),
      ),
    );
  }

  /// Плаваючі кнопки над обраним об'єктом у режимі редагування. Під час
  /// перетягування та поки триває інша дія — ховаються.
  List<Widget> _selectionButtons(Size area) {
    if (!selectMode || _drag != null || _busy) return const [];
    final cellsSel = [for (final e in selection) (e.x, e.y)];
    if (cellsSel.isEmpty) return const [];
    return [
      AnimatedBuilder(
        animation: grid,
        builder: (context, _) {
          final r = cellsScreenBounds(grid, cellsSel);
          if (r == null) return const SizedBox.shrink();
          const bs = 36.0;
          const gap = kHintGap + kHintSize + 8;
          var top = r.top - gap - bs;
          if (top < 52) top = r.bottom + gap; // згори не вміщається — під об'єктом
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
                  onPressed: _onRotate),
              const SizedBox(width: 6),
              CircleIconButton(
                  icon: 'trash',
                  bg: AppColors.danger,
                  size: bs,
                  tooltip: 'Видалити',
                  onPressed: _onDelete),
            ]),
          );
        },
      ),
    ];
  }

  /// Кнопка зліва внизу (поза редагуванням): «Редагувати» — режим
  /// редагування й одразу вибір шаблону, щоб додати вулик на карту.
  /// Список шаблонів (створення, зміна) — лише в меню ☰ → «Шаблони».
  List<Widget> _fab() => [
        Positioned(
          left: 16,
          bottom: 18,
          child: PillButton(
            text: 'Редагувати',
            bg: AppColors.accent,
            width: 150,
            height: 50,
            radius: 25,
            fontSize: 16,
            onPressed: _busy ? null : _editAndAdd,
          ),
        ),
      ];

  /// «Редагувати»: увійти в редагування й одразу запропонувати шаблон.
  /// Якщо шаблон не обрали — лишаємось у редагуванні (перемістити,
  /// повернути, видалити; «Готово» — вийти).
  Future<void> _editAndAdd() async {
    _enterEdit();
    await _onAddObject();
  }

  Widget _actionBar() {
    final enabled = hasSelection && !_busy && _drag == null;
    return Container(
      height: 70,
      color: AppColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleIconButton(
              icon: 'plus_circle',
              bg: AppColors.addObject,
              tooltip: "Додати об'єкт",
              onPressed: _onAddObject),
          const SizedBox(width: 16),
          CircleIconButton(
              icon: 'back_arrow',
              bg: AppColors.darkBtn,
              tooltip: 'Крок назад',
              onPressed: (undoStack.isEmpty || _busy || _drag != null) ? null : _onUndo),
          const SizedBox(width: 16),
          CircleIconButton(
              icon: 'trash',
              bg: AppColors.danger,
              tooltip: 'Видалити',
              onPressed: enabled ? _onDelete : null),
          const SizedBox(width: 16),
          CircleIconButton(
              icon: 'check',
              bg: AppColors.accent,
              tooltip: 'Готово',
              // поки триває дія (розміщення, видалення…), вийти не можна: вона
              // завершилась би вже поза редагуванням
              onPressed: (_busy || _drag != null) ? null : _exitEdit),
        ]),
      ),
    );
  }
}
