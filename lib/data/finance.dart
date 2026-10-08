import 'package:sqflite/sqflite.dart';

import 'repository.dart';

/// Фінанси: довідник категорій, витрати/доходи з таблицею рядків.
///
/// Єдине джерело правди про товар - склад: рядок витрати з «на склад» створює
/// звичайний прихід (stock_moves), а в рядку лише посилання на нього
/// (stock_move_id). Прихід, внесений просто на складі, у фінансах з'являється
/// сам - як витрата «внесено на складі». Скасування в будь-якому з двох місць
/// скасовує й друге.

const kFinExpense = 'expense';
const kFinIncome = 'income';


class FinCategory {
  final String id;
  final String name;
  final String kind;

  /// Позиції таблиці витрати з цієї категорії за замовчуванням йдуть на склад.
  final bool toStock;
  final String icon;
  final String color;
  final bool deleted;
  const FinCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.toStock,
    required this.icon,
    required this.color,
    this.deleted = false,
  });

  bool get isExpense => kind == kFinExpense;

  factory FinCategory.fromRow(Map<String, Object?> r) => FinCategory(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: r['kind'] as String,
        toStock: (r['to_stock'] as int? ?? 0) == 1,
        icon: (r['icon'] as String?) ?? 'other',
        color: (r['color'] as String?) ?? 'honey',
        deleted: (r['deleted'] as int? ?? 0) == 1,
      );
}

/// Рядок таблиці, який вводить користувач.
class FinLineInput {
  final String name;
  final double qty;
  final String unit;
  final double price;
  final bool toStock;
  const FinLineInput({
    required this.name,
    required this.qty,
    required this.unit,
    required this.price,
    this.toStock = false,
  });

  double get total => qty * price;
}

/// Запис у журналі фінансів: власна операція або прихід, внесений на складі.
class FinEntry {
  /// Для власної операції - id fin_ops, для складської - id stock_moves.
  final String id;
  final String kind;
  final String? categoryId;
  final double amount;
  final DateTime date;
  final String title;
  final int lineCount;
  final String? comment;
  final bool cancelled;

  /// Внесено прямо на складі (витрата без довідника категорій).
  final bool fromStock;
  const FinEntry({
    required this.id,
    required this.kind,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.title,
    required this.lineCount,
    required this.cancelled,
    required this.fromStock,
    this.comment,
  });

  bool get isExpense => kind == kFinExpense;
}

/// Підсумок за період (скасовані записи не рахуються).
class FinSummary {
  final double income;
  final double expense;

  /// Витрати за категоріями (ключ null - «внесено на складі»).
  final Map<String?, double> expenseByCategory;
  final Map<String?, double> incomeByCategory;
  const FinSummary(this.income, this.expense, this.expenseByCategory, this.incomeByCategory);

  double get balance => income - expense;

  factory FinSummary.of(Iterable<FinEntry> entries) {
    var inc = 0.0, exp = 0.0;
    final eb = <String?, double>{}, ib = <String?, double>{};
    for (final e in entries) {
      if (e.cancelled) continue;
      if (e.isExpense) {
        exp += e.amount;
        eb[e.categoryId] = (eb[e.categoryId] ?? 0) + e.amount;
      } else {
        inc += e.amount;
        ib[e.categoryId] = (ib[e.categoryId] ?? 0) + e.amount;
      }
    }
    return FinSummary(inc, exp, eb, ib);
  }
}

double _secs(DateTime d) => d.microsecondsSinceEpoch / 1e6;
DateTime _dt(num secs) => DateTime.fromMicrosecondsSinceEpoch((secs * 1e6).round());

/// Початкові категорії (створюються один раз).
const _seed = <(String, String, bool, String, String)>[
  ('Корми', kFinExpense, true, 'feed', 'honey'),
  ('Ліки', kFinExpense, true, 'medicine', 'olive'),
  ('Рамки', kFinExpense, true, 'frame', 'nut'),
  ('Дорога', kFinExpense, false, 'car', 'sky'),
  ('Ремонт', kFinExpense, false, 'tool', 'terra'),
  ('Продаж меду', kFinIncome, true, 'honey', 'honey'),
  ('Інший дохід', kFinIncome, false, 'other', 'olive'),
];

/// Густина меду: 1 л = 1,4 кг (продаж у літрах списує кілограми).
const kHoneyDensity = 1.4;

bool _isKgL(String a, String b) {
  final x = a.trim().toLowerCase(), y = b.trim().toLowerCase();
  return (x == 'л' && y == 'кг') || (x == 'кг' && y == 'л');
}

bool _unitsMatch(String lineUnit, String stockUnit) =>
    lineUnit.trim().toLowerCase() == stockUnit.trim().toLowerCase() || _isKgL(lineUnit, stockUnit);

/// Кількість у одиницях складу ([qty] - у одиницях рядка; кг і л перераховуються).
double stockQty(String lineUnit, String stockUnit, double qty) {
  if (!_isKgL(lineUnit, stockUnit)) return qty;
  return lineUnit.trim().toLowerCase() == 'л' ? qty * kHoneyDensity : qty / kHoneyDensity;
}

extension RepositoryFinance on Repository {
  // ---------------------------------------------------------------- категорії

  Future<void> seedFinanceCategories() async {
    const key = 'fin_seed_v1';
    if (await getMeta(key) != null) {
      // v2: «Продаж меду» списує мед зі складу
      if (await getMeta('fin_seed_v2') == null) {
        await db.update('fin_categories', {'to_stock': 1, 'updated_at': Repository.now(), 'synced': 0},
            where: "name = 'Продаж меду' AND kind = 'income' AND deleted = 0");
        await setMeta('fin_seed_v2', '1');
      }
      return;
    }
    var order = 0;
    for (final s in _seed) {
      await addFinCategory(s.$1, s.$2, toStock: s.$3, icon: s.$4, color: s.$5, sortOrder: order++);
    }
    await setMeta(key, '1');
    await setMeta('fin_seed_v2', '1');
  }

  Future<List<FinCategory>> listFinCategories({String? kind}) async {
    final rows = await db.query('fin_categories',
        where: kind == null ? 'deleted = 0' : 'deleted = 0 AND kind = ?',
        whereArgs: kind == null ? null : [kind],
        orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(FinCategory.fromRow).toList();
  }

  /// Усі категорії, зокрема видалені (для підписів у старих записах).
  Future<Map<String, FinCategory>> finCategoryMap() async {
    final rows = await db.query('fin_categories');
    return {for (final r in rows) r['id'] as String: FinCategory.fromRow(r)};
  }

  Future<String> addFinCategory(String name, String kind,
      {bool toStock = false, String icon = 'other', String color = 'honey', int? sortOrder}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'порожня назва');
    final id = Repository.newId();
    final t = Repository.now();
    var order = sortOrder;
    if (order == null) {
      final r = await db.rawQuery('SELECT MAX(sort_order) AS m FROM fin_categories');
      order = ((r.first['m'] as int?) ?? -1) + 1;
    }
    await db.insert('fin_categories', {
      'id': id,
      'name': clean,
      'kind': kind,
      'to_stock': toStock ? 1 : 0,
      'icon': icon,
      'color': color,
      'sort_order': order,
      'updated_at': t,
      'synced': 0,
    });
    return id;
  }

  Future<void> updateFinCategory(String id,
      {String? name, bool? toStock, String? icon, String? color}) async {
    final f = <String, Object?>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (toStock != null) 'to_stock': toStock ? 1 : 0,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
    };
    if (f.isEmpty) return;
    await db.update('fin_categories', {...f, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// М'яке видалення: у старих операціях назва лишається.
  Future<void> deleteFinCategory(String id) async {
    await db.update('fin_categories', {'deleted': 1, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- операції

  /// Нова операція. Для витрати рядки з `toStock` одразу стають приходом на
  /// складі (нова номенклатура створюється, наявна - за назвою - поповнюється);
  /// усе в одній транзакції: або все, або нічого. Повертає id операції.
  Future<String> addFinOp({
    required String kind,
    required String? categoryId,
    required double amount,
    required DateTime date,
    List<FinLineInput> lines = const [],
    String? comment,
  }) async {
    if (kind != kFinExpense && kind != kFinIncome) throw ArgumentError.value(kind, 'kind');
    if (amount.isNaN || amount < 0) throw ArgumentError.value(amount, 'amount', 'не менше 0');
    for (final l in lines) {
      if (l.name.trim().isEmpty || !(l.qty > 0) || l.price.isNaN || l.price < 0) {
        throw ArgumentError('Рядок «${l.name}»: потрібні назва, кількість більше 0 і ціна');
      }
    }
    final opId = Repository.newId();
    var touchedStock = false;
    await db.transaction((txn) async {
      final t = Repository.now();
      await txn.insert('fin_ops', {
        'id': opId,
        'kind': kind,
        'category_id': categoryId,
        'amount': amount,
        'op_date': _secs(date),
        'comment': comment,
        'created_at': t,
        'updated_at': t,
        'synced': 0,
      });
      final byName = <String, Map<String, Object?>>{};
      for (final r in await txn.query('stock_items', where: 'deleted = 0')) {
        byName.putIfAbsent((r['name'] as String).trim().toLowerCase(), () => r);
      }
      for (final l in lines) {
        final stock = l.toStock;
        String? itemId, moveId, unit = l.unit;
        if (stock && kind == kFinExpense) {
          touchedStock = true;
          final key = l.name.trim().toLowerCase();
          final found = byName[key];
          if (found == null) {
            itemId = Repository.newId();
            await txn.insert('stock_items', {
              'id': itemId,
              'name': l.name.trim(),
              'unit': l.unit.trim(),
              'created_at': t,
              'updated_at': t,
              'synced': 0,
            });
            byName[key] = {'id': itemId, 'name': l.name.trim(), 'unit': l.unit.trim()};
          } else {
            itemId = found['id'] as String;
            unit = found['unit'] as String; // одиниця наявної номенклатури незмінна
          }
          final rows = await txn.query('stock_items',
              columns: ['quantity'], where: 'id = ?', whereArgs: [itemId], limit: 1);
          final prev = (rows.first['quantity'] as num?)?.toDouble() ?? 0;
          final next = prev + l.qty;
          moveId = Repository.newId();
          await txn.update('stock_items', {'quantity': next, 'updated_at': t, 'synced': 0},
              where: 'id = ?', whereArgs: [itemId]);
          await txn.insert('stock_moves', {
            'id': moveId,
            'item_id': itemId,
            'kind': 'in',
            'amount': l.qty,
            'quantity_after': next,
            'op_date': _secs(date),
            'total': l.total,
            'price': l.price,
            'comment': 'Фінанси',
            'created_at': t,
            'updated_at': t,
            'synced': 0,
          });
        } else if (stock) {
          // продаж: списання зі складу (товар має бути на складі й у потрібній кількості)
          touchedStock = true;
          final found = byName[l.name.trim().toLowerCase()];
          if (found == null) {
            throw StateError('«${l.name.trim()}» немає на складі - спершу додайте прихід '
                '(наприклад, відкачали мед) або зніміть позначку «зі складу».');
          }
          itemId = found['id'] as String;
          final rows = await txn.query('stock_items',
              columns: ['quantity', 'unit'], where: 'id = ?', whereArgs: [itemId], limit: 1);
          final stockUnit = rows.first['unit'] as String;
          if (!_unitsMatch(l.unit, stockUnit)) {
            throw StateError('«${l.name.trim()}» на складі в одиницях «$stockUnit», '
                'а в продажі «${l.unit}». Продавати можна в тих самих одиницях '
                '(кг і л перераховуються: 1 л = $kHoneyDensity кг).');
          }
          final q = stockQty(l.unit, stockUnit, l.qty);
          final prev = (rows.first['quantity'] as num?)?.toDouble() ?? 0;
          moveId = Repository.newId();
          if (q > prev + 1e-9) {
            // продаємо більше, ніж записано: спершу коригування (переоблік,
            // надлишок), щоб залишок на складі відповідав дійсності
            await txn.insert('stock_moves', {
              'id': Repository.newId(),
              'item_id': itemId,
              'kind': 'inv',
              'amount': q - prev,
              'quantity_after': q,
              'op_date': _secs(date),
              'comment': 'Коригування під час продажу',
              'ref_id': moveId, // пов'язано з продажем: скасовуються разом
              'created_at': t,
              'updated_at': t,
              'synced': 0,
            });
          }
          var next = (q > prev ? q : prev) - q;
          if (next.abs() < 1e-9) next = 0;
          await txn.update('stock_items', {'quantity': next, 'updated_at': t, 'synced': 0},
              where: 'id = ?', whereArgs: [itemId]);
          await txn.insert('stock_moves', {
            'id': moveId,
            'item_id': itemId,
            'kind': 'out',
            'amount': q,
            'quantity_after': next,
            'op_date': _secs(date),
            'reason': 'Продаж',
            'comment': 'Фінанси',
            'created_at': t + 0.000001,
            'updated_at': t,
            'synced': 0,
          });
        }
        await txn.insert('fin_lines', {
          'id': Repository.newId(),
          'op_id': opId,
          'name': l.name.trim(),
          'qty': l.qty,
          'unit': unit,
          'price': l.price,
          'to_stock': stock ? 1 : 0,
          'stock_item_id': itemId,
          'stock_move_id': moveId,
          'updated_at': t,
          'synced': 0,
        });
      }
    });
    if (touchedStock) stockChanges.value++;
    return opId;
  }

  /// Скасувати запис журналу. Власна операція: скасовуються і її приходи на
  /// складі (якщо частину вже списано - помилка й нічого не змінюється).
  /// Прихід, внесений на складі: скасовується він (і операція, якщо була).
  Future<void> cancelFinEntry(FinEntry e) async {
    if (e.fromStock) {
      await cancelStockMove(e.id);
      return;
    }
    var touched = false;
    await db.transaction((txn) async {
      final ops = await txn.query('fin_ops', where: 'id = ?', whereArgs: [e.id], limit: 1);
      if (ops.isEmpty) throw StateError('Запис не знайдено');
      if ((ops.first['cancelled'] as int? ?? 0) == 1) throw StateError('Цей запис уже скасовано');
      final lines = await txn.query('fin_lines',
          where: 'op_id = ? AND deleted = 0 AND stock_move_id IS NOT NULL', whereArgs: [e.id]);
      for (final l in lines) {
        final mv = await txn.query('stock_moves',
            columns: ['cancelled'], where: 'id = ?', whereArgs: [l['stock_move_id']], limit: 1);
        if (mv.isNotEmpty && (mv.first['cancelled'] as int? ?? 0) == 0) {
          await cancelStockMoveTx(txn, l['stock_move_id'] as String);
          await _cancelFixTx(txn, l['stock_move_id'] as String);
          touched = true;
        }
      }
      await txn.update('fin_ops', {'cancelled': 1, 'updated_at': Repository.now(), 'synced': 0},
          where: 'id = ?', whereArgs: [e.id]);
    });
    if (touched) stockChanges.value++;
  }

  /// Коригування (переоблік), що було зроблено разом із продажем [moveId], скасовується з ним.
  Future<void> _cancelFixTx(DatabaseExecutor txn, String moveId) async {
    final fixes = await txn.query('stock_moves',
        where: "kind = 'inv' AND ref_id = ? AND cancelled = 0", whereArgs: [moveId]);
    for (final f in fixes) {
      await cancelStockMoveTx(txn, f['id'] as String);
    }
  }

  /// Викликається зі складу, коли скасовано прихід: якщо він належав операції
  /// фінансів - операція скасовується разом з усіма її приходами.
  Future<void> finCascadeStockCancelTx(DatabaseExecutor txn, String moveId) async {
    final links = await txn.query('fin_lines',
        columns: ['op_id'], where: 'stock_move_id = ? AND deleted = 0', whereArgs: [moveId]);
    final opIds = {for (final r in links) r['op_id'] as String};
    for (final opId in opIds) {
      final ops = await txn.query('fin_ops', where: 'id = ?', whereArgs: [opId], limit: 1);
      if (ops.isEmpty || (ops.first['cancelled'] as int? ?? 0) == 1) continue;
      final lines = await txn.query('fin_lines',
          where: 'op_id = ? AND deleted = 0 AND stock_move_id IS NOT NULL AND stock_move_id <> ?',
          whereArgs: [opId, moveId]);
      for (final l in lines) {
        final mv = await txn.query('stock_moves',
            columns: ['cancelled'], where: 'id = ?', whereArgs: [l['stock_move_id']], limit: 1);
        if (mv.isNotEmpty && (mv.first['cancelled'] as int? ?? 0) == 0) {
          await cancelStockMoveTx(txn, l['stock_move_id'] as String);
          await _cancelFixTx(txn, l['stock_move_id'] as String);
        }
      }
      await _cancelFixTx(txn, moveId);
      await txn.update('fin_ops', {'cancelled': 1, 'updated_at': Repository.now(), 'synced': 0},
          where: 'id = ?', whereArgs: [opId]);
    }
  }

  /// Журнал за період [from, to) - від нових до старих.
  Future<List<FinEntry>> listFinEntries({required DateTime from, required DateTime to}) async {
    final a = _secs(from), b = _secs(to);
    final out = <FinEntry>[];

    final ops = await db.query('fin_ops',
        where: 'deleted = 0 AND op_date >= ? AND op_date < ?', whereArgs: [a, b]);
    final lineRows = ops.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query('fin_lines',
            where: 'deleted = 0 AND op_id IN (${List.filled(ops.length, '?').join(',')})',
            whereArgs: [for (final o in ops) o['id']],
            orderBy: 'rowid');
    final byOp = <String, List<Map<String, Object?>>>{};
    for (final l in lineRows) {
      byOp.putIfAbsent(l['op_id'] as String, () => []).add(l);
    }
    for (final o in ops) {
      final ls = byOp[o['id']] ?? const <Map<String, Object?>>[];
      out.add(FinEntry(
        id: o['id'] as String,
        kind: o['kind'] as String,
        categoryId: o['category_id'] as String?,
        amount: (o['amount'] as num).toDouble(),
        date: _dt(o['op_date'] as num),
        title: ls.map((l) => l['name'] as String).join(', '),
        lineCount: ls.length,
        comment: o['comment'] as String?,
        cancelled: (o['cancelled'] as int? ?? 0) == 1,
        fromStock: false,
      ));
    }

    // приходи, внесені на складі (не прив'язані до жодної операції)
    final moves = await db.rawQuery('''
      SELECT m.id, m.amount, m.total, m.comment, m.cancelled,
             COALESCE(m.op_date, m.created_at) AS d, i.name AS name, i.unit AS unit
      FROM stock_moves m JOIN stock_items i ON i.id = m.item_id
      WHERE m.kind = 'in' AND m.deleted = 0
        AND COALESCE(m.op_date, m.created_at) >= ? AND COALESCE(m.op_date, m.created_at) < ?
        AND m.id NOT IN (SELECT stock_move_id FROM fin_lines WHERE stock_move_id IS NOT NULL)
    ''', [a, b]);
    for (final m in moves) {
      out.add(FinEntry(
        id: m['id'] as String,
        kind: kFinExpense,
        categoryId: null,
        amount: (m['total'] as num?)?.toDouble() ?? 0,
        date: _dt(m['d'] as num),
        title: m['name'] as String,
        lineCount: 1,
        comment: m['comment'] as String?,
        cancelled: (m['cancelled'] as int? ?? 0) == 1,
        fromStock: true,
      ));
    }
    out.sort((x, y) => y.date.compareTo(x.date));
    return out;
  }

  /// Останні ціни приходу за одиницю: id номенклатури -> ціна (для позначки «перевір»).
  Future<Map<String, double>> lastStockPrices() async {
    final rows = await db.rawQuery('''
      SELECT item_id, price FROM stock_moves
      WHERE kind = 'in' AND cancelled = 0 AND deleted = 0 AND price IS NOT NULL AND price > 0
      ORDER BY COALESCE(op_date, created_at), created_at
    ''');
    return {for (final r in rows) r['item_id'] as String: (r['price'] as num).toDouble()};
  }
}
