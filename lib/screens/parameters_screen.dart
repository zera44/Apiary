import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'history_screen.dart';

/// Екран "Список параметрів" (порт parameters_screen.py).
///
/// Чекбоксом параметр із каталогу прив'язується до об'єкта; "Зберегти"
/// записує весь набір. "+" — новий параметр у каталозі. Базові
/// характеристики для типу об'єкта завжди позначені й заблоковані.
///
/// Два режими: для вже розміщеного об'єкта/групи ([ParametersScreen.forElement]
/// — набір пишеться в базу) і для екземпляра в редакторі шаблону
/// ([ParametersScreen.forTemplate] — обраний список повертається через
/// Navigator.pop).
class ParametersScreen extends StatefulWidget {
  final Repository repo;
  final MapElement? element;
  final List<String> initialIds;
  final String? elType;

  /// Загальний каталог (з бокового меню): без вибору й без "Зберегти" —
  /// лише створення, редагування, видалення та історія параметрів.
  final bool catalog;

  const ParametersScreen.forElement({super.key, required this.repo, required MapElement this.element})
      : initialIds = const [],
        elType = null,
        catalog = false;

  const ParametersScreen.catalog({super.key, required this.repo})
      : element = null,
        initialIds = const [],
        elType = null,
        catalog = true;

  const ParametersScreen.forTemplate({
    super.key,
    required this.repo,
    required this.initialIds,
    required this.elType,
  })  : element = null,
        catalog = false;

  bool get templateMode => element == null && !catalog;

  @override
  State<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {
  Repository get repo => widget.repo;
  List<Parameter>? params;

  /// УПОРЯДКОВАНИЙ список: порядок вибору = порядок показу на панелі.
  List<String> selected = [];

  String? get targetType => widget.element?.type ?? widget.elType;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.element != null) {
      selected = await repo.attachedParameterIds(widget.element!.entity, elType: targetType);
    } else {
      final base = await repo.baseParameterIds(targetType);
      selected = [
        ...base.where((id) => !widget.initialIds.contains(id)),
        ...widget.initialIds,
      ];
    }
    await _reload();
  }

  Future<void> _reload() async {
    var list = await repo.listParameters();
    // базові характеристики ІНШИХ типів об'єктів (напр., вулика в списку
    // перешкоди) прив'язати не можна — у списку об'єкта їх не показуємо
    if (!widget.catalog) list = [for (final p in list) if (!p.isBase || _lockedBase(p)) p];
    // обов'язкові (з замочком) — завжди вгорі, решта в тому ж порядку
    final pinned = [for (final p in list) if (_pinned(p)) p];
    final rest = [for (final p in list) if (!_pinned(p)) p];
    if (mounted) setState(() => params = [...pinned, ...rest]);
  }

  bool _lockedBase(Parameter p) => p.isBase && targetType != null && p.baseType == targetType;

  /// Характеристика з замочком: обов'язкова, закріплена вгорі, без редагування.
  bool _pinned(Parameter p) => _lockedBase(p) || (widget.catalog && p.isBase);

  bool _saving = false;

  Future<void> _save() async {
    // подвійний тап: другий виклик пізніше закрив би ще й екран під цим
    if (_saving) return;
    _saving = true;
    if (widget.templateMode) {
      Navigator.pop(context, List<String>.from(selected));
      return;
    }
    try {
      await repo.setAttachedParameters(selected, widget.element!.entity);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _saving = false;
      rethrow;
    }
  }

  /// Форма "Новий параметр" / "Редагувати параметр". Повертає id
  /// створеного параметра (для нового), інакше null.
  ///
  /// Тип даних обирається ОДИН раз — під час створення. Щоб перейти на
  /// інший тип, створюють новий параметр і переносять у нього історію
  /// (кнопка "Перенести історію…" у формі редагування).
  Future<String?> _openForm([Parameter? param, String? presetName, String? presetUnit]) async {
    final isEdit = param != null;
    final isBase = param?.isBase ?? false;
    final nameCtrl = TextEditingController(text: param?.name ?? presetName ?? '');
    final unitCtrl = TextEditingController(text: param?.unit ?? presetUnit ?? '');
    var type = param?.dataType ?? DataTypes.text;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
        final note = TextStyle(color: AppColors.textMuted, fontSize: 10.5);
        return AlertDialog(
          title: Text(isEdit ? 'Редагувати параметр' : 'Новий параметр'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Назва', style: muted),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameCtrl,
                    autofocus: !isEdit,
                    readOnly: isBase,
                    style: TextStyle(color: isBase ? AppColors.textMuted : AppColors.text),
                  ),
                  if (isBase)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Назву Базової характеристики змінити не можна', style: muted),
                    ),
                  const SizedBox(height: 10),
                  Text('Одиниця виміру', style: muted),
                  const SizedBox(height: 4),
                  TextField(controller: unitCtrl, style: TextStyle(color: AppColors.text)),
                  const SizedBox(height: 10),
                  Text('Тип даних', style: muted),
                  const SizedBox(height: 6),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 2.4,
                    children: [
                      for (final (key, label) in DataTypes.all)
                        PillButton(
                          text: label,
                          bg: key == type ? AppColors.accent : AppColors.typeBtn,
                          fontSize: 11,
                          radius: 12,
                          // тип обирається лише під час створення
                          onPressed: isEdit ? null : () => setD(() => type = key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isEdit
                        ? (isBase
                            ? 'Тип даних Базової характеристики змінити не можна'
                            : 'Тип даних обирається один раз. Щоб змінити тип — створіть '
                                'новий параметр і перенесіть у нього історію.')
                        : 'Тип даних потім змінити не можна — оберіть уважно.',
                    textAlign: TextAlign.center,
                    style: note,
                  ),
                  if (isEdit && !isBase) ...[
                    const SizedBox(height: 8),
                    PillButton(
                      text: 'Перенести історію…',
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 38,
                      fontSize: 13,
                      onPressed: () => Navigator.pop(ctx, 'port'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            Row(children: [
              Expanded(
                child: PillButton(
                    text: 'Скасувати',
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(
                  text: 'Зберегти',
                  bg: AppColors.accent,
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx, 'save');
                  },
                ),
              ),
            ]),
          ],
        );
      }),
    );
    // контролери не звільняємо одразу: діалог ще анімує закриття й
    // користується ними (їх прибере збирач сміття)
    if (action == 'port' && param != null) {
      await _portFlow(param);
      return null;
    }
    final name = nameCtrl.text.trim();
    final unit = unitCtrl.text.trim();
    if (action != 'save' || name.isEmpty) return null;

    String? created;
    if (isEdit) {
      // тип даних не змінюється ніколи — лише назва й одиниця
      await repo.updateParameter(param!.id, {
        if (!isBase) 'name': name,
        'unit': unit.isEmpty ? null : unit,
      });
    } else {
      created = await repo.addParameter(name, unit: unit.isEmpty ? null : unit, dataType: type);
      // новостворений параметр одразу позначаємо обраним
      if (!widget.catalog) selected.add(created);
    }
    await _reload();
    return created;
  }

  /// "Перенести історію": обрати параметр-приймач (або створити новий),
  /// показати, скільки записів перейде, і перенести.
  Future<void> _portFlow(Parameter from) async {
    final all = await repo.listParameters();
    if (!mounted) return;
    final targets = [for (final p in all) if (p.id != from.id && !p.deleted) p];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Куди перенести історію?'),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('З «${from.nameWithUnit}» (${DataTypes.label(from.dataType)})',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              PillButton(
                text: '+ Новий параметр…',
                bg: AppColors.accent,
                height: 42,
                width: double.infinity,
                onPressed: () => Navigator.pop(ctx, ''),
              ),
              for (final p in targets) ...[
                const SizedBox(height: 6),
                PillButton(
                  text: '${p.nameWithUnit} · ${DataTypes.label(p.dataType)}',
                  bg: AppColors.darkBtn,
                  fg: AppColors.text,
                  height: 42,
                  fontSize: 13,
                  width: double.infinity,
                  onPressed: () => Navigator.pop(ctx, p.id),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    var toId = picked;
    if (toId.isEmpty) {
      final created = await _openForm(null, from.name, from.unit);
      if (created == null || !mounted) return;
      toId = created;
    }
    final to = await repo.getParameter(toId);
    final preview = await repo.previewHistoryPort(from.id, toId);
    if (to == null || !mounted) return;
    final typeName = DataTypes.label(to.dataType);
    final text = StringBuffer(
        'З «${from.nameWithUnit}» у «${to.nameWithUnit}» ($typeName) буде перенесено '
        '${preview.movable} запис(ів) історії з тими самими датами й об\'єктами.');
    if (preview.skipped > 0) {
      text.write('\n\n${preview.skipped} запис(ів) не підходять до типу «$typeName» — вони '
          'лишаться в «${from.name}».');
    }
    text.write('\n\nДе був «${from.name}», там з\'явиться «${to.name}».');
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перенести історію'),
        content: Text(text.toString(), style: TextStyle(color: AppColors.text)),
        actions: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            PillButton(
                text: 'Перенести',
                bg: AppColors.accent,
                width: double.infinity,
                onPressed: () => Navigator.pop(ctx, 'keep')),
            if (!from.isBase) ...[
              const SizedBox(height: 8),
              PillButton(
                  text: 'Перенести й видалити «${from.name}»',
                  bg: AppColors.danger,
                  width: double.infinity,
                  onPressed: () => Navigator.pop(ctx, 'delete')),
            ],
            const SizedBox(height: 8),
            PillButton(
                text: 'Скасувати',
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                width: double.infinity,
                onPressed: () => Navigator.pop(ctx)),
          ]),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final hadFrom = selected.contains(from.id);
    final res =
        await repo.portParameterHistory(from.id, toId, deleteSource: choice == 'delete');
    if (choice == 'delete') selected.remove(from.id);
    if (hadFrom && !to.isBase && !selected.contains(toId)) selected.add(toId);
    await _reload();
    if (!mounted) return;
    await showInfo(
      context,
      'Перенесено записів: ${res.moved}.'
      '${res.skipped > 0 ? '\nНе підійшли до типу й лишились: ${res.skipped}.' : ''}',
      title: 'Готово',
    );
  }

  Future<void> _delete(Parameter p) async {
    if (p.isBase) {
      await showInfo(
        context,
        '«${p.name}» — Базова характеристика, обов\'язкова для усього класу об\'єктів. '
        'Її не можна видалити.',
        title: 'Не можна видалити',
      );
      return;
    }
    final ok = await showConfirm(context, text: 'Видалити параметр «${p.name}»?');
    if (!ok) return;
    await repo.deleteParameter(p.id);
    selected.remove(p.id);
    await _reload();
  }

  Future<void> _history(Parameter p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistoryScreen(repo: repo, parameter: p),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = params;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(
              title: widget.catalog ? 'Характеристики' : 'Список параметрів',
              onBack: () => Navigator.pop(context),
              trailing: CircleIconButton(
                icon: 'plus_circle',
                bg: AppColors.accent,
                size: 34,
                tooltip: 'Новий параметр',
                onPressed: () => _openForm(),
              ),
            ),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодного параметра.\nСтвори його кнопкою «+» вгорі.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _card(list[i]),
                        ),
            ),
            if (!widget.catalog)
              Padding(
                padding: const EdgeInsets.all(12),
                child: PillButton(
                  text: 'Зберегти',
                  bg: AppColors.accent,
                  height: 48,
                  radius: 16,
                  width: double.infinity,
                  onPressed: _save,
                ),
              ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _card(Parameter p) {
    final locked = _lockedBase(p);
    var subtitle = DataTypes.label(p.dataType);
    if (p.unit != null && p.unit!.isNotEmpty) subtitle += ' · ${p.unit}';
    if (locked) subtitle += " · Базова характеристика (обов'язкова)";
    return ListCard(
      height: 66,
      child: Row(children: [
        if (!widget.catalog || p.isBase) ...[
        if (_pinned(p))
          const LockMark()
        else
        CheckToggle(
          checked: selected.contains(p.id),
          onChanged: (v) => setState(() {
                    // тап додає id В КІНЕЦЬ — щойно обраний стає останнім
                    if (v) {
                      if (!selected.contains(p.id)) selected.add(p.id);
                    } else {
                      selected.remove(p.id);
                    }
                  }),
        ),
        const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        // історія характеристик у каталозі — окремою вкладкою меню («Історія»)
        if (!widget.catalog) ...[
          CircleIconButton(
              icon: 'history',
              bg: AppColors.addObject,
              size: 36,
              tooltip: 'Історія',
              onPressed: () => _history(p)),
          const SizedBox(width: 6),
        ],
        // редагувати й видаляти параметр можна лише в каталозі (меню →
        // «Характеристики»); зміни назви одразу видно в усіх вуликах, бо
        // параметр один на всіх
        if (widget.catalog && !_pinned(p)) ...[
          CircleIconButton(
              icon: 'pencil',
              bg: AppColors.rename,
              size: 36,
              tooltip: 'Редагувати',
              onPressed: () => _openForm(p)),
          const SizedBox(width: 6),
        ],
        if (widget.catalog)
          CircleIconButton(
            icon: 'trash',
            bg: AppColors.danger,
            size: 36,
            tooltip: 'Видалити',
            onPressed: () => _delete(p)),
      ]),
    );
  }
}
