import 'package:sqflite/sqflite.dart';

import 'repository.dart';

/// Дії з базою, потрібні синхронізації (етап 5).
extension RepositorySync on Repository {
  /// Залишок номенклатури [itemIds] - заново з її рухів (у порядку
  /// створення). Рухи з різних телефонів сходяться на сервері, а залишок
  /// («останній записаний») - ні: якщо два телефони одночасно додали
  /// прихід, правильний залишок дає лише сума рухів. Позначку «відправлено»
  /// не чіпаємо: кожен телефон рахує те саме з тих самих рухів.
  Future<int> recomputeStock(Iterable<String> itemIds) async {
    var changed = 0;
    await db.transaction((txn) async {
      for (final id in itemIds.toSet()) {
        final moves = await txn.query('stock_moves',
            columns: ['kind', 'amount'],
            where: 'item_id = ? AND deleted = 0',
            whereArgs: [id],
            orderBy: 'created_at, rowid');
        if (moves.isEmpty) continue;
        var q = 0.0;
        for (final m in moves) {
          final a = (m['amount'] as num?)?.toDouble() ?? 0;
          switch (m['kind']) {
            case 'set': // старий запис «перезаписано» - сам залишок
              q = a;
            case 'out':
              q -= a;
            default: // in, add, inv (різниця зі знаком), cancel (зі знаком)
              q += a;
          }
        }
        if (q.abs() < 1e-9) q = 0;
        final row = await txn.query('stock_items', columns: ['quantity'], where: 'id = ?', whereArgs: [id]);
        if (row.isEmpty) continue;
        final prev = (row.first['quantity'] as num?)?.toDouble() ?? 0;
        if ((prev - q).abs() > 1e-9) {
          await txn.update('stock_items', {'quantity': q}, where: 'id = ?', whereArgs: [id]);
          changed++;
        }
      }
    });
    if (changed > 0) stockChanges.value++;
    return changed;
  }

  /// Записи, які помічник зробив у даних власника, - власнику.
  ///
  /// Помічник працює в пасіці власника своїми характеристиками й мітками
  /// (базові «Огляд», «Сила» тощо - у кожного свої). Перед відправкою записи
  /// в пасіках власника переводимо на характеристики й мітки САМЕ ВЛАСНИКА
  /// (ту саму типову - за сталим ключем, свою - за назвою й типом; немає -
  /// копія для власника), інакше власник отримав би записи з невідомою
  /// йому характеристикою. Повертає, скільки записів переведено.
  Future<int> adoptForeignRefs() async {
    var moved = 0;
    final t = Repository.now();
    await db.transaction((txn) async {
      // склад і фінанси: рух чужої позиції, рядок чужої операції, операція
      // з чужою категорією - теж того власника (інакше на сервері вони
      // стали б моїми, і власник їх не побачив би)
      for (final (tbl, ref, parent) in const [
        ('stock_moves', 'item_id', 'stock_items'),
        ('fin_ops', 'category_id', 'fin_categories'),
        ('fin_lines', 'op_id', 'fin_ops'),
      ]) {
        moved += await txn.rawUpdate(
            'UPDATE $tbl SET owner_id = (SELECT x.owner_id FROM $parent x WHERE x.id = $tbl.$ref) '
            'WHERE owner_id IS NULL AND synced = 0 AND $ref IN (SELECT id FROM $parent WHERE owner_id IS NOT NULL)');
      }
      final owners = [
        for (final r in await txn.rawQuery(
            'SELECT DISTINCT owner_id FROM apiaries WHERE owner_id IS NOT NULL AND deleted = 0'))
          r['owner_id']! as String
      ];
      for (final owner in owners) {
        const inOwner = 'apiary_id IN (SELECT id FROM apiaries WHERE owner_id = ?)';
        // характеристики: прив'язки й історія
        final params = {
          for (final tbl in const ['element_parameters', 'parameter_records'])
            for (final r in await txn.rawQuery(
                'SELECT DISTINCT x.parameter_id AS id FROM $tbl x JOIN parameters p ON p.id = x.parameter_id '
                'WHERE x.$inOwner AND p.owner_id IS NOT ?',
                [owner, owner]))
              r['id']! as String,
        };
        for (final pid in params) {
          final target = await _ownerCopy(txn, 'parameters', pid, owner, t,
              match: const ['name', 'data_type']);
          moved += await txn.rawUpdate(
              'UPDATE element_parameters SET parameter_id = ?, updated_at = ?, synced = 0 '
              'WHERE parameter_id = ? AND $inOwner',
              [target, t, pid, owner]);
          moved += await txn.rawUpdate(
              'UPDATE parameter_records SET parameter_id = ?, synced = 0 WHERE parameter_id = ? AND $inOwner',
              [target, pid, owner]);
        }
        // мітки нотаток
        final labels = [
          for (final r in await txn.rawQuery(
              'SELECT DISTINCT n.label_id AS id FROM hive_notes n JOIN note_labels l ON l.id = n.label_id '
              'WHERE n.$inOwner AND l.owner_id IS NOT ?',
              [owner, owner]))
            r['id']! as String
        ];
        for (final lid in labels) {
          final target = await _ownerCopy(txn, 'note_labels', lid, owner, t, match: const ['name']);
          moved += await txn.rawUpdate(
              'UPDATE hive_notes SET label_id = ?, updated_at = ?, synced = 0 WHERE label_id = ? AND $inOwner',
              [target, t, lid, owner]);
        }
      }
    });
    if (moved > 0) notifyAllChanged();
    return moved;
  }

  /// Відповідник рядка [id] таблиці [table] у власника [owner]: за сталим
  /// ключем або за колонками [match]; немає - копія для власника.
  static Future<String> _ownerCopy(DatabaseExecutor txn, String table, String id, String owner, double t,
      {required List<String> match}) async {
    final src = (await txn.query(table, where: 'id = ?', whereArgs: [id])).single;
    final seed = src['seed_key'] as String?;
    final same = await txn.query(table,
        columns: ['id'],
        where: seed != null
            ? 'owner_id = ? AND deleted = 0 AND seed_key = ?'
            : 'owner_id = ? AND deleted = 0 AND ${[for (final c in match) '$c IS ?'].join(' AND ')}',
        whereArgs: seed != null ? [owner, seed] : [owner, for (final c in match) src[c]],
        orderBy: 'id',
        limit: 1);
    if (same.isNotEmpty) return same.first['id']! as String;
    final copy = Repository.newId();
    await txn.insert(table, {
      ...src,
      'id': copy,
      'owner_id': owner,
      'updated_at': t,
      'synced': 0,
      'deleted': 0,
    });
    return copy;
  }

  /// Привести дані на телефоні у відповідність до доступу: пасіки
  /// власників, до яких доступ забрали, - прибрати (без позначок
  /// «видалено»); склад і фінанси власника без дозволу - теж. Повертає
  /// сигнатуру доступу (змінилась - отримати чужі дані заново).
  Future<String> applyAccess(String myUserId) async {
    final mine = await db.query('apiary_members',
        where: 'user_id = ? AND deleted = 0', whereArgs: [myUserId], orderBy: 'id');
    bool covers(String owner, String apiary) => mine.any((m) =>
        m['owner_id'] == owner && (m['apiary_id'] == null || m['apiary_id'] == apiary));
    for (final a in await db.query('apiaries', columns: ['id', 'owner_id'], where: 'owner_id IS NOT NULL')) {
      if (!covers(a['owner_id']! as String, a['id']! as String)) await evictApiary(a['id']! as String);
    }
    // склад і фінанси - лише з дозволом
    const stockTables = ['stock_moves', 'stock_items', 'fin_lines', 'fin_ops', 'fin_categories'];
    final stockOwners = {for (final m in mine) if (m['stock_access'] == 1) m['owner_id']};
    var dropped = 0;
    await db.transaction((txn) async {
      for (final t in stockTables) {
        final owners = [
          for (final r in await txn.rawQuery('SELECT DISTINCT owner_id FROM $t WHERE owner_id IS NOT NULL'))
            r['owner_id'],
        ];
        for (final o in owners) {
          if (!stockOwners.contains(o)) dropped += await txn.delete(t, where: 'owner_id = ?', whereArgs: [o]);
        }
      }
    });
    if (dropped > 0) stockChanges.value++;
    return [for (final m in mine) '${m['id']}:${m['stock_access']}'].join(',');
  }
}
