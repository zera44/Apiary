import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/stock_format.dart';
import '../services/stock_photos.dart';
import '../ui/common.dart';
import '../ui/first_hints.dart';
import '../ui/date_picker.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'history_hub_screen.dart' show StockHistoryScreen;
import '../ui/thousands_input.dart';

/// Склад: три вкладки.
/// «Прихід» — плитки номенклатури (з фото), під кожною «Прихід», внизу
/// «Додати номенклатуру». «Прихід і списання» — на кожній плитці «Прихід» і «Списати»; раніше «Вибуття» — номенклатура із залишком, під
/// кожною «Списати». «Переоблік» — «Перерахувати»: фактична кількість,
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
  late StockOp _op = widget.initialTab == StockOp.writeOff ? StockOp.receive : widget.initialTab;

  Repository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _reload();
    // склад змінили не тут (фото перетиснули фоном, операція з фінансів)
    repo.stockChanges.addListener(_reload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Hints.show(context, repo, Hints.stock);
    });
  }

  // позиції, що видаляються (чекають кінця «Відмінити»): _reload їх не повертає
  final Set<String> _hiding = {};

  Future<void> _reload() async {
    final list = [for (final i in await repo.listStockItems()) if (!_hiding.contains(i.id)) i];
    if (!mounted) return;
    // поля «Фактично», які не чіпали, показують свіжий залишок
    for (final it in list) {
      final base = formatAmount(it.quantity ?? 0);
      final c = _actual[it.id];
      if (c != null && c.text == _actualBase[it.id]) c.text = base;
      _actualBase[it.id] = base;
    }
    setState(() => items = list);
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
        if (res.photo != null || res.min != null) {
          await repo.updateStockItem(id,
              photo: res.photo != null ? (res.photo,) : null,
              minQuantity: res.min != null ? (res.min,) : null);
        }
        final r = res.receive;
        if (r != null) await repo.receiveStock(id, r.amount, total: r.total);
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
          // без підтвердження: позиція зникає одразу, внизу «Відмінити»
          unawaited(deleteWithUndo(
            context,
            message: 'Номенклатуру «${it.name}» видалено',
            hide: () {
              _hiding.add(it.id);
              setState(() => items = [...?items]..removeWhere((x) => x.id == it.id));
            },
            restore: () {
              _hiding.remove(it.id);
              _reload();
            },
            commit: () async {
              // фото лишається до прибирання сиріт: воно знадобиться, якщо
              // відновлять резервну копію з цією позицією
              await repo.deleteStockItem(it.id);
              _hiding.remove(it.id);
              if (mounted) await _reload();
            },
          ));
          return;
        } else {
          final photoChanged = res.photo != it.photo;
          await repo.updateStockItem(it.id,
              name: res.name,
              unit: res.unit,
              photo: photoChanged ? (res.photo,) : null,
              minQuantity: res.min != it.minQuantity ? (res.min,) : null);
          // старе фото прибере sweepOrphans (на нього можуть посилатися копії)
        }
        await _reload();
      });

  /// Операція з номенклатурою: прихід, списання або переоблік.
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

  Future<void> _history(StockItem it) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StockHistoryScreen(repo: repo, item: it)));
    await _reload(); // залишок міг змінитись (скасування запису)
  }

  /// Переоблік списком (усі позиції на одному екрані) чи по одній.
  bool _invList = false;
  final Map<String, TextEditingController> _actual = {};

  @override
  void dispose() {
    repo.stockChanges.removeListener(_reload);
    for (final c in _actual.values) {
      c.dispose();
    }
    super.dispose();
  }

  // чим поле «Фактично» було заповнене (щоб відрізнити неторкнуте від зміненого)
  final Map<String, String> _actualBase = {};

  TextEditingController _actualFor(StockItem it) {
    final base = formatAmount(it.quantity ?? 0);
    _actualBase.putIfAbsent(it.id, () => base);
    return _actual.putIfAbsent(it.id, () => TextEditingController(text: base));
  }

  /// «Зберегти переоблік»: записуються лише позиції, де фактична
  /// кількість відрізняється від облікової.
  Future<void> _saveInventoryList() => _guard(() async {
        final list = items ?? const <StockItem>[];
        for (final it in list) {
          final c = _actual[it.id];
          if (c == null) continue;
          final v = parseAmount(c.text);
          if (v == null) {
            if (mounted) {
              await showInfo(context, '«${it.name}»: фактична кількість - число, не менше 0',
                  title: 'Не збережено');
            }
            return;
          }
          if (!amountFitsUnit(v, it.unit)) {
            if (mounted) {
              await showInfo(context, '«${it.name}»: для «${it.unit}» вкажіть ціле число',
                  title: 'Не збережено');
            }
            return;
          }
        }
        var changed = 0;
        for (final it in list) {
          final text = _actual[it.id]?.text ?? '';
          if (text.trim() == _actualBase[it.id]) continue; // не чіпали
          final v = parseAmount(text);
          if (v == null || (v - (it.quantity ?? 0)).abs() < 1e-9) continue;
          await repo.inventoryStock(it.id, v);
          changed++;
        }
        await _reload();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(changed == 0
                  ? 'Розбіжностей немає - усе збігається з обліком'
                  : 'Переоблік збережено: змінено позицій - $changed')));
        }
      });

  Widget _inventoryList(List<StockItem> list) => ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final it = list[i];
          return ListCard(
            height: 64,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(it.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text('За обліком: ${formatAmount(it.quantity ?? 0)} ${it.unit}',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _actualFor(it),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(isDense: true, labelText: 'Фактично', suffixText: it.unit),
                ),
              ),
            ]),
          );
        },
      );

  Widget _modeChip(String text, bool list) => ChoiceChip(
        label: Text(text),
        selected: _invList == list,
        onSelected: (_) => setState(() => _invList = list),
      );

  Widget _tab(String text, StockOp op) => Expanded(
        child: PillButton(
          text: text,
          bg: _op == op ? AppColors.accent : AppColors.darkBtn,
          fg: _op == op ? Colors.white : AppColors.text,
          // великий шрифт: «Прихід і списання» у два рядки - вкладка вища
          height: math.max(40, MediaQuery.textScalerOf(context).scale(13) * 1.1 * 2 + 10),
          fontSize: 13,
          onPressed: () => setState(() => _op = op),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final all = items;
    final list = all;
    final title = switch (_op) {
      StockOp.receive || StockOp.writeOff => 'Прихід і списання',
      StockOp.inventory => 'Переоблік',
    };
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: title, onBack: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                // «Прихід» і «Списати» - на кожній плитці, тож одна вкладка
                _tab('Прихід і списання', StockOp.receive),
                const SizedBox(width: 8),
                _tab('Переоблік', StockOp.inventory),
              ]),
            ),
            // переоблік: по одній позиції чи всім списком
            if (_op == StockOp.inventory)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Wrap(spacing: 8, children: [
                  _modeChip('По одному', false),
                  _modeChip('Списком', true),
                ]),
              ),
            Expanded(
              child: TabSwipe(
              index: _op == StockOp.inventory ? 1 : 0,
              count: 2,
              onChanged: (i) => setState(() => _op = i == 1 ? StockOp.inventory : StockOp.receive),
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Ще немає жодної номенклатури',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textMuted)),
                          ))
                      : (_op == StockOp.inventory && _invList)
                          ? _inventoryList(list)
                          : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          // телефон боком: плитки нижчі за ширину, щоб «Прихід» і
                          // «Списати» було видно без прокрутки
                          gridDelegate: MediaQuery.sizeOf(context).height < 500
                              ? const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 190,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 200,
                                )
                              : const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 170,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.62,
                                ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _tile(list[i]),
                        ),
              ),
            ),
            if (_op == StockOp.inventory && _invList && (list?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.all(12),
                child: PillButton(
                  text: 'Зберегти переоблік',
                  bg: AppColors.accent,
                  height: 48,
                  radius: 16,
                  width: double.infinity,
                  onPressed: _saveInventoryList,
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
    final qty = it.quantity == null ? '-' : '${formatAmount(it.quantity!)} ${it.unit}';
    final (text, color) = switch (_op) {
      StockOp.receive => ('Прихід', AppColors.addObject),
      StockOp.writeOff => ('Списати', AppColors.danger),
      StockOp.inventory => ('Перерахувати', AppColors.rename),
    };
    return Column(children: [
      Text(it.name,
          maxLines: 2,
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
              // дійшли до мінімального залишку — червона рамка
              border: Border.all(color: it.low ? AppColors.danger : AppColors.darkBtn, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _edit(it),
                  child: Stack(children: [
                    Positioned.fill(child: StockPhoto(photo: it.photo)),
                    if (it.low)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: Container(
                          color: AppColors.danger,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: const Text('Час докупити',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    Positioned(
                      right: 2,
                      top: it.low ? 24 : 2,
                      child: Tooltip(
                        message: 'Історія',
                        child: InkWell(
                          onTap: () => _history(it),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.history, size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                        child: Text(qty,
                            textAlign: TextAlign.center,
                            maxLines: 2,
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
      if (_op == StockOp.receive)
        // «Прихід» і «Списати» поруч — не треба шукати вкладку
        Row(children: [
          Expanded(
            child: PillButton(
              text: text,
              bg: color,
              height: 36,
              radius: 12,
              fontSize: 13,
              onPressed: () => _move(it, _op),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: PillButton(
              text: 'Списати',
              bg: AppColors.danger,
              height: 36,
              radius: 12,
              fontSize: 13,
              // списати можна лише те, що є на складі
              onPressed: (it.quantity ?? 0) > 0 ? () => _move(it, StockOp.writeOff) : null,
            ),
          ),
        ])
      else
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

/// Фото номенклатури або заглушка. [thumb] - мініатюра (маленькі списки);
/// інакше повне фото (плитки складу, перегляд).
class StockPhoto extends StatelessWidget {
  final String? photo;
  final bool thumb;
  const StockPhoto({super.key, required this.photo, this.thumb = false});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.bgLight,
      alignment: Alignment.center,
      child: AppIcon('box', color: AppColors.textMuted, size: 44),
    );
    final path = thumb ? StockPhotos.thumbPath(photo) : StockPhotos.fullPath(photo);
    if (path == null) return placeholder;
    return Image.file(File(path),
        fit: BoxFit.cover,
        cacheWidth: thumb ? 200 : 400,
        errorBuilder: (_, _, _) => placeholder);
  }
}

/// Повне фото на весь екран (масштаб пальцями).
Future<void> showStockPhoto(BuildContext context, String photo) {
  final path = StockPhotos.fullPath(photo);
  if (path == null) return Future.value();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: Image.file(File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 64)),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              tooltip: tr.close,
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ]),
    ),
  );
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
  final double? min;
  final bool delete;

  /// Нова номенклатура: одразу оприбуткувати (кількість і загальна вартість).
  final ({double amount, double total})? receive;
  const _ItemResult(this.name, this.unit, this.photo, {this.min, this.delete = false, this.receive});
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
  final _recvAmount = TextEditingController();
  final _recvTotal = TextEditingController();
  late final _min = TextEditingController(
      text: widget.item?.minQuantity == null ? '' : formatAmount(widget.item!.minQuantity!));
  String? _error;
  bool _picking = false;

  /// Фото, зроблене в цьому діалозі (якщо діалог скасують — прибрати).
  String? _fresh;

  @override
  void dispose() {
    _name.dispose();
    _custom.dispose();
    _min.dispose();
    _recvAmount.dispose();
    _recvTotal.dispose();
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
      if (mounted) setState(() => _error = tr.photoFailed('$e'));
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
    final minText = _min.text.trim();
    final min = minText.isEmpty ? null : parseAmount(minText);
    if (minText.isNotEmpty && min == null) {
      setState(() => _error = 'Мінімальний залишок - число, не менше 0');
      return;
    }
    // нова номенклатура: одразу прихід (якщо вказали кількість)
    ({double amount, double total})? receive;
    if (widget.item == null && _recvAmount.text.trim().isNotEmpty) {
      final a = parseAmount(_recvAmount.text);
      final t = parseAmount(_recvTotal.text);
      if (a == null || a <= 0) {
        setState(() => _error = 'Прихід: кількість - число більше 0');
        return;
      }
      if (t == null) {
        setState(() => _error = 'Прихід: вкажіть загальну вартість');
        return;
      }
      receive = (amount: a, total: t);
    }
    Navigator.pop(context, _ItemResult(name, _unitValue, _photo, min: min, receive: receive));
  }

  /// Одиниця виміру - плитка, як тип даних параметра: обрана медова.
  Widget _chip(String label, String value) {
    final selected = _unit == value;
    final fg = selected ? Colors.white : AppColors.text;
    return Material(
      color: selected ? AppColors.accent : AppColors.typeBtn,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _unit = value;
          _error = null;
        }),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppColors.create : AppColors.hive.withValues(alpha: 0.25)),
          ),
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

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
            // плитки по три в ряд
            LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - 16) / 3;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final u in kStockUnits) SizedBox(width: w, height: 42, child: _chip(u, u)),
                SizedBox(width: w, height: 42, child: _chip('інша…', '')),
              ]);
            }),
            const SizedBox(height: 4),
            if (_unit == '')
              TextField(
                controller: _custom,
                autofocus: true,
                style: TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Своя одиниця'),
                onChanged: (_) => setState(() => _error = null),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: thousandsInput,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                labelText: 'Мінімальний залишок',
                helperText: 'Дійде до нього - «час докупити»',
                suffixText: _unitValue.isEmpty ? null : _unitValue,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (!edit) ...[
              const SizedBox(height: 14),
              Text('Одразу прихід (необов\'язково)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _recvAmount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: thousandsInput,
                    style: TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                        labelText: 'Кількість',
                        suffixText: _unitValue.isEmpty ? null : _unitValue),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _recvTotal,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: thousandsInput,
                    style: TextStyle(color: AppColors.text),
                    decoration: const InputDecoration(labelText: 'Вартість', suffixText: 'грн'),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  // дотик - повне фото
                  child: GestureDetector(
                    onTap: _photo == null ? null : () => showStockPhoto(context, _photo!),
                    child: Tooltip(
                      message: _photo == null ? '' : tr.photoOpen,
                      child: StockPhoto(photo: _photo, thumb: true),
                    ),
                  ),
                ),
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

/// Результат діалогу операції. [amount] — кількість (для переобліку —
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
    if (!amountFitsUnit(v, it.unit)) {
      setState(() => _error = 'Для «${it.unit}» вкажіть ціле число');
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
      // вартість приходу необов'язкова: порожньо - 0 (ціна за одиницю 0)
      total = parseAmount(_total.text) ?? 0;
    }
    final c = _comment.text.trim();
    Navigator.pop(context, _Move(v, _date, total: total, comment: c.isEmpty ? null : c));
  }

  InputDecoration _dec(String label, {String? suffix}) =>
      InputDecoration(labelText: label, suffixText: suffix, isDense: true);

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final numeric = thousandsInput;
    final (title, button, color) = switch (op) {
      StockOp.receive => ('Прихід', 'Зберегти', AppColors.accent),
      StockOp.writeOff => ('Списання', 'Списати', AppColors.danger),
      StockOp.inventory => ('Переоблік', 'Зберегти', AppColors.accent),
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
                decoration: _dec('Загальна вартість (за замовч. 0)', suffix: 'грн'),
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
