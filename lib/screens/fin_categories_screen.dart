import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import 'fin_category_screen.dart';

/// Список категорій фінансів (витрати / дохід): натиснути - змінити,
/// «+» - додати нову.
class FinCategoriesScreen extends StatefulWidget {
  final Repository repo;
  const FinCategoriesScreen({super.key, required this.repo});

  @override
  State<FinCategoriesScreen> createState() => _FinCategoriesScreenState();
}

class _FinCategoriesScreenState extends State<FinCategoriesScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _kind = kFinExpense;
  List<FinCategory> _cats = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.listFinCategories(kind: _kind);
    if (!mounted) return;
    setState(() {
      _cats = list;
      _loaded = true;
    });
  }

  Future<void> _open({FinCategory? category}) async {
    await Navigator.of(context).push(MaterialPageRoute<String>(
        builder: (_) => FinCategoryScreen(repo: widget.repo, kind: _kind, category: category)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _scaffoldKey,
        drawer: FinDrawer(repo: widget.repo, current: FinSection.categories),
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(
                title: tr.finCategories,
                onBack: () => Navigator.pop(context),
                onTitleTap: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FinSegment(
                  labels: [tr.expenses, tr.income],
                  selected: _kind == kFinExpense ? 0 : 1,
                  onChanged: (i) {
                    setState(() {
                      _kind = i == 0 ? kFinExpense : kFinIncome;
                      _loaded = false;
                    });
                    _reload();
                  },
                ),
              ),
              Expanded(
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
                        for (final c in _cats)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                                color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _open(category: c),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  FinBadge(icon: c.icon, color: c.color, size: 44),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Text(c.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppColors.text, fontSize: 16))),
                                  if (c.toStock)
                                    Icon(TablerIcons.package,
                                        size: 20, color: AppColors.textMuted),
                                ]),
                              ),
                            ),
                          ),
                      ]),
              ),
            ]),
            Positioned(
              right: 20,
              bottom: 24,
              child: Material(
                color: const Color(0xFFFBC02D),
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _open(),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Tooltip(
                        message: tr.categoryNew,
                        child: const Icon(TablerIcons.plus, size: 36, color: Color(0xFF1D1611))),
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      );
}
