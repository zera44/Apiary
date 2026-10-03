import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
import '../ui/date_picker.dart' show formatDdMmYyyy;
import '../ui/first_hints.dart';
import '../ui/guide_bubble.dart';
import '../ui/icons.dart';
import 'settings_screen.dart';
import '../ui/fill_values_dialog.dart';
import '../ui/grid_view.dart';
import '../ui/mode_toggle.dart';
import '../ui/pill_choice.dart';
import '../ui/theme.dart';
import 'history_screen.dart';
import 'parameters_screen.dart';
import 'qr_scan_screen.dart';
import 'template_editor_screen.dart';
import 'templates_screen.dart' show TemplateTile;

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

  /// Разом із [focusElementId]: одразу відкрити форму «Оглянути» цього
  /// вулика (після сканування QR чи натискання на нагадування — людина
  /// прийшла саме заповнити).
  final bool openFill;

  /// Відсканований код, якого ще немає в базі: на карті пасічник торкається
  /// вулика — код прив'язується, і одразу відкривається огляд.
  final String? bindCode;

  /// Куди веде «Зберегти й далі».
  final NextHive next;

  /// Урок «Базові поняття» (пісочниця): пасічник веде крок за кроком,
  /// звичайні підказки першого запуску не показуються.
  final bool tutorial;

  /// Кінець уроку: пасіка [apiaryId] з пісочниці переноситься у справжні.
  /// [magic] — урок пройшов повний огляд меню («червона пігулка»), інакше
  /// «синя пігулка» (меню ще покаже справжня карта).
  final Future<void> Function(bool magic, String apiaryId)? onLessonDone;

  /// Після «Я сам собі маг пасіки»: на справжній карті пасічник востаннє
  /// просить відкрити меню навігації (кнопка в медовому ободку).
  final bool menuTour;
  const MapScreen(
      {super.key,
      required this.repo,
      required this.apiary,
      this.focusElementId,
      this.openFill = false,
      this.bindCode,
      this.next = NextHive.order,
      this.tutorial = false,
      this.menuTour = false,
      this.onLessonDone});

  /// Урок: на карті ще немає вуликів.
  static final tutorialNoHives = <InlineSpan>[
    const TextSpan(text: 'Щось у тебе, друже, і вуликів то нема. Додай нові, увімкнувши режим '),
    GuideBubble.highlight('«Редагування»'),
    const TextSpan(text: ' унизу ліворуч'),
  ];
  @override
  State<MapScreen> createState() => _MapScreenState();
}


/// Урок: панель вулика закінчується над пасічником і його хмаркою.
const kLessonPanelBottom = 290.0;

/// Кроки уроку «Базові поняття» на карті.
enum _Lesson { place, congrats, openHive, inspect, magic, menu, drawer }

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

  // ---- урок «Базові поняття» ----
  _Lesson _lesson = _Lesson.place;
  bool _lessonPlaced = false; // у цьому редагуванні вже поставили шаблон
  bool _fillSaved = false; // форму «Заповнити параметри» збережено
  bool _menuHint = false; // меню відкрито після уроку: одна репліка пасічника
  late bool _tourMenu = widget.menuTour; // пасічник просить відкрити меню
  bool _lessonFormOpen = false; // відкрита форма огляду (у ній свій пасічник)
  (int, int)? _lessonTarget; // куди перетягнути щойно поставлений вулик
  bool _lessonMoved = false; // перетягнули на підсвічену клітинку

  // ключі кнопок, які урок дозволяє натиснути (решта — під «завісою»)
  final _gateKey = GlobalKey();
  final _backKey = GlobalKey();
  final _editKey = GlobalKey();
  final _fillKey = GlobalKey();
  final _actionBarKey = GlobalKey();
  final _zoomKey = GlobalKey();
  final _menuKey = GlobalKey();
  final _panelBoxKey = GlobalKey();
  bool _inspectRead = false; // урок: перша хмарка про панель прочитана
  final _topKey = GlobalKey();

  /// Урок: що зараз можна натиснути (у координатах карти).
  bool _lessonAllows(Offset p) {
    final ref = _gateKey.currentContext?.findRenderObject();
    if (ref is! RenderBox) return true;
    bool inKey(GlobalKey k) => rectOfKey(k, ref)?.contains(p) ?? false;
    bool onHive() {
      final el = elements.where((e) => e.isHive).firstOrNull;
      if (el == null) return false;
      return mergedObjectOf(el, elements).any((c) => grid.cellRect(c.x, c.y).contains(p));
    }

    if (inKey(_backKey)) return true; // вийти з уроку можна завжди
    if (selectMode) {
      if (pendingTemplate == null) return false; // вибір шаблону — у вікні
      if (!_lessonPlaced) {
        // будь-де на карті, але не кнопки
        return !inKey(_actionBarKey) && !inKey(_editKey) && !inKey(_zoomKey) && !inKey(_topKey);
      }
      if (!_lessonMoved) return onHive(); // лише тягнути свій вулик
      return inKey(_editKey); // підтвердити — перемкнути в робочий режим
    }
    switch (_lesson) {
      case _Lesson.place:
        return inKey(_editKey);
      case _Lesson.openHive:
        return !panelOpen && onHive();
      case _Lesson.inspect:
        // панель можна гортати вниз до «Оглянути»; решта кнопок у ній вимкнені
        // спершу хмарка пасічника, але панель гортати можна й тоді
        if (!_inspectRead) return panelOpen && inKey(_panelBoxKey);
        return inKey(_fillKey) || (panelOpen && inKey(_panelBoxKey));
      case _Lesson.menu:
        return inKey(_menuKey); // лише кнопка меню навігації
      case _Lesson.congrats:
      case _Lesson.magic:
      case _Lesson.drawer:
        return false; // відповідь — у хмарці пасічника
    }
  }

  /// Урок: підсвічена клітинка, куди перетягнути вулик.
  List<Widget> _lessonTargetCell() {
    final t = _lessonTarget;
    if (!widget.tutorial || !selectMode || !_lessonPlaced || _lessonMoved || t == null) {
      return const [];
    }
    return [
      AnimatedBuilder(
        animation: grid,
        builder: (context, _) {
          final r = grid.cellRect(t.$1, t.$2).inflate(2);
          return Positioned.fromRect(
            key: const ValueKey('lesson-target'),
            rect: r,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.create.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.create, width: 3),
                  boxShadow: [
                    BoxShadow(color: AppColors.create.withValues(alpha: 0.6), blurRadius: 10)
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  }
  /// Урок «Натисни на свій вулик»: медове сяйво навколо вулика.
  List<Widget> _lessonHiveGlow() {
    if (!widget.tutorial || selectMode || panelOpen || _lesson != _Lesson.openHive) {
      return const [];
    }
    final hive = elements.where((e) => e.isHive).firstOrNull;
    if (hive == null) return const [];
    final cells = mergedObjectOf(hive, elements);
    return [
      for (final c in cells)
        AnimatedBuilder(
          animation: grid,
          builder: (context, _) => Positioned.fromRect(
            key: ValueKey('lesson-hive-glow-${c.id}'),
            rect: grid.cellRect(c.x, c.y).inflate(3),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.create, width: 3),
                  boxShadow: [
                    BoxShadow(color: AppColors.create.withValues(alpha: 0.7), blurRadius: 14)
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  String _lessonHive = 'Вулик';

  /// Підтвердити розміщення: перемикач у медовому ободку.
  bool get _lessonConfirm => widget.tutorial && selectMode && _lessonPlaced && _lessonMoved;

  /// Огляд: «Оглянути» на панелі в медовому ободку.
  bool get _lessonInspect => widget.tutorial && _lesson == _Lesson.inspect && panelOpen;

  /// Навчання необов'язкове: «завершити навчання» під хмаркою — на головний.
  void _finishLesson() => Navigator.of(context).popUntil((r) => r.isFirst);

  /// Підказка пасічника для поточного кроку уроку.
  List<Widget> _lessonOverlay() {
    if (!widget.tutorial) return const [];
    // поки відкрите вікно «Оберіть шаблон» чи форма огляду — пасічник у ньому,
    // на тому ж місці (а не двоє одночасно)
    if (selectMode && pendingTemplate == null) return const [];
    if (_lessonFormOpen) return const [];
    // увесь урок пасічник спирається на перемикач режимів
    const pose = LessonPose.leaning;
    final msg = _lessonMessage();
    const up = 0.0;
    // на кроці «Оглянути» (панель вулика) таблички немає; інакше вона висить
    // під кнопкою «Продовжити» (без кнопки - без таблички)
    final VoidCallback? finish = _lesson == _Lesson.inspect ? null : _finishLesson;
    if (msg == null) {
      return lessonScene(pose: pose, bottomInset: selectMode ? 0 : up, onFinish: finish);
    }
    final (text, onTap) = msg;
    if (_lesson == _Lesson.magic && !selectMode) {
      // фінал уроку: дві відповіді під хмаркою
      final done = widget.onLessonDone;
      return lessonScene(
        pose: pose,
        bottomInset: selectMode ? 0 : up,
        text: text,
        below: Row(children: [
          Expanded(
            child: PillChoice(
              text: 'Синя',
              color: kPillBlue,
              onPressed: done == null ? null : () => done(false, widget.apiary.id),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PillChoice(
              text: 'Червона',
              color: kPillRed,
              onPressed: () => setState(() => _lesson = _Lesson.menu),
            ),
          ),
        ]),
      );
    }
    return lessonScene(
      pose: pose,
      bottomInset: selectMode ? 0 : up,
      onFinish: finish,
      text: text,
      onTap: onTap,
      below: onTap == null
          ? null
          : PillButton(
              text: 'Продовжити',
              bg: AppColors.accent,
              height: 38,
              fontSize: 13,
              width: double.infinity,
              onPressed: onTap),
    );
  }

  /// Що каже пасічник на поточному кроці уроку (і що робить тап по хмарці),
  /// або null — мовчить.
  (List<InlineSpan>, VoidCallback?)? _lessonMessage() {
    final hasHive = elements.any((e) => e.isHive);
    if (selectMode) {
      if (!_lessonPlaced) {
        return (const [TextSpan(text: 'Натисни на карту в будь-якому місці')], null);
      }
      if (!_lessonMoved) {
        return (
          const [
            TextSpan(
                text: 'Щось ти геть не туди поставив. Перемісти перетягуванням на сусідню клітинку')
          ],
          null
        );
      }
      return (
        [
          const TextSpan(text: 'Підтверди вибір - перемкни в '),
          GuideBubble.highlight('«Робочий режим»'),
        ],
        null
      );
    }
    switch (_lesson) {
      case _Lesson.place:
        return hasHive ? null : (MapScreen.tutorialNoHives, null);
      case _Lesson.congrats:
        return (
          const [TextSpan(text: 'З легким стартом, друже!')],
          // кінець уроку (після огляду меню): справжня карта зі своїм вуликом
          () => widget.onLessonDone?.call(true, widget.apiary.id)
        );
      case _Lesson.openHive:
        if (panelOpen) return null;
        return (
          [
            const TextSpan(text: 'Не час відпочивати, натисни на '),
            GuideBubble.highlight('«$_lessonHive»'),
          ],
          null
        );
      case _Lesson.menu:
        return (
          [
            const TextSpan(text: 'Розкажу коротко, що ми маємо. '),
            GuideBubble.highlight('Відкрий меню навігації'),
          ],
          null
        );
      case _Lesson.drawer:
        return null;
      case _Lesson.magic:
        return (
          [
            ...pillChoiceSpans('Вулик додав, обхід зробив. '),
          ],
          null
        );
      case _Lesson.inspect:
        if (!panelOpen) return null;
        if (!_inspectRead) {
          return (
            const [TextSpan(text: 'Це короткі замітки про твій вулик.')],
            () => setState(() => _inspectRead = true)
          );
        }
        return (
          [
            const TextSpan(text: 'Прокрути донизу й '),
            GuideBubble.task('проведи огляд вулика'),
          ],
          null
        );
    }
  }

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
    _bindCode = widget.bindCode;
    if (_bindCode != null) _warning = 'Торкніться вулика, до якого прив\'язати код';
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
    if (mounted && !widget.tutorial) await Hints.show(context, repo, Hints.map);
    final focusId = widget.focusElementId;
    if (focusId != null && mounted) {
      final el = elements.where((e) => e.id == focusId).firstOrNull;
      if (el != null) {
        grid.centerOnGrid(el.x + 0.5, el.y + 0.5);
        if (widget.openFill && el.isHive && mounted) {
          await _fillThenPanel(el);
        } else {
          await _onInfoRequest(el);
        }
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
    if (!repo.db.isOpen) return; // урок: пісочницю вже закрили
    final els = await repo.listElements(widget.apiary.id);
    final overdue = await _loadOverdue();
    if (!mounted) return;
    setState(() {
      elements = els;
      _overdue = overdue;
      _blocked = false;
      // урок: вулик уже на підсвіченій клітинці
      final t = _lessonTarget;
      if (widget.tutorial && t != null && !_lessonMoved &&
          els.any((e) => e.isHive && e.x == t.$1 && e.y == t.$2)) {
        _lessonMoved = true;
      }
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
    // урок: довгий дотик вивів би з кроку й заблокував завісу
    if (widget.tutorial || _busy || _elementAt(p.cell) == null) return false;
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
    setState(() {
      _select(match);
      panelOpen = false; // панель властивостей - лише для щойно обраного
    });
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
        // урок: вулик перетягнули на підсвічену клітинку
        final t = _lessonTarget;
        if (widget.tutorial && t != null && !_lessonMoved &&
            els.any((e) => e.isHive && e.x == t.$1 && e.y == t.$2)) {
          _lessonMoved = true;
        }
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
      final hit = _elementAt(p.cell);
      if (_bindCode != null) {
        if (hit != null && hit.isHive) await _bindScannedTo(hit);
        return; // чекаємо вулик для коду
      }
      await _onInfoRequest(hit);
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
      if (widget.tutorial) {
        _lessonPlaced = true;
        // урок: сусідня вільна клітинка — сюди перетягнути
        final occupied = {for (final e in elements) (e.x, e.y)};
        _lessonTarget = [(gx + 1, gy), (gx - 1, gy), (gx, gy + 1), (gx, gy - 1)]
            .firstWhere((c) => !occupied.contains(c), orElse: () => (gx + 2, gy));
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // попередження / статус
  // ---------------------------------------------------------------------

  void _showWarning(String text, {Duration? duration}) {
    if (!mounted) return;
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
      return 'Тапай - ставити «${pendingTemplate!.name}», тягни - перемістити';
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
      // урок: крок повертається разом із дією (поставили/перемістили заново)
      if (widget.tutorial && mounted) {
        final t = _lessonTarget;
        setState(() {
          if (!elements.any((e) => e.isHive)) {
            _lessonPlaced = false;
            _lessonMoved = false;
            _lessonTarget = null;
          } else if (t != null && !elements.any((e) => e.isHive && e.x == t.$1 && e.y == t.$2)) {
            _lessonMoved = false;
          }
        });
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
      _lessonPlaced = false;
      _lessonMoved = false;
      _lessonTarget = null;
      panelOpen = false;
      selectMode = true;
      selectedId = null;
      selectedGroupId = null;
      _placedGids = const {};
    });
  }

  void _exitEdit() {
    // урок: вулик поставили й підтвердили — далі відкрити його
    if (widget.tutorial && _lesson == _Lesson.place && elements.any((e) => e.isHive)) {
      final hive = elements.firstWhere((e) => e.isHive);
      _lessonHive = (hive.label?.trim().isNotEmpty ?? false) ? hive.label!.trim() : 'Вулик';
      _lesson = _Lesson.openHive;
    }
    // «Відмінити» під видаленням діє лише в режимі редагування
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      selectMode = false;
      panelOpen = false;
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

  /// Урок: під вікном вибору шаблону — пасічник: «Я трохи про тебе
  /// потурбувався. Створив «Вулик» і «Лежак». Обери «Вулик»» (назви
  /// шаблонів — жирним медовим).
  Widget _withTutorialGuide(List<ApiaryTemplate> templates, Widget dialog) {
    if (!widget.tutorial || templates.isEmpty) return dialog;
    final names = [for (final t in templates) t.name];
    final pick = names.contains('Вулик') ? 'Вулик' : names.first;
    // радимо перший — його й називаємо першим
    names
      ..remove(pick)
      ..insert(0, pick);
    final spans = <InlineSpan>[
      const TextSpan(text: 'Я трохи про тебе потурбувався. Створив '),
      for (var i = 0; i < names.length; i++) ...[
        if (i > 0) TextSpan(text: i == names.length - 1 ? ' і ' : ', '),
        GuideBubble.highlight('«${names[i]}»'),
      ],
      const TextSpan(text: '. Обери '),
      GuideBubble.highlight('«$pick»'),
    ];
    return Stack(children: [
      // вікно вибору — вище, щоб пасічник унизу його не закривав
      Positioned.fill(child: Padding(padding: const EdgeInsets.only(bottom: 300), child: dialog)),
      // те саме місце, що й на карті: і карта, і вікно (showDialog) — у SafeArea,
      // тож системний відступ знизу вже врахований
      ...lessonScene(
          pose: LessonPose.leaning, text: spans, toggleEditing: true, onFinish: _finishLesson),
    ]);
  }

  Future<void> _onAddObject() async {
    final templates = await repo.listTemplates();
    if (!mounted) return;
    // урок: вибрати можна лише запропонований шаблон, закрити вікно — ні
    final lessonPick = widget.tutorial && templates.isNotEmpty
        ? (templates.where((t) => t.name == 'Вулик').firstOrNull ?? templates.first)
        : null;
    final picked = await showDialog<ApiaryTemplate>(
      context: context,
      barrierDismissible: lessonPick == null,
      builder: (ctx) => PopScope(
          canPop: lessonPick == null,
          child: _withTutorialGuide(
          templates,
          AlertDialog(
        // ширше за звичайне вікно — щоб плитки шаблонів стали по 3 в ряд
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Оберіть шаблон'),
        content: SizedBox(
          width: 274,
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
              // плитки — ті самі, що в списку «Шаблони» (мініатюра й розмір)
              // (Wrap, а не GridView: вікно міряє вміст, а сітка цього не вміє)
              : SingleChildScrollView(
                  // по 3 в ряд (вікно ширше за звичайне — див. insetPadding)
                  child: Wrap(spacing: 8, runSpacing: 10, children: [
                    for (final t in templates)
                      SizedBox(
                        width: 86,
                        height: 106,
                        // урок: потрібну плитку обведено медовим
                        child: HoneyRing(
                          on: lessonPick != null && t.id == lessonPick.id,
                          radius: 20,
                          child: TemplateTile(
                            template: t,
                            onTap: lessonPick != null && t.id != lessonPick.id
                                ? null
                                : () => Navigator.pop(ctx, t),
                          ),
                        ),
                      ),
                  ]),
                ),
        ),
      ))),
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
    // без «Точно видалити?»: одразу, а внизу «Відмінити»
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
        // з дією SnackBar інакше висить, доки не натиснуть — а видалення має
        // завершитись само через 5 с
        persist: false,
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

  /// Режим редагування: панель властивостей (назва, значок, колір, параметри)
  /// обраного об'єкта.
  Future<void> _openProperties() async {
    final el = selection.firstOrNull;
    if (el == null || _busy) return;
    await _loadPanel(el);
    if (!mounted) return;
    setState(() => panelOpen = true);
  }

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
    setState(() {
      panelOpen = true;
      // урок: відкрили свій вулик — тепер огляд
      if (_lesson == _Lesson.openHive && el.isHive) {
        _lesson = _Lesson.inspect;
        _inspectRead = false;
      }
    });
    _revealBesidePanel(el);
    if (!widget.tutorial) await Hints.show(context, repo, Hints.panel);
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
    final qrNum = qr == null ? null : await repo.qrNumberOf(qr);
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
        qrNumber: qrNum,
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
    final r = await pickIcon(context, elType: el.type); // лише іконки свого типу
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
    _fillSaved = false;
    final panelWasOpen = panelOpen; // з сповіщення панель відкриється лише після «Зберегти»
    final first0 = await _fillPage(el);
    if (first0 == null || !mounted) return;
    if (first0.params.isEmpty) {
      _showWarning("Спершу прив'яжіть хоча б один параметр",
          duration: const Duration(milliseconds: 1200));
      return;
    }
    if (!widget.tutorial) await Hints.show(context, repo, Hints.fill);
    if (!mounted) return;
    var cur = el;
    ({Apiary apiary, String elementId})? away; // наступний — на іншій пасіці
    // урок: у формі пасічник і ведмежа ведуть по комірках
    FillLesson? lesson;
    if (widget.tutorial && _lesson == _Lesson.inspect && el.isHive) {
      final period = await repo.baseParameterId(el.type, 'visit_period');
      final mark = await repo.baseParameterId(el.type, 'queen_mark');
      if (period != null && mark != null) {
        lesson = FillLesson(periodParamId: period, colorParamId: mark);
      }
      if (!mounted) return;
    }
    // періодичність обходу — налаштування вулика, не показник огляду: у формі
    // її немає (змінюють тапом по значенню на панелі); урок її ще заповнює
    final periodId = lesson == null ? await repo.baseParameterId(el.type, 'visit_period') : null;
    FillPage formPage(FillPage pg) => periodId == null
        ? pg
        : FillPage(
            params: [for (final p in pg.params) if (p.id != periodId) p],
            latest: pg.latest,
            stock: pg.stock,
            title: pg.title);
    final first = formPage(first0);
    final skipped = <String>{}; // «Пропустити» в цьому обході — не пропонувати знову
    if (!mounted) return;
    if (lesson != null) setState(() => _lessonFormOpen = true);
    final result = await showFillValuesDialog(
      context,
      params: first.params,
      latest: first.latest,
      stock: first.stock,
      title: first.title,
      offerNext: el.isHive,
      lesson: lesson,
      // «Зберегти» / «Змін немає» / «Пропустити»: записати своє, показати
      // наступний вулик на карті й підставити його дані в ту саму форму
      // (вікно не закривається); далі нікого — огляд закривається
      onNext: (r) async {
        switch (r.action) {
          case FillAction.skip:
            skipped.add(ownerKeyOf(cur));
          case FillAction.noChange:
            await _saveFill(cur, const FillResult({})); // лише дата огляду
            _fillSaved = true;
          case FillAction.save:
            await _saveFill(cur, r);
            _fillSaved = true;
        }
        final n = await _nextTarget(cur, skipped: skipped);
        if (n == null || !mounted) return null;
        final here = n.here;
        if (here == null) {
          away = n.away;
          return null;
        }
        cur = here;
        await _showOnMap(here, openPanel: panelWasOpen);
        final pg = await _fillPage(here);
        return pg == null ? null : formPage(pg);
      },
    );
    if (lesson != null && mounted) setState(() => _lessonFormOpen = false);
    if (result != null) {
      await _saveFill(cur, result);
      _fillSaved = true;
    }
    // урок: огляд зроблено — одразу далі, до меню навігації
    if (result != null && lesson != null && mounted) {
      setState(() {
        _lesson = _Lesson.menu;
        panelOpen = false;
      });
    }
    final a = away;
    if (a != null && mounted) {
      AppDrawer.openHive(Navigator.of(context), repo, a.apiary, a.elementId,
          fill: true, next: widget.next);
    }
  }

  /// Дані форми для вулика: параметри, останні значення, склад, назва.
  Future<FillPage?> _fillPage(MapElement el) async {
    final entity = el.entity;
    final params = await repo.attachedParameters(entity, elType: el.type);
    final latest = await repo.latestParameterValues(entity);
    final stock = el.isHive ? await repo.listStockItems() : const <StockItem>[];
    final title = panelElement?.id == el.id ? panelData?.title : null;
    return FillPage(
        params: params, latest: latest, stock: stock, title: title ?? el.label ?? 'Вулик');
  }

  /// Записати результат форми для вулика [el].
  Future<void> _saveFill(MapElement el, FillResult result) async {
    final entity = el.entity;
    final values = result.values;
    for (final e in values.entries) {
      await repo.addParameterRecord(e.key, e.value, entity);
    }
    // підгодівля: списати зі складу з назвою вулика в коментарі
    final feed = result.feed;
    if (feed != null) {
      try {
        await repo.writeOffStock(feed.itemId, feed.amount,
            reason: 'Підгодівля',
            comment: (panelElement?.id == el.id ? panelData?.title : null) ?? el.label ?? 'Вулик');
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

  /// Показати вулик на цій карті: центр, панель поруч (без форми).
  Future<void> _showOnMap(MapElement el, {bool openPanel = true}) async {
    grid.centerOnGrid(el.x + 0.5, el.y + 0.5);
    await _loadPanel(el);
    if (!mounted || !openPanel) return;
    setState(() => panelOpen = true);
    _revealBesidePanel(el);
  }

  /// Показати вулик на цій карті й одразу відкрити його форму.
  Future<void> _focusAndFill(MapElement el) async {
    await _showOnMap(el);
    if (!mounted) return;
    await _panelFill();
  }

  /// «Зберегти й далі»: наступний вулик за [MapScreen.next] — на цій карті
  /// ([here]) чи на іншій пасіці ([away]); null — далі нікого.
  Future<({MapElement? here, ({Apiary apiary, String elementId})? away})?> _nextTarget(
      MapElement cur, {Set<String> skipped = const {}}) async {
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
        // наступний за порядком (по колу), ще не оглянутий сьогодні й не
        // пропущений у цьому обході
        final today = formatDdMmYyyy(DateTime.now());
        final visited = {
          for (final t in await repo.visitTargets())
            if (t.lastVisit == today) t.key
        };
        if (!mounted) return null;
        final i = list.indexWhere((e) => ownerKeyOf(e) == ownerKeyOf(cur));
        for (var k = 1; k < list.length; k++) {
          final e = list.elementAt((i + k) % list.length);
          final key = ownerKeyOf(e);
          if (key == ownerKeyOf(cur) || skipped.contains(key) || visited.contains(key)) continue;
          return (here: e, away: null);
        }
        _showWarning(skipped.isEmpty ? 'Усі вулики на сьогодні оглянуто' : 'Обхід завершено',
            duration: const Duration(milliseconds: 1500));
        return null;
      case NextHive.qr:
        final code = await scanQrCode(context, title: 'Наступний вулик');
        if (code == null || !mounted) return null;
        final found = await repo.findByQr(code);
        if (!mounted) return null;
        if (found == null) {
          final why = await repo.qrProblem(code);
          if (!mounted) return null;
          await showInfo(
              context, '${why ?? 'Цей QR-код ще не прив\'язаний до жодного вулика.'}\n\nКод: $code',
              title: 'Вулик не знайдено');
          return null;
        }
        if (found.apiary.id == widget.apiary.id) {
          final el = elements.where((e) => e.id == found.element.id).firstOrNull ?? found.element;
          return (here: el, away: null);
        }
        return (here: null, away: (apiary: found.apiary, elementId: found.element.id));
      case NextHive.overdue:
        final now = DateTime.now();
        final due = [
          for (final t in await repo.visitTargets())
            if (t.key != ownerKeyOf(cur) && !skipped.contains(t.key))
              if (dueReminder(t, now: now) case final d?) (t: t, at: d.when)
        ]..sort((a, b) => a.at.compareTo(b.at));
        if (!mounted) return null;
        if (due.isEmpty) {
          await showInfo(context, 'Прострочених оглядів більше немає.', title: 'Готово');
          return null;
        }
        final el = await repo.getElement(due.first.t.elementId);
        final aid = el?.apiaryId;
        if (el == null || aid == null || !mounted) return null;
        if (aid == widget.apiary.id) {
          return (here: elements.where((e) => e.id == el.id).firstOrNull ?? el, away: null);
        }
        final a = await repo.getApiary(aid);
        if (a == null) return null;
        return (here: null, away: (apiary: a, elementId: el.id));
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

  /// Швидка правка одного значення (тап по рядку на панелі): маленьке вікно
  /// з одним полем та історією іконкою. Це не огляд — дата обходу не
  /// змінюється.
  Future<void> _panelQuickEdit(String parameterId) async {
    final el = panelElement;
    if (el == null) return;
    final p = await repo.getParameter(parameterId);
    final latest = await repo.latestParameterValues(el.entity);
    if (p == null || !mounted) return;
    final result = await showFillValuesDialog(
      context,
      params: [p],
      latest: latest,
      title: p.nameWithUnit,
      subtitle: panelData?.title ?? el.label ?? 'Вулик',
      onHistory: () => _panelHistory(parameterId),
    );
    if (result == null || result.values.isEmpty || !mounted) return;
    for (final e in result.values.entries) {
      await repo.addParameterRecord(e.key, e.value, el.entity);
    }
    unawaited(ReminderService.instance.reschedule());
    await _refreshPanel();
    await _refreshOverdue();
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
    final skipped = <String>{}; // «Пропустити цей вулик»
    try {
      if (selectMode) _exitEdit();
      setState(() => panelOpen = false);
      while (mounted) {
        List<MapElement>? members;
        for (final o in hiveObjects(elements)) {
          if (!skipped.contains(o.first.id) && await repo.qrForObject(o) == null) {
            members = o;
            break;
          }
        }
        if (!mounted) return;
        if (members == null) {
          await showInfo(
              context,
              linked == 0
                  ? (skipped.isEmpty
                      ? 'У всіх вуликів цієї пасіки вже є QR-коди.'
                      : 'Лишилось без коду (пропущено): ${skipped.length}.')
                  : 'Прив\'язано наліпок: $linked.'
                      '${skipped.isEmpty ? ' Тепер у всіх вуликів є QR-коди.' : ' Пропущено: ${skipped.length}.'}',
              title: 'QR-коди');
          return;
        }
        final hive = members.first;
        final name = (hive.label ?? '').trim().isEmpty ? 'вулик' : hive.label!.trim();
        grid.centerOnGrid(hive.x + 0.5, hive.y + 0.5);
        setState(() => _select(hive)); // підсвітити, для якого вулика наліпка
        final scanned = await scanQrCode(context,
            title: 'Наліпка для: $name', skipLabel: 'Пропустити цей вулик');
        if (scanned == null || !mounted) break;
        if (scanned == kQrSkip) {
          skipped.add(hive.id);
          continue;
        }
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
            title: Text(Repository.appQrNumber(current) != null
                ? 'QR-код № ${Repository.appQrNumber(current)}'
                : 'QR-код вулика'),
            content: SizedBox(
              width: 220,
              height: 220,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: current, backgroundColor: Colors.white),
              ),
            ),
            actions: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                PillButton(
                    text: 'Інший код',
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
                    text: 'Закрити',
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

  String? _scenePanelKey;

  /// Урок: вулик, чию панель відкрили, — обведений.
  Set<String>? get _lessonOutlined {
    if (!widget.tutorial) return null;
    // «Натисни на свій вулик» — вулик уже обведено
    if (!selectMode && !panelOpen && _lesson == _Lesson.openHive) {
      return {for (final e in elements) if (e.isHive) e.id};
    }
    final el = panelElement;
    if (!panelOpen || el == null || !el.isHive) return null;
    return {for (final e in mergedObjectOf(el, elements)) e.id};
  }

  String? get _lessonPanelKey => !widget.tutorial
      ? null
      : panelOpen
          ? panelElement?.id
          : (!selectMode && _lesson == _Lesson.openHive ? 'open-hive' : null);

  List<SceneCell> _scene() {
    if (_sceneBase == null ||
        !identical(_sceneEls, elements) ||
        _sceneSelId != selectedId ||
        _sceneSelGid != selectedGroupId ||
        !identical(_scenePlaced, _placedGids) ||
        _scenePanelKey != _lessonPanelKey) {
      _scenePanelKey = _lessonPanelKey;
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
      // урок: відкритий вулик обведено медовим; інакше червоний ободок —
      // давно не оглядали (час огляду настав)
      outlined: _lessonOutlined ??
          {for (final e in elements) if (e.isHive && _overdue.contains(ownerKeyOf(e))) e.id},
      outlineColor: _lessonOutlined != null ? AppColors.create : AppColors.danger,
    );
  }

  /// З сповіщення / QR: спершу лише форма «Заповнити параметри»,
  /// панель вулика з'являється після «Зберегти».
  Future<void> _fillThenPanel(MapElement el) async {
    grid.centerOnGrid(el.x + 0.5, el.y + 0.5);
    await _loadPanel(el);
    if (!mounted || panelElement == null) return;
    await _panelFill();
    if (mounted && _fillSaved && panelElement != null) {
      await _loadPanel(panelElement!);
      if (!mounted) return;
      setState(() => panelOpen = true);
      _revealBesidePanel(panelElement!);
    }
  }

  String? _bindCode;

  late String _apiaryName = widget.apiary.name;

  Future<void> _renameApiary() async {
    final name = await showTextPrompt(context,
        title: 'Назва пасіки', initial: _apiaryName);
    final t = name?.trim() ?? '';
    if (t.isEmpty || t == _apiaryName || !mounted) return;
    await repo.updateApiary(widget.apiary.id, name: t);
    if (mounted) setState(() => _apiaryName = t);
  }

  /// Тап по вулику, коли чекаємо вибору для відсканованого коду.
  Future<void> _bindScannedTo(MapElement el) async {
    final code = _bindCode;
    if (code == null || _qrBusy) return;
    _qrBusy = true;
    try {
      final members = hiveObjectOf(el, elements);
      final current = await repo.qrForObject(members);
      if (!mounted) return;
      if (current != null) {
        final ok = await showConfirm(context,
            title: 'У вулика вже є код',
            text: 'Замінити поточний QR-код цього вулика на відсканований?',
            confirmText: 'Замінити',
            danger: false);
        if (!ok || !mounted) return;
      }
      for (final m in members.skip(1)) {
        await repo.unlinkQr(EntityRef.element(m.id));
      }
      await repo.linkQr(code, EntityRef.element(members.first.id));
      _bindCode = null;
      _clearWarning();
    } finally {
      _qrBusy = false;
    }
    if (!mounted) return;
    _showWarning('QR-код прив\'язано', duration: const Duration(seconds: 1));
    await _fillThenPanel(el);
  }

  @override
  Widget build(BuildContext context) {
    final status = _warning ?? _statusText;
    final isWarn = _warning != null;
    // урок: вийти можна лише кнопкою «назад» угорі ліворуч (системне «назад»
    // і меню ☰ вивели б із пісочниці на справжні екрани)
    return PopScope(
      canPop: !widget.tutorial,
      child: Scaffold(
      drawer: widget.tutorial && _lesson != _Lesson.menu && _lesson != _Lesson.drawer
          ? null
          : AppDrawer(
              tour: widget.tutorial,
              // навчання необов'язкове: завершити можна й посеред огляду меню
              onFinishTutorial: widget.tutorial
                  ? () => Navigator.of(context).popUntil((r) => r.isFirst)
                  : null,
              hint: _menuHint
                  ? [
                      const TextSpan(
                          text: 'Тут ти зможеш керувати своєю пасікою. Щоб дізнатися про всі '
                              'функції - '),
                      GuideBubble.highlight('пройди навчання'),
                      const TextSpan(text: '.'),
                    ]
                  : null,
              repo: repo,
              currentApiary: widget.apiary,
              onReturn: _afterExternalChange,
              onBindQrRow: _bindQrInRow),
      // свайп від лівого краю конфліктував би з панорамуванням карти —
      // меню відкривається лише кнопкою
      drawerEnableOpenDragGesture: false,
      onDrawerChanged: (open) {
        if (!open && _menuHint) setState(() => _menuHint = false);
        // урок: огляд меню завершено - наприкінці пасічник вітає
        if (!open && widget.tutorial && _lesson == _Lesson.drawer) {
          setState(() => _lesson = _Lesson.congrats);
        }
      },
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
            // «козирьок»: меню навігації - з одного боку, назва пасіки (з олівцем
            // для перейменування) - по центру, шестерня налаштувань - з іншого
            Positioned(
              key: _topKey,
              top: 0,
              left: 0,
              right: 0,
              height: 64,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.popupBg,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                  border: Border(bottom: BorderSide(color: AppColors.hive, width: 2.5)),
                ),
                padding: const EdgeInsets.fromLTRB(70, 0, 70, 0), // місце під кнопки з боків
                child: Center(
                  child: GestureDetector(
                    onTap: widget.tutorial ? null : _renameApiary,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(_apiaryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ),
                      if (!widget.tutorial) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                            message: 'Перейменувати пасіку',
                            child: AppIcon('pencil', size: 20, color: AppColors.textMuted)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
            // статус (підказки режиму редагування, попередження) - під козирьком
            if (status.isNotEmpty)
              Positioned(
                top: 70,
                left: 70,
                right: 70,
                child: IgnorePointer(
                  child: Center(
                    child: CapsuleLabel(status,
                        bg: isWarn ? AppColors.warning : null,
                        fg: isWarn ? Colors.white : null),
                  ),
                ),
              ),
            const Positioned.fill(child: ScreenFrame()),
            // меню навігації (в уроці — «Назад»): більша кнопка ліворуч під
            // назвою пасіки
            Positioned(
              top: 8,
              left: 10,
              child: Center(child: Builder(
                      builder: (ctx) => widget.tutorial && _lesson == _Lesson.menu
                          ? HoneyRing(
                              key: _menuKey,
                              on: true,
                              child: CircleIconButton(
                                icon: 'menu',
                                bg: AppColors.roundBtn,
                                iconColor: AppColors.text,
                                size: 48,
                                tooltip: 'Меню',
                                onPressed: () {
                                  setState(() => _lesson = _Lesson.drawer);
                                  Scaffold.of(ctx).openDrawer();
                                },
                              ),
                            )
                          : widget.tutorial
                          ? CircleIconButton(
                              key: _backKey,
                              icon: 'back_arrow',
                              bg: AppColors.roundBtn,
                              iconColor: AppColors.text,
                              size: 48,
                              tooltip: 'Назад',
                              onPressed: () => Navigator.of(ctx).pop(),
                            )
                          : HoneyRing(
                              on: _tourMenu,
                              child: CircleIconButton(
                                icon: 'menu',
                                bg: AppColors.roundBtn,
                                iconColor: AppColors.text,
                                size: 48,
                                tooltip: 'Меню',
                                onPressed: () {
                                  if (_tourMenu) {
                                    setState(() {
                                      _tourMenu = false;
                                      _menuHint = true; // репліка пасічника в меню
                                    });
                                  }
                                  Scaffold.of(ctx).openDrawer();
                                },
                              ),
                            ),
                    )),
            ),
            // налаштування (у навчанні шестерні немає)
            if (!widget.tutorial)
              Positioned(
                top: 8,
                right: 10,
                child: GearButton(
                    size: 48,
                    onPressed: () => SettingsScreen.open(Navigator.of(context), repo)),
              ),
            // зум
            Positioned(
              right: 14,
              top: box.maxHeight / 2 - 46,
              child: Column(key: _zoomKey, children: [
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
            // перемикач режимів: унизу ліворуч (у редагуванні — над панеллю дій;
            // в уроці — завжди на одному місці, на ньому спирається пасічник)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: kToggleLeft,
              bottom: _toggleBottom,
              child: _modeToggle(),
            ),
            // редагування: «Додати» — поруч із перемикачем, під пальцем
            if (selectMode)
              Positioned(
                left: kToggleLeft + kToggleW + 12,
                bottom: _toggleBottom + (kToggleH - 52) / 2,
                child: KeyedSubtree(
                  key: _actionBarKey,
                  // шаблон обрано — «+» стає «×»: завершити додавання (лишаємось у
                  // редагуванні — вулики можна торкати й переміщувати)
                  child: pendingTemplate != null
                      ? CircleIconButton(
                          icon: 'close',
                          bg: AppColors.roundBtn,
                          iconColor: AppColors.text,
                          size: 52,
                          tooltip: 'Завершити додавання',
                          onPressed: _busy || _drag != null
                              ? null
                              : () => setState(() {
                                    pendingTemplate = null;
                                    _placedGids = const {};
                                  }))
                      : CircleIconButton(
                          icon: 'plus_circle',
                          bg: AppColors.addObject,
                          size: 52,
                          tooltip: "Додати об'єкт",
                          onPressed: _busy || _drag != null ? null : _onAddObject),
                ),
              ),
            // панель "Характеристики"
            AnimatedPositioned(
              key: _panelBoxKey,
              duration: const Duration(milliseconds: 220),
              curve: panelOpen ? Curves.easeOutCubic : Curves.easeInCubic,
              top: 70,
              // урок: панель закінчується над пасічником (він увесь урок унизу)
              bottom: widget.tutorial ? kLessonPanelBottom : 12,
              right: panelOpen ? 0 : -(CharacteristicsPanel.width + 12),
              child: panelData == null
                  ? const SizedBox(width: CharacteristicsPanel.width)
                  : CharacteristicsPanel(
                      data: panelData!,
                      onClose: _lessonInspect ? () {} : () => setState(() => panelOpen = false),
                      // подвійний тап не відкриває два вікна
                      // (у кроці уроку «Оглянути» решта кнопок панелі вимкнена)
                      // назву, значок і колір можна змінити й у робочому режимі
                      editable: selectMode || !widget.tutorial,
                      inspect: !selectMode,
                      onRename: _lessonInspect ? () {} : () => _panelGuard(_panelRename),
                      onIcon: _lessonInspect ? () {} : () => _panelGuard(_panelIcon),
                      onColor: _lessonInspect ? () {} : () => _panelGuard(_panelColor),
                      onEditParams: _lessonInspect ? () {} : () => _panelGuard(_panelEditParams),
                      onFill: _lessonInspect && !_inspectRead ? () {} : () => _panelGuard(_panelFill),
                      onVisited: (panelElement?.isHive ?? false)
                          ? (_lessonInspect ? () {} : () => _panelGuard(_panelVisited))
                          : null,
                      // тап по значенню — швидка правка (історія — іконкою в ній)
                      onValue: selectMode
                          ? null
                          : (id) => _lessonInspect ? null : _panelGuard(() => _panelQuickEdit(id)),
                      // QR-коди — лише для вуликів
                      onQr: (panelElement?.isHive ?? false) && !selectMode
                          ? (_lessonInspect ? () {} : _panelQr)
                          : null,
                      highlightFill: _lessonInspect && _inspectRead,
                      fillKey: _fillKey,
                    ),
            ),
            // урок «Базові поняття»: підсвічена клітинка, «завіса» (поки урок
            // чекає дії, решта не натискається) і пасічник
            ..._lessonTargetCell(),
            ..._lessonHiveGlow(),
            if (widget.tutorial)
              Positioned.fill(child: LessonGate(key: _gateKey, allow: _lessonAllows)),
            ..._lessonOverlay(),
            // справжня карта після уроку: «Наостанок покажу меню навігації»
            if (_tourMenu && !widget.tutorial && !selectMode && !panelOpen)
              ...lessonScene(pose: LessonPose.onButton, text: [
                const TextSpan(text: 'Наостанок покажу меню навігації. '),
                GuideBubble.highlight('Відкрий його'),
              ]),
          ]);
        }),
      ),
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
          final maxLeft = area.width - 3 * bs - 22;
          final left =
              maxLeft <= 4 ? 4.0 : (r.center.dx - 1.5 * bs - 6).clamp(4.0, maxLeft).toDouble();
          return Positioned(
            left: left,
            top: top,
            child: Row(children: [
              CircleIconButton(
                  icon: 'pencil',
                  bg: AppColors.accent,
                  size: bs,
                  tooltip: 'Властивості',
                  onPressed: _openProperties),
              const SizedBox(width: 6),
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

  /// Перемикач режимів унизу ліворуч: «Робочий» (дивимось інформацію й проводимо
  /// огляд) і «Редагування» (рухаємо, додаємо, видаляємо, міняємо вигляд).
  /// Перехід у редагування одразу пропонує шаблон, щоб додати вулик.
  /// Перемикач стоїть на одному місці в обох режимах.
  double get _toggleBottom => widget.tutorial ? kToggleLessonBottom : 24;

  /// Перехід у робочий режим і є збереженням (окремого «Готово» немає).
  Widget _modeToggle() {
    return HoneyRing(
      on: widget.tutorial && ((!selectMode && _lesson == _Lesson.place) || _lessonConfirm),
      radius: 28,
      child: ModeToggle(
        key: _editKey,
        editing: selectMode,
        onWork: selectMode && !_busy && _drag == null ? _exitEdit : null,
        onEdit: !selectMode && !_busy ? _editAndAdd : null,
      ),
    );
  }

  /// «Редагувати»: увійти в редагування; на порожній карті — одразу шаблон.
  /// Якщо шаблон не обрали — лишаємось у редагуванні (перемістити,
  /// повернути, видалити; перемикач — вийти).
  Future<void> _editAndAdd() async {
    _enterEdit();
    if (!widget.tutorial) await Hints.show(context, repo, Hints.edit);
    if (!mounted) return;
    // шаблон пропонується одразу лише на порожній карті; інакше — кнопкою «+»
    if (elements.isEmpty) await _onAddObject();
  }

}
