import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/cell_value.dart' show parseCellKey;
import '../logic/geometry.dart';
import '../logic/hive_objects.dart';
import '../logic/merge_layout.dart';
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
import 'templates_screen.dart';

/// Головний екран: карта пасіки (порт map_screen.py).
///
///  * FAB "+" — меню "Редагувати" / "Шаблони".
///  * "Редагувати": натиснути на об'єкт — обрати його (разом з усією групою)
///    і тим самим дотиком перетягувати; знизу — панель дій: додати об'єкт
///    із шаблону, повернути, перейменувати, крок назад, видалити, готово.
///  * Поза режимом редагування тап по об'єкту відкриває панель
///    "Характеристики".
class MapScreen extends StatefulWidget {
  final Repository repo;
  final Apiary apiary;

  /// Одразу показати цей об'єкт і відкрити його панель (після сканування
  /// QR-коду вулика).
  final String? focusElementId;
  const MapScreen({super.key, required this.repo, required this.apiary, this.focusElementId});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _Undo {
  final List<MapElement>? restore;
  // ВИПРАВЛЕНО: знімок прив'язок параметрів на момент видалення — без
  // нього "крок назад" після видалення міг повернути об'єкт без
  // призначених йому (не базових) параметрів.
  final List<Map<String, Object?>>? paramRows;
  final String? deleteGroupId;
  const _Undo.restore(this.restore, {this.paramRows}) : deleteGroupId = null;
  const _Undo.deleteGroup(this.deleteGroupId)
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

  bool menuOpen = false;
  bool selectMode = false;
  ApiaryTemplate? pendingTemplate;
  String? selectedId;
  String? selectedGroupId;
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
    if (!mounted) return;
    setState(() {
      elements = els;
      _blocked = false;
    });
  }

  // ---------------------------------------------------------------------
  // вибір
  // ---------------------------------------------------------------------

  List<MapElement> get selection {
    if (selectedGroupId != null) {
      return elements.where((e) => e.groupId == selectedGroupId).toList();
    }
    if (selectedId != null) return elements.where((e) => e.id == selectedId).toList();
    return const [];
  }

  bool get hasSelection => selectedGroupId != null || selectedId != null;

  MapElement? _elementAt((int, int) cell) {
    for (final e in elements) {
      if (e.x == cell.$1 && e.y == cell.$2) return e;
    }
    return null;
  }

  void _select(MapElement el) {
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
    if (_drag == null) return;
    if (_busy) {
      setState(() {
        _drag = null;
        _blocked = false;
      });
      return;
    }
    final (target, _) = _dragTarget(delta);
    final releasedBlocked = _blocked;
    _drag = null;
    setState(() => _busy = true);
    try {
      final (dx, dy) = target;
      if (dx != 0 || dy != 0) {
        if (selectedGroupId != null) {
          final members = selection;
          _pushUndo(_Undo.restore(members));
          await repo.moveGroup(selectedGroupId!, dx, dy);
        } else if (selectedId != null) {
          final el = selection.firstOrNull;
          if (el != null) {
            _pushUndo(_Undo.restore([el]));
            await repo.moveElement(el.id, el.x + dx, el.y + dy);
          }
        }
      }
      await _reload();
      if (releasedBlocked) {
        _showWarning("Тут уже є інший об'єкт", duration: const Duration(seconds: 1));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
      final label = await repo.nextGroupLabel(widget.apiary.id, tpl.name);
      final gid = await repo.addGroup(widget.apiary.id, tpl.cells, gx, gy, groupLabel: label);
      _pushUndo(_Undo.deleteGroup(gid));
      selectedId = null;
      selectedGroupId = gid; // щойно поставлений — обраний
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
      } else if (u.deleteGroupId != null) {
        await repo.deleteGroup(u.deleteGroupId!);
        if (selectedGroupId == u.deleteGroupId) selectedGroupId = null;
      }
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
      menuOpen = false;
      selectMode = true;
      selectedId = null;
      selectedGroupId = null;
    });
  }

  void _exitEdit() {
    setState(() {
      selectMode = false;
      pendingTemplate = null;
      selectedId = null;
      selectedGroupId = null;
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
        await repo.rotateGroup(selectedGroupId!);
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
    final ok = await showConfirm(context,
        text: isGroup ? "Точно видалити цю групу об'єктів?" : 'Точно видалити цей елемент?');
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      // ВИПРАВЛЕНО: знімок прив'язок параметрів ПЕРЕД видаленням, щоб
      // "крок назад" міг відновити їх, навіть якщо фонова синхронізація
      // встигне остаточно прибрати їх із бази до натискання undo.
      final paramRows = await repo.attachedParameterRows(sel.first.entity);
      _pushUndo(_Undo.restore(sel, paramRows: paramRows));
      if (isGroup) {
        await repo.deleteGroup(selectedGroupId!);
      } else {
        await repo.deleteElement(sel.first.id);
      }
      selectedId = null;
      selectedGroupId = null;
      await _reload();
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
    if (panelOpen && panelElement != null && panelElement!.entity == el.entity) {
      setState(() => panelOpen = false);
      return;
    }
    await _loadPanel(el);
    if (mounted) setState(() => panelOpen = true);
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
    if (el.groupId != null) {
      await repo.setGroupIcon(el.groupId!, r.$1);
    } else {
      await repo.updateElement(el.id, {'icon': r.$1});
    }
    await _refreshPanel();
  }

  Future<void> _panelColor() async {
    final el = panelElement;
    if (el == null) return;
    final r = await pickObjectColor(context);
    if (r == null) return;
    if (el.groupId != null) {
      await repo.setGroupColor(el.groupId!, r.$1);
    } else {
      await repo.updateElement(el.id, {'color': r.$1});
    }
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
    final values = await showFillValuesDialog(context, params: params, latest: latest);
    if (values == null) return;
    for (final e in values.entries) {
      await repo.addParameterRecord(e.key, e.value, entity);
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
      final code = await scanQrCode(context, title: 'QR-код для вулика');
      if (code == null || !mounted) return;
      final other = await repo.findByQr(code);
      if (!mounted) return;
      final sameHive = other != null &&
          (other.element.id == el.id ||
              (el.groupId != null && other.element.groupId == el.groupId));
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

  Future<void> _openTemplates() async {
    setState(() => menuOpen = false);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemplatesScreen(repo: repo),
    ));
    await _reload();
  }

  // ---------------------------------------------------------------------
  // побудова
  // ---------------------------------------------------------------------

  // Кеш сцени: злиття клітинок (mergeLayout) не залежить від зсувів під час
  // перетягування/"трусіння", тож перераховується лише коли змінився список
  // елементів або вибір — а не на кожному кадрі анімації.
  List<MapElement>? _sceneEls;
  String? _sceneSelId, _sceneSelGid;
  List<SceneCell>? _sceneBase;
  Set<String> _sceneSel = const {};

  List<SceneCell> _scene() {
    if (_sceneBase == null ||
        !identical(_sceneEls, elements) ||
        _sceneSelId != selectedId ||
        _sceneSelGid != selectedGroupId) {
      _sceneSel = {for (final e in selection) e.id};
      _sceneBase = _buildBaseScene(_sceneSel);
      _sceneEls = elements;
      _sceneSelId = selectedId;
      _sceneSelGid = selectedGroupId;
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
    return buildScene<String>(items: items, look: look, selected: sel);
  }

  @override
  Widget build(BuildContext context) {
    final status = _warning ?? _statusText;
    final isWarn = _warning != null;
    final placing = selectMode && pendingTemplate != null;

    return Scaffold(
      drawer: AppDrawer(repo: repo, currentApiary: widget.apiary),
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
              ),
            ),
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
            // завершити розміщення шаблону
            if (placing)
              Positioned(
                left: 14,
                top: box.maxHeight / 2 - 23,
                child: CircleIconButton(
                  icon: 'close',
                  bg: AppColors.danger,
                  tooltip: 'Завершити розміщення',
                  onPressed: () => setState(() => pendingTemplate = null),
                ),
              ),
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
                      onRename: _panelRename,
                      onIcon: _panelIcon,
                      onColor: _panelColor,
                      onEditParams: _panelEditParams,
                      onFill: _panelFill,
                      onHistory: _panelHistory,
                      onQr: _panelQr,
                    ),
            ),
          ]);
        }),
      ),
    );
  }

  List<Widget> _fab() => [
        if (menuOpen) ...[
          Positioned(
            left: 16,
            bottom: 128,
            child: PillButton(
                text: 'Редагувати',
                bg: AppColors.accent,
                width: 150,
                height: 42,
                radius: 21,
                onPressed: _enterEdit),
          ),
          Positioned(
            left: 16,
            bottom: 78,
            child: PillButton(
                text: 'Шаблони',
                bg: AppColors.create,
                width: 150,
                height: 42,
                radius: 21,
                onPressed: _openTemplates),
          ),
        ],
        Positioned(
          left: 16,
          bottom: 18,
          child: PillButton(
            text: menuOpen ? '×' : '+',
            bg: AppColors.create,
            width: 54,
            height: 54,
            radius: 27,
            fontSize: 26,
            onPressed: () => setState(() => menuOpen = !menuOpen),
          ),
        ),
      ];

  Widget _actionBar() {
    final enabled = hasSelection && !_busy;
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
              icon: 'rotate',
              bg: AppColors.darkBtn,
              tooltip: 'Повернути',
              onPressed: enabled ? _onRotate : null),
          const SizedBox(width: 16),
          CircleIconButton(
              icon: 'back_arrow',
              bg: AppColors.darkBtn,
              tooltip: 'Крок назад',
              onPressed: (undoStack.isEmpty || _busy) ? null : _onUndo),
          const SizedBox(width: 16),
          CircleIconButton(
              icon: 'trash',
              bg: AppColors.danger,
              tooltip: 'Видалити',
              onPressed: enabled ? _onDelete : null),
          const SizedBox(width: 16),
          CircleIconButton(
              icon: 'check', bg: AppColors.accent, tooltip: 'Готово', onPressed: _exitEdit),
        ]),
      ),
    );
  }
}
