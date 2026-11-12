import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../logic/fin_import.dart';
import 'fin_accounts.dart';
import 'finance.dart';
import 'repository.dart';

const _colors = ['honey', 'olive', 'terra', 'light', 'nut', 'sky', 'plum'];
const _accountIcons = ['payments', 'card', 'bank', 'savings', 'wallet', 'safe'];

/// Що додасть імпорт (до запису): нові рахунки й категорії.
class FinImportPlan {
  final List<String> newAccounts;
  final List<String> newCategories;
  const FinImportPlan(this.newAccounts, this.newCategories);
}

class FinImportResult {
  final int added;

  /// Уже були в базі (той самий файл імпортують повторно).
  final int duplicates;
  const FinImportResult(this.added, this.duplicates);
}

String _norm(String s) => s.trim().toLowerCase();

extension RepositoryFinImport on Repository {
  Future<FinImportPlan> planFinImport(FinImportData data) async {
    final accounts = {for (final a in await listFinAccounts()) _norm(a.name)};
    final cats = {
      for (final c in await listFinCategories()) '${c.kind}|${_norm(c.name)}',
    };
    final newAcc = <String>{}, newCat = <String>{};
    void account(String n) {
      if (!accounts.contains(_norm(n))) newAcc.add(n.trim());
    }

    for (final o in data.ops) {
      account(o.account);
      final kind = o.expense ? kFinExpense : kFinIncome;
      if (!cats.contains('$kind|${_norm(o.category)}')) newCat.add('${o.expense ? '−' : '+'} ${o.category}');
    }
    for (final t in data.transfers) {
      account(t.from);
      account(t.to);
    }
    return FinImportPlan(newAcc.toList(), newCat.toList());
  }

  /// Записує дані з файла: потрібні рахунки й категорії створюються, наявні
  /// (за назвою) беруться. Один і той самий файл удруге дублів не дає.
  Future<FinImportResult> importFinData(FinImportData data) async {
    var saved = await getMeta('fin_import_salt');
    if (saved == null) {
      saved = Repository.newId();
      await setMeta('fin_import_salt', saved);
    }
    final salt = saved;
    String idOf(String key) => 'fi-${sha1.convert(utf8.encode(salt + key)).toString().substring(0, 32)}';

    final accounts = {for (final a in await listFinAccounts()) _norm(a.name): a.id};
    Future<String> account(String name) async {
      final k = _norm(name);
      final found = accounts[k];
      if (found != null) return found;
      final n = accounts.length;
      return accounts[k] = await addFinAccount(name,
          icon: _accountIcons[n % _accountIcons.length], color: _colors[n % _colors.length]);
    }

    final cats = {
      for (final c in await listFinCategories()) '${c.kind}|${_norm(c.name)}': c.id,
    };
    Future<String> category(String name, bool expense) async {
      final kind = expense ? kFinExpense : kFinIncome;
      final k = '$kind|${_norm(name)}';
      final found = cats[k];
      if (found != null) return found;
      return cats[k] = await addFinCategory(name, kind, color: _colors[cats.length % _colors.length]);
    }

    final haveOps = {
      for (final r in await db.query('fin_ops', columns: ['id'], where: "id LIKE 'fi-%'")) r['id'] as String,
    };
    final haveTransfers = {
      for (final r in await db.query('fin_transfers', columns: ['id'], where: "id LIKE 'fi-%'"))
        r['id'] as String,
    };

    // довідники - до запису операцій (рахунок/категорія мають уже існувати)
    final rowsOps = <Map<String, Object?>>[];
    final rowsTransfers = <Map<String, Object?>>[];
    var duplicates = 0;
    final t = Repository.now();
    double secs(DateTime d) => DateTime(d.year, d.month, d.day, 12).microsecondsSinceEpoch / 1e6;
    for (final o in data.ops) {
      final id = idOf(o.key);
      if (haveOps.contains(id)) {
        duplicates++;
        continue;
      }
      rowsOps.add({
        'id': id,
        'kind': o.expense ? kFinExpense : kFinIncome,
        'category_id': await category(o.category, o.expense),
        'account_id': await account(o.account),
        'amount': o.amount,
        'op_date': secs(o.date),
        'comment': o.comment.isEmpty ? null : o.comment,
        'created_at': t,
        'updated_at': t,
        'synced': 0,
      });
    }
    for (final x in data.transfers) {
      final id = idOf(x.key);
      if (haveTransfers.contains(id)) {
        duplicates++;
        continue;
      }
      rowsTransfers.add({
        'id': id,
        'from_account_id': await account(x.from),
        'to_account_id': await account(x.to),
        'amount': x.amount,
        'op_date': secs(x.date),
        'comment': x.comment.isEmpty ? null : x.comment,
        'created_at': t,
        'updated_at': t,
        'synced': 0,
      });
    }
    await db.transaction((txn) async {
      final b = txn.batch();
      for (final r in rowsOps) {
        b.insert('fin_ops', r, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final r in rowsTransfers) {
        b.insert('fin_transfers', r, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await b.commit(noResult: true);
    });
    return FinImportResult(rowsOps.length + rowsTransfers.length, duplicates);
  }
}
