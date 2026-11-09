import 'package:apiary/data/finance.dart';
import 'package:flutter_test/flutter_test.dart';

FinEntry _e(String kind, double amount, DateTime d, {bool cancelled = false}) => FinEntry(
    id: '$d$amount',
    kind: kind,
    categoryId: null,
    amount: amount,
    date: d,
    title: '',
    lineCount: 0,
    cancelled: cancelled,
    fromStock: false);

void main() {
  test('finMonthlyTotals групує за місяцями, пропускає скасовані й інші роки', () {
    final r = finMonthlyTotals([
      _e(kFinExpense, 100, DateTime(2026, 3, 5)),
      _e(kFinExpense, 50, DateTime(2026, 3, 20)),
      _e(kFinIncome, 400, DateTime(2026, 3, 21)),
      _e(kFinIncome, 999, DateTime(2026, 4, 1), cancelled: true),
      _e(kFinIncome, 10, DateTime(2025, 12, 31)),
    ], 2026);
    expect(r.length, 12);
    expect(r[2].expense, 150);
    expect(r[2].income, 400);
    expect(r[2].balance, 250);
    expect(r[3].income, 0);
    expect(r[11].income, 0);
  });

  test('finYearlyTotals групує за роками по зростанню', () {
    final r = finYearlyTotals([
      _e(kFinIncome, 5, DateTime(2026, 1, 1)),
      _e(kFinExpense, 2, DateTime(2024, 6, 1)),
      _e(kFinExpense, 3, DateTime(2026, 7, 1)),
      _e(kFinExpense, 9, DateTime(2025, 7, 1), cancelled: true),
    ]);
    expect(r.map((x) => x.month), [2024, 2026]);
    expect(r[1].income, 5);
    expect(r[1].expense, 3);
  });
}
