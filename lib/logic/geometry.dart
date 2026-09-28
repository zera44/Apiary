/// Цілочисельні операції над клітинками сітки (вісь y — вгору).
library;

typedef Cell = (int, int);

/// Поворот набору клітинок на 90° як жорсткої фігури — навколо лівого
/// нижнього кута її рамки: (col, row) -> (row, W-1-col). Без дробових
/// центрів і округлень, тож сусідство клітинок зберігається завжди
/// (див. коментар до rotate_group у старій версії).
Map<K, Cell> rotatedPositions<K>(Map<K, Cell> cells) {
  if (cells.isEmpty) return {};
  final first = cells.values.first;
  var minX = first.$1, minY = first.$2, maxX = first.$1;
  for (final (x, y) in cells.values) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
  }
  final oldW = maxX - minX + 1;
  return {
    for (final e in cells.entries)
      e.key: (minX + (e.value.$2 - minY), minY + (oldW - 1) - (e.value.$1 - minX)),
  };
}
