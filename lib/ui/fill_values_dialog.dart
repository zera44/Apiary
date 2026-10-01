import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../logic/stock_format.dart';
import 'common.dart';
import 'date_picker.dart';
import 'icons.dart';
import 'theme.dart';

/// Форма "Заповнити": поле на кожен прив'язаний параметр. Тип даних
/// обмежує ввід (ціле / дробове), для "Дата" — календар, для "Колір" —
/// фіксовані зразки. Повертає {parameter_id: нове значення} лише для
/// змінених полів (порожній рядок — значення прибрали), або null, якщо
/// скасовано.
///
/// [onNext] — «Зберегти й далі» БЕЗ закриття вікна: викликач зберігає
/// результат і повертає дані наступного вулика (вікно лише міняє вміст)
/// або null — тоді вікно закривається (результат уже збережено).
Future<FillResult?> showFillValuesDialog(
  BuildContext context, {
  required List<Parameter> params,
  required Map<String, String?> latest,
  bool offerNext = false,
  List<StockItem> stock = const [],
  String? title,
  Future<FillPage?> Function(FillResult result)? onNext,
}) {
  return showDialog<FillResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FillHost(
      first: FillPage(params: params, latest: latest, stock: stock, title: title),
      offerNext: offerNext,
      onNext: onNext,
    ),
  );
}

/// Вміст форми для одного вулика (для «Зберегти й далі» — наступного).
class FillPage {
  final String? title;
  final List<Parameter> params;
  final Map<String, String?> latest;
  final List<StockItem> stock;
  const FillPage(
      {required this.params, required this.latest, this.stock = const [], this.title});
}

/// Тримає поточну сторінку: на «Зберегти й далі» підміняє вміст тієї самої
/// форми даними наступного вулика (нове вікно не відкривається).
class _FillHost extends StatefulWidget {
  final FillPage first;
  final bool offerNext;
  final Future<FillPage?> Function(FillResult result)? onNext;
  const _FillHost({required this.first, required this.offerNext, this.onNext});
  @override
  State<_FillHost> createState() => _FillHostState();
}

class _FillHostState extends State<_FillHost> {
  late FillPage _page = widget.first;
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    final onNext = widget.onNext;
    return _FillDialog(
      key: ValueKey(_n), // новий вулик — нові поля
      title: _page.title,
      params: _page.params,
      latest: _page.latest,
      offerNext: widget.offerNext,
      stock: [for (final it in _page.stock) if ((it.quantity ?? 0) > 0) it],
      onNext: onNext == null
          ? null
          : (result) async {
              final next = await onNext(result);
              if (!mounted) return;
              if (next == null) {
                Navigator.pop(context);
              } else {
                setState(() {
                  _page = next;
                  _n++;
                });
              }
            },
    );
  }
}

/// Результат форми: змінені значення й чи натиснули «Зберегти й далі»
/// (обхід ланцюжком — одразу наступний вулик).
class FillResult {
  final Map<String, String> values;
  final bool next;

  /// Підгодівля зі складу: що й скільки списати (або null).
  final ({String itemId, double amount})? feed;
  const FillResult(this.values, {this.next = false, this.feed});
}

class _FillDialog extends StatefulWidget {
  final String? title;
  final List<Parameter> params;
  final Map<String, String?> latest;
  final bool offerNext;
  final List<StockItem> stock;
  final Future<void> Function(FillResult result)? onNext;
  const _FillDialog(
      {super.key,
      this.title,
      required this.params,
      required this.latest,
      this.offerNext = false,
      this.stock = const [],
      this.onNext});
  @override
  State<_FillDialog> createState() => _FillDialogState();
}

class _FillDialogState extends State<_FillDialog> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _picked = {}; // для дати й кольору
  // ВИПРАВЛЕНО: фільтр вводу пропускав "напівготові" значення типу "-"
  // чи "," — без цієї перевірки вони зберігались в історію як нібито
  // числове значення.
  String? _error;

  static final _intFilter = WholeValueFormatter(RegExp(r'^-?\d*$'));
  static final _floatFilter = WholeValueFormatter(RegExp(r'^-?\d*[.,]?\d*$'));

  @override
  void initState() {
    super.initState();
    for (final p in widget.params) {
      final cur = widget.latest[p.id] ?? '';
      if (p.dataType == DataTypes.date || p.dataType == DataTypes.color) {
        _picked[p.id] = cur;
      } else {
        _text[p.id] = TextEditingController(text: cur);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _feedAmount.dispose();
    super.dispose();
  }

  String? _feedItem;
  final _feedAmount = TextEditingController();

  bool _saving = false;

  Future<void> _save({bool next = false}) async {
    if (_saving) return;
    ({String itemId, double amount})? feed;
    final fid = _feedItem;
    if (fid != null) {
      final it = widget.stock.firstWhere((s) => s.id == fid);
      final a = parseAmount(_feedAmount.text);
      if (a == null || a <= 0) {
        setState(() => _error = 'Підгодівля: вкажіть кількість');
        return;
      }
      if (a > (it.quantity ?? 0) + 1e-9) {
        setState(() => _error =
            'Підгодівля: на складі лише ${formatAmount(it.quantity ?? 0)} ${it.unit}');
        return;
      }
      feed = (itemId: fid, amount: a);
    }
    final out = <String, String>{};
    for (final p in widget.params) {
      final raw = (_text[p.id]?.text ?? _picked[p.id] ?? '').trim();
      final before = (widget.latest[p.id] ?? '').trim();
      // поле не чіпали — не перевіряємо й не записуємо (навіть якщо старе
      // значення не відповідає типу, напр., з давніших версій)
      if (raw == before) continue;
      if (raw.isEmpty) {
        // поле спорожнили (або "Очистити" в календарі): якщо раніше значення
        // було — записуємо порожнє, тож у історії видно, що його прибрали
        if ((widget.latest[p.id] ?? '').isNotEmpty) out[p.id] = '';
        continue;
      }
      var v = raw;
      if (p.dataType == DataTypes.int_) {
        final n = int.tryParse(v);
        if (n == null) {
          setState(() => _error = '«${p.nameWithUnit}»: введіть ціле число');
          return;
        }
        v = n.toString();
      } else if (p.dataType == DataTypes.float_) {
        final n = double.tryParse(v.replaceAll(',', '.'));
        if (n == null) {
          setState(() => _error = '«${p.nameWithUnit}»: введіть число');
          return;
        }
        v = n.toString();
      }
      if (v != (widget.latest[p.id] ?? '')) out[p.id] = v;
    }
    final result = FillResult(out, next: next, feed: feed);
    final onNext = widget.onNext;
    if (next && onNext != null) {
      setState(() => _saving = true);
      try {
        await onNext(result); // збереже й підставить наступний вулик
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    Navigator.pop(context, result);
  }

  /// Значення — таблицею, як на панелі вулика: зліва параметр, справа
  /// поле. Сітка медова; підгодівля зі складу — останніми рядками.
  Widget _table() {
    final grid = AppColors.hive.withValues(alpha: 0.55);
    TableRow row(String name, Widget value) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(name,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.25)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: value,
          ),
        ]);
    final feed = _feedItem == null ? null : widget.stock.firstWhere((s) => s.id == _feedItem);
    return Table(
      border: TableBorder.all(color: grid, width: 1, borderRadius: BorderRadius.circular(10)),
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final p in widget.params) row(p.nameWithUnit, _field(p)),
        if (widget.stock.isNotEmpty)
          row(
            'Підгодівля зі складу',
            DropdownButton<String?>(
              value: _feedItem,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.popupBg,
              hint: Text('Не списувати', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              items: [
                DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Не списувати', style: TextStyle(color: AppColors.text))),
                for (final s in widget.stock)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text('${s.name} (є ${formatAmount(s.quantity ?? 0)} ${s.unit})',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text)),
                  ),
              ],
              onChanged: (v) => setState(() {
                _feedItem = v;
                _error = null;
              }),
            ),
          ),
        if (feed != null)
          row(
            'Скільки, ${feed.unit}',
            TextField(
              controller: _feedAmount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.text, fontSize: 15),
              decoration: _cellInput,
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
      ],
    );
  }

  static const _cellInput = InputDecoration(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
    hintText: '—',
  );

  Widget _field(Parameter p) {
    switch (p.dataType) {
      case DataTypes.date:
        final dateText = _picked[p.id] ?? '';
        // уся клітинка — кнопка календаря
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final r = await showAppDatePicker(context, dateText);
            if (r != null) setState(() => _picked[p.id] = r);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(children: [
              Expanded(
                child: Text(dateText.isEmpty ? 'Обрати дату' : dateText,
                    style: TextStyle(
                        color: dateText.isEmpty ? AppColors.textMuted : AppColors.text,
                        fontSize: 15)),
              ),
              Icon(Icons.calendar_today, size: 16, color: AppColors.textMuted),
            ]),
          ),
        );
      case DataTypes.color:
        final colorLabel = _picked[p.id] ?? '';
        return Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (label, c) in queenTagChoices)
            ColorTagSwatch(
              fill: c,
              size: 28,
              selected: colorLabel == label,
              tooltip: label,
              // повторний тап по обраному кольору — зняти вибір
              onTap: () => setState(() => _picked[p.id] = colorLabel == label ? '' : label),
            ),
        ]);
      default:
        return TextField(
          controller: _text[p.id],
          style: TextStyle(color: AppColors.text, fontSize: 15),
          decoration: _cellInput,
          keyboardType: p.dataType == DataTypes.int_
              ? const TextInputType.numberWithOptions(signed: true)
              : p.dataType == DataTypes.float_
                  ? const TextInputType.numberWithOptions(signed: true, decimal: true)
                  : TextInputType.text,
          inputFormatters: p.dataType == DataTypes.int_
              ? [_intFilter]
              : p.dataType == DataTypes.float_
                  ? [_floatFilter]
                  : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // назва вулика — видно, що «Зберегти й далі» перейшло до наступного
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.title != null) Text(widget.title!),
        Text('Заповнити параметри',
            style: widget.title == null
                ? null
                : TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w400)),
      ]),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [_table()],
        )),
      ),
      actions: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          // помилка — біля кнопок, щоб її було видно при будь-якій кількості полів
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          Row(children: [
            Expanded(
              child: PillButton(
                  text: 'Скасувати',
                  bg: AppColors.neutralBtn,
                  fg: AppColors.text,
                  onPressed: () => Navigator.pop(context)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: PillButton(
                    text: 'Зберегти', bg: AppColors.accent, onPressed: _saving ? null : _save)),
          ]),
          if (widget.offerNext) ...[
            const SizedBox(height: 8),
            // обхід ланцюжком: зберегти й одразу наступний вулик
            PillButton(
              text: 'Зберегти й далі →',
              bg: AppColors.create,
              width: double.infinity,
              onPressed: _saving ? null : () => _save(next: true),
            ),
          ],
        ]),
      ],
    );
  }
}

/// Пропускає зміну поля, лише якщо ВЕСЬ новий текст відповідає [pattern];
/// інакше лишає попередній (раніше фільтр вирізав "зайве" й з "1.5" у
/// цілому полі виходило "15", а вставка " 25" очищала поле). Пробіли по
/// краях вставленого тексту прибираються.
class WholeValueFormatter extends TextInputFormatter {
  final RegExp pattern;
  WholeValueFormatter(this.pattern);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (pattern.hasMatch(newValue.text)) return newValue;
    final trimmed = newValue.text.trim();
    if (trimmed != newValue.text && pattern.hasMatch(trimmed)) {
      return TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    return oldValue;
  }
}
