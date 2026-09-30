import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/stock_format.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/theme.dart';
import 'history_screen.dart';
import 'stock_screen.dart' show StockPhoto;

/// Меню навігації → «Історія»: окремо історія характеристик і історія
/// складу (прихід і вибуття номенклатури).
class HistoryHubScreen extends StatefulWidget {
  final Repository repo;

  /// true — одразу відкрити вкладку «Склад».
  final bool stock;
  const HistoryHubScreen({super.key, required this.repo, this.stock = false});
  @override
  State<HistoryHubScreen> createState() => _HistoryHubScreenState();
}

class _HistoryHubScreenState extends State<HistoryHubScreen> {
  late bool _stock = widget.stock;
  List<Parameter>? _params;
  List<StockItem>? _items;

  Repository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await repo.listParameters();
    final s = await repo.listStockItems();
    if (!mounted) return;
    setState(() {
      _params = p;
      _items = s;
    });
  }

  Widget _tab(String text, bool stock) => Expanded(
        child: PillButton(
          text: text,
          bg: _stock == stock ? AppColors.accent : AppColors.darkBtn,
          fg: _stock == stock ? Colors.white : AppColors.text,
          height: 40,
          onPressed: () => setState(() => _stock = stock),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Історія', onBack: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                _tab('Характеристики', false),
                const SizedBox(width: 8),
                _tab('Склад', true),
              ]),
            ),
            Expanded(child: _stock ? _stockList() : _paramList()),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
        ),
      );

  Widget _paramList() {
    final list = _params;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return _empty('Ще немає жодної характеристики.');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = list[i];
        return _card(
          title: p.nameWithUnit,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HistoryScreen(repo: repo, parameter: p),
          )),
        );
      },
    );
  }

  Widget _stockList() {
    final list = _items;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return _empty('Ще немає жодної номенклатури.\nДодайте її в меню → «Склад».');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final it = list[i];
        return _card(
          title: it.name,
          subtitle: it.quantity == null ? 'Ще не було приходу' : 'Залишок: ${formatAmount(it.quantity!)} ${it.unit}',
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 44, height: 44, child: StockPhoto(path: it.photo)),
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StockHistoryScreen(repo: repo, item: it),
          )),
        );
      },
    );
  }

  Widget _card({required String title, String? subtitle, Widget? leading, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ListCard(
          height: 62,
          child: Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
                  if (subtitle != null)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

/// Історія однієї номенклатури: кожен прихід і списання, найновіші першими.
class StockHistoryScreen extends StatefulWidget {
  final Repository repo;
  final StockItem item;
  const StockHistoryScreen({super.key, required this.repo, required this.item});
  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  List<Map<String, Object?>>? _rows;

  @override
  void initState() {
    super.initState();
    widget.repo.stockMoves(widget.item.id).then((r) {
      if (mounted) setState(() => _rows = r.reversed.toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows;
    final unit = widget.item.unit;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Історія: ${widget.item.name}', onBack: () => Navigator.pop(context)),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Ще немає жодного запису.\nЗаписи з\'являються після приходу чи списання на складі.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = list[i];
                            final kind = r['kind'] as String;
                            final out = kind == 'out';
                            final amount = formatAmount((r['amount'] as num).toDouble());
                            final after = formatAmount((r['quantity_after'] as num).toDouble());
                            final when = formatDdMmYyyy(DateTime.fromMicrosecondsSinceEpoch(
                                (((r['op_date'] ?? r['created_at']) as num).toDouble() * 1e6).round()));
                            final price = (r['price'] as num?)?.toDouble();
                            final comment = r['comment'] as String?;
                            final details = [
                              when,
                              if (price != null) '${formatAmount(price)} грн/$unit',
                              if (comment != null && comment.isNotEmpty) comment,
                            ].join(' · ');
                            return ListCard(
                              height: 62,
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(stockMoveTitle(kind, r['reason'] as String?),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: AppColors.text,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold)),
                                      Text(details,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(out ? '−$amount $unit' : (kind == 'set' ? '$amount $unit' : '+$amount $unit'),
                                        style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold)),
                                    Text('стало: $after $unit',
                                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                  ],
                                ),
                              ]),
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
}
