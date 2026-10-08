import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../logic/receipt_parser.dart';
import '../logic/stock_format.dart';
import '../services/receipt_ocr.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'stock_screen.dart';

/// Чек після сканування: розпізнані позиції в таблиці «Товар / Кількість /
/// Ціна». Усе можна виправити, зайве - зняти галочкою чи видалити; «Додати на
/// склад» записує прихід (нова номенклатура створюється, наявна - за назвою -
/// поповнюється).
class ReceiptScreen extends StatefulWidget {
  final Repository repo;

  /// Фото чека (null - порожня таблиця для ручного введення).
  final String? imagePath;

  /// Чим розпізнавати (у тестах підміняється).
  final ReceiptOcr? ocr;
  const ReceiptScreen({super.key, required this.repo, this.imagePath, this.ocr});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _Line {
  bool use = true;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  String unit;

  _Line(ReceiptRow r)
      : name = TextEditingController(text: r.name),
        qty = TextEditingController(text: formatAmount(r.qty)),
        price = TextEditingController(text: r.price == 0 ? '' : formatMoney(r.price)),
        unit = r.unit;

  double? get qtyValue => parseAmount(qty.text);
  double? get priceValue => parseAmount(price.text);

  /// Рядок придатний до запису: назва, кількість > 0, ціна (може бути 0).
  bool get valid =>
      name.text.trim().isNotEmpty && (qtyValue ?? 0) > 0 && priceValue != null;

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
  }
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final List<_Line> _lines = [];
  bool _reading = true;
  bool _saving = false;
  String? _note;

  ReceiptOcr get _ocr => widget.ocr ?? ReceiptOcr.instance;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _recognize() async {
    final path = widget.imagePath;
    if (path == null) {
      setState(() => _reading = false);
      return;
    }
    if (!_ocr.supported) {
      setState(() {
        _reading = false;
        _note = 'Розпізнавання тексту працює на телефоні. Тут заповніть таблицю вручну.';
      });
      return;
    }
    try {
      final text = await _ocr.read(path);
      final rows = parseReceipt(text);
      if (!mounted) return;
      setState(() {
        _lines.addAll(rows.map(_Line.new));
        _reading = false;
        _note = rows.isEmpty
            ? 'Не вдалося розпізнати позиції. Спробуйте сфотографувати рівніше й при гарному '
                'світлі або додайте рядки вручну.'
            : 'Перевірте таблицю: розпізнавання може помилятися.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _note = 'Не вдалося розпізнати чек. Додайте рядки вручну.';
      });
    }
  }

  /// Позначені рядки списком «Назва 1 шт, 75 грн, сума 75 грн».
  Future<void> _copy() async {
    final rows = [
      for (final l in _lines)
        if (l.use && l.valid)
          ReceiptRow(name: l.name.text.trim(), qty: l.qtyValue!, unit: l.unit, price: l.priceValue!)
    ];
    if (rows.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: receiptAsText(rows)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Список скопійовано')));
  }

  void _addLine() => setState(() => _lines.add(_Line(ReceiptRow(name: '', price: 0))));

  void _remove(_Line l) {
    setState(() => _lines.remove(l));
    l.dispose();
  }

  double get _sum => [
        for (final l in _lines)
          if (l.use && l.valid) l.qtyValue! * l.priceValue!
      ].fold(0.0, (a, b) => a + b);

  Future<void> _save() async {
    if (_saving) return;
    final todo = [for (final l in _lines) if (l.use) l];
    if (todo.isEmpty) {
      await showInfo(context, 'Немає позицій для запису: позначте хоча б одну.');
      return;
    }
    final bad = todo.where((l) => !l.valid).toList();
    if (bad.isNotEmpty) {
      await showInfo(
          context,
          'У ${bad.length == 1 ? 'одному рядку' : '${bad.length} рядках'} не вистачає назви, '
          'кількості (більше 0) або ціни. Виправте їх чи зніміть галочку.',
          title: 'Не записано');
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = {
        for (final i in await widget.repo.listStockItems()) i.name.trim().toLowerCase(): i.id
      };
      var created = 0, topped = 0;
      for (final l in todo) {
        final name = l.name.text.trim();
        var id = existing[name.toLowerCase()];
        if (id == null) {
          id = await widget.repo.addStockItem(name, l.unit);
          existing[name.toLowerCase()] = id;
          created++;
        } else {
          topped++;
        }
        final qty = l.qtyValue!;
        await widget.repo.receiveStock(id, qty, total: qty * l.priceValue!, comment: 'Чек');
      }
      if (!mounted) return;
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      nav.pushReplacement(MaterialPageRoute(builder: (_) => StockScreen(repo: widget.repo)));
      messenger.showSnackBar(SnackBar(
          content: Text('Додано на склад: ${todo.length} '
              '(нових - $created, поповнено - $topped)')));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await showInfo(context, 'Не вдалося записати: $e', title: 'Помилка');
      }
    }
  }

  Widget _header() {
    final s = TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(children: [
        const SizedBox(width: 40),
        Expanded(flex: 5, child: Text('Товар', style: s)),
        const SizedBox(width: 6),
        Expanded(flex: 3, child: Text('Кількість', style: s)),
        const SizedBox(width: 6),
        Expanded(flex: 3, child: Text('Ціна', style: s)),
        const SizedBox(width: 36),
      ]),
    );
  }

  Widget _row(_Line l) {
    const dense = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10));
    final style = TextStyle(color: AppColors.text, fontSize: 13.5);
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 6, 2, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: l.use && !l.valid ? AppColors.danger : AppColors.darkBtn),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
       Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 36,
          child: Checkbox(
            value: l.use,
            onChanged: (v) => setState(() => l.use = v ?? true),
          ),
        ),
        Expanded(
          flex: 5,
          child: TextField(
            controller: l.name,
            style: style,
            minLines: 1,
            maxLines: 3,
            decoration: dense.copyWith(hintText: 'Назва'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: TextField(
            controller: l.qty,
            style: style,
            keyboardType: numKb,
            decoration: dense.copyWith(
              suffixIcon: PopupMenuButton<String>(
                tooltip: 'Одиниця',
                padding: EdgeInsets.zero,
                onSelected: (u) => setState(() => l.unit = u),
                itemBuilder: (_) => [
                  for (final u in {...kStockUnits, l.unit}) PopupMenuItem(value: u, child: Text(u)),
                ],
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(l.unit,
                      style: TextStyle(color: AppColors.create, fontSize: 12.5, fontWeight: FontWeight.bold)),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: TextField(
            controller: l.price,
            style: style,
            keyboardType: numKb,
            decoration: dense.copyWith(hintText: '0'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          width: 34,
          child: IconButton(
            tooltip: 'Видалити рядок',
            padding: EdgeInsets.zero,
            icon: Icon(Icons.close, size: 20, color: AppColors.textMuted),
            onPressed: () => _remove(l),
          ),
        ),
       ]),
        if (l.valid)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 4, 40, 0),
            child: Text('сума ${formatMoney(l.qtyValue! * l.priceValue!)} грн',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.imagePath;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Чек', onBack: () => Navigator.pop(context)),
            if (_reading)
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text('Розпізнаю чек…', style: TextStyle(color: AppColors.textMuted)),
                  ]),
                ),
              )
            else ...[
              if (img != null && File(img).existsSync())
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 90,
                      width: double.infinity,
                      child: Image.file(File(img), fit: BoxFit.cover, alignment: Alignment.topCenter),
                    ),
                  ),
                ),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(_note!,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.3)),
                ),
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  children: [
                    for (final l in _lines) _row(l),
                    PillButton(
                      text: '+ Додати рядок',
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 42,
                      width: double.infinity,
                      onPressed: _addLine,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(children: [
                  Text('Разом: ', style: TextStyle(color: AppColors.textMuted)),
                  Text('${formatMoney(_sum)} грн',
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_lines.any((l) => l.use && l.valid))
                    IconButton(
                      tooltip: 'Копіювати список',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copy,
                      icon: Icon(Icons.copy, size: 20, color: AppColors.textMuted),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: PillButton(
                  text: 'Додати на склад',
                  bg: AppColors.accent,
                  height: 48,
                  radius: 16,
                  width: double.infinity,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
