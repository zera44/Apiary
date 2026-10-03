import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/type_picker.dart';
import '../ui/theme.dart';
import 'history_screen.dart';

/// Екран "Список параметрів" (порт parameters_screen.py).
///
/// Чекбоксом параметр із каталогу прив'язується до об'єкта; вихід «назад»
/// автоматично записує весь набір. "+" — новий параметр у каталозі. Базові
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

  /// Вкладка в «Налаштуваннях»: без власної верхньої панелі й рамки.
  final bool embedded;

  const ParametersScreen.forElement({super.key, required this.repo, required MapElement this.element})
      : initialIds = const [],
        elType = null,
        embedded = false,
        catalog = false;

  const ParametersScreen.catalog({super.key, required this.repo, this.embedded = false})
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
        embedded = false,
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

  /// Вкладка: 0 - «Список», 1 - «Конструктор» (групи обраних параметрів).
  int _tab = 0;
  List<ParamGroup> groups = [];
  String? _dragOver; // id групи ('' - пул без групи), над якою тримають параметр

  String? get targetType => widget.element?.type ?? widget.elType;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    groups = await repo.paramGroups();
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
    if (mounted) {
      setState(() => params = [
            for (final p in [...pinned, ...rest])
              if (!_hiding.contains(p.id)) p
          ]);
    }
  }

  // параметри, що видаляються (чекають кінця «Відмінити»): _reload їх не повертає
  final Set<String> _hiding = {};

  /// «1 запис», «2 записи», «5 записів».
  static String _recordsWord(int n) {
    final t = n % 100, o = n % 10;
    if (t >= 11 && t <= 14) return '$n записів';
    return o == 1 ? '$n запис' : (o >= 2 && o <= 4 ? '$n записи' : '$n записів');
  }

  bool _lockedBase(Parameter p) => p.isBase && targetType != null && p.baseType == targetType;

  /// Характеристика з замочком: обов'язкова, закріплена вгорі, без редагування.
  bool _pinned(Parameter p) => _lockedBase(p) || (widget.catalog && p.isBase);

  bool _saving = false;

  /// «Для всіх вуликів пасіки»: такий самий набір і порядок — усім вуликам
  /// пасіки цього вулика (лише для вулика на карті).
  bool _allHives = false;

  bool get _canApplyToAll => widget.element?.isHive == true && widget.element?.apiaryId != null;

  /// «Назад» (стрілка чи системна): у списку вулика/шаблону зміни
  /// зберігаються автоматично — окремої кнопки «Зберегти» немає.
  void _back() {
    if (widget.catalog || params == null) {
      Navigator.pop(context); // поки список не завантажено — нічого не знімаємо
      return;
    }
    _save();
  }

  Future<void> _save() async {
    // подвійний тап: другий виклик пізніше закрив би ще й екран під цим
    if (_saving) return;
    _saving = true;
    await repo.setParamGroups(groups);
    if (!mounted) return;
    if (widget.templateMode) {
      Navigator.pop(context, List<String>.from(selected));
      return;
    }
    try {
      if (_allHives && _canApplyToAll) {
        final owners = <String, EntityRef>{};
        for (final e in await repo.listElements(widget.element!.apiaryId!)) {
          if (!e.isHive) continue;
          owners[e.groupId != null ? 'g:${e.groupId}' : 'e:${e.id}'] = e.entity;
        }
        for (final o in owners.values) {
          await repo.setAttachedParameters(selected, o);
        }
      } else {
        await repo.setAttachedParameters(selected, widget.element!.entity);
      }
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
    var options = [...?param?.options];
    final optionCtrl = TextEditingController();
    String? formError;
    var nameError = false;
    var optionsError = false;
    // тип можна змінити, поки в параметра немає жодного запису (базовим — ніколи)
    final typeLocked = isEdit && (isBase || await repo.parameterHasRecords(param!.id));
    if (!mounted) return null;

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
                    // decoration: null прибрав би заливку поля, тож завжди InputDecoration
                    decoration: InputDecoration(
                        enabledBorder: nameError ? redFieldBorder() : null,
                        focusedBorder: nameError ? redFieldBorder() : null),
                    onChanged: (_) {
                      if (nameError) {
                        setD(() {
                          nameError = false;
                          formError = null;
                        });
                      }
                    },
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
                  DataTypePicker(
                    value: type,
                    // тип змінюється, поки немає записів
                    onChanged: typeLocked ? null : (t) => setD(() => type = t),
                  ),
                  // «Список»: які варіанти обиратимуть під час огляду
                  if (type == DataTypes.choice) ...[
                    const SizedBox(height: 12),
                    Text('Варіанти списку', style: muted),
                    const SizedBox(height: 6),
                    OptionsEditor(
                      options: options,
                      controller: optionCtrl,
                      error: optionsError,
                      onChanged: (o) => setD(() {
                        options = o;
                        formError = null;
                        optionsError = false;
                      }),
                    ),
                  ],
                  if (formError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(formError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    isBase
                        ? 'Тип даних Базової характеристики змінити не можна'
                        : typeLocked
                            ? 'Записи вже є, тож тип даних змінити не можна. Щоб змінити тип - '
                                'створіть новий параметр і перенесіть у нього історію.'
                            : 'Тип даних можна змінити, поки немає жодного запису.',
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
                    if (nameCtrl.text.trim().isEmpty) {
                      setD(() {
                        nameError = true;
                        formError = 'Так не можна - вкажіть назву параметра';
                      });
                      return;
                    }
                    if (type == DataTypes.choice) {
                      // недописаний варіант у полі — теж додаємо
                      final pending = optionCtrl.text.trim();
                      if (pending.isNotEmpty &&
                          !options.any((o) => o.toLowerCase() == pending.toLowerCase())) {
                        options = [...options, pending];
                        optionCtrl.clear();
                      }
                      if (options.length < 2) {
                        setD(() {
                          optionsError = true;
                          formError = 'Так не можна - додайте щонайменше два варіанти';
                        });
                        return;
                      }
                    }
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
      // тип даних — лише поки немає записів
      await repo.updateParameter(param!.id, {
        if (!isBase) 'name': name,
        if (!typeLocked && type != param!.dataType) 'data_type': type,
        'unit': unit.isEmpty ? null : unit,
        if (type == DataTypes.choice) 'options': Parameter.encodeOptions(options),
      });
    } else {
      created = await repo.addParameter(name,
          unit: unit.isEmpty ? null : unit,
          dataType: type,
          options: type == DataTypes.choice ? options : const []);
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
        '${_recordsWord(preview.movable)} історії з тими самими датами й об\'єктами.');
    if (preview.skipped > 0) {
      text.write('\n\n${_recordsWord(preview.skipped)} не підходять до типу «$typeName» - вони '
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
        '«${p.name}» - Базова характеристика, обов\'язкова для усього класу об\'єктів. '
        'Її не можна видалити.',
        title: 'Не можна видалити',
      );
      return;
    }
    // без підтвердження: параметр зникає одразу, внизу «Відмінити»
    await deleteWithUndo(
      context,
      message: 'Параметр «${p.name}» видалено',
      hide: () {
        _hiding.add(p.id);
        setState(() => params = [...?params]..removeWhere((x) => x.id == p.id));
      },
      restore: () {
        _hiding.remove(p.id);
        _reload();
      },
      commit: () async {
        await repo.deleteParameter(p.id);
        _hiding.remove(p.id);
        selected.remove(p.id);
        if (mounted) await _reload();
      },
    );
  }

  Future<void> _history(Parameter p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistoryScreen(repo: repo, parameter: p),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = params;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: CircleIconButton(
                    icon: 'plus_circle',
                    bg: AppColors.accent,
                    size: 34,
                    tooltip: 'Новий параметр',
                    onPressed: () => _openForm(),
                  ),
                ),
              )
            else
            TopBar(
              title: widget.catalog ? 'Характеристики' : 'Список параметрів',
              onBack: _back,
              trailing: CircleIconButton(
                icon: 'plus_circle',
                bg: AppColors.accent,
                size: 34,
                tooltip: 'Новий параметр',
                onPressed: () => _openForm(),
              ),
            ),
            if (!widget.catalog && !widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(children: [
                  for (final (i, t) in const ['Список', 'Конструктор'].indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: PillButton(
                        text: t,
                        bg: _tab == i ? AppColors.accent : AppColors.darkBtn,
                        fg: _tab == i ? Colors.white : AppColors.text,
                        height: 38,
                        fontSize: 13,
                        onPressed: () => setState(() => _tab = i),
                      ),
                    ),
                  ],
                ]),
              ),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : (!widget.catalog && _tab == 1)
                      ? _constructor(list)
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодного параметра.\nСтвори його кнопкою «+» вгорі.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
                        )
                      : widget.catalog
                          ? ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: list.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _card(list[i]),
                            )
                          : _orderList(list),
            ),
            if (!widget.catalog && _tab == 1 && _canApplyToAll)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: InkWell(
                  onTap: () => setState(() => _allHives = !_allHives),
                  child: Row(children: [
                    CheckToggle(checked: _allHives, onChanged: (v) => setState(() => _allHives = v)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Для всіх вуликів пасіки (такий самий набір і порядок)',
                          style: TextStyle(color: AppColors.text, fontSize: 14)),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
          ]),
          if (!widget.embedded) const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    ),
    );
  }

  // ---------------------------------------------------------------------
  // Конструктор: групи й параметри під ними
  // ---------------------------------------------------------------------

  /// Кинути параметр у групу [groupId] (null - зняти з груп) на позицію [at].
  void _drop(String paramId, String? groupId, {int? at}) {
    setState(() {
      for (final g in groups) {
        g.ids.remove(paramId);
      }
      if (groupId != null) {
        final g = groups.firstWhere((x) => x.id == groupId);
        // позиція рахується серед ВИДИМИХ (обраних), у повному списку - до id перед нею
        if (at == null || at >= g.ids.length) {
          g.ids.add(paramId);
        } else {
          g.ids.insert(at, paramId);
        }
      }
      _dragOver = null;
    });
  }

  Future<void> _addGroup() async {
    final name = await showTextPrompt(context, title: 'Нова група', initial: '');
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => groups.add(ParamGroup(id: 'g${DateTime.now().microsecondsSinceEpoch}', name: name.trim())));
  }

  Future<void> _renameGroup(ParamGroup g) async {
    final name = await showTextPrompt(context, title: 'Назва групи', initial: g.name);
    if (name == null || !mounted) return;
    setState(() => g.name = name);
  }

  void _deleteGroup(ParamGroup g) => setState(() => groups.remove(g));

  Widget _dragChip(Parameter p, Widget child) => LongPressDraggable<String>(
        data: p.id,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hive, width: 1.5),
            ),
            child: Text(p.nameWithUnit,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: child),
        child: child,
      );

  /// Вкладка «Конструктор»: у ній лише параметри, обрані у вкладці «Список».
  Widget _constructor(List<Parameter> all) {
    final byId = {for (final p in all) p.id: p};
    final chosen = [for (final id in selected) if (byId[id] != null) byId[id]!];
    final chosenIds = {for (final p in chosen) p.id};
    final grouped = <String>{for (final g in groups) ...g.ids.where(chosenIds.contains)};
    final loose = [for (final p in chosen) if (!grouped.contains(p.id)) p];
    const honeyDark = Color(0xFF2B1A08);

    Widget groupCard(ParamGroup g) {
      final members = [for (final id in g.ids) if (byId[id] != null && chosenIds.contains(id)) byId[id]!];
      return DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          if (_dragOver != g.id) setState(() => _dragOver = g.id);
          return true;
        },
        onLeave: (_) {
          if (_dragOver == g.id) setState(() => _dragOver = null);
        },
        onAcceptWithDetails: (d) => _drop(d.data, g.id),
        builder: (_, _, _) {
          final over = _dragOver == g.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.popupBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: over ? AppColors.hive : AppColors.hive.withValues(alpha: 0.5),
                  width: over ? 2 : 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                height: 46,
                color: AppColors.hive,
                padding: const EdgeInsets.only(left: 14, right: 6),
                child: Row(children: [
                  Expanded(
                    child: Text(g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: honeyDark, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: 'Назва групи',
                    icon: const Icon(Icons.edit, color: honeyDark, size: 20),
                    onPressed: () => _renameGroup(g),
                  ),
                  IconButton(
                    tooltip: 'Видалити групу',
                    icon: const Icon(Icons.delete_outline, color: honeyDark, size: 22),
                    onPressed: () => _deleteGroup(g),
                  ),
                ]),
              ),
              for (final p in members)
                DragTarget<String>(
                  onWillAcceptWithDetails: (d) => d.data != p.id,
                  onAcceptWithDetails: (d) => _drop(d.data, g.id, at: g.ids.indexOf(p.id)),
                  builder: (_, _, _) => _dragChip(
                    p,
                    Container(
                      height: 44,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppColors.hive.withValues(alpha: 0.22)))),
                      child: Text(p.nameWithUnit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.text, fontSize: 14)),
                    ),
                  ),
                ),
              if (members.isEmpty || over)
                Container(
                  height: 44,
                  alignment: Alignment.center,
                  color: over ? AppColors.hive.withValues(alpha: 0.14) : null,
                  child: Text(over ? 'Відпусти тут' : 'Перетягни сюди параметри',
                      style: TextStyle(
                          color: over ? AppColors.hive : AppColors.textMuted, fontSize: 13)),
                ),
            ]),
          );
        },
      );
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
            chosen.isEmpty
                ? 'Тут з\'являться параметри, які ви оберете у вкладці «Список».'
                : 'Затисни параметр і веди в потрібну групу.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ),
      for (final g in groups) groupCard(g),
      PillButton(
        text: '+ Нова група',
        bg: AppColors.darkBtn,
        fg: AppColors.text,
        height: 42,
        width: double.infinity,
        onPressed: _addGroup,
      ),
      const SizedBox(height: 14),
      DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          if (_dragOver != '') setState(() => _dragOver = '');
          return true;
        },
        onLeave: (_) {
          if (_dragOver == '') setState(() => _dragOver = null);
        },
        onAcceptWithDetails: (d) => _drop(d.data, null),
        builder: (_, _, _) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: _dragOver == '' ? Border.all(color: AppColors.hive, width: 2) : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Обрані, але ще без групи',
                style: TextStyle(
                    color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(loose.isEmpty ? 'Усі параметри розкладено по групах.' : 'Затисни й перетягни в групу.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            if (loose.isNotEmpty) const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in loose)
                _dragChip(
                  p,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.darkBtn,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.neutralBtn),
                    ),
                    child: Text(p.nameWithUnit,
                        style: TextStyle(color: AppColors.text, fontSize: 13)),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  /// Вибір для вулика / шаблону: обрані — вгорі в їхньому порядку, їх можна
  /// перетягувати за ручку (порядок показу на панелі; у шаблоні — для всіх
  /// майбутніх екземплярів); нижче — решта каталогу.
  Widget _orderList(List<Parameter> all) {
    final byId = {for (final p in all) p.id: p};
    final chosen = [for (final id in selected) if (byId[id] != null) byId[id]!];
    final rest = [for (final p in all) if (!selected.contains(p.id)) p];
    final items = [...chosen, ...rest];
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: (from, to) {
        if (to > from) to -= 1;
        if (from >= chosen.length) return; // необрані не впорядковуються
        to = to.clamp(0, chosen.length - 1);
        if (to == from) return;
        setState(() {
          final moved = chosen[from].id;
          final ids = [for (final p in chosen) p.id]..removeAt(from);
          ids.insert(to, moved);
          // невідомі каталогу id (напр., ще не завантажені) — лишаються в кінці
          selected = [...ids, ...selected.where((id) => !ids.contains(id))];
        });
      },
      itemBuilder: (_, i) => Padding(
        key: ValueKey(items[i].id),
        padding: const EdgeInsets.only(bottom: 10),
        child: _card(items[i], dragIndex: i < chosen.length ? i : null),
      ),
    );
  }

  Widget _card(Parameter p, {int? dragIndex}) {
    final locked = _lockedBase(p);
    var subtitle = DataTypes.label(p.dataType);
    if (p.unit != null && p.unit!.isNotEmpty) subtitle += ' · ${p.unit}';
    if (locked) subtitle += " · Базова характеристика (обов'язкова)";
    return ListCard(
      height: 66,
      child: Row(children: [
        // ручка перетягування — лише в обраних
        if (dragIndex != null) ...[
          ReorderableDragStartListener(
            index: dragIndex,
            child: Tooltip(
              message: 'Перетягніть, щоб змінити порядок',
              child: Icon(Icons.drag_indicator, color: AppColors.textMuted, size: 26),
            ),
          ),
          const SizedBox(width: 4),
        ],
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
