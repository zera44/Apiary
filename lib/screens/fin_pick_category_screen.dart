import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../ui/common.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import '../l10n/l10n.dart';

/// Знак «створити нову категорію» у відповіді [FinPickCategoryScreen].
const kPickNewCategory = '__new__';

/// Усі категорії сіткою з пошуком. Повертає id обраної або [kPickNewCategory].
class FinPickCategoryScreen extends StatefulWidget {
  final List<FinCategory> categories;
  final String? selected;
  const FinPickCategoryScreen({super.key, required this.categories, this.selected});

  @override
  State<FinPickCategoryScreen> createState() => _FinPickCategoryScreenState();
}

class _FinPickCategoryScreenState extends State<FinPickCategoryScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [
      for (final c in widget.categories)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c
    ];
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: tr.category, onBack: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                key: const ValueKey('fin-cat-search'),
                style: TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: tr.searchHint,
                  prefixIcon: Icon(TablerIcons.search, color: AppColors.textMuted),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 6,
                childAspectRatio: 0.78,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                children: [
                  for (final c in list)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context, c.id),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: c.id == widget.selected ? AppColors.create : Colors.transparent,
                                width: 3),
                          ),
                          child: FinBadge(icon: c.icon, color: c.color, size: 52),
                        ),
                        const SizedBox(height: 4),
                        Text(c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.text,
                                fontSize: 12,
                                fontWeight: c.id == widget.selected ? FontWeight.w700 : FontWeight.w400)),
                      ]),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: AddButton(
                text: tr.newCategoryBtn,
                onPressed: () => Navigator.pop(context, kPickNewCategory),
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
