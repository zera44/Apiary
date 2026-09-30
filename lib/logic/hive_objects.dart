/// "Об'єкти" карти: злиті в одну фігуру сусідні однакові клітинки однієї
/// групи (напр., вулик-лежак на 2 клітинки). QR-код, назва на наліпці й
/// вибір у генераторі кодів — на весь об'єкт, а не на окрему клітинку.
library;

import '../data/models.dart';
import 'merge_layout.dart';

/// Ознака злиття: зливаються лише однакові на вигляд клітинки ОДНІЄЇ групи.
/// Спільна для карти, генератора QR і наліпок.
String mergeKeyOf(MapElement e) =>
    '${e.groupId ?? e.id}|${e.type}|${e.isHive ? '' : (e.variant ?? '')}|${e.icon ?? ''}|${e.color ?? ''}';

/// Порядок "зверху вниз, зліва направо".
int compareTopLeft(MapElement a, MapElement b) =>
    a.y != b.y ? b.y.compareTo(a.y) : a.x.compareTo(b.x);

/// Вулики [all], згруповані в об'єкти. Клітинки кожного об'єкта впорядковані
/// зверху вниз, зліва направо; перша — "головна" (до неї чіпляється код).
/// Самі об'єкти — теж у цьому порядку за головною клітинкою.
List<List<MapElement>> hiveObjects(List<MapElement> all) {
  final hives = [for (final e in all) if (e.isHive) e];
  final byId = {for (final e in hives) e.id: e};
  final res = mergeLayout([for (final e in hives) MergeItem<String>(e.id, e.x, e.y, mergeKeyOf(e))]);
  final out = [
    for (final comp in res.components) [for (final id in comp) byId[id]!]..sort(compareTopLeft)
  ]..sort((a, b) => compareTopLeft(a.first, b.first));
  return out;
}

/// Об'єкт, до якого належить вулик [el] (щонайменше сам [el]).
List<MapElement> hiveObjectOf(MapElement el, List<MapElement> all) {
  for (final o in hiveObjects(all)) {
    if (o.any((e) => e.id == el.id)) return o;
  }
  return [el];
}

/// Злитий об'єкт (вулик чи перешкода), до якого належить [el]: сусідні
/// однакові клітинки ТІЄЇ Ж групи. Для одиночного об'єкта — лише [el].
List<MapElement> mergedObjectOf(MapElement el, List<MapElement> all) {
  if (el.groupId == null) return [el];
  final same = [for (final e in all) if (e.groupId == el.groupId) e];
  if (!same.any((e) => e.id == el.id)) return [el];
  final byId = {for (final e in same) e.id: e};
  final res = mergeLayout([for (final e in same) MergeItem<String>(e.id, e.x, e.y, mergeKeyOf(e))]);
  for (final comp in res.components) {
    if (comp.contains(el.id)) return [for (final id in comp) byId[id]!]..sort(compareTopLeft);
  }
  return [el];
}
