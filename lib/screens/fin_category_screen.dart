import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import '../l10n/l10n.dart';

/// Нова (або змінена) категорія довідника: назва, Витрати/Дохід, чи йдуть
/// позиції на склад, значок і колір. Повертає id категорії.
class FinCategoryScreen extends StatefulWidget {
  final Repository repo;

  /// Вид нової категорії (для зміни береться з [category]).
  final String kind;
  final FinCategory? category;
  const FinCategoryScreen({super.key, required this.repo, this.kind = kFinExpense, this.category});

  @override
  State<FinCategoryScreen> createState() => _FinCategoryScreenState();
}

class _FinCategoryScreenState extends State<FinCategoryScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.category?.name ?? '');
  late String _kind = widget.category?.kind ?? widget.kind;
  late bool _toStock = widget.category?.toStock ?? false;
  late String _icon = widget.category?.icon ?? 'other';
  late String _color = widget.category?.color ?? 'honey';
  bool _saving = false;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      await showInfo(context, tr.enterCategoryName);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = widget.repo;
      final String id;
      if (_editing) {
        id = widget.category!.id;
        await repo.updateFinCategory(id,
            name: name, toStock: _toStock, icon: _icon, color: _color);
      } else {
        id = await repo.addFinCategory(name, _kind,
            toStock: _toStock, icon: _icon, color: _color);
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await showInfo(context, tr.saveFailed('$e'), title: tr.error);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirm(context,
        title: tr.categoryDeleteTitle, text: tr.categoryDeleteText);
    if (!ok) return;
    await widget.repo.deleteFinCategory(widget.category!.id);
    if (mounted) Navigator.pop(context, '');
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(t, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final expense = _kind == kFinExpense;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(
                title: _editing ? tr.category : tr.categoryNew,
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    FinBadge(icon: _icon, color: _color, size: 60),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        style: TextStyle(color: AppColors.text, fontSize: 16),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(labelText: tr.name),
                      ),
                    ),
                  ]),
                ),
                if (!_editing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: FinSegment(
                      labels: [tr.expenses, tr.income],
                      selected: expense ? 0 : 1,
                      onChanged: (i) => setState(() {
                        _kind = i == 0 ? kFinExpense : kFinIncome;
                        _toStock = false;
                      }),
                    ),
                  ),
                Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _toStock ? AppColors.addObject : AppColors.darkBtn),
                    ),
                    child: Row(children: [
                      Icon(Icons.inventory_2_outlined, color: AppColors.addObject),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(expense ? tr.catGoesToStock : tr.catFromStock,
                              style: TextStyle(color: AppColors.text, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(expense ? tr.catGoesToStockHint : tr.catFromStockHint,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ]),
                      ),
                      Switch(value: _toStock, onChanged: (v) => setState(() => _toStock = v)),
                    ]),
                  ),
                _label(tr.icon),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final k in kFinIcons.keys)
                      GestureDetector(
                        onTap: () => setState(() => _icon = k),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: k == _icon ? finColor(_color) : AppColors.typeBtn,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(finIcon(k),
                              size: 22,
                              color: k == _icon ? AppColors.bg : AppColors.textMuted),
                        ),
                      ),
                  ]),
                ),
                _label(tr.color),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final e in kFinColors.entries)
                      GestureDetector(
                        onTap: () => setState(() => _color = e.key),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: e.key == _color
                                ? Border.all(color: AppColors.text, width: 3)
                                : null,
                          ),
                        ),
                      ),
                  ]),
                ),
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: PillButton(
                      text: tr.categoryDelete,
                      bg: AppColors.neutralBtn,
                      fg: AppColors.text,
                      height: 44,
                      width: double.infinity,
                      onPressed: _delete,
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: PillButton(
                text: _editing ? tr.save : tr.create,
                bg: AppColors.accent,
                height: 52,
                radius: 26,
                fontSize: 17,
                width: double.infinity,
                onPressed: _saving ? null : _save,
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
