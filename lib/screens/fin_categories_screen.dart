import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/nav_drawer.dart';
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
  List<FinCategory> _cats = [];
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

  /// Перенести категорію [fromId] на місце [toId] й зберегти порядок.
  Future<void> _move(String fromId, String toId) async {
    final from = _cats.indexWhere((c) => c.id == fromId);
    final to = _cats.indexWhere((c) => c.id == toId);
    if (from < 0 || to < 0 || from == to) return;
    setState(() => _cats.insert(to, _cats.removeAt(from)));
    await widget.repo.reorderFinCategories([for (final c in _cats) c.id]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _scaffoldKey,
        drawer: NavDrawer(repo: widget.repo, current: NavSection.finances, finSection: FinSection.categories),
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
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, mainAxisSpacing: 14, childAspectRatio: 0.82),
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
                        itemCount: _cats.length + 1,
                        itemBuilder: (_, i) {
                          if (i == _cats.length) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _open(),
                              child: _tile(
                                  Container(
                                    width: 68,
                                    height: 68,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFFFBC02D), shape: BoxShape.circle),
                                    child: const Icon(TablerIcons.plus,
                                        size: 40, color: Color(0xFF1D1611)),
                                  ),
                                  tr.create),
                            );
                          }
                          final c = _cats[i];
                          final tile = _tile(
                              FinBadge(icon: c.icon, color: c.color, size: 68), c.name);
                          // довге натискання - узяти категорію, відпустити на іншій - поміняти місцями
                          return DragTarget<String>(
                            onWillAcceptWithDetails: (d) => d.data != c.id,
                            onAcceptWithDetails: (d) => _move(d.data, c.id),
                            builder: (_, hover, __) => LongPressDraggable<String>(
                              data: c.id,
                              feedback: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(width: 110, child: Opacity(opacity: 0.9, child: tile))),
                              childWhenDragging: Opacity(opacity: 0.3, child: tile),
                              child: Container(
                                decoration: BoxDecoration(
                                    color: hover.isEmpty ? null : AppColors.darkBtn,
                                    borderRadius: BorderRadius.circular(16)),
                                child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _open(category: c),
                                    child: tile),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      );
}

Widget _tile(Widget badge, String name) => Column(children: [
      badge,
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.text, fontSize: 13)),
      ),
    ]);
