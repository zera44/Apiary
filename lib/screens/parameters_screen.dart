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

  const ParametersScreen.forElement({super.key, required this.repo, required MapElement this.element})
      : initialIds = const [],
        elType = null;

  const ParametersScreen.forTemplate({
    super.key,
    required this.repo,
    required this.initialIds,
    required this.elType,
  }) : element = null;

  bool get templateMode => element == null;

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
    final list = await repo.listParameters();
    if (mounted) setState(() => params = list);
  }

  bool _lockedBase(Parameter p) => p.isBase && targetType != null && p.baseType == targetType;

  Future<void> _save() async {
    if (widget.templateMode) {
      Navigator.pop(context, List<String>.from(selected));
      return;
    }
    await repo.setAttachedParameters(selected, widget.element!.entity);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _openForm([Parameter? param]) async {
    final isEdit = param != null;
    final isBase = param?.isBase ?? false;
    final nameCtrl = TextEditingController(text: param?.name ?? '');
    final unitCtrl = TextEditingController(text: param?.unit ?? '');
    var type = param?.dataType ?? DataTypes.text;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
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
                  TextField(controller: nameCtrl, autofocus: !isEdit, style: TextStyle(color: AppColors.text)),
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
                          onPressed: isBase ? null : () => setD(() => type = key),
                        ),
                    ],
                  ),
                  if (isBase) ...[
                    const SizedBox(height: 6),
                    Text('Тип даних Базової характеристики змінити не можна',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
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
                    onPressed: () => Navigator.pop(ctx, false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(
                  text: 'Зберегти',
                  bg: AppColors.accent,
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx, true);
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
    final name = nameCtrl.text.trim();
    final unit = unitCtrl.text.trim();
    if (saved != true || name.isEmpty) return;

    if (isEdit) {
      await repo.updateParameter(param!.id, {
        'name': name,
        'unit': unit.isEmpty ? null : unit,
        if (!isBase) 'data_type': type,
      });
    } else {
      final id = await repo.addParameter(name, unit: unit.isEmpty ? null : unit, dataType: type);
      // новостворений параметр одразу позначаємо обраним
      selected.add(id);
    }
    await _reload();
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
              title: 'Список параметрів',
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
        CheckToggle(
          checked: locked || selected.contains(p.id),
          onChanged: locked
              ? null
              : (v) => setState(() {
                    // тап додає id В КІНЕЦЬ — щойно обраний стає останнім
                    if (v) {
                      if (!selected.contains(p.id)) selected.add(p.id);
                    } else {
                      selected.remove(p.id);
                    }
                  }),
        ),
        const SizedBox(width: 8),
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
        CircleIconButton(
            icon: 'history',
            bg: AppColors.addObject,
            size: 36,
            tooltip: 'Історія',
            onPressed: () => _history(p)),
        const SizedBox(width: 6),
        CircleIconButton(
            icon: 'pencil',
            bg: AppColors.rename,
            size: 36,
            tooltip: 'Редагувати',
            onPressed: () => _openForm(p)),
        const SizedBox(width: 6),
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
