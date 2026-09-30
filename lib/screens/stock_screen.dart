import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/stock_format.dart';
import '../services/stock_photos.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';

/// Склад: три вкладки.
/// «Прихід» — плитки номенклатури (з фото), під кожною «Прихід», внизу
/// «Додати номенклатуру». «Вибуття» — номенклатура із залишком, під
/// кожною «Списати». «Інвентаризація» — «Перерахувати»: фактична кількість,
/// різниця (нестача/надлишок) записується окремо.
///
/// За правилами обліку нічого не перезаписується: кожна операція — окремий
/// запис (дата, кількість, ціна/причина, коментар), а залишок = прихід −
/// вибуття.
class StockScreen extends StatefulWidget {
  final Repository repo;

  /// Вкладка, що відкривається першою.
  final StockOp initialTab;
  const StockScreen({super.key, required this.repo, this.initialTab = StockOp.receive});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<StockItem>? items;
  bool _busy = false;
  late StockOp _op = widget.initialTab;

  Repository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await repo.listStockItems();
    if (mounted) setState(() => items = list);
  }

  /// Одна дія за раз (подвійний тап не відкриває два діалоги).
  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    _busy = true;
    try {
      await f();
    } finally {
      _busy = false;
    }
  }

  Future<void> _add() => _guard(() async {
        final res = await showDialog<_ItemResult>(
          context: context,
          builder: (_) => const _ItemDialog(),
        );
        if (res == null || res.delete) return;
        final id = await repo.addStockItem(res.name, res.unit);
        if (res.photo != null) await repo.updateStockItem(id, photo: (res.photo,));
        await _reload();
      });

  Future<void> _edit(StockItem it) => _guard(() async {
        final res = await showDialog<_ItemResult>(
          context: context,
          builder: (_) => _ItemDialog(item: it),
        );
        if (res == null) return;
        if (res.delete) {
          if (!mounted) return;
          final ok = await showConfirm(context, text: 'Видалити номенклатуру «${it.name}»?');
          if (!ok) return;
          await repo.deleteStockItem(it.id);
          await StockPhotos.remove(it.photo);
        } else {
          final photoChanged = res.photo != it.photo;
          await repo.updateStockItem(it.id,
              name: res.name, unit: res.unit, photo: photoChanged ? (res.photo,) : null);
          if (photoChanged) await StockPhotos.remove(it.photo);
        }
        await _reload();
      });

  /// Операція з номенклатурою: прихід, списання або інвентаризація.
  Future<void> _move(StockItem it, StockOp op) => _guard(() async {
        final m = await showDialog<_Move>(
          context: context,
          builder: (_) => _MoveDialog(item: it, op: op),
        );
        if (m == null) return;
        try {
          switch (op) {
            case StockOp.receive:
              await repo.receiveStock(it.id, m.amount, total: m.total!, date: m.date, comment: m.comment);
            case StockOp.writeOff:
              await repo.writeOffStock(it.id, m.amount, date: m.date, comment: m.comment);
            case StockOp.inventory:
              await repo.inventoryStock(it.id, m.amount, date: m.date, comment: m.comment);
          }
        } on StateError catch (e) {
          if (mounted) await showInfo(context, e.message);
        }
        await _reload();
      });

  Widget _tab(String text, StockOp op) => Expanded(
        child: PillButton(
          text: text,
          bg: _op == op ? AppColors.accent : AppColors.darkBtn,
          fg: _op == op ? Colors.white : AppColors.text,
          height: 40,
          fontSize: 13,
          onPressed: () => setState(() => _op = op),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final all = items;
    final out = _op == StockOp.writeOff;
    final list = all == null
        ? null
        : (out ? [for (final i in all) if ((i.quantity ?? 0) > 0) i] : all);
    final title = switch (_op) {
      StockOp.receive => 'Прихід номенклатури',
      StockOp.writeOff => 'Вибуття номенклатури',
      StockOp.inventory => 'Інвентаризація',
    };
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: title, onBack: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                _tab('Прихід', StockOp.receive),
                const SizedBox(width: 6),
                _tab('Вибуття', StockOp.writeOff),
                const SizedBox(width: 6),
                _tab('Інвентаризація', StockOp.inventory),
              ]),
            ),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                                out
                                    ? 'Немає що списувати.\nСпершу оформіть прихід номенклатури.'
                                    : 'Ще немає жодної номенклатури',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textMuted)),
                          ))
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 170,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.62,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _tile(list[i]),
                        ),
            ),
            if (_op == StockOp.receive)
              Padding(
                padding: const EdgeInsets.all(12),
                child: PillButton(
                  text: 'Додати номенклатуру',
                  bg: AppColors.accent,
                  height: 48,
                  radius: 16,
                  width: double.infinity,
                  onPressed: _add,
                ),
              ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  /// Плитка: назва, фото (тап — змінити), залишок і кнопка дії вкладки.
  Widget _tile(StockItem it) {
    final qty = it.quantity == null ? '—' : '${formatAmount(it.quantity!)} ${it.unit}';
    final (text, color) = switch (_op) {
      StockOp.receive => ('Прихід', AppColors.addObject),
      StockOp.writeOff => ('Списати', AppColors.danger),
      StockOp.inventory => ('Перерахувати', AppColors.rename),
    };
    return Column(children: [
      Text(it.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Expanded(
        child: Tooltip(
          message: 'Змінити',
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.darkBtn, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _edit(it),
                  child: Stack(children: [
                    Positioned.fill(child: StockPhoto(path: it.photo)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                        child: Text(qty,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      PillButton(
        text: text,
        bg: color,
        height: 36,
        radius: 12,
        width: double.infinity,
        onPressed: () => _move(it, _op),
      ),
    ]);
  }
}

/// Вкладки/операції складу.
enum StockOp { receive, writeOff, inventory }

/// Фото номенклатури або заглушка.
class StockPhoto extends StatelessWidget {
  final String? path;
  const StockPhoto({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.bgLight,
      alignment: Alignment.center,
      child: AppIcon('box', color: AppColors.textMuted, size: 44),
    );
    final p = path;
    if (p == null) return placeholder;
    return Image.file(File(p),
        fit: BoxFit.cover, cacheWidth: 400, errorBuilder: (_, __, ___) => placeholder);
  }
}

Widget _buttons(List<Widget> buttons) => Row(children: [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: buttons[i]),
      ]
    ]);

class _ItemResult {
  final String name;
  final String unit;
  final String? photo;
  final bool delete;
  const _ItemResult(this.name, this.unit, this.photo, {this.delete = false});
}

/// Створення/зміна номенклатури: назва, одиниця виміру, фото.
class _ItemDialog extends StatefulWidget {
  final StockItem? item;
  const _ItemDialog({this.item});
  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _custom = TextEditingController(
      text: kStockUnits.contains(widget.item?.unit) ? '' : (widget.item?.unit ?? ''));
  late String? _unit = widget.item == null
      ? null
      : (kStockUnits.contains(widget.item!.unit) ? widget.item!.unit : '');
  late String? _photo = widget.item?.photo;
  String? _error;
  bool _picking = false;

  /// Фото, зроблене в цьому діалозі (якщо діалог скасують — прибрати).
  String? _fresh;

  @override
  void dispose() {
    _name.dispose();
    _custom.dispose();
    super.dispose();
  }

  String get _unitValue => _unit == '' ? _custom.text.trim() : (_unit ?? '');

  Future<void> _pick(bool camera) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final path = await StockPhotos.pick(camera: camera);
      if (path == null || !mounted) return;
      if (_fresh != null) await StockPhotos.remove(_fresh);
      setState(() {
        _photo = path;
        _fresh = path;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Не вдалося отримати фото: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _cancel() {
    StockPhotos.remove(_fresh);
    Navigator.pop(context);
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Вкажіть назву');
      return;
    }
    if (_unitValue.isEmpty) {
      setState(() => _error = 'Вкажіть одиницю виміру');
      return;
    }
    Navigator.pop(context, _ItemResult(name, _unitValue, _photo));
  }

  Widget _chip(String label, String value) => ChoiceChip(
        label: Text(label),
        // компактні: з клавіатурою на екрані діалог і так невисокий
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        selected: _unit == value,
        onSelected: (_) => setState(() {
          _unit = value;
          _error = null;
        }),
      );

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    return AlertDialog(
      title: Text(edit ? 'Номенклатура' : 'Нова номенклатура'),
      scrollable: false,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          // відступ зверху — щоб підпис поля «Назва» не обрізався краєм прокрутки
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: !edit,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Назва'),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 14),
            Text('Одиниця виміру', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final u in kStockUnits) _chip(u, u),
              _chip('інша…', ''),
            ]),
            if (_unit == '')
              TextField(
                controller: _custom,
                autofocus: true,
                style: TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Своя одиниця'),
                onChanged: (_) => setState(() => _error = null),
              ),
            const SizedBox(height: 14),
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 72, height: 72, child: StockPhoto(path: _photo)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (StockPhotos.cameraSupported)
                    PillButton(
                      text: 'Зробити фото',
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 34,
                      onPressed: _picking ? null : () => _pick(true),
                    ),
                  if (StockPhotos.cameraSupported) const SizedBox(height: 6),
                  PillButton(
                    text: StockPhotos.cameraSupported ? 'З галереї' : 'Обрати фото',
                    bg: AppColors.darkBtn,
                    fg: AppColors.text,
                    height: 34,
                    onPressed: _picking ? null : () => _pick(false),
                  ),
                  if (_photo != null) ...[
                    const SizedBox(height: 6),
                    PillButton(
                      text: 'Прибрати фото',
                      bg: AppColors.neutralBtn,
                      fg: AppColors.text,
                      height: 34,
                      onPressed: () => setState(() => _photo = null),
                    ),
                  ],
                ]),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        if (edit)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PillButton(
              text: 'Видалити',
              bg: AppColors.danger,
              width: double.infinity,
              onPressed: () => Navigator.pop(
                  context, _ItemResult(widget.item!.name, widget.item!.unit, null, delete: true)),
            ),
          ),
        _buttons([
          PillButton(text: 'Скасувати', bg: AppColors.neutralBtn, fg: AppColors.text, onPressed: _cancel),
          PillButton(text: 'Зберегти', bg: AppColors.accent, onPressed: _save),
        ]),
      ],
    );
  }
}

/// Результат діалогу операції. [amount] — кількість (для інвентаризації —
/// фактична кількість), [total] — загальна вартість приходу.
class _Move {
  final double amount;
  final DateTime date;
  final double? total;
  final String? comment;
  const _Move(this.amount, this.date, {this.total, this.comment});
}

/// Діалог операції. Порядок полів: дата (типово сьогодні) → кількість →
/// (для приходу, обов'язково) загальна вартість → коментар. Ціну за одиницю система
/// рахує сама: вартість / кількість.
class _MoveDialog extends StatefulWidget {
  final StockItem item;
  final StockOp op;
  const _MoveDialog({required this.item, required this.op});
  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  final _amount = TextEditingController();
  final _total = TextEditingController();
  final _comment = TextEditingController();
  DateTime _date = DateTime.now();
  String? _error;

  StockOp get op => widget.op;

  @override
  void dispose() {
    _amount.dispose();
    _total.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final v = await showAppDatePicker(context, formatDdMmYyyy(_date));
    final d = parseDdMmYyyy(v);
    if (d != null && mounted) setState(() => _date = d);
  }

  /// Ціна за одиницю з того, що введено зараз (або null).
  String? get _unitPrice {
    final a = parseAmount(_amount.text), t = parseAmount(_total.text);
    if (a == null || a == 0 || t == null) return null;
    return '${formatMoney(t / a)} грн/${widget.item.unit}';
  }

  void _save() {
    final it = widget.item;
    final v = parseAmount(_amount.text);
    if (v == null || (op != StockOp.inventory && v == 0)) {
      setState(() => _error = op == StockOp.inventory
          ? 'Введіть фактичну кількість (0 або більше)'
          : 'Введіть кількість більше 0');
      return;
    }
    if (op == StockOp.writeOff) {
      final left = it.quantity ?? 0;
      if (v > left + 1e-9) {
        setState(() => _error = 'Можна списати не більше ${formatAmount(left)} ${it.unit}');
        return;
      }
    }
    double? total;
    if (op == StockOp.receive) {
      // вартість приходу обов'язкова: з неї рахується ціна за одиницю
      total = parseAmount(_total.text);
      if (total == null) {
        setState(() => _error = 'Вкажіть загальну вартість приходу');
        return;
      }
    }
    final c = _comment.text.trim();
    Navigator.pop(context, _Move(v, _date, total: total, comment: c.isEmpty ? null : c));
  }

  InputDecoration _dec(String label, {String? suffix}) =>
      InputDecoration(labelText: label, suffixText: suffix, isDense: true);

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final numeric = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final (title, button, color) = switch (op) {
      StockOp.receive => ('Прихід', 'Зберегти', AppColors.accent),
      StockOp.writeOff => ('Списання', 'Списати', AppColors.danger),
      StockOp.inventory => ('Інвентаризація', 'Зберегти', AppColors.accent),
    };
    final price = op == StockOp.receive ? _unitPrice : null;
    return AlertDialog(
      title: Text('$title: ${it.name}'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                op == StockOp.inventory
                    ? 'За обліком: ${formatAmount(it.quantity ?? 0)} ${it.unit}'
                    : 'Залишок: ${formatAmount(it.quantity ?? 0)} ${it.unit}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            // 1. дата
            Row(children: [
              Text('Дата: ', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              Expanded(
                child: PillButton(
                  text: formatDdMmYyyy(_date),
                  bg: AppColors.darkBtn,
                  fg: AppColors.text,
                  height: 36,
                  onPressed: _pickDate,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // 2. кількість
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numeric,
              style: TextStyle(color: AppColors.text),
              decoration: _dec(op == StockOp.inventory ? 'Фактична кількість' : 'Кількість', suffix: it.unit),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 10),
            // 3. загальна вартість (лише прихід) — ціну за одиницю рахує система
            if (op == StockOp.receive) ...[
              TextField(
                controller: _total,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numeric,
                style: TextStyle(color: AppColors.text),
                decoration: _dec('Загальна вартість', suffix: 'грн'),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (price != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Ціна за одиницю: $price',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ),
              const SizedBox(height: 10),
            ],
            // 4. коментар
            TextField(
              controller: _comment,
              style: TextStyle(color: AppColors.text),
              decoration: _dec('Коментар (необов\'язково)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        _buttons([
          PillButton(
              text: 'Скасувати',
              bg: AppColors.neutralBtn,
              fg: AppColors.text,
              onPressed: () => Navigator.pop(context)),
          PillButton(text: button, bg: color, onPressed: _save),
        ]),
      ],
    );
  }
}
