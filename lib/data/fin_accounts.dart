import 'finance.dart';
import 'repository.dart';

/// Рахунки фінансів (гаманці): залишок = початкова сума + доходи - витрати
/// операцій рахунку + перекази на нього - перекази з нього. Зміна залишку
/// вручну записується звичайною операцією «Коригування рахунку»: мінус - це
/// витрата, плюс - дохід, тож різниця видна в статистиці.

/// Назва категорії, на яку йдуть коригування залишку.
const kFinAdjustName = 'Коригування рахунку';

const kFinDefaultAccountName = 'Готівка';

class FinAccount {
  final String id;
  final String name;
  final String icon;
  final String color;
  final double startBalance;

  /// Чи входить залишок у «Загалом».
  final bool inTotal;
  const FinAccount({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.startBalance,
    required this.inTotal,
  });

  factory FinAccount.fromRow(Map<String, Object?> r) => FinAccount(
        id: r['id'] as String,
        name: r['name'] as String,
        icon: (r['icon'] as String?) ?? 'payments',
        color: (r['color'] as String?) ?? 'honey',
        startBalance: (r['start_balance'] as num?)?.toDouble() ?? 0,
        inTotal: (r['in_total'] as int? ?? 1) == 1,
      );
}

class FinTransfer {
  final String id;
  final String fromId;
  final String toId;
  final double amount;
  final DateTime date;
  final String? comment;
  const FinTransfer({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.amount,
    required this.date,
    this.comment,
  });
}

double _secs(DateTime d) => d.microsecondsSinceEpoch / 1e6;
DateTime _dt(num secs) => DateTime.fromMicrosecondsSinceEpoch((secs * 1e6).round());

extension RepositoryFinAccounts on Repository {
  Future<List<FinAccount>> listFinAccounts() async {
    final rows = await db.query('fin_accounts',
        where: 'deleted = 0', orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(FinAccount.fromRow).toList();
  }

  /// Усі рахунки, зокрема видалені (для підписів у старих переказах).
  Future<Map<String, FinAccount>> finAccountMap() async {
    final rows = await db.query('fin_accounts');
    return {for (final r in rows) r['id'] as String: FinAccount.fromRow(r)};
  }

  /// Перший рахунок; якщо рахунків ще немає - створює «Готівку».
  Future<String> defaultFinAccountId() async {
    final list = await listFinAccounts();
    if (list.isNotEmpty) return list.first.id;
    return addFinAccount(kFinDefaultAccountName, icon: 'payments', color: 'honey');
  }

  Future<String> addFinAccount(String name,
      {String icon = 'payments',
      String color = 'honey',
      double startBalance = 0,
      bool inTotal = true}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'порожня назва');
    final id = Repository.newId();
    final r = await db.rawQuery('SELECT MAX(sort_order) AS m FROM fin_accounts');
    final order = ((r.first['m'] as int?) ?? -1) + 1;
    await db.insert('fin_accounts', {
      'id': id,
      'name': clean,
      'icon': icon,
      'color': color,
      'start_balance': startBalance,
      'in_total': inTotal ? 1 : 0,
      'sort_order': order,
      'updated_at': Repository.now(),
      'synced': 0,
    });
    return id;
  }

  Future<void> updateFinAccount(String id,
      {String? name, String? icon, String? color, bool? inTotal}) async {
    final f = <String, Object?>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (inTotal != null) 'in_total': inTotal ? 1 : 0,
    };
    if (f.isEmpty) return;
    await db.update('fin_accounts', {...f, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// М'яке видалення рахунку: його операції й перекази лишаються в журналі.
  Future<void> deleteFinAccount(String id) async {
    await db.update('fin_accounts', {'deleted': 1, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Залишки всіх рахунків: id -> сума.
  Future<Map<String, double>> finAccountBalances() async {
    final out = <String, double>{};
    for (final a in await db.query('fin_accounts', where: 'deleted = 0')) {
      out[a['id'] as String] = (a['start_balance'] as num?)?.toDouble() ?? 0;
    }
    final ops = await db.rawQuery('''
      SELECT account_id AS a, kind AS k, SUM(amount) AS s FROM fin_ops
      WHERE deleted = 0 AND cancelled = 0 AND account_id IS NOT NULL
      GROUP BY account_id, kind''');
    for (final r in ops) {
      final id = r['a'] as String;
      if (!out.containsKey(id)) continue;
      final s = (r['s'] as num?)?.toDouble() ?? 0;
      out[id] = out[id]! + (r['k'] == kFinIncome ? s : -s);
    }
    final tr = await db.rawQuery('''
      SELECT from_account_id AS f, to_account_id AS t, SUM(amount) AS s FROM fin_transfers
      WHERE deleted = 0 GROUP BY from_account_id, to_account_id''');
    for (final r in tr) {
      final s = (r['s'] as num?)?.toDouble() ?? 0;
      final f = r['f'] as String, t = r['t'] as String;
      if (out.containsKey(f)) out[f] = out[f]! - s;
      if (out.containsKey(t)) out[t] = out[t]! + s;
    }
    return out;
  }

  /// Нова сума рахунку вручну: різниця йде звичайною операцією (мінус -
  /// витрата, плюс - дохід) на категорію «Коригування рахунку».
  /// Повертає, на скільки змінився залишок (0 - нічого не змінено).
  Future<double> setFinAccountBalance(String id, double target) async {
    final current = (await finAccountBalances())[id] ?? 0;
    final diff = double.parse((target - current).toStringAsFixed(2));
    if (diff == 0) return 0;
    final kind = diff < 0 ? kFinExpense : kFinIncome;
    final cats = await listFinCategories(kind: kind);
    var catId = cats.where((c) => c.name == kFinAdjustName).map((c) => c.id).firstOrNull;
    catId ??= await addFinCategory(kFinAdjustName, kind, icon: 'scale', color: 'nut');
    await addFinOp(
        kind: kind,
        categoryId: catId,
        amount: diff.abs(),
        date: DateTime.now(),
        comment: kFinAdjustName,
        accountId: id);
    return diff;
  }

  Future<String> addFinTransfer({
    required String fromId,
    required String toId,
    required double amount,
    required DateTime date,
    String? comment,
  }) async {
    if (fromId == toId) throw ArgumentError('Рахунки збігаються');
    if (amount.isNaN || !(amount > 0)) throw ArgumentError.value(amount, 'amount', 'більше 0');
    final id = Repository.newId();
    final t = Repository.now();
    await db.insert('fin_transfers', {
      'id': id,
      'from_account_id': fromId,
      'to_account_id': toId,
      'amount': amount,
      'op_date': _secs(date),
      'comment': comment,
      'created_at': t,
      'updated_at': t,
      'synced': 0,
    });
    return id;
  }

  /// Перекази за період [from, to) - від нових до старих.
  Future<List<FinTransfer>> listFinTransfers({required DateTime from, required DateTime to}) async {
    final rows = await db.query('fin_transfers',
        where: 'deleted = 0 AND op_date >= ? AND op_date < ?',
        whereArgs: [_secs(from), _secs(to)],
        orderBy: 'op_date DESC');
    return [
      for (final r in rows)
        FinTransfer(
          id: r['id'] as String,
          fromId: r['from_account_id'] as String,
          toId: r['to_account_id'] as String,
          amount: (r['amount'] as num).toDouble(),
          date: _dt(r['op_date'] as num),
          comment: r['comment'] as String?,
        )
    ];
  }

  Future<void> deleteFinTransfer(String id) async {
    await db.update('fin_transfers', {'deleted': 1, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
  }
}
