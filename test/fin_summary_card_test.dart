import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apiary/ui/fin_summary_card.dart';
import 'package:apiary/ui/theme.dart';

Future<void> _pump(WidgetTester t, double inc, double exp) => t.pumpWidget(MaterialApp(
    theme: buildAppTheme(), home: Scaffold(body: FinSummaryCard(income: inc, expense: exp))));

void main() {
  testWidgets('прибуток: підпис, плюс і частка від доходу', (t) async {
    await _pump(t, 1000, 700);
    expect(find.text('Прибуток'), findsOneWidget);
    expect(find.text('+300 ₴'), findsOneWidget);
    expect(find.text('30% від доходу'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('збиток: підпис «Збиток» і мінус', (t) async {
    await _pump(t, 700, 1000);
    expect(find.text('Збиток'), findsOneWidget);
    expect(find.text('−300 ₴'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('порожній період не падає', (t) async {
    await _pump(t, 0, 0);
    expect(find.text('Прибуток'), findsOneWidget);
    expect(find.textContaining('від доходу'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('рядок періоду: підпис, прибуток і дохід з витратами', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: FinPeriodRow(label: '2025', income: 400, expense: 500))));
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('−100 ₴'), findsOneWidget); // збиток
    expect(find.text('400 ₴'), findsOneWidget);
    expect(find.text('−500 ₴'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
