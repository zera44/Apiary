import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/stock_format.dart';
import '../ui/apiary_report.dart';
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

  /// Пасіка, з карти якої відкрито: «Звіт по пасіці (Excel)» — для неї.
  final Apiary? apiary;
  const HistoryHubScreen({super.key, required this.repo, this.stock = false, this.apiary});
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
            if (!_stock && widget.apiary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: PillButton(
                  text: 'Звіт по пасіці (Excel)',
                  bg: AppColors.roundBtn,
                  fg: AppColors.text,
                  width: double.infinity,
                  height: 40,
                  onPressed: () => showApiaryReport(context, repo, widget.apiary!),
                ),
              ),
            Expanded(
              child: TabSwipe(
                index: _stock ? 1 : 0,
                count: 2,
                onChanged: (i) => setState(() => _stock = i == 1),
                child: _stock ? _stockList() : _paramList(),
              ),
            ),
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
            child: SizedBox(width: 44, height: 44, child: StockPhoto(photo: it.photo, thumb: true)),
          ),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StockHistoryScreen(repo: repo, item: it),
            ));
            await _load(); // залишок міг змінитись (скасування запису)
          },
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
                  if (subtitle != null)
                    Text(subtitle,
                        maxLines: 2,
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

/// Історія однієї номенклатури: кожен прихід, списання, переоблік й
/// скасування, найновіші першими. Помилковий запис не видаляється, а
/// скасовується (кнопка ×): він лишається в історії закресленим, а окремий
/// запис «Скасування» повертає залишок.
class StockHistoryScreen extends StatefulWidget {
  final Repository repo;
  final StockItem item;
  const StockHistoryScreen({super.key, required this.repo, required this.item});
  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  List<Map<String, Object?>>? _rows;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.repo.stockMoves(widget.item.id);
    if (mounted) setState(() => _rows = r.reversed.toList());
  }

  Future<void> _cancel(Map<String, Object?> r, String title) async {
    if (_busy) return;
    final ok = await showConfirm(context,
        title: 'Скасувати запис?',
        text: '«$title» від ${_date(r)} буде позначено як скасований, а залишок '
            'повернеться назад. Запис лишиться в історії.',
        confirmText: 'Скасувати запис',
        cancelText: 'Закрити');
    if (!ok) return;
    _busy = true;
    try {
      await widget.repo.cancelStockMove(r['id'] as String);
    } on StateError catch (e) {
      if (mounted) await showInfo(context, e.message);
    } finally {
      _busy = false;
    }
    await _load();
  }

  static String _date(Map<String, Object?> r) => formatDdMmYyyy(DateTime.fromMicrosecondsSinceEpoch(
      (((r['op_date'] ?? r['created_at']) as num).toDouble() * 1e6).round()));

  static String _signed(double v, String unit) {
    if (v > 0) return '+${formatAmount(v)} $unit';
    if (v < 0) return '−${formatAmount(-v)} $unit';
    return '0 $unit';
  }

  Widget _row(Map<String, Object?> r) {
    final unit = widget.item.unit;
    final kind = r['kind'] as String;
    final amount = (r['amount'] as num).toDouble();
    final cancelled = (r['cancelled'] as int? ?? 0) == 1;
    final title = stockMoveTitle(kind, r['reason'] as String?, amount: amount);
    final value = switch (kind) {
      'out' => _signed(-amount, unit),
      'set' => '${formatAmount(amount)} $unit',
      _ => _signed(amount, unit), // in/add: +, inv і cancel — зі знаком
    };
    final total = (r['total'] as num?)?.toDouble();
    final price = (r['price'] as num?)?.toDouble();
    final comment = r['comment'] as String?;
    final details = [
      _date(r),
      if (total != null) '${formatMoney(total)} грн',
      if (price != null) '${formatMoney(price)} грн/$unit',
      if (cancelled) 'скасовано',
      if (comment != null && comment.isNotEmpty) comment,
    ].join(' · ');
    final canCancel = !cancelled && kind != 'cancel' && kind != 'set';
    final strike = cancelled ? TextDecoration.lineThrough : null;
    final color = cancelled ? AppColors.textMuted : AppColors.text;
    return ListCard(
      height: 62,
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color, fontSize: 14, fontWeight: FontWeight.bold, decoration: strike)),
              Text(details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.bold, decoration: strike)),
            Text('стало: ${formatAmount((r['quantity_after'] as num).toDouble())} $unit',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
        if (canCancel) ...[
          const SizedBox(width: 8),
          CircleIconButton(
            icon: 'close',
            bg: AppColors.neutralBtn,
            iconColor: AppColors.text,
            size: 30,
            tooltip: 'Скасувати запис',
            onPressed: () => _cancel(r, title),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _rows;
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
                              'Ще немає жодного запису.\nЗаписи з\'являються після приходу, '
                              'списання чи переобліку на складі.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _row(list[i]),
                        ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
