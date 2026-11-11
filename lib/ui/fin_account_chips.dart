import 'package:flutter/material.dart';

import '../data/fin_accounts.dart';
import '../l10n/l10n.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Вибір рахунку рядком кружечків-«таблеток» (у формі операції й переказу).
class FinAccountChips extends StatelessWidget {
  final List<FinAccount> accounts;
  final String? selected;
  final ValueChanged<String> onChanged;
  final String? label;
  const FinAccountChips({
    super.key,
    required this.accounts,
    required this.selected,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label ?? tr.finAccount, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in accounts)
              GestureDetector(
                onTap: () => onChanged(a.id),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                  decoration: BoxDecoration(
                    color: a.id == selected ? AppColors.darkBtn : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: a.id == selected ? AppColors.create : AppColors.darkBtn, width: 1.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FinBadge(icon: a.icon, color: a.color, size: 28),
                    const SizedBox(width: 8),
                    Text(a.name, style: TextStyle(color: AppColors.text, fontSize: 14)),
                  ]),
                ),
              ),
          ]),
        ]),
      );
}
