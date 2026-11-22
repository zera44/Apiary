import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Єдина картка-підсумок для статистики (за роками й за місяцями): великий
/// прибуток (збиток) з часткою від доходу, смужка «витрати / залишок» і під нею
/// дохід та витрати дрібніше. Кольори ті самі, що в легенді діаграми.
class FinSummaryCard extends StatelessWidget {
  final double income;
  final double expense;
  const FinSummaryCard({super.key, required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final inc = income, exp = expense;
    final green = finColor('olive'), yellow = finColor('honey');
    final profit = finColor('sky'), loss = finColor('terra');
    final bal = inc - exp;
    final c = bal >= 0 ? profit : loss;
    final share = inc > 0 ? (bal / inc * 100).round() : null;
    // смужка: при прибутку витрати + залишок = дохід, при збитку дохід + перевитрата = витрати
    final first = bal >= 0 ? exp : inc;
    final second = bal.abs();
    Widget part(double v, Color color) =>
        Expanded(flex: (v * 100).round().clamp(1, 1 << 30), child: Container(color: color));
    Widget col(String label, String value, Color dot, CrossAxisAlignment a) => Column(
          crossAxisAlignment: a,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ]),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w500)),
          ],
        );
    return Container(
      key: const ValueKey('stat-summary'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bal >= 0 ? tr.finProfit : tr.finLossOne,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('${bal > 0 ? '+' : ''}${uah(bal)}',
                    key: const ValueKey('stat-balance'),
                    style: TextStyle(color: c, fontSize: 30, fontWeight: FontWeight.w700, height: 1.15)),
              ),
            ]),
          ),
          if (share != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: Text(tr.finShareOfIncome(share),
                  style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
        ]),
        if (inc > 0 || exp > 0) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                if (first > 0) part(first, bal >= 0 ? yellow : green),
                if (first > 0 && second > 0) const SizedBox(width: 3),
                if (second > 0) part(second, c),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: col(tr.income, uah(inc), green, CrossAxisAlignment.start)),
          const SizedBox(width: 10),
          Expanded(child: col(tr.expenses, uah(exp), yellow, CrossAxisAlignment.end)),
        ]),
      ]),
    );
  }
}
