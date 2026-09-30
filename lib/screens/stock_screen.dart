import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/stock_format.dart';
import '../services/stock_photos.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';

/// Склад → «Прихід номенклатури»: плитки номенклатури (з фото), кнопка
/// «Заповнити» під кожною й «Додати номенклатуру» внизу.
class StockScreen extends StatefulWidget {
  final Repository repo;
  const StockScreen({super.key, required this.repo});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<StockItem>? items;
  bool _busy = false;

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

  /// «Заповнити»: уперше — просто кількість; далі спершу вибір
  /// «Перезаписати» / «Додати».
  Future<void> _fill(StockItem it) => _guard(() async {
        bool add = false;
        if (it.quantity != null) {
          final choice = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(it.name),
              content: Text(
                'Зараз: ${formatAmount(it.quantity!)} ${it.unit}.\n'
                '«Перезаписати» — замінити цю кількість новою.\n'
                '«Додати» — додати нову кількість до наявної.',
                style: TextStyle(color: AppColors.text),
              ),
              actions: [
                _buttons([
                  PillButton(
                      text: 'Перезаписати',
                      bg: AppColors.danger,
                      onPressed: () => Navigator.pop(ctx, false)),
                  PillButton(
                      text: 'Додати', bg: AppColors.accent, onPressed: () => Navigator.pop(ctx, true)),
                ]),
              ],
            ),
          );
          if (choice == null) return;
          add = choice;
        }
        if (!mounted) return;
        final amount = await showDialog<double>(
          context: context,
          builder: (_) => _AmountDialog(item: it, add: add),
        );
        if (amount == null) return;
        await repo.fillStock(it.id, amount, add: add);
        await _reload();
      });

  @override
  Widget build(BuildContext context) {
    final list = items;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Прихід номенклатури', onBack: () => Navigator.pop(context)),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодної номенклатури',
                              style: TextStyle(color: AppColors.textMuted)))
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

  /// Плитка: назва, фото (тап — змінити), кількість і «Заповнити».
  Widget _tile(StockItem it) {
    final qty = it.quantity == null ? '—' : '${formatAmount(it.quantity!)} ${it.unit}';
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
        text: 'Заповнити',
        bg: AppColors.addObject,
        height: 36,
        radius: 12,
        width: double.infinity,
        onPressed: () => _fill(it),
      ),
    ]);
  }
}

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
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
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

/// Введення кількості (дробові числа — з комою або крапкою).
class _AmountDialog extends StatefulWidget {
  final StockItem item;
  final bool add;
  const _AmountDialog({required this.item, required this.add});
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseAmount(_ctrl.text);
    if (v == null) {
      setState(() => _error = 'Введіть число, не менше 0');
      return;
    }
    if (widget.add && v == 0) {
      setState(() => _error = 'Додати можна лише більше 0');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final title = it.quantity == null ? 'Кількість' : (widget.add ? 'Додати кількість' : 'Нова кількість');
    return AlertDialog(
      title: Text('$title: ${it.name}'),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (it.quantity != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Зараз: ${formatAmount(it.quantity!)} ${it.unit}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: TextStyle(color: AppColors.text),
            decoration: InputDecoration(suffixText: it.unit),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        _buttons([
          PillButton(
              text: 'Скасувати',
              bg: AppColors.neutralBtn,
              fg: AppColors.text,
              onPressed: () => Navigator.pop(context)),
          PillButton(text: 'Зберегти', bg: AppColors.accent, onPressed: _save),
        ]),
      ],
    );
  }
}
