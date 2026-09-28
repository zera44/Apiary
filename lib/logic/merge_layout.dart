/// Візуальне злиття сусідніх однакових клітинок в одну фігуру — спільне
/// для карти й редактора шаблону (порт cell_style.merge_layout).
library;

/// З яких боків клітинка злита з сусідом (вісь y — вгору: top = y + 1).
class Merge {
  final bool left, right, bottom, top;
  const Merge({this.left = false, this.right = false, this.bottom = false, this.top = false});

  bool get any => left || right || bottom || top;

  static const none = Merge();
}

class MergeItem<K> {
  final K id;
  final int x, y;

  /// Ознака "однаковості": зливаються лише клітинки з однаковим key.
  final String key;
  const MergeItem(this.id, this.x, this.y, this.key);
}

class MergeResult<K> {
  final Map<K, Merge> merges;

  /// Чи малює ця клітинка іконку (одна на фігуру).
  final Map<K, bool> iconDraw;

  /// Зсув іконки (у клітинках) від центру клітинки до центру фігури.
  final Map<K, (double, double)> iconOffset;

  /// Фігури — списки id злитих клітинок.
  final List<List<K>> components;

  const MergeResult(this.merges, this.iconDraw, this.iconOffset, this.components);
}

MergeResult<K> mergeLayout<K>(List<MergeItem<K>> items) {
  final byKey = <(int, int, String), MergeItem<K>>{};
  for (final it in items) {
    byKey[(it.x, it.y, it.key)] = it;
  }
  final merges = <K, Merge>{};
  for (final it in items) {
    merges[it.id] = Merge(
      left: byKey.containsKey((it.x - 1, it.y, it.key)),
      right: byKey.containsKey((it.x + 1, it.y, it.key)),
      bottom: byKey.containsKey((it.x, it.y - 1, it.key)),
      top: byKey.containsKey((it.x, it.y + 1, it.key)),
    );
  }

  final iconDraw = <K, bool>{};
  final iconOffset = <K, (double, double)>{};
  final components = <List<K>>[];
  final visited = <K>{};
  const dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];

  for (final it in items) {
    if (visited.contains(it.id)) continue;
    visited.add(it.id);
    final comp = <MergeItem<K>>[it];
    final stack = <MergeItem<K>>[it];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final (dx, dy) in dirs) {
        final nb = byKey[(cur.x + dx, cur.y + dy, cur.key)];
        if (nb != null && !visited.contains(nb.id)) {
          visited.add(nb.id);
          comp.add(nb);
          stack.add(nb);
        }
      }
    }
    components.add([for (final c in comp) c.id]);
    if (comp.length == 1) {
      iconDraw[it.id] = true;
      iconOffset[it.id] = (0.0, 0.0);
      continue;
    }
    var minX = comp.first.x, maxX = comp.first.x, minY = comp.first.y, maxY = comp.first.y;
    for (final c in comp) {
      if (c.x < minX) minX = c.x;
      if (c.x > maxX) maxX = c.x;
      if (c.y < minY) minY = c.y;
      if (c.y > maxY) maxY = c.y;
    }
    final isRect = comp.length == (maxX - minX + 1) * (maxY - minY + 1);
    double cx, cy;
    if (isRect) {
      // прямокутна фігура — іконка точно по центру
      cx = (minX + maxX + 1) / 2.0;
      cy = (minY + maxY + 1) / 2.0;
    } else {
      // фігура неправильної форми (Г, Т…): центр мас клітинок; іконка —
      // у центрі найближчої до нього клітинки, щоб не вилазити на траву
      cx = comp.fold<double>(0, (s, c) => s + c.x + 0.5) / comp.length;
      cy = comp.fold<double>(0, (s, c) => s + c.y + 0.5) / comp.length;
    }
    MergeItem<K>? rep;
    (double, int, int)? best;
    for (final c in comp) {
      final d = (c.x + 0.5 - cx) * (c.x + 0.5 - cx) + (c.y + 0.5 - cy) * (c.y + 0.5 - cy);
      final score = (d, c.y, c.x);
      if (best == null || _lessThan(score, best)) {
        best = score;
        rep = c;
      }
    }
    for (final c in comp) {
      final isRep = identical(c, rep);
      iconDraw[c.id] = isRep;
      iconOffset[c.id] =
          (isRep && isRect) ? (cx - (c.x + 0.5), cy - (c.y + 0.5)) : (0.0, 0.0);
    }
  }
  return MergeResult(merges, iconDraw, iconOffset, components);
}

bool _lessThan((double, int, int) a, (double, int, int) b) {
  if ((a.$1 - b.$1).abs() > 1e-9) return a.$1 < b.$1;
  if (a.$2 != b.$2) return a.$2 < b.$2;
  return a.$3 < b.$3;
}
