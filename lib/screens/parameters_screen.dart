import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/type_picker.dart';
import '../ui/theme.dart';
import '../tutorial/lesson.dart';
import '../tutorial/lessons.dart' show kVisitKeys, kVisitsGroup;
import 'history_screen.dart';

/// Кому застосувати набір і порядок параметрів (перемикач унизу).
enum ApplyScope {
  /// Лише цьому вулику.
  hive,

  /// Усім вуликам цієї пасіки того самого класу (з того самого шаблону:
  /// «Вулик 1», «Вулик 2»… - клас «Вулик»).
  kind,

  /// Усім вуликам пасіки.
  apiary,
}

/// Екран «Таблиця параметрів» (порт parameters_screen.py).
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

  /// Урок «Групи і параметри обходу».
  final LessonController? lesson;

  const ParametersScreen.forElement(
      {super.key, required this.repo, required MapElement this.element, this.lesson})
      : initialIds = const [],
        elType = null,
        embedded = false,
        catalog = false;

  const ParametersScreen.catalog({super.key, required this.repo, this.embedded = false})
      : element = null,
        initialIds = const [],
        elType = null,
        lesson = null,
        catalog = true;

  const ParametersScreen.forTemplate({
    super.key,
    required this.repo,
    required this.initialIds,
    required this.elType,
  })  : element = null,
        embedded = false,
        lesson = null,
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

  LessonController? get _lesson => widget.lesson;

  /// Урок: три базові характеристики обходу (їх розкладають у «Обходи»).
  List<String> _visitIds = const [];

  @override
  void initState() {
    super.initState();
    final l = _lesson;
    if (l != null) {
      _tab = _lessonTab(l.step) ?? 0;
      l.addListener(_onLesson);
    }
    _init();
  }

  @override
  void dispose() {
    _lesson?.removeListener(_onLesson);
    _autoScroll?.cancel();
    _consScroll.dispose();
    super.dispose();
  }

  /// Яку вкладку показує крок уроку (null - не важливо).
  static int? _lessonTab(int step) => step >= 8 && step <= 11 ? 1 : (step >= 3 && step <= 13 ? 0 : null);

  void _onLesson() {
    if (!mounted) return;
    // перебудувати й тоді, коли вкладка та сама (перемикач з'являється на кроці 11)
    final want = _lessonTab(_lesson!.step);
    setState(() {
      if (want != null) _tab = want;
    });
  }

  void _setTab(int i) {
    if (i == _tab) return;
    // в уроці вкладку веде сам урок (свайп не має збити крок), крім
    // «Відкрий конструктор»
    final l = _lesson;
    if (l != null && !(i == 1 && l.step == 7)) return;
    setState(() => _tab = i);
    if (i == 1) _lesson?.advance(7, 8);
  }

  Future<void> _init() async {
    groups = await repo.paramGroups();
    if (_lesson != null) {
      _visitIds = [
        for (final k in kVisitKeys)
          if (await repo.baseParameterId('hive', k) case final id?) id
      ];
    }
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

  /// Кому застосувати набір і порядок (лише для вулика на карті).
  ApplyScope _scope = ApplyScope.hive;

  bool get _canApplyToAll => widget.element?.isHive == true && widget.element?.apiaryId != null;

  /// Клас вулика - назва без номера: «Вулик 3» → «Вулик».
  static String kindOf(String? label) =>
      (label ?? '').trim().replaceFirst(RegExp(r'\s+\d+$'), '').trim();

  /// «Назад» (стрілка чи системна): у списку вулика/шаблону зміни
  /// зберігаються автоматично — окремої кнопки «Зберегти» немає.
  void _back() {
    final l = _lesson;
    if (l != null) {
      // в уроці «назад» - на кроці «Повернімось до вулика»; раніше - вихід з уроку
      // (а після нього, з панелі на фіналі, - звичайне «назад»)
      if (l.step < 13) {
        l.exit();
        return;
      }
      l.advance(13, 14);
    }
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
      if (_scope != ApplyScope.hive && _canApplyToAll) {
        final kind = kindOf(widget.element!.label);
        final owners = <String, EntityRef>{};
        for (final e in await repo.listElements(widget.element!.apiaryId!)) {
          if (!e.isHive) continue;
          if (_scope == ApplyScope.kind && kindOf(e.label) != kind) continue;
          owners[e.groupId != null ? 'g:${e.groupId}' : 'e:${e.id}'] = e.entity;
        }
        // сам вулик - завжди (навіть якщо його перейменували)
        owners[widget.element!.groupId != null
            ? 'g:${widget.element!.groupId}'
            : 'e:${widget.element!.id}'] = widget.element!.entity;
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
    final typeLocked = isEdit && (isBase || await repo.parameterHasRecords(param.id));
    if (!mounted) return null;
    final l = isEdit ? null : _lesson;
    l?.advance(3, 4);

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
        final note = TextStyle(color: AppColors.textMuted, fontSize: 10.5);
        return lessonDialog(l, 'param-form', AlertDialog(
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
                    // в уроці клавіатура закрила б пасічника - поле відкривають самі
                    autofocus: !isEdit && l == null,
                    readOnly: isBase,
                    style: TextStyle(color: isBase ? AppColors.textMuted : AppColors.text),
                    // decoration: null прибрав би заливку поля, тож завжди InputDecoration
                    decoration: InputDecoration(
                        enabledBorder: nameError ? redFieldBorder() : null,
                        focusedBorder: nameError ? redFieldBorder() : null),
                    onChanged: (v) {
                      if (nameError) {
                        setD(() {
                          nameError = false;
                          formError = null;
                        });
                      }
                      // урок: назву вписали - «Не забудь зберегти»
                      if (l != null) {
                        if (v.trim().isNotEmpty) {
                          l.advance(5, 6);
                        } else {
                          l.advance(6, 5);
                        }
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
                    // налаштувань із характеристиками більше немає - видаляють тут
                    if (!widget.catalog) ...[
                      const SizedBox(height: 8),
                      PillButton(
                        text: 'Видалити параметр',
                        bg: AppColors.danger,
                        height: 38,
                        fontSize: 13,
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            Row(children: [
              Expanded(
                child: LessonTarget(
                  lesson: l,
                  name: 'form-cancel',
                  radius: 14,
                  child: PillButton(
                      text: 'Скасувати',
                      bg: AppColors.neutralBtn,
                      fg: AppColors.text,
                      onPressed: () => Navigator.pop(ctx)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LessonTarget(
                  lesson: l,
                  name: 'form-save',
                  radius: 14,
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
              ),
            ]),
          ],
        ));
      }),
    );
    // контролери не звільняємо одразу: діалог ще анімує закриття й
    // користується ними (їх прибере збирач сміття)
    if (action == 'port' && param != null) {
      await _portFlow(param);
      return null;
    }
    if (action == 'delete' && param != null) {
      await _delete(param);
      return null;
    }
    // урок: форму закрили («назад» системи) - знову крок «Створити параметр»
    if (l != null && action != 'save' && l.step >= 4 && l.step <= 6) l.go(3);
    final name = nameCtrl.text.trim();
    final unit = unitCtrl.text.trim();
    if (action != 'save' || name.isEmpty) return null;

    String? created;
    if (isEdit) {
      // тип даних — лише поки немає записів
      await repo.updateParameter(param.id, {
        if (!isBase) 'name': name,
        if (!typeLocked && type != param.dataType) 'data_type': type,
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
      if (l != null) {
        l.setData('param', name);
        l.setData('param_id', created);
        l.setData('param_type', type);
        if (unit.isNotEmpty) l.setData('param_unit', unit);
        l.advance(6, 7);
      }
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
          ScreenColumn(children: [
            if (!widget.embedded)
            TopBar(
              title: widget.catalog ? 'Характеристики' : 'Таблиця параметрів',
              onBack: _back,
              decorateBack: _lesson == null
                  ? null
                  : (b) => LessonTarget(lesson: _lesson, name: 'params-back', child: b),
              trailing: LessonTarget(
                lesson: _lesson,
                name: 'param-create',
                child: CircleIconButton(
                  icon: 'plus_circle',
                  bg: AppColors.accent,
                  size: 34,
                  tooltip: 'Створити параметр',
                  onPressed: () => _openForm(),
                ),
              ),
            ),
            if (!widget.catalog && !widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(children: [
                  for (final (i, t) in const ['Список', 'Конструктор'].indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: LessonTarget(
                        lesson: _lesson,
                        name: i == 1 ? 'tab-constructor' : 'tab-list',
                        radius: 14,
                        child: PillButton(
                          text: t,
                          bg: _tab == i ? AppColors.accent : AppColors.darkBtn,
                          fg: _tab == i ? Colors.white : AppColors.text,
                          height: 38,
                          fontSize: 13,
                          onPressed: () => _setTab(i),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            Expanded(
              child: TabSwipe(
              index: _tab,
              count: widget.catalog ? 1 : 2,
              onChanged: _setTab,
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
            ),
            // у «Налаштуваннях» створення - кнопкою знизу
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: PillButton(
                  text: 'Створити характеристику',
                  bg: AppColors.accent,
                  height: 46,
                  width: double.infinity,
                  onPressed: () => _openForm(),
                ),
              ),
            // кому застосувати набір і порядок: вулику, таким самим вуликам, усій пасіці
            if (!widget.catalog && _canApplyToAll && (_lesson == null || _lesson!.step >= 11))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: LessonTarget(
                  lesson: _lesson,
                  name: 'apply-scope',
                  radius: 16,
                  child: ApplyScopeSwitch(
                    value: _scope,
                    kind: kindOf(widget.element!.label),
                    onChanged: (v) => setState(() => _scope = v),
                  ),
                ),
              ),
            // урок: місце під пасічника з хмаркою
            if (_lesson != null) const SizedBox(height: kLessonReserve),
            const SizedBox(height: 12),
          ]),
          if (!widget.embedded) const Positioned.fill(child: ScreenFrame()),
          if (_lesson != null) Positioned.fill(child: LessonLayer(lesson: _lesson!, screen: 'params')),
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
    _lessonGroupsChanged();
  }

  /// Урок: групи пишемо одразу (щоб перерваний урок продовжився з ними) і
  /// дивимось, чи три характеристики обходу вже в «Обходах».
  void _lessonGroupsChanged() {
    final l = _lesson;
    if (l == null) return;
    repo.setParamGroups(groups);
    final g = groups.where((x) => x.name.trim().toLowerCase() == kVisitsGroup.toLowerCase()).firstOrNull;
    if (g != null && _visitIds.isNotEmpty && _visitIds.every(g.ids.contains)) l.advance(10, 11);
  }

  /// Переставити параметр усередині групи (за ручку): [from]/[to] - серед
  /// видимих (обраних) параметрів групи.
  void _reorderInGroup(ParamGroup g, List<String> visible, int from, int to) {
    if (to > from) to -= 1;
    if (from < 0 || from >= visible.length) return;
    to = to.clamp(0, visible.length - 1);
    if (to == from) return;
    setState(() {
      final ids = [...visible];
      final moved = ids.removeAt(from);
      ids.insert(to, moved);
      // приховані (не обрані тут) id групи лишаються в кінці
      g.ids = [...ids, ...g.ids.where((id) => !ids.contains(id))];
    });
    _lessonGroupsChanged();
  }

  Future<void> _addGroup() async {
    final l = _lesson;
    l?.advance(8, 9);
    final name = await showTextPrompt(
      context,
      title: 'Нова група',
      initial: '',
      dismissible: l == null,
      // урок: група має зватися «Обходи»
      validate: l == null
          ? null
          : (v) => v.toLowerCase() == kVisitsGroup.toLowerCase()
              ? null
              : 'Назви групу «$kVisitsGroup»',
      wrap: l == null ? null : (d) => lessonDialog(l, 'group-form', d),
      decorate: l == null
          ? null
          : (which, b) => LessonTarget(lesson: l, name: 'group-$which', radius: 14, child: b),
    );
    if (name == null || name.trim().isEmpty || !mounted) {
      l?.advance(9, 8); // урок: вікно закрили - знову «Нова група»
      return;
    }
    setState(() => groups.add(ParamGroup(id: 'g${DateTime.now().microsecondsSinceEpoch}', name: name.trim())));
    l?.advance(9, 10);
    _lessonGroupsChanged();
  }

  Future<void> _renameGroup(ParamGroup g) async {
    final name = await showTextPrompt(context, title: 'Назва групи', initial: g.name);
    if (name == null || !mounted) return;
    setState(() => g.name = name);
    _lessonGroupsChanged();
  }

  void _deleteGroup(ParamGroup g) {
    setState(() => groups.remove(g));
    _lessonGroupsChanged();
  }

  // поки параметр тягнуть до краю конструктора - список сам гортається
  final _consScroll = ScrollController();
  final _consBox = GlobalKey();
  Timer? _autoScroll;
  double _dragY = 0;

  void _dragMoved(DragUpdateDetails d) {
    _dragY = d.globalPosition.dy;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
  }

  void _dragStopped() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _autoScrollTick() {
    final box = _consBox.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !_consScroll.hasClients) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edge = 56.0, speed = 10.0;
    double v = 0;
    if (_dragY < top + edge) {
      v = -speed * ((top + edge - _dragY) / edge).clamp(0.0, 1.0);
    } else if (_dragY > bottom - edge) {
      v = speed * ((_dragY - bottom + edge) / edge).clamp(0.0, 1.0);
    }
    if (v == 0) return;
    final p = _consScroll.position;
    final to = (p.pixels + v).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to != p.pixels) _consScroll.jumpTo(to);
  }

  Widget _dragChip(Parameter p, Widget child) => LongPressDraggable<String>(
        data: p.id,
        onDragUpdate: _dragMoved,
        onDragEnd: (_) => _dragStopped(),
        onDraggableCanceled: (_, _) => _dragStopped(),
        onDragCompleted: _dragStopped,
        // майже одразу після дотику (не 0,5 с), але гортання списку ще працює
        delay: const Duration(milliseconds: 120),
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
              // назва групи - заокруглена медова плашка
              Container(
                height: 46,
                margin: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                decoration: BoxDecoration(
                    color: AppColors.hive, borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.only(left: 14, right: 6),
                child: Row(children: [
                  Expanded(
                    child: Text(g.name,
                        maxLines: 2,
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
              // параметри групи: ручка ліворуч - переставити місцями (як у «Списку»),
              // довгий дотик до назви - перенести в іншу групу
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: members.length,
                onReorder: (from, to) =>
                    _reorderInGroup(g, [for (final p in members) p.id], from, to),
                itemBuilder: (_, i) {
                  final p = members[i];
                  return DragTarget<String>(
                    key: ValueKey('${g.id}/${p.id}'),
                    onWillAcceptWithDetails: (d) => d.data != p.id,
                    onAcceptWithDetails: (d) => _drop(d.data, g.id, at: g.ids.indexOf(p.id)),
                    builder: (_, _, _) => Container(
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.popupBg,
                          border: Border(
                              top: BorderSide(color: AppColors.hive.withValues(alpha: 0.22)))),
                      child: Row(children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.drag_indicator, color: AppColors.textMuted, size: 24),
                          ),
                        ),
                        Expanded(
                          child: _dragChip(
                            p,
                            Container(
                              height: 44,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(right: 14),
                              child: Text(p.nameWithUnit,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppColors.text, fontSize: 14)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  );
                },
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

    return KeyedSubtree(
      key: _consBox,
      child: ListView(
        key: _lesson?.key('constructor'),
        controller: _consScroll,
        cacheExtent: _lesson != null ? 4000 : null,
        padding: const EdgeInsets.all(12),
        children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
            chosen.isEmpty
                ? 'Тут з\'являться параметри, які ви оберете у вкладці «Список».'
                : 'Затисни параметр і веди в потрібну групу.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ),
      for (final g in groups) groupCard(g),
      LessonTarget(
        lesson: _lesson,
        name: 'new-group',
        radius: 14,
        child: PillButton(
          text: '+ Нова група',
          bg: AppColors.darkBtn,
          fg: AppColors.text,
          height: 42,
          width: double.infinity,
          onPressed: _addGroup,
        ),
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
    ]),
    );
  }

  /// Вибір для вулика / шаблону: обрані — вгорі в їхньому порядку, їх можна
  /// перетягувати за ручку (порядок показу на панелі; у шаблоні — для всіх
  /// майбутніх екземплярів); нижче — решта каталогу.
  Widget _orderList(List<Parameter> all) {
    final byId = {for (final p in all) p.id: p};
    final chosen = [for (final id in selected) if (byId[id] != null) byId[id]!];
    final rest = [for (final p in all) if (!selected.contains(p.id)) p];
    final items = [...chosen, ...rest];
    // в уроці порядок не міняють (і копія картки під пальцем дублювала б ціль уроку)
    final reorder = _lesson == null;
    return ReorderableListView.builder(
      key: _lesson?.key('list'),
      // урок: усі картки одразу - ціль уроку існує, навіть коли нижче екрана
      cacheExtent: _lesson != null ? 4000 : null,
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
      itemBuilder: (_, i) {
        final card = _card(items[i], dragIndex: reorder && i < chosen.length ? i : null);
        return Padding(
          key: ValueKey(items[i].id),
          padding: const EdgeInsets.only(bottom: 10),
          // обраний можна тягнути й за саму картку (довгим дотиком), не лише за ручку
          child: reorder && i < chosen.length
              ? ReorderableDelayedDragStartListener(index: i, child: card)
              : card,
        );
      },
    );
  }

  /// Тап по параметру - перейменувати (поки в нього немає жодного запису).
  Future<void> _renameIfFree(Parameter p) async {
    if (p.isBase) return;
    if (await repo.parameterHasRecords(p.id)) {
      if (!mounted) return;
      await showInfo(context,
          'У «${p.name}» уже є записи, тож назву змінити не можна. Можна створити новий '
          'параметр і перенести в нього історію.',
          title: 'Не можна перейменувати');
      return;
    }
    if (!mounted) return;
    await _openForm(p);
  }

  Widget _card(Parameter p, {int? dragIndex}) {
    final locked = _lockedBase(p);
    var subtitle = DataTypes.label(p.dataType);
    if (p.unit != null && p.unit!.isNotEmpty) subtitle += ' · ${p.unit}';
    if (locked) subtitle += " · обов'язкова";
    return ListCard(
      height: 66,
      child: Row(children: [
        // ручка перетягування — лише в обраних (без підказки: її довгий дотик
        // заважав почати перетягування)
        if (dragIndex != null) ...[
          ReorderableDragStartListener(
            index: dragIndex,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.drag_indicator, color: AppColors.textMuted, size: 26),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (!widget.catalog || p.isBase) ...[
        if (_pinned(p))
          const LockMark()
        else
        LessonTarget(
          lesson: p.id == _lesson?.data['param_id'] ? _lesson : null,
          name: 'lesson-param-check',
          radius: 8,
          child: CheckToggle(
            checked: selected.contains(p.id),
            onChanged: (v) {
              setState(() {
                // тап додає id В КІНЕЦЬ — щойно обраний стає останнім
                if (v) {
                  if (!selected.contains(p.id)) selected.add(p.id);
                } else {
                  selected.remove(p.id);
                }
              });
              // урок: зайвий параметр вимкнено
              if (!v && p.id == _lesson?.data['param_id']) _lesson?.advance(12, 13);
            },
          ),
        ),
        const SizedBox(width: 8),
        ],
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // у таблиці вулика / шаблону: тап по назві - перейменувати (поки немає записів)
            onTap: widget.catalog || p.isBase || _lesson != null ? null : () => _renameIfFree(p),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.text, fontSize: 14, height: 1.05, fontWeight: FontWeight.bold)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.05)),
            ],
          ),
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

/// Перемикач на три положення: кому застосувати набір і порядок параметрів -
/// цьому вулику (типово), таким самим вуликам (того самого класу) чи всій пасіці.
class ApplyScopeSwitch extends StatelessWidget {
  final ApplyScope value;

  /// Клас вулика («Вулик», «Лежак»…) - для напису середнього положення.
  final String kind;
  final ValueChanged<ApplyScope> onChanged;
  const ApplyScopeSwitch({super.key, required this.value, required this.kind, required this.onChanged});

  static const _h = 40.0;

  @override
  Widget build(BuildContext context) {
    final labels = {
      ApplyScope.hive: 'Цей вулик',
      ApplyScope.kind: kind.isEmpty ? 'Такі самі' : 'Усі «$kind»',
      ApplyScope.apiary: 'Уся пасіка',
    };
    final i = ApplyScope.values.indexOf(value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text('Застосувати до:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ),
      Container(
        height: _h + 8,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.roundBtn,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth / 3;
          return Stack(children: [
            // медовий повзунок під обраним положенням
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: w * i,
              top: 0,
              width: w,
              height: _h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Row(children: [
              for (final s in ApplyScope.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: s == value,
                    label: labels[s],
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(s),
                      child: SizedBox(
                        height: _h,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(labels[s]!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: s == value ? Colors.white : AppColors.text,
                                    fontSize: 13,
                                    fontWeight: s == value ? FontWeight.bold : FontWeight.w500)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    ]);
  }
}
