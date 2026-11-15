import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/fin_accounts.dart';
import '../l10n/l10n.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Вибір рахунку списком у нижньому вікні: назва і залишок. Повертає id.
Future<String?> pickFinAccount(
  BuildContext context, {
  required List<FinAccount> accounts,
  required Map<String, double> balances,
  required String? selected,
  String? title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 44,
              height: 5,
              decoration:
                  BoxDecoration(color: AppColors.darkBtn, borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title ?? tr.chooseAccount,
                  style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final a in accounts)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(ctx, a.id),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: a.id == selected ? AppColors.create : Colors.transparent, width: 1.5),
                      ),
                      child: Row(children: [
                        FinBadge(icon: a.icon, color: a.color, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(a.foreign ? '${a.name} · ${a.currency}' : a.name,
                                style: TextStyle(color: AppColors.text, fontSize: 16))),
                        const SizedBox(width: 8),
                        Text(money(balances[a.id] ?? a.startBalance, a.currency),
                            style: TextStyle(
                                color: (balances[a.id] ?? 0) < 0 ? AppColors.danger : AppColors.textMuted,
                                fontSize: 15)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Поле «Переказати з рахунку / на рахунок»: підпис, значок, назва, залишок, стрілка вниз.
class FinAccountField extends StatelessWidget {
  final String label;
  final FinAccount? account;
  final double? balance;
  final VoidCallback onTap;
  const FinAccountField(
      {super.key, required this.label, required this.account, this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = account;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 6),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.darkBtn)),
              child: Row(children: [
                if (a != null) FinBadge(icon: a.icon, color: a.color, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a == null ? '—' : (a.foreign ? '${a.name} · ${a.currency}' : a.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
                    if (a != null && balance != null)
                      Text(money(balance!, a.currency),
                          style: TextStyle(
                              color: balance! < 0 ? AppColors.danger : AppColors.textMuted, fontSize: 12)),
                  ]),
                ),
                Icon(TablerIcons.chevron_down, color: AppColors.textMuted),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
