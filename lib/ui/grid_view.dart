import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/merge_layout.dart';
import 'cell_style.dart';
import 'common.dart';
import 'theme.dart';

/// Нескінченне поле з сіткою (порт infinite_view.py) — спільне для карти
/// й редактора шаблону.
///
/// Клітинка сітки (gx, gy) — вісь y ВГОРУ, як і в базі. На екрані вона
/// займає прямокутник [gx*cs, (gx+1)*cs] × [-(gy+1)*cs, -gy*cs] у
/// "світових" пікселях (вісь y вниз), зсунутих на камеру.
class GridController extends ChangeNotifier {
  double cellSize;
  final double minCell;
  final double maxCell;

  /// Світова координата лівого верхнього кута видимої області.
  Offset camera = Offset.zero;
  Size viewSize = Size.zero;
  (double, double)? _pendingCenter;

  /// Скільки клітинок уміщати по коротшій стороні при першому показі
  /// (планшет); далі масштаб - як людина наблизить чи віддалить.
  int? fitCells;

  GridController({this.cellSize = 34, this.minCell = 18, this.maxCell = 56, (double, double)? center})
      : _pendingCenter = center ?? (0.5, 0.5);

  /// Навести камеру, щоб точка сітки (gx, gy) (можна дробову) була в центрі.
  void centerOnGrid(double gx, double gy) {
    if (viewSize.isEmpty) {
      _pendingCenter = (gx, gy);
      return;
    }
    camera = Offset(gx * cellSize - viewSize.width / 2, -gy * cellSize - viewSize.height / 2);
    notifyListeners();
  }

  void _setViewSize(Size s) {
    if (s == viewSize) return;
    final oldCenter = viewSize.isEmpty ? null : _centerGrid();
    final fit = fitCells;
    if (viewSize.isEmpty && fit != null && !s.isEmpty) {
      cellSize = (s.shortestSide / fit).clamp(minCell, maxCell).toDouble();
      fitCells = null;
    }
    viewSize = s;
    final c = _pendingCenter ?? oldCenter;
    _pendingCenter = null;
    if (c != null) {
      camera = Offset(c.$1 * cellSize - s.width / 2, -c.$2 * cellSize - s.height / 2);
    }
  }

  (double, double) _centerGrid() => (
        (camera.dx + viewSize.width / 2) / cellSize,
        -(camera.dy + viewSize.height / 2) / cellSize,
      );

  void panBy(Offset screenDelta) {
    camera -= screenDelta;
    notifyListeners();
  }

  /// Масштаб навколо точки екрана [focal] (типово — центр).
  bool zoomTo(double newSize, {Offset? focal}) {
    newSize = newSize.clamp(minCell, maxCell).toDouble();
    if ((newSize - cellSize).abs() < 0.01) return false;
    final f = focal ?? viewSize.center(Offset.zero);
    final world = camera + f; // світова точка під фокусом
    final k = newSize / cellSize;
    cellSize = newSize;
    camera = world * k - f;
    notifyListeners();
    return true;
  }

  bool zoomBy(double delta) => zoomTo(cellSize + delta);

  /// Клітинка під точкою екрана.
  (int, int) screenToCell(Offset screen) {
    final w = camera + screen;
    return ((w.dx / cellSize).floor(), (-w.dy / cellSize).floor());
  }

  /// Прямокутник клітинки на екрані.
  Rect cellRect(int gx, int gy) => Rect.fromLTWH(
        gx * cellSize - camera.dx,
        -(gy + 1) * cellSize - camera.dy,
        cellSize,
        cellSize,
      );

  /// Зсув у пікселях екрана -> зсув у цілих клітинках (y вгору).
  (int, int) screenDeltaToCells(Offset d) =>
      ((d.dx / cellSize).round(), (-d.dy / cellSize).round());

  void refresh() => notifyListeners();
}

/// Одна клітинка сцени для малювання.
class SceneCell {
  final Object id;
  final int x, y;
  final String type;
  final String? variant, icon, color;
  final Merge merge;
  final bool drawIcon;
  final (double, double) iconOffset;
  final bool selected;

  /// Бічні сторони, по яких клітинка злита з іншою ОБРАНОЮ — там рамка
  /// виділення не малюється (одна рамка по контуру фігури).
  final Merge selOpen;

  /// Тимчасовий зсув на екрані (перетягування / "трусіння").
  final Offset shift;

  /// Зелений ободок (напр., "у вулика вже є QR-код") і сторони, по яких він
  /// не малюється (злиття з іншою клітинкою з ободком — один контур).
  final bool outlined;
  final Merge outlineOpen;

  /// Колір ободка: зелений (є QR-код) чи червоний (прострочений огляд).
  final Color outlineColor;

  /// Та сама клітинка з іншим тимчасовим зсувом (для перетягування без
  /// повторного обчислення злиття).
  SceneCell withShift(Offset s) => SceneCell(
        id: id,
        x: x,
        y: y,
        type: type,
        variant: variant,
        icon: icon,
        color: color,
        merge: merge,
        drawIcon: drawIcon,
        iconOffset: iconOffset,
        selected: selected,
        selOpen: selOpen,
        shift: s,
        outlined: outlined,
        outlineOpen: outlineOpen,
        outlineColor: outlineColor,
      );

  const SceneCell({
    required this.id,
    required this.x,
    required this.y,
    required this.type,
    this.variant,
    this.icon,
    this.color,
    this.merge = Merge.none,
    this.drawIcon = true,
    this.iconOffset = (0.0, 0.0),
    this.selected = false,
    this.selOpen = Merge.none,
    this.shift = Offset.zero,
    this.outlined = false,
    this.outlineOpen = Merge.none,
    this.outlineColor = AppColors.qrLinked,
  });
}

/// Побудова клітинок сцени зі злиттям і виділенням.
List<SceneCell> buildScene<K extends Object>({
  required List<MergeItem<K>> items,
  required Map<K, ({String type, String? variant, String? icon, String? color})> look,
  required Set<K> selected,
  Map<K, Offset> shifts = const {},
  Set<K> outlined = const {},
  Color outlineColor = AppColors.qrLinked,

  /// Колір ободка окремих клітинок (інакше [outlineColor]).
  Map<K, Color> outlineColors = const {},
}) {
  final res = mergeLayout(items);
  final selKeys = <(int, int, String)>{
    for (final it in items)
      if (selected.contains(it.id)) (it.x, it.y, it.key)
  };
  final outKeys = <(int, int, String)>{
    for (final it in items)
      if (outlined.contains(it.id)) (it.x, it.y, it.key)
  };
  Merge openAmong(MergeItem<K> it, Merge m, Set<(int, int, String)> keys) => Merge(
        left: m.left && keys.contains((it.x - 1, it.y, it.key)),
        right: m.right && keys.contains((it.x + 1, it.y, it.key)),
        bottom: m.bottom && keys.contains((it.x, it.y - 1, it.key)),
        top: m.top && keys.contains((it.x, it.y + 1, it.key)),
      );
  final out = <SceneCell>[];
  for (final it in items) {
    final l = look[it.id]!;
    final m = res.merges[it.id] ?? Merge.none;
    final isSel = selected.contains(it.id);
    final open = isSel ? openAmong(it, m, selKeys) : Merge.none;
    final isOut = outlined.contains(it.id);
    out.add(SceneCell(
      id: it.id,
      x: it.x,
      y: it.y,
      type: l.type,
      variant: l.variant,
      icon: l.icon,
      color: l.color,
      merge: m,
      drawIcon: res.iconDraw[it.id] ?? true,
      iconOffset: res.iconOffset[it.id] ?? (0.0, 0.0),
      selected: isSel,
      selOpen: open,
      shift: shifts[it.id] ?? Offset.zero,
      outlined: isOut,
      outlineOpen: isOut ? openAmong(it, m, outKeys) : Merge.none,
      outlineColor: outlineColors[it.id] ?? outlineColor,
    ));
  }
  return out;
}

/// Інформація про дотик у світі.
class GridPress {
  final Offset screen;
  final (int, int) cell;
  const GridPress(this.screen, this.cell);
}

/// Віджет поля: малює сітку й клітинки, обробляє дотики.
///
///  * натиснули — спершу [onPressDown]: чи забирає світ цей дотик собі
///    (перетягування об'єкта). Якщо так — рух іде в [onPressMove], кінець —
///    у [onPressUp];
///  * інакше: рух більше порогу — панорамування; відпустили без руху —
///    тап ([onTap]);
///  * два пальці — масштабування щипком; коліщатко миші — прокрутка
///    (з Ctrl — масштаб).
class InfiniteGrid extends StatefulWidget {
  final GridController controller;
  final List<SceneCell> cells;
  final bool blocked;
  final bool maskSelected;

  /// Стрілки-натяки "об'єкт можна перетягнути" біля обраного (вимикаються там,
  /// де нічого переміщувати не можна, наприклад у генераторі QR).
  final bool showMoveHints;

  /// Колір і товщина рамки виділення (за замовчуванням - акцентний, 2.5).
  final Color? selectColor;
  final double selectWidth;
  final bool Function(GridPress p)? onPressDown;
  final void Function(Offset screenDelta)? onPressMove;
  final void Function(Offset screenDelta)? onPressUp;
  final void Function(GridPress p)? onTap;

  /// Довгий дотик (0,5 с без руху). true — дотик «захоплено» (далі, як після
  /// [onPressDown], ідуть [onPressMove]/[onPressUp], відлік зсуву — з цієї
  /// точки).
  final bool Function(GridPress p)? onLongPress;

  const InfiniteGrid({
    super.key,
    required this.controller,
    required this.cells,
    this.blocked = false,
    this.maskSelected = true,
    this.showMoveHints = true,
    this.selectColor,
    this.selectWidth = 2.5,
    this.onPressDown,
    this.onPressMove,
    this.onPressUp,
    this.onTap,
    this.onLongPress,
  });

  /// Поріг, після якого рух — це панорамування, а не тап (запас на
  /// тремтіння пальця на телефоні).
  static const double panThreshold = 20;

  @override
  State<InfiniteGrid> createState() => _InfiniteGridState();
}

class _InfiniteGridState extends State<InfiniteGrid> {
  final Map<int, Offset> _pointers = {};
  int? _primary;
  Offset _start = Offset.zero;
  Offset _camStart = Offset.zero;
  bool _claimed = false;
  bool _panning = false;
  bool _pinched = false;
  double _pinchStartDist = 0;
  double _pinchStartCell = 0;
  Timer? _longTimer;

  static const longPressDelay = Duration(milliseconds: 500);

  void _cancelLong() {
    _longTimer?.cancel();
    _longTimer = null;
  }

  void _armLong() {
    _cancelLong();
    if (widget.onLongPress == null || _claimed) return;
    _longTimer = Timer(longPressDelay, () {
      _longTimer = null;
      final id = _primary;
      if (id == null || _panning || _pinched || _claimed || !mounted) return;
      final pos = _pointers[id];
      if (pos == null) return;
      if (widget.onLongPress!(GridPress(pos, c.screenToCell(pos)))) {
        _claimed = true;
        _start = pos;
        HapticFeedback.mediumImpact();
      }
    });
  }

  GridController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onCam);
  }

  @override
  void didUpdateWidget(InfiniteGrid old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onCam);
      widget.controller.addListener(_onCam);
    }
  }

  @override
  void dispose() {
    _cancelLong();
    c.removeListener(_onCam);
    super.dispose();
  }

  void _onCam() {
    if (mounted) setState(() {});
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _primary = e.pointer;
      _start = e.localPosition;
      _camStart = c.camera;
      _panning = false;
      _pinched = false;
      _claimed = widget.onPressDown?.call(GridPress(e.localPosition, c.screenToCell(e.localPosition))) ??
          false;
      _armLong();
    } else if (_pointers.length == 2 && !_claimed) {
      _cancelLong();
      final pts = _pointers.values.toList();
      _pinched = true;
      _pinchStartDist = (pts[0] - pts[1]).distance;
      _pinchStartCell = c.cellSize;
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pinched && _pointers.length >= 2) {
      final pts = _pointers.values.toList();
      final d = (pts[0] - pts[1]).distance;
      if (_pinchStartDist > 0) {
        c.zoomTo(_pinchStartCell * d / _pinchStartDist, focal: (pts[0] + pts[1]) / 2);
      }
      return;
    }
    if (e.pointer != _primary || _pinched) return;
    final delta = e.localPosition - _start;
    if (_claimed) {
      widget.onPressMove?.call(delta);
      return;
    }
    if (!_panning && delta.distance > InfiniteGrid.panThreshold) {
      _panning = true;
      _cancelLong();
    }
    if (_panning) {
      c.camera = _camStart - delta;
      c.refresh();
    }
  }

  void _up(PointerEvent e, {bool cancelled = false}) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers.remove(e.pointer);
    if (e.pointer == _primary) _cancelLong();
    if (e.pointer == _primary) {
      final delta = e.localPosition - _start;
      if (_claimed) {
        // скасування жесту: повернути показаний зсув на місце
        if (cancelled) widget.onPressMove?.call(Offset.zero);
        widget.onPressUp?.call(cancelled ? Offset.zero : delta);
      } else if (!_panning && !_pinched && !cancelled) {
        widget.onTap?.call(GridPress(e.localPosition, c.screenToCell(e.localPosition)));
      }
      _primary = null;
      _claimed = false;
    }
    if (_pointers.isEmpty) {
      _pinched = false;
      _panning = false;
    } else if (_pinched && _pointers.length == 1) {
      // ВИПРАВЛЕНО: лишився один палець після щипка (масштабування).
      // Раніше тут нічого не відбувалось, і панорамування "заморожувалось"
      // до повного відриву обох пальців — тепер переходимо в режим
      // панорамування цим пальцем, перебазувавши початкову точку на
      // поточну позицію, щоб камера не "стрибнула".
      _pinched = false;
      _primary = _pointers.keys.first;
      _start = _pointers.values.first;
      _camStart = c.camera;
      _panning = true;
      _claimed = false;
    }
  }

  // Сенсорна панель (тачпад): прокрутка двома пальцями й
  // щипок приходять окремими подіями PanZoom, а не колесом миші.
  Offset _pzLastPan = Offset.zero;
  double _pzStartCell = 0;

  void _pzStart(PointerPanZoomStartEvent e) {
    _pzLastPan = Offset.zero;
    _pzStartCell = c.cellSize;
  }

  void _pzUpdate(PointerPanZoomUpdateEvent e) {
    if (e.scale != 1.0 && _pzStartCell > 0) {
      c.zoomTo(_pzStartCell * e.scale, focal: e.localPosition);
    }
    final d = e.pan - _pzLastPan;
    _pzLastPan = e.pan;
    if (d != Offset.zero) c.panBy(d);
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final ctrl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (ctrl) {
        c.zoomTo(c.cellSize * (e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1), focal: e.localPosition);
      } else {
        final shift = HardwareKeyboard.instance.isShiftPressed;
        c.panBy(shift ? Offset(-e.scrollDelta.dy, 0) : -e.scrollDelta);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      c._setViewSize(Size(box.maxWidth, box.maxHeight));
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (e) => _up(e),
        onPointerCancel: (e) => _up(e, cancelled: true),
        onPointerSignal: _signal,
        onPointerPanZoomStart: _pzStart,
        onPointerPanZoomUpdate: _pzUpdate,
        child: ClipRect(
          child: CustomPaint(
            size: Size(box.maxWidth, box.maxHeight),
            painter: _ScenePainter(
              camera: c.camera,
              cs: c.cellSize,
              cells: widget.cells,
              blocked: widget.blocked,
              maskSelected: widget.maskSelected,
              showMoveHints: widget.showMoveHints,
              selectColor: widget.selectColor,
              selectWidth: widget.selectWidth,
            ),
          ),
        ),
      );
    });
  }
}

class _ScenePainter extends CustomPainter {
  final Offset camera;
  final double cs;
  final List<SceneCell> cells;
  final bool blocked;
  final bool maskSelected;
  final bool showMoveHints;
  final Color? selectColor;
  final double selectWidth;

  _ScenePainter({
    required this.camera,
    required this.cs,
    required this.cells,
    required this.blocked,
    required this.maskSelected,
    this.showMoveHints = true,
    this.selectColor,
    this.selectWidth = 2.5,
  });

  Rect _cellRect(SceneCell c) => Rect.fromLTWH(
        c.x * cs - camera.dx + c.shift.dx,
        -(c.y + 1) * cs - camera.dy + c.shift.dy,
        cs,
        cs,
      );

  @override
  void paint(Canvas canvas, Size size) {
    // трава
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.grass);
    // сітка лише у видимій частині
    final line = Paint()
      ..color = AppColors.gridLine
      ..strokeWidth = 1;
    final i0 = (camera.dx / cs).floor(), i1 = ((camera.dx + size.width) / cs).ceil();
    for (var i = i0; i <= i1; i++) {
      final x = i * cs - camera.dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    final j0 = (camera.dy / cs).floor(), j1 = ((camera.dy + size.height) / cs).ceil();
    for (var j = j0; j <= j1; j++) {
      final y = j * cs - camera.dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // прямокутники рахуються один раз на кадр і для видимих клітинок
    final visible = (Offset.zero & size).inflate(cs * 2);
    final vis = <SceneCell>[];
    final rects = <Rect>[];
    for (final c in cells) {
      final r = _cellRect(c);
      if (visible.overlaps(r)) {
        vis.add(c);
        rects.add(r);
      }
    }

    // маска під обраними (щоб сітка не "прозирала" крізь підсвічений об'єкт)
    if (maskSelected) {
      final grass = Paint()..color = AppColors.grass;
      for (var i = 0; i < vis.length; i++) {
        final c = vis[i];
        if (!c.selected) continue;
        final b = bodyRect(rects[i], c.merge);
        const pad = 2.0;
        canvas.drawRect(
          Rect.fromLTRB(
            b.left - (c.selOpen.left ? 0 : pad),
            b.top - (c.selOpen.top ? 0 : pad),
            b.right + (c.selOpen.right ? 0 : pad),
            b.bottom + (c.selOpen.bottom ? 0 : pad),
          ),
          grass,
        );
      }
    }
    // 1) плашки
    for (var i = 0; i < vis.length; i++) {
      final c = vis[i];
      drawBody(canvas, bodyRect(rects[i], c.merge), c.merge, fillColor(c.type, c.color));
    }
    // 2) іконки — після всіх плашок, щоб сусідня плашка не перекрила іконку фігури
    for (var i = 0; i < vis.length; i++) {
      final c = vis[i];
      if (!c.drawIcon) continue;
      final r = rects[i];
      final center = r.center + Offset(c.iconOffset.$1 * cs, -c.iconOffset.$2 * cs);
      drawCellIcon(canvas, center, cs, c.type, c.variant, c.icon);
    }
    // 2б) ободок: зелений — у вулика є QR-код, червоний — прострочений огляд
    if (cells.any((c) => c.outlined)) {
      final ring = Paint()
        ..color = AppColors.qrLinked
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (var i = 0; i < vis.length; i++) {
        final c = vis[i];
        if (!c.outlined) continue;
        ring.color = c.outlineColor;
        final b = bodyRect(rects[i], c.merge).deflate(2.5);
        final o = c.outlineOpen;
        if (!o.any) {
          canvas.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(4)), ring);
          continue;
        }
        final full = bodyRect(rects[i], c.merge);
        // на злитих сторонах лінія доходить до краю, щоб контури з'єднались
        final r = Rect.fromLTRB(
          o.left ? full.left : b.left,
          o.top ? full.top : b.top,
          o.right ? full.right : b.right,
          o.bottom ? full.bottom : b.bottom,
        );
        if (!o.bottom) canvas.drawLine(r.bottomLeft, r.bottomRight, ring);
        if (!o.top) canvas.drawLine(r.topLeft, r.topRight, ring);
        if (!o.left) canvas.drawLine(r.topLeft, r.bottomLeft, ring);
        if (!o.right) canvas.drawLine(r.topRight, r.bottomRight, ring);
      }
    }
    // 3) рамка виділення — одна по зовнішньому контуру обраної фігури
    final sel = cells.where((c) => c.selected).toList();
    if (sel.isEmpty) return;
    final frameColor = blocked ? AppColors.danger : (selectColor ?? AppColors.accent);
    final frame = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = selectWidth;
    Rect? bounds;
    for (final c in sel) {
      final b = bodyRect(_cellRect(c), c.merge).inflate(2);
      bounds = bounds == null ? b : bounds.expandToInclude(b);
      final o = c.selOpen;
      if (!o.any) {
        canvas.drawRRect(RRect.fromRectAndRadius(b, const Radius.circular(5)), frame);
        continue;
      }
      if (!o.bottom) canvas.drawLine(b.bottomLeft, b.bottomRight, frame);
      if (!o.top) canvas.drawLine(b.topLeft, b.topRight, frame);
      if (!o.left) canvas.drawLine(b.topLeft, b.bottomLeft, frame);
      if (!o.right) canvas.drawLine(b.topRight, b.bottomRight, frame);
    }
    // 4) декоративні стрілки-натяки: об'єкт можна перетягнути
    if (bounds != null && showMoveHints) _hints(canvas, bounds, frameColor);
  }

  void _hints(Canvas canvas, Rect b, Color color) {
    const gap = kHintGap, s = kHintSize;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = b.center.dx, cy = b.center.dy;
    void chevron(List<Offset> pts) {
      canvas.drawPath(Path()..addPolygon(pts, false), p);
    }

    chevron([Offset(cx - s, b.top - gap), Offset(cx, b.top - gap - s), Offset(cx + s, b.top - gap)]);
    chevron([
      Offset(cx - s, b.bottom + gap),
      Offset(cx, b.bottom + gap + s),
      Offset(cx + s, b.bottom + gap)
    ]);
    chevron([
      Offset(b.left - gap, cy - s),
      Offset(b.left - gap - s, cy),
      Offset(b.left - gap, cy + s)
    ]);
    chevron([
      Offset(b.right + gap, cy - s),
      Offset(b.right + gap + s, cy),
      Offset(b.right + gap, cy + s)
    ]);
  }

  // Перемальовуємо лише коли щось справді змінилось (раніше — щоразу).
  // Список клітинок незмінний: нова сцена завжди приходить НОВИМ списком.
  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.camera != camera ||
      old.cs != cs ||
      !identical(old.cells, cells) ||
      old.blocked != blocked ||
      old.maskSelected != maskSelected ||
      old.showMoveHints != showMoveHints ||
      old.selectColor != selectColor ||
      old.selectWidth != selectWidth;
}

/// Лише для бенчмарків/тестів: painter сцени без віджета.
@visibleForTesting
CustomPainter debugScenePainter({
  required Offset camera,
  required double cs,
  required List<SceneCell> cells,
}) =>
    _ScenePainter(camera: camera, cs: cs, cells: cells, blocked: false, maskSelected: true);

/// Статичний зменшений знімок карти: усі клітинки вписуються в доступний
/// розмір (для плиток списку пасік). Без жестів і виділення.
class SceneThumbnail extends StatelessWidget {
  final List<SceneCell> cells;
  const SceneThumbnail({super.key, required this.cells});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 120.0;
      final h = box.maxHeight.isFinite ? box.maxHeight : 120.0;
      double cs = 14;
      var camera = Offset(-w / 2, -h / 2);
      if (cells.isNotEmpty) {
        var minX = cells.first.x, maxX = minX, minY = cells.first.y, maxY = minY;
        for (final c in cells) {
          if (c.x < minX) minX = c.x;
          if (c.x > maxX) maxX = c.x;
          if (c.y < minY) minY = c.y;
          if (c.y > maxY) maxY = c.y;
        }
        const pad = 8.0;
        final cols = maxX - minX + 1, rows = maxY - minY + 1;
        cs = math.min((w - 2 * pad) / cols, (h - 2 * pad) / rows);
        cs = cs.clamp(0.5, 28.0); // велика карта теж має вміщатись повністю
        // центр знімка: середина обсягу клітинок -> середина віджета
        final cxWorld = (minX + cols / 2) * cs;
        final cyWorld = -(minY + rows / 2) * cs;
        camera = Offset(cxWorld - w / 2, cyWorld - h / 2);
      }
      return ClipRect(
        child: CustomPaint(
          size: Size(w, h),
          painter: _ScenePainter(
            camera: camera,
            cs: cs,
            cells: cells,
            blocked: false,
            maskSelected: false,
          ),
        ),
      );
    });
  }
}

/// Відступ і розмір стрілок-натяків навколо обраного об'єкта.
const double kHintGap = 12;
const double kHintSize = 8;

/// Межі клітинок на екрані (для розміщення плаваючих кнопок над фігурою).
Rect? cellsScreenBounds(GridController c, Iterable<(int, int)> cells) {
  Rect? r;
  for (final (x, y) in cells) {
    final cr = c.cellRect(x, y);
    r = r == null ? cr : r.expandToInclude(cr);
  }
  return r;
}

/// Невелика допоміжна функція для "трусіння" (жест "ні").
double shakeOffset(double t, double duration) {
  if (t >= duration) return 0;
  return 4 * math.sin(t / duration * 3 * 2 * math.pi) * (1 - t / duration);
}


/// Кнопки масштабу «+» / «−» - однакові на всіх картах (ставляться праворуч
/// по центру висоти карти).
class ZoomButtons extends StatelessWidget {
  final GridController controller;
  const ZoomButtons({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        PillButton(
            text: '+',
            bg: AppColors.roundBtn,
            fg: AppColors.text,
            width: 42,
            height: 42,
            radius: 21,
            fontSize: 20,
            onPressed: () => controller.zoomBy(4)),
        const SizedBox(height: 8),
        PillButton(
            text: '−',
            bg: AppColors.roundBtn,
            fg: AppColors.text,
            width: 42,
            height: 42,
            radius: 21,
            fontSize: 20,
            onPressed: () => controller.zoomBy(-4)),
      ]);
}
