import 'dart:math' as math;
import 'dart:ui';

/// Розбір простих SVG-іконок у контури Flutter (без сторонніх пакетів і
/// без асинхронності — іконки малюються прямо на Canvas під час малювання
/// карти).
///
/// Підтримується проста підмножина SVG (усе, що видає Figma, Inkscape,
/// Illustrator для лінійних іконок): `path`, `circle`, `ellipse`, `rect`,
/// `line`, `polyline`, `polygon`, групи `g`; атрибути `fill`, `stroke`,
/// `stroke-width`, `stroke-linecap`, `stroke-linejoin`, `opacity`,
/// `fill-opacity`, `stroke-opacity` (також усередині `style="…"`).
/// Кольори з файлу ігноруються — іконка фарбується кольором застосунку
/// (`currentColor`). Усе інше (transform, градієнти, текст, зображення,
/// маски…) не підтримується, про це повідомляє [parseSvgIcon] через
/// `onWarning`, а тест `test/icons_test.dart` не пропустить таку іконку.

/// Один намальований елемент іконки.
class SvgShape {
  final Path path;
  final bool fill;
  final bool stroke;
  final double strokeWidth;
  final StrokeCap cap;
  final StrokeJoin join;
  final double fillOpacity;
  final double strokeOpacity;

  final Paint _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  SvgShape({
    required this.path,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.cap,
    required this.join,
    required this.fillOpacity,
    required this.strokeOpacity,
  }) {
    _strokePaint
      ..strokeWidth = strokeWidth
      ..strokeCap = cap
      ..strokeJoin = join;
  }

  void draw(Canvas canvas, Color color) {
    if (fill) {
      _fillPaint.color = color.withValues(alpha: color.a * fillOpacity);
      canvas.drawPath(path, _fillPaint);
    }
    if (stroke) {
      _strokePaint.color = color.withValues(alpha: color.a * strokeOpacity);
      canvas.drawPath(path, _strokePaint);
    }
  }
}

/// Розібрана іконка: набір елементів у системі координат viewBox.
class SvgIconData {
  final List<SvgShape> shapes;

  /// Прямокутник viewBox (за замовчуванням 0 0 24 24).
  final Rect viewBox;

  const SvgIconData(this.shapes, this.viewBox);

  double get size => math.max(viewBox.width, viewBox.height);
}

// ---------------------------------------------------------------------------
// Розбір SVG
// ---------------------------------------------------------------------------

final _tagRe = RegExp(
  r'<\s*(/?)\s*([A-Za-z][\w:.-]*)((?:\s+[^\s=>/]+\s*=\s*(?:"[^"]*"|' "'[^']*'" r'))*)\s*(/?)\s*>',
);
final _attrRe = RegExp(r'([\w:.-]+)\s*=\s*(?:"([^"]*)"|' "'([^']*)'" r')');

const _ignoredTags = {'title', 'desc', 'metadata', 'defs', 'sodipodi:namedview', 'style'};
const _shapeTags = {'path', 'circle', 'ellipse', 'rect', 'line', 'polyline', 'polygon'};
const _containerTags = {'svg', 'g'};
const _unsupportedAttrs = {'transform', 'clip-path', 'mask', 'filter', 'marker-start', 'marker-end'};

Map<String, String> _attrs(String src) {
  final m = <String, String>{};
  for (final a in _attrRe.allMatches(src)) {
    m[a.group(1)!] = a.group(2) ?? a.group(3) ?? '';
  }
  final style = m['style'];
  if (style != null) {
    for (final part in style.split(';')) {
      final i = part.indexOf(':');
      if (i > 0) m[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
  }
  return m;
}

class _Style {
  final String? fill, stroke;
  final double strokeWidth, opacity, fillOpacity, strokeOpacity;
  final StrokeCap cap;
  final StrokeJoin join;
  const _Style({
    this.fill,
    this.stroke,
    this.strokeWidth = 1.5,
    this.opacity = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
  });

  _Style apply(Map<String, String> a) {
    double? num(String k) => double.tryParse((a[k] ?? '').replaceAll('px', '').trim());
    return _Style(
      fill: a['fill'] ?? fill,
      stroke: a['stroke'] ?? stroke,
      strokeWidth: num('stroke-width') ?? strokeWidth,
      // opacity вкладених груп перемножується, як у SVG
      opacity: opacity * (num('opacity') ?? 1),
      fillOpacity: num('fill-opacity') ?? fillOpacity,
      strokeOpacity: num('stroke-opacity') ?? strokeOpacity,
      cap: switch (a['stroke-linecap']) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        'butt' => StrokeCap.butt,
        _ => cap,
      },
      join: switch (a['stroke-linejoin']) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        'miter' => StrokeJoin.miter,
        _ => join,
      },
    );
  }
}

bool _on(String? v) => v != null && v.trim().toLowerCase() != 'none';

/// Розбирає SVG-текст. Кидає [FormatException], якщо файл непридатний.
/// [onWarning] отримує повідомлення про непідтримувані можливості.
SvgIconData parseSvgIcon(String svg, {void Function(String message)? onWarning}) {
  void warn(String m) => onWarning?.call(m);
  final text = svg
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'<\?.*?\?>', dotAll: true), '')
      .replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');

  var viewBox = const Rect.fromLTWH(0, 0, 24, 24);
  var sawRoot = false;
  final shapes = <SvgShape>[];
  final stack = <_Style>[const _Style()];
  var ignoreDepth = 0; // усередині title/defs/…

  for (final m in _tagRe.allMatches(text)) {
    final closing = m.group(1) == '/';
    final name = m.group(2)!;
    final selfClosing = m.group(4) == '/';
    if (_ignoredTags.contains(name)) {
      if (!selfClosing) ignoreDepth += closing ? -1 : 1;
      if ((name == 'defs' || name == 'style') && !closing) {
        warn('<$name> ігнорується (градієнти, CSS і повторне використання не підтримуються)');
      }
      continue;
    }
    if (ignoreDepth > 0) continue;
    if (closing) {
      if (_containerTags.contains(name) && stack.length > 1) stack.removeLast();
      continue;
    }
    final a = _attrs(m.group(3) ?? '');
    for (final k in _unsupportedAttrs) {
      if (a.containsKey(k)) warn('атрибут "$k" не підтримується (<$name>): «розгорніть» його в редакторі');
    }
    if (_containerTags.contains(name)) {
      if (name == 'svg' && !sawRoot) {
        sawRoot = true;
        final vb = (a['viewBox'] ?? '')
            .split(RegExp(r'[\s,]+'))
            .where((s) => s.isNotEmpty)
            .map(double.tryParse)
            .toList();
        if (vb.length == 4 && !vb.contains(null) && vb[2]! > 0 && vb[3]! > 0) {
          viewBox = Rect.fromLTWH(vb[0]!, vb[1]!, vb[2]!, vb[3]!);
        } else if (a.containsKey('viewBox')) {
          throw const FormatException('некоректний viewBox');
        }
      }
      final st = stack.last.apply(a);
      if (!selfClosing) stack.add(st);
      continue;
    }
    if (!_shapeTags.contains(name)) {
      warn('елемент <$name> не підтримується й пропущений');
      continue;
    }
    final st = stack.last.apply(a);
    final path = _shapePath(name, a);
    if (path == null) {
      warn('<$name> без потрібних атрибутів — пропущено');
      continue;
    }
    var fill = _on(st.fill);
    var stroke = _on(st.stroke);
    if (st.fill == null && st.stroke == null) stroke = true; // лінійна іконка за замовчуванням
    if (st.fill == null) fill = false;
    if (!fill && !stroke) continue;
    shapes.add(SvgShape(
      path: path,
      fill: fill,
      stroke: stroke,
      strokeWidth: st.strokeWidth,
      cap: st.cap,
      join: st.join,
      fillOpacity: st.opacity * st.fillOpacity,
      strokeOpacity: st.opacity * st.strokeOpacity,
    ));
  }
  if (!sawRoot) throw const FormatException('немає кореневого елемента <svg>');
  if (shapes.isEmpty) throw const FormatException('в іконці немає жодного видимого елемента');
  return SvgIconData(shapes, viewBox);
}

double _n(Map<String, String> a, String k, [double def = 0]) =>
    double.tryParse((a[k] ?? '').replaceAll('px', '').trim()) ?? def;

Path? _shapePath(String tag, Map<String, String> a) {
  switch (tag) {
    case 'path':
      final d = a['d'];
      return d == null ? null : parseSvgPathData(d);
    case 'circle':
      final r = _n(a, 'r');
      if (r <= 0) return null;
      return Path()..addOval(Rect.fromCircle(center: Offset(_n(a, 'cx'), _n(a, 'cy')), radius: r));
    case 'ellipse':
      final rx = _n(a, 'rx'), ry = _n(a, 'ry');
      if (rx <= 0 || ry <= 0) return null;
      return Path()
        ..addOval(Rect.fromCenter(
            center: Offset(_n(a, 'cx'), _n(a, 'cy')), width: rx * 2, height: ry * 2));
    case 'rect':
      final w = _n(a, 'width'), h = _n(a, 'height');
      if (w <= 0 || h <= 0) return null;
      final rect = Rect.fromLTWH(_n(a, 'x'), _n(a, 'y'), w, h);
      var rx = _n(a, 'rx', double.nan), ry = _n(a, 'ry', double.nan);
      if (rx.isNaN && ry.isNaN) return Path()..addRect(rect);
      if (rx.isNaN) rx = ry;
      if (ry.isNaN) ry = rx;
      return Path()..addRRect(RRect.fromRectXY(rect, math.min(rx, w / 2), math.min(ry, h / 2)));
    case 'line':
      return Path()
        ..moveTo(_n(a, 'x1'), _n(a, 'y1'))
        ..lineTo(_n(a, 'x2'), _n(a, 'y2'));
    case 'polyline':
    case 'polygon':
      final nums = _numRe
          .allMatches(a['points'] ?? '')
          .map((m) => double.parse(m.group(0)!))
          .toList();
      if (nums.length < 4) return null;
      final p = Path()..moveTo(nums[0], nums[1]);
      for (var i = 2; i + 1 < nums.length; i += 2) {
        p.lineTo(nums[i], nums[i + 1]);
      }
      if (tag == 'polygon') p.close();
      return p;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Дані контуру (атрибут d)
// ---------------------------------------------------------------------------

final _numRe = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

class _Scan {
  final String s;
  int i = 0;
  _Scan(this.s);

  void skipSep() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D) {
        i++;
      } else {
        break;
      }
    }
  }

  bool get atEnd {
    skipSep();
    return i >= s.length;
  }

  /// Наступний символ — літера-команда?
  bool get atCommand {
    skipSep();
    if (i >= s.length) return false;
    return RegExp(r'[MmLlHhVvCcSsQqTtAaZz]').hasMatch(s[i]);
  }

  String command() => s[i++];

  double number() {
    skipSep();
    final m = _numRe.matchAsPrefix(s, i);
    if (m == null) throw FormatException('очікувалось число у d="…" на позиції $i');
    i = m.end;
    return double.parse(m.group(0)!);
  }

  /// Прапорець дуги: один символ 0/1 (може стояти впритул до наступного числа).
  bool flag() {
    skipSep();
    if (i >= s.length || (s[i] != '0' && s[i] != '1')) {
      throw FormatException('очікувався прапорець дуги (0 або 1) на позиції $i');
    }
    return s[i++] == '1';
  }
}

/// Перетворює дані контуру SVG (`M L H V C S Q T A Z`, великі й малі літери).
Path parseSvgPathData(String d) {
  final path = Path();
  final sc = _Scan(d);
  double x = 0, y = 0, sx = 0, sy = 0;
  double? lcx, lcy; // остання контрольна точка кривої (для S і T)
  String cmd = '';
  var started = false;
  while (!sc.atEnd) {
    if (sc.atCommand) {
      cmd = sc.command();
    } else if (cmd.isEmpty || cmd == 'Z' || cmd == 'z') {
      throw FormatException('очікувалась команда контуру на позиції ${sc.i}');
    }
    if (!started && cmd != 'M' && cmd != 'm') {
      throw const FormatException('контур має починатися з M');
    }
    started = true;
    final rel = cmd.toLowerCase() == cmd;
    final up = cmd.toUpperCase();
    double ax(double v) => rel ? x + v : v;
    double ay(double v) => rel ? y + v : v;
    switch (up) {
      case 'M':
        x = ax(sc.number());
        y = ay(sc.number());
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L'; // наступні пари — лінії
        lcx = lcy = null;
      case 'L':
        x = ax(sc.number());
        y = ay(sc.number());
        path.lineTo(x, y);
        lcx = lcy = null;
      case 'H':
        x = ax(sc.number());
        path.lineTo(x, y);
        lcx = lcy = null;
      case 'V':
        y = ay(sc.number());
        path.lineTo(x, y);
        lcx = lcy = null;
      case 'C':
        final x1 = ax(sc.number()), y1 = ay(sc.number());
        final x2 = ax(sc.number()), y2 = ay(sc.number());
        final nx = ax(sc.number()), ny = ay(sc.number());
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        lcx = x2;
        lcy = y2;
        x = nx;
        y = ny;
      case 'S':
        final x1 = lcx == null ? x : 2 * x - lcx, y1 = lcy == null ? y : 2 * y - lcy!;
        final x2 = ax(sc.number()), y2 = ay(sc.number());
        final nx = ax(sc.number()), ny = ay(sc.number());
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        lcx = x2;
        lcy = y2;
        x = nx;
        y = ny;
      case 'Q':
        final x1 = ax(sc.number()), y1 = ay(sc.number());
        final nx = ax(sc.number()), ny = ay(sc.number());
        path.quadraticBezierTo(x1, y1, nx, ny);
        lcx = x1;
        lcy = y1;
        x = nx;
        y = ny;
      case 'T':
        final x1 = lcx == null ? x : 2 * x - lcx, y1 = lcy == null ? y : 2 * y - lcy!;
        final nx = ax(sc.number()), ny = ay(sc.number());
        path.quadraticBezierTo(x1, y1, nx, ny);
        lcx = x1;
        lcy = y1;
        x = nx;
        y = ny;
      case 'A':
        final rx = sc.number().abs(), ry = sc.number().abs();
        final rot = sc.number();
        final large = sc.flag(), sweep = sc.flag();
        final nx = ax(sc.number()), ny = ay(sc.number());
        if (rx == 0 || ry == 0) {
          path.lineTo(nx, ny);
        } else {
          path.arcToPoint(Offset(nx, ny),
              radius: Radius.elliptical(rx, ry),
              rotation: rot,
              largeArc: large,
              clockwise: sweep);
        }
        x = nx;
        y = ny;
        lcx = lcy = null;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        lcx = lcy = null;
    }
  }
  return path;
}
