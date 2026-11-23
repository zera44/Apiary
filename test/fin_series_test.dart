import 'package:apiary/data/finance.dart';
import 'package:apiary/logic/fin_analytics.dart';
import 'package:apiary/logic/fin_period.dart';
import 'package:apiary/logic/fin_series.dart';
import 'package:flutter_test/flutter_test.dart';

FinEntry _e(String kind, double amount, DateTime d, {String? cat, bool cancelled = false}) => FinEntry(
    id: '$d$amount$kind',
    kind: kind,
    categoryId: cat,
    amount: amount,
    date: d,
    title: '',
    lineCount: 0,
    cancelled: cancelled,
    fromStock: false);

void main() {
  final now = DateTime(2026, 11, 22);

  test('місяць: точки від січня до поточного місяця, вибрано місяць якоря', () {
    final w = finWindow(FinPeriodSel(period: FinPeriod.month, anchor: DateTime(2026, 3, 1)), now: now);
    expect(w.buckets.length, 11);
    expect(w.selected, 2);
    final past = finWindow(FinPeriodSel(period: FinPeriod.month, anchor: DateTime(2025, 5, 1)), now: now);
    expect(past.buckets.length, 12);
  });

  test('тиждень: 12 тижнів, останній - вибраний; рік - 5 років', () {
    final w = finWindow(FinPeriodSel(period: FinPeriod.week, anchor: DateTime(2026, 11, 22)), now: now);
    expect(w.buckets.length, 12);
    expect(w.selected, 11);
    expect(w.buckets.last.from, DateTime(2026, 11, 16));
    final y = finWindow(FinPeriodSel(period: FinPeriod.year, anchor: DateTime(2026, 1, 1)), now: now);
    expect(y.buckets.map((b) => b.label), ['2022', '2023', '2024', '2025', '2026']);
  });

  test('роки: вікно стоїть, поки вибір не дійде до краю, і лише тоді зсувається', () {
    final first = DateTime(2017, 3, 1);
    FinWindow at(int year, int? start) => finWindow(
        FinPeriodSel(period: FinPeriod.year, anchor: DateTime(year, 1, 1)),
        now: now, earliest: first, start: start);
    // найновіше вікно 2022-2026; обрали 2025 - 2026 нікуди не зникає
    var w = at(2025, null);
    expect(w.buckets.map((b) => b.label), ['2022', '2023', '2024', '2025', '2026']);
    expect(w.selected, 3);
    w = at(2023, w.start);
    expect(w.buckets.first.label, '2022');
    // вибір дійшов до лівого краю - з'являється рік раніше
    w = at(2022, w.start);
    expect(w.buckets.map((b) => b.label), ['2021', '2022', '2023', '2024', '2025']);
    expect(w.selected, 1);
    // на межі даних вікно далі не їде
    w = at(2017, w.start);
    expect(w.buckets.first.label, '2017');
    expect(w.selected, 0);
    // назад до правого краю: вікно зсувається так, щоб праворуч був ще один рік
    w = at(2021, w.start);
    w = at(2022, w.start);
    w = at(2025, w.start);
    expect(w.buckets.last.label, '2026');
    expect(w.selected, 3);
  });

  test('finWindowStart: найновіше за замовчуванням, межі даних', () {
    expect(finWindowStart(null, 9, 5, 10), 5);
    expect(finWindowStart(5, 6, 5, 10), 5);
    expect(finWindowStart(5, 5, 5, 10), 4);
    expect(finWindowStart(0, 0, 5, 10), 0);
    expect(finWindowStart(null, 2, 5, 3), 0);
  });

  test('власний період: тижні, а вибраної точки немає', () {
    final s = FinPeriodSel(period: FinPeriod.month, anchor: DateTime(2026, 11, 1))
      ..setCustom(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    final w = finWindow(s, now: now);
    expect(w.selected, isNull);
    expect(w.buckets.first.from, DateTime(2026, 11, 1));
    expect(w.buckets.last.to, DateTime(2026, 12, 1));
    expect(w.buckets.length, 5);
  });

  test('результат: дохід мінус витрати, збиток - від’ємне число', () {
    final w = finWindow(FinPeriodSel(period: FinPeriod.month, anchor: DateTime(2026, 3, 1)), now: now);
    final entries = [
      _e(kFinIncome, 1000, DateTime(2026, 1, 5)),
      _e(kFinExpense, 400, DateTime(2026, 1, 6)),
      _e(kFinIncome, 100, DateTime(2026, 3, 5)),
      _e(kFinExpense, 700, DateTime(2026, 3, 6)),
      _e(kFinExpense, 999, DateTime(2026, 3, 7), cancelled: true),
    ];
    final r = finSeries(entries, w.buckets, FinStatKind.result);
    expect(r[0], 600);
    expect(r[2], -600);
    expect(finSeries(entries, w.buckets, FinStatKind.expense)[2], 700);
    expect(finSeries(entries, w.buckets, FinStatKind.income)[2], 100);
    final cat = finSeries([_e(kFinExpense, 5, DateTime(2026, 1, 1), cat: 'a'), ...entries], w.buckets,
        FinStatKind.expense,
        where: (e) => e.categoryId == 'a');
    expect(cat[0], 5);
    expect(cat[2], 0);
  });

  test('межі ряду зі знаком можуть бути нижчими за нуль', () {
    final s = finControlStats([600, -600, 300, 100], allowNegative: true);
    expect(s.low, lessThan(0));
    expect(finControlStats([600, 0, 300, 100]).low, greaterThanOrEqualTo(0));
  });
}
