import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../l10n/l10n.dart';
import '../logic/fin_analytics.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Колір шматка: колір категорії, для «Інше» - сірий.
Color finSliceColor(FinSlice s, Map<String, FinCategory> cats) {
  if (s.isRest) return finColor('stone');
  if (s.key == null) return finColor('olive');
  return finColor(cats[s.key]?.color ?? 'nut');
}

String finSliceName(FinSlice s, Map<String, FinCategory> cats) {
  if (s.isRest) return tr.finOtherCat;
  if (s.key == null) return kFinStockCategoryName;
  return cats[s.key]?.name ?? tr.noCategory;
}

/// Горизонтальна смуга розподілу: кожен шматок - своїм кольором, «Інше» останнім.
class FinSliceBar extends StatelessWidget {
  final List<FinSlice> slices;
  final Map<String, FinCategory> cats;
  final double height;
  const FinSliceBar({super.key, required this.slices, required this.cats, this.height = 22});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: height,
          child: Row(children: [
            for (var i = 0; i < slices.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (slices[i].amount * 100).round().clamp(1, 1 << 30),
                child: Container(color: finSliceColor(slices[i], cats)),
              ),
            ],
          ]),
        ),
      );
}

/// Рядок розподілу: кольорова крапка, назва, частка й сума.
/// Якщо задано [onTap] - рядок натискається.
class FinSliceRow extends StatelessWidget {
  final FinSlice slice;
  final double total;
  final Map<String, FinCategory> cats;
  final bool expense;
  final VoidCallback? onTap;
  final bool dense;
  const FinSliceRow({
    super.key,
    required this.slice,
    required this.total,
    required this.cats,
    required this.expense,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (slice.amount / total * 100).round() : 0;
    final color = finSliceColor(slice, cats);
    final c = slice.key == null ? null : cats[slice.key];
    final badge = slice.isRest
        ? Container(
            width: dense ? 14 : 40,
            height: dense ? 14 : 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle))
        : dense
            ? Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle))
            : (slice.key == null
                ? const FinBadge(icon: 'home', color: 'olive', size: 40)
                : FinBadge(icon: c?.icon ?? 'other', color: c?.color ?? 'nut', size: 40));
    final row = Row(children: [
      badge,
      SizedBox(width: dense ? 10 : 12),
      Expanded(
        child: Text(finSliceName(slice, cats),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.text, fontSize: dense ? 14 : 16)),
      ),
      const SizedBox(width: 8),
      Text('$pct%', style: TextStyle(color: AppColors.textMuted, fontSize: dense ? 13 : 14)),
      const SizedBox(width: 12),
      Text('${expense ? '−' : '+'}${uah(slice.amount)}',
          style: TextStyle(color: AppColors.text, fontSize: dense ? 14 : 16)),
    ]);
    if (dense) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: onTap == null ? row : InkWell(onTap: onTap, child: row));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: row),
        ),
      ),
    );
  }
}

/// Категорії, що злилися в «Інше»: усі з [byCategory], яких нема серед [slices].
List<FinSlice> finRestMembers(Map<String?, double> byCategory, List<FinSlice> slices) {
  final shown = {for (final s in slices.where((s) => !s.isRest)) s.key};
  final out = [
    for (final e in byCategory.entries)
      if (e.value > 0 && !shown.contains(e.key)) FinSlice(e.key, e.value)
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return out;
}
