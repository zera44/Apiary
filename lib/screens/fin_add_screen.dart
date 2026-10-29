import 'package:flutter/material.dart';

import '../data/finance.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../logic/receipt_parser.dart';
import '../logic/stock_format.dart';
import '../services/receipt_ocr.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import 'fin_category_screen.dart';
import '../ui/thousands_input.dart';
import '../l10n/l10n.dart';

/// Нова витрата / дохід. Одна таблиця «Товар / К-сть / Ціна» і для ручного
/// введення, і для розпізнаного чека; категорія - з довідника; рядки з «на
/// склад» стають приходом на складі. Сума за замовчуванням рахується з
/// таблиці, але її можна виправити (знижка, округлення).
class FinAddScreen extends StatefulWidget {
  final Repository repo;
  final String kind;

  /// Фото чека: одразу відкривається режим «З чека» і чек розпізнається.
  final String? imagePath;

  /// Чим розпізнавати (у тестах підміняється).
  final ReceiptOcr? ocr;
  const FinAddScreen(
      {super.key, required this.repo, this.kind = kFinExpense, this.imagePath, this.ocr});

  @override
  State<FinAddScreen> createState() => _FinAddScreenState();
}

class _FLine {
  bool toStock;

  /// Користувач сам торкнувся позначки «на склад» - категорія її більше не змінює.
  bool touched = false;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  final FocusNode focus = FocusNode();
  String unit;

  _FLine({String name = '', double qty = 1, String unit = 'шт', double price = 0, this.toStock = false})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: formatAmount(qty)),
        price = TextEditingController(text: price == 0 ? '' : formatMoney(price)),
        unit = unit;

  double? get qtyValue => parseAmount(qty.text);
  double? get priceValue => parseAmount(price.text);

  /// Порожній рядок (нічого не введено) - ігнорується.
  bool get empty => name.text.trim().isEmpty && price.text.trim().isEmpty;

  bool get valid =>
      name.text.trim().isNotEmpty &&
      (qtyValue ?? 0) > 0 &&
      priceValue != null &&
      amountFitsUnit(qtyValue!, unit);

  double get total => valid ? qtyValue! * priceValue! : 0;

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
    focus.dispose();
  }
}

class _FinAddScreenState extends State<FinAddScreen> {
  late String _kind = widget.kind;
  List<FinCategory> _cats = [];
  String? _catId;
  final List<_FLine> _lines = [];
  final _sum = TextEditingController();
  bool _sumManual = false;
  int _mode = 0; // 0 - вручну, 1 - з чека
  DateTime _date = DateTime.now();
  bool _saving = false;

  // склад: підказки назв і останні ціни
  List<StockItem> _stock = [];
  Map<String, double> _prices = {};

  // чек
  bool _reading = false;
  String? _receiptNote;
  bool _receiptOk = false;
  double? _declared;
  bool _hasReceipt = false;

  Repository get repo => widget.repo;
  ReceiptOcr get _ocr => widget.ocr ?? ReceiptOcr.instance;
  bool get _expense => _kind == kFinExpense;

  FinCategory? get _cat {
    for (final c in _cats) {
      if (c.id == _catId) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _lines.add(_FLine());
    if (widget.imagePath != null) _mode = 1;
    _load().then((_) {
      if (widget.imagePath != null) _recognize(widget.imagePath!);
    });
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _sum.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cats = await repo.listFinCategories(kind: _kind);
    final stock = await repo.listStockItems();
    final prices = await repo.lastStockPrices();
    final last = await repo.getMeta(_lastCatKey);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _stock = stock;
      _prices = prices;
      if (_catId != null && !cats.any((c) => c.id == _catId)) _catId = null;
    });
    // ще не обрали - категорія минулого запису цього виду (видалена - ніяка)
    if (_catId == null) {
      for (final c in cats) {
        if (c.id == last) _pickCategory(c);
      }
    }
  }

  /// Остання категорія - окремо для витрат і для доходів.
  String get _lastCatKey => 'fin_last_cat:$_kind';

  // ------------------------------------------------------------- розрахунки

  double get _tableSum => [for (final l in _lines) if (!l.empty) l.total].fold(0.0, (a, b) => a + b);

  void _syncSum() {
    if (_sumManual) return;
    final t = _tableSum;
    _sum.text = t > 0 ? formatMoney(t) : '';
  }

  void _changed() {
    setState(_syncSum);
  }

  StockItem? _stockByName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final i in _stock) {
      if (i.name.trim().toLowerCase() == key) return i;
    }
    return null;
  }

  /// Для рядка «на склад» з наявною номенклатурою одиниця береться зі складу.
  void _applyStockUnit(_FLine l) {
    if (!l.toStock) return;
    final it = _stockByName(l.name.text);
    if (it == null) return;
    // продаж меду: можна в кг або в літрах (перераховується), решта - як на складі
    final keep = !_expense &&
        (it.unit == 'кг' || it.unit == 'л') &&
        (l.unit == 'кг' || l.unit == 'л');
    if (!keep) l.unit = it.unit;
  }

  void _setKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _catId = null;
      for (final l in _lines) {
        l.toStock = false;
        l.touched = false;
      }
    });
    _load();
  }

  void _pickCategory(FinCategory c) {
    setState(() {
      _catId = c.id;
      for (final l in _lines) {
        if (!l.touched) l.toStock = c.toStock;
        _applyStockUnit(l);
      }
    });
  }

  Future<void> _newCategory() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => FinCategoryScreen(repo: repo, kind: _kind)));
    if (id == null || id.isEmpty) return;
    await _load();
    if (!mounted) return;
    final c = _cats.where((x) => x.id == id).toList();
    if (c.isNotEmpty) _pickCategory(c.first);
  }

  // ------------------------------------------------------------------- чек

  Future<void> _pickReceipt({required bool camera}) async {
    final path = await pickReceiptPhoto(camera: camera);
    if (path == null || !mounted) return;
    await _recognize(path);
  }

  Future<void> _recognize(String path) async {
    if (!_ocr.supported) {
      setState(() {
        _mode = 1;
        _hasReceipt = true;
        _receiptOk = false;
        _receiptNote = tr.receiptOnPhoneOnly;
      });
      return;
    }
    setState(() {
      _mode = 1;
      _reading = true;
      _receiptNote = null;
    });
    try {
      final text = await _ocr.read(path);
      final rows = parseReceipt(text);
      if (!mounted) return;
      final cat = _cat;
      setState(() {
        _reading = false;
        _hasReceipt = true;
        _declared = receiptDeclaredTotal(text);
        if (rows.isEmpty) {
          _receiptOk = false;
          _receiptNote = tr.receiptNoRows;
          return;
        }
        // порожні рядки замінюються розпізнаними
        _lines.removeWhere((l) {
          if (!l.empty) return false;
          l.dispose();
          return true;
        });
        for (final r in rows) {
          final l = _FLine(
              name: r.name,
              qty: r.qty,
              unit: r.unit,
              price: r.price,
              toStock: cat?.toStock ?? false);
          _applyStockUnit(l);
          _lines.add(l);
        }
        _sumManual = false;
        _syncSum();
        final t = _tableSum;
        final d = _declared;
        final n = rows.length;
        final word = tr.receiptRows(n);
        if (d != null && (d - t).abs() < 0.015) {
          _receiptOk = true;
          _receiptNote = tr.receiptOk(word);
        } else if (d != null) {
          _receiptOk = false;
          _receiptNote = tr.receiptMismatch(word, uah(d), uah(t));
        } else {
          _receiptOk = true;
          _receiptNote = tr.receiptCheck(word);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _receiptOk = false;
        _receiptNote = tr.receiptFailed;
      });
    }
  }

  // ------------------------------------------------------------- запис

  Future<void> _pickDate() async {
    final res = await showAppDatePicker(context, formatDdMmYyyy(_date));
    final d = parseDdMmYyyy(res);
    if (d != null && mounted) setState(() => _date = d);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _save() async {
    if (_saving) return;
    final cat = _cat;
    if (cat == null) {
      await showInfo(context, tr.finChooseCategory);
      return;
    }
    final used = [for (final l in _lines) if (!l.empty) l];
    final bad = used.where((l) => !l.valid).toList();
    if (bad.isNotEmpty) {
      await showInfo(
          context,
          tr.finBadRows(bad.length),
          title: tr.notRecorded);
      return;
    }
    final typed = _sum.text.trim();
    if (typed.startsWith('-')) {
      await showInfo(context, tr.finNegative, title: tr.notRecorded);
      return;
    }
    var amount = parseAmount(_sum.text) ?? 0;
    if (amount <= 0 && used.isNotEmpty) amount = _tableSum;
    if (!(amount > 0)) {
      await showInfo(context, tr.finEnterSum);
      return;
    }
    final d = _declared;
    if (d != null && !_sumManual && (d - _tableSum).abs() > 0.015) {
      final ok = await showConfirm(context,
          title: tr.finSumMismatch,
          text: tr.finSumMismatchText(uah(_tableSum), uah(d)),
          confirmText: tr.recordAction,
          cancelText: tr.check,
          danger: false);
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final when = _sameDay(_date, now) ? now : DateTime(_date.year, _date.month, _date.day, 12);
      await repo.addFinOp(
        kind: _kind,
        categoryId: cat.id,
        amount: amount,
        date: when,
        lines: [
          for (final l in used)
            FinLineInput(
                name: l.name.text.trim(),
                qty: l.qtyValue!,
                unit: l.unit,
                price: l.priceValue!,
                toStock: l.toStock)
        ],
      );
      await repo.setMeta(_lastCatKey, cat.id);
      if (!mounted) return;
      final toStock = used.where((l) => l.toStock).length;
      Navigator.pop(
          context,
          toStock > 0
              ? tr.recordedToStock(_expense, toStock)
              : tr.recorded);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await showInfo(context, e is StateError ? e.message : tr.recordFailed('$e'),
            title: tr.notRecorded);
      }
    }
  }

  // ------------------------------------------------------------------ вигляд

  Widget _card({required Widget child, EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _sumBlock() {
    final t = _tableSum;
    final cur = parseAmount(_sum.text) ?? 0;
    String? note;
    if (_sumManual && t > 0 && (cur - t).abs() > 0.005) {
      note = tr.finFixedByHand(uah(t));
      if (cur < t) note += tr.finDiscount(uah(t - cur));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(children: [
        Text(tr.sum, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        TextField(
          key: const ValueKey('fin-sum'),
          controller: _sum,
          // вручну - одразу клавіатура для суми (як у Складі); з чека - ні
          autofocus: widget.imagePath == null,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: thousandsInput,
          style: TextStyle(color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: '0',
            suffixText: '₴',
            suffixStyle: TextStyle(color: AppColors.create, fontSize: 28),
            filled: false,
          ),
          onChanged: (_) => setState(() => _sumManual = true),
        ),
        if (note != null)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(note,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.rename, fontSize: 12.5)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _sumManual = false;
                _syncSum();
              }),
              child: Text(tr.fromTable, style: TextStyle(color: AppColors.create, fontSize: 12.5)),
            ),
          ]),
      ]),
    );
  }

  Widget _categories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr.category, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _cats)
            GestureDetector(
              onTap: () => _pickCategory(c),
              onLongPress: () async {
                await Navigator.of(context).push(MaterialPageRoute<String>(
                    builder: (_) => FinCategoryScreen(repo: repo, category: c)));
                await _load();
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                decoration: BoxDecoration(
                  color: c.id == _catId ? AppColors.darkBtn : AppColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: c.id == _catId ? AppColors.create : AppColors.darkBtn, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FinBadge(icon: c.icon, color: c.color, size: 30),
                  const SizedBox(width: 8),
                  Text(c.name, style: TextStyle(color: AppColors.text, fontSize: 14)),
                  if (c.toStock) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.addObject),
                  ],
                ]),
              ),
            ),
          GestureDetector(
            onTap: _newCategory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.create, width: 1.5),
              ),
              child: Text(tr.newCategoryShort, style: TextStyle(color: AppColors.create, fontSize: 14)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _receiptPanel() {
    if (_reading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Text(tr.receiptReading, style: TextStyle(color: AppColors.textMuted)),
        ]),
      );
    }
    if (!_hasReceipt) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(children: [
          Text(
              tr.receiptPhotoHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3)),
          const SizedBox(height: 10),
          PillButton(
            text: tr.receiptPhoto,
            bg: AppColors.accent,
            height: 46,
            radius: 16,
            width: double.infinity,
            onPressed: () => _pickReceipt(camera: true),
          ),
          const SizedBox(height: 8),
          PillButton(
            text: tr.photoFromGallery,
            bg: AppColors.darkBtn,
            fg: AppColors.text,
            height: 42,
            width: double.infinity,
            onPressed: () => _pickReceipt(camera: false),
          ),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _receiptOk ? AppColors.addObject : AppColors.danger),
      ),
      child: Row(children: [
        Icon(_receiptOk ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 20, color: _receiptOk ? AppColors.addObject : AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_receiptNote ?? '',
              style: TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.3)),
        ),
        TextButton(
          onPressed: () => _pickReceipt(camera: true),
          child: Text(tr.reshoot, style: TextStyle(color: AppColors.create, fontSize: 12.5)),
        ),
      ]),
    );
  }

  Widget _tableHeader() {
    final s = TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
      child: Row(children: [
        SizedBox(width: 34, child: Tooltip(message: _expense ? tr.toStock : tr.fromStock, child: Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textMuted))),
        Expanded(flex: 5, child: Text(tr.goods, style: s)),
        const SizedBox(width: 6),
        Expanded(flex: 3, child: Text(tr.qtyShort, style: s)),
        const SizedBox(width: 6),
        Expanded(flex: 3, child: Text(tr.price, style: s)),
        const SizedBox(width: 30),
      ]),
    );
  }

  Widget _nameField(_FLine l, InputDecoration dense, TextStyle style) {
    return RawAutocomplete<String>(
      textEditingController: l.name,
      focusNode: l.focus,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return [
          for (final i in _stock)
            if (i.name.toLowerCase().contains(q) && i.name.toLowerCase() != q) i.name
        ].take(6);
      },
      onSelected: (s) => setState(() {
        _applyStockUnit(l);
        _syncSum();
      }),
      fieldViewBuilder: (ctx, ctl, focus, submit) => TextField(
        controller: ctl,
        focusNode: focus,
        style: style,
        minLines: 1,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: dense.copyWith(hintText: tr.name),
        onChanged: (_) => setState(() {
          _applyStockUnit(l);
          _syncSum();
        }),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          color: AppColors.popupBg,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 260),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (c, i) {
                final o = options.elementAt(i);
                return InkWell(
                  onTap: () => onSelected(o),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(o, style: TextStyle(color: AppColors.text, fontSize: 14)),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(_FLine l) {
    const dense =
        InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10));
    final style = TextStyle(color: AppColors.text, fontSize: 13.5);
    const numKb = TextInputType.numberWithOptions(decimal: true);
    final item = l.toStock ? _stockByName(l.name.text) : null;
    final kgl = item != null && !_expense && (item.unit == 'кг' || item.unit == 'л');
    final locked = item != null && !kgl;

    // підказки під рядком
    final hints = <Widget>[];
    if (l.toStock && l.name.text.trim().isNotEmpty) {
      if (item != null) {
        hints.add(Text(tr.inStockAmount('${formatAmount(item.quantity ?? 0)} ${item.unit}'),
            style: TextStyle(color: AppColors.addObject, fontSize: 12)));
        if (!_expense && (l.qtyValue ?? 0) > 0) {
          final q = stockQty(l.unit, item.unit, l.qtyValue!);
          if (l.unit.toLowerCase() != item.unit.toLowerCase()) {
            hints.add(Text(tr.willWriteOff('${formatAmount(q)} ${item.unit}'),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)));
          }
          final have = item.quantity ?? 0;
          if (q > have + 1e-9) {
            hints.add(Text(tr.moreThanStock('${formatAmount(q - have)} ${item.unit}'),
                style: TextStyle(color: AppColors.create, fontSize: 12, fontWeight: FontWeight.w600)));
          }
        }
      } else if (_expense) {
        hints.add(Text(tr.newGoods, style: TextStyle(color: AppColors.create, fontSize: 12)));
      } else {
        hints.add(Text(tr.notInStock,
            style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)));
      }
    }
    final pv = l.priceValue;
    if (item != null && pv != null && pv > 0) {
      final last = _prices[item.id];
      if (last != null && (pv > last * 3 || pv < last / 3)) {
        hints.add(Text(tr.checkPrice(formatMoney(last)),
            style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)));
      }
    }
    if (l.valid) {
      hints.add(Text(tr.sumOf(uah(l.total)), style: TextStyle(color: AppColors.textMuted, fontSize: 12)));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: !l.empty && !l.valid ? AppColors.danger : AppColors.darkBtn, width: 1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
              width: 34,
              child: IconButton(
                tooltip: _expense ? tr.putToStock : tr.writeOffFromStock,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(l.toStock ? Icons.inventory_2 : Icons.inventory_2_outlined,
                    size: 22, color: l.toStock ? AppColors.addObject : AppColors.textMuted),
                onPressed: () => setState(() {
                  l.toStock = !l.toStock;
                  l.touched = true;
                  _applyStockUnit(l);
                }),
              ),
            ),
          Expanded(flex: 5, child: _nameField(l, dense, style)),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(
              controller: l.qty,
              style: style,
              keyboardType: numKb,
              inputFormatters: thousandsInput,
              decoration: dense.copyWith(
                suffixIcon: locked
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 2),
                          Text(l.unit, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                        ]),
                      )
                    : PopupMenuButton<String>(
                        tooltip: tr.unitShort,
                        padding: EdgeInsets.zero,
                        onSelected: (u) => setState(() => l.unit = u),
                        itemBuilder: (_) => [
                          for (final u in (kgl ? const ['кг', 'л'] : {...kStockUnits, l.unit}))
                            PopupMenuItem(value: u, child: Text(u)),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(l.unit,
                              style: TextStyle(
                                  color: AppColors.create,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              ),
              onChanged: (_) => _changed(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(
              controller: l.price,
              style: style,
              keyboardType: numKb,
              inputFormatters: thousandsInput,
              decoration: dense.copyWith(hintText: '0'),
              onChanged: (_) => _changed(),
            ),
          ),
          SizedBox(
            width: 30,
            child: IconButton(
              tooltip: tr.deleteRow,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: AppColors.textMuted),
              onPressed: () => setState(() {
                _lines.remove(l);
                l.dispose();
                if (_lines.isEmpty) _lines.add(_FLine());
                _syncSum();
              }),
            ),
          ),
        ]),
        if (hints.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 3, 30, 0),
            child: Wrap(spacing: 12, runSpacing: 2, children: hints),
          ),
      ]),
    );
  }

  Widget _table() {
    final t = _tableSum;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FinSegment(
          labels: [tr.byHand, tr.fromReceipt],
          selected: _mode,
          onChanged: (i) => setState(() => _mode = i),
        ),
        if (_mode == 1) _receiptPanel(),
        _tableHeader(),
        for (final l in _lines) _row(l),
        Row(children: [
          TextButton(
            onPressed: () => setState(() => _lines.add(_FLine(toStock: _cat?.toStock ?? false))),
            child: Text(tr.addRow, style: TextStyle(color: AppColors.create)),
          ),
          const Spacer(),
          if (t > 0)
            Text(tr.tableOf(uah(t)), style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ]),
      ]),
    );
  }

  Widget _dateRow() {
    final now = DateTime.now();
    final today = _sameDay(_date, now);
    final yesterday = _sameDay(_date, now.subtract(const Duration(days: 1)));
    Widget chip(String text, bool on, VoidCallback tap) => GestureDetector(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? AppColors.darkBtn : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? AppColors.create : AppColors.darkBtn, width: 1.5),
            ),
            child: Text(text, style: TextStyle(color: AppColors.text, fontSize: 14)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        chip(tr.today, today, () => setState(() => _date = DateTime.now())),
        chip(tr.yesterday, yesterday,
            () => setState(() => _date = DateTime.now().subtract(const Duration(days: 1)))),
        chip(today || yesterday ? tr.otherDate : formatDdMmYyyy(_date), !today && !yesterday, _pickDate),
      ]),
    );
  }

  /// Щось уже введено (сума, рядки таблиці чи розпізнаний чек).
  bool get _dirty =>
      (parseAmount(_sum.text) ?? 0) != 0 || _hasReceipt || _lines.any((l) => !l.empty);

  /// Вихід без збереження: якщо щось введено — спершу перепитати.
  Future<void> _leave() async {
    if (_saving) return;
    if (_dirty) {
      final ok = await showConfirm(context,
          title: tr.leaveUnsavedTitle,
          text: tr.leaveUnsavedText,
          confirmText: tr.leave,
          cancelText: tr.stay);
      if (!ok || !mounted) return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // рішення — у _leave (дані могли змінитись без перебудови екрана)
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: _expense ? tr.newExpense : tr.newIncome, onBack: _leave),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: FinSegment(
                      labels: [tr.expenses, tr.income],
                      selected: _expense ? 0 : 1,
                      onChanged: (i) => _setKind(i == 0 ? kFinExpense : kFinIncome),
                    ),
                  ),
                  _sumBlock(),
                  _categories(),
                  _table(),
                  _dateRow(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: PillButton(
                text: tr.add,
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
      ),
    );
  }
}
