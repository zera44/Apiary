import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../logic/stock_format.dart';
import 'common.dart';
import 'date_picker.dart';
import 'guide_bubble.dart';
import 'icons.dart';
import 'theme.dart';
import 'thousands_input.dart';
import '../l10n/l10n.dart';

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
  FillLesson? lesson,
  String? subtitle,
  VoidCallback? onHistory,
  List<(String, String)> infoRows = const [],
  bool withNote = false,
  List<ParamGroup> groups = const [],
}) {
  Widget host() => _FillHost(
        groups: groups,
        first: FillPage(params: params, latest: latest, stock: stock, title: title),
        offerNext: lesson == null && offerNext,
        onNext: onNext,
        lesson: lesson,
        subtitle: subtitle ?? tr.fillParams,
        onHistory: onHistory,
        infoRows: infoRows,
        withNote: withNote && lesson == null,
      );
  // урок: пасічник на карті зникає, а в формі з'являється на тому ж місці -
  // без анімації, щоб він не блимав
  if (lesson != null) {
    return showGeneralDialog<FillResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      barrierLabel: '',
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) =>
          Material(type: MaterialType.transparency, child: SafeArea(child: host())),
    );
  }
  return showDialog<FillResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => host(),
  );
}

/// Урок «Базові поняття» у формі огляду: які комірки заповнити і чим.
class FillLesson {
  /// «Дата останнього обходу» — обрати сьогоднішню (є і в справжній формі).
  final String dateParamId;
  final String colorParamId;
  final String colorValue;
  const FillLesson({
    required this.dateParamId,
    required this.colorParamId,
    this.colorValue = 'Білий',
  });
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
  final FillLesson? lesson;
  final String? subtitle;
  final VoidCallback? onHistory;
  final List<(String, String)> infoRows;
  final bool withNote;
  final List<ParamGroup> groups;
  const _FillHost(
      {this.groups = const [],
      this.infoRows = const [],
      this.withNote = false,
      required this.first,
      required this.offerNext,
      this.onNext,
      this.lesson,
      this.subtitle,
      this.onHistory});
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
      lesson: widget.lesson,
      subtitle: widget.subtitle,
      onHistory: widget.onHistory,
      infoRows: widget.infoRows,
      withNote: widget.withNote,
      groups: widget.groups,
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

/// Чим закінчили огляд вулика в обході: записати зміни, «змін немає» (лише
/// дата огляду) чи пропустити (нічого не записувати, вулик лишається на потім).
enum FillAction { save, noChange, skip }

/// Результат форми: змінені значення й чи далі наступний вулик (обхід
/// ланцюжком: будь-яка з трьох кнопок відкриває наступний).
class FillResult {
  final Map<String, String> values;
  final bool next;
  final FillAction action;

  /// Підгодівля зі складу: що й скільки списати (або null).
  final ({String itemId, double amount})? feed;

  /// Нотатка до огляду (стане нотаткою вулика з міткою «Огляд») або null.
  final String? note;
  const FillResult(this.values,
      {this.next = false, this.feed, this.action = FillAction.save, this.note});
}

class _FillDialog extends StatefulWidget {
  final String? title;
  final List<Parameter> params;
  final Map<String, String?> latest;
  final bool offerNext;
  final List<StockItem> stock;
  final Future<void> Function(FillResult result)? onNext;
  final FillLesson? lesson;
  final String? subtitle;
  final VoidCallback? onHistory;

  /// Рядки лише для перегляду (назва, значення) - над полями.
  final List<(String, String)> infoRows;

  /// Поле «Нотатка» під таблицею (огляд одного вулика).
  final bool withNote;
  final List<ParamGroup> groups;
  const _FillDialog(
      {super.key,
      this.groups = const [],
      this.infoRows = const [],
      this.withNote = false,
      this.lesson,
      this.subtitle,
      this.onHistory,
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

  // цілі параметри — кількості й дні: від'ємними не бувають
  static final _intFilter = WholeValueFormatter(RegExp(r'^\d*$'));
  static final _floatFilter = WholeValueFormatter(RegExp(r'^-?\d*[.,]?\d*$'));

  @override
  void initState() {
    super.initState();
    for (final p in widget.params) {
      final cur = widget.latest[p.id] ?? '';
      if (const {DataTypes.date, DataTypes.color, DataTypes.bool_, DataTypes.choice}
          .contains(p.dataType)) {
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
    _note.dispose();
    super.dispose();
  }

  String? _feedItem;
  final _feedAmount = TextEditingController();
  final _note = TextEditingController();

  String? get _noteText {
    if (!widget.withNote) return null;
    final t = _note.text.trim();
    return t.isEmpty ? null : t;
  }

  bool _saving = false;

  // ---- урок «Базові поняття»: кроки в самій формі ----
  // 0 пасічник пояснює; (1 пропущено); 2 — з'являється ведмежа; 3 — «матка біла»;
  // 4 — «обери сьогоднішню дату»; 5 — «Збережи»
  int _step = 0;
  FillLesson? get _lesson => widget.lesson;

  bool _ring(int step) => _lesson != null && _step == step;

  /// Кроки 3 і 4 йдуть далі самі, щойно в комірці потрібне значення.
  void _lessonCheck() {
    final l = _lesson;
    if (l == null) return;
    if (_step == 3 && (_picked[l.colorParamId] ?? '') == l.colorValue) {
      setState(() => _step = 4);
    }
    if (_step == 4 && (_picked[l.dateParamId] ?? '').isNotEmpty) {
      setState(() => _step = 5);
    }
  }

  ({List<InlineSpan> text, bool bear, bool tapNext}) get _lessonLine {
    final l = _lesson!;
    return switch (_step) {
      0 => (
          text: [
            TextSpan(text: tr.fillLesson0a),
            GuideBubble.highlight(tr.fillLesson0b),
            const TextSpan(text: '.'),
          ],
          bear: false,
          tapNext: true
        ),
      1 => (
          text: [TextSpan(text: tr.fillLesson1)],
          bear: false,
          tapNext: true
        ),
      2 => (
          text: [
            TextSpan(text: tr.fillLesson2a),
            GuideBubble.highlight(tr.fillLesson2b),
            TextSpan(text: tr.fillLesson2c),
          ],
          bear: true,
          tapNext: true
        ),
      3 => (
          text: [
            TextSpan(text: tr.fillLesson3a),
            // матка — вона: «біла», «жовта»…
            GuideBubble.task(tr.lessonQueenColor(l.colorValue)),
            const TextSpan(text: '.'),
          ],
          bear: true,
          tapNext: false
        ),
      4 => (
          text: [
            TextSpan(text: tr.fillLesson4a),
            GuideBubble.task(tr.fillLesson4b),
            TextSpan(text: tr.fillLesson4c),
          ],
          bear: true,
          tapNext: false
        ),
      _ => (
          text: [TextSpan(text: tr.fillLesson5)],
          bear: true,
          tapNext: false
        ),
    };
  }

  /// «Змін немає» / «Пропустити»: без перевірки полів, одразу наступний вулик.
  Future<void> _quick(FillAction action) async {
    if (_saving) return;
    final onNext = widget.onNext;
    final result = FillResult(const {},
        next: true, action: action, note: action == FillAction.noChange ? _noteText : null);
    if (onNext == null) {
      Navigator.pop(context, result);
      return;
    }
    setState(() => _saving = true);
    try {
      await onNext(result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save({bool next = false}) async {
    if (_saving) return;
    if (_lesson != null && _step < 5) return; // урок: спершу заповнити комірки
    ({String itemId, double amount})? feed;
    final fid = _feedItem;
    if (fid != null) {
      final it = widget.stock.firstWhere((s) => s.id == fid);
      final a = parseAmount(_feedAmount.text);
      if (a == null || a <= 0) {
        setState(() => _error = tr.feedNeedQty);
        return;
      }
      if (a > (it.quantity ?? 0) + 1e-9) {
        setState(() => _error = tr.feedOnlyInStock('${formatAmount(it.quantity ?? 0)} ${it.unit}'));
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
        if (n == null || n < 0) {
          setState(() => _error = tr.fillWholeFrom0(p.nameWithUnit));
          return;
        }
        v = n.toString();
      } else if (p.dataType == DataTypes.float_) {
        final n = double.tryParse(v.replaceAll(',', '.'));
        if (n == null) {
          setState(() => _error = tr.fillNumber(p.nameWithUnit));
          return;
        }
        v = n.toString();
      }
      if (v != (widget.latest[p.id] ?? '')) out[p.id] = v;
    }
    final result = FillResult(out, next: next, feed: feed, note: _noteText);
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
    // великий шрифт (Налаштування → «Розмір шрифту»): у дві колонки слова
    // рвались би посередині - назва над полем
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 11.6;
    TableRow row(String name, Widget value) => stacked
        ? TableRow(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(name, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.25)),
                value,
              ]),
            ),
          ])
        : TableRow(children: [
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
    Table table(List<TableRow> rows) => Table(
          border: TableBorder.all(color: grid, width: 1, borderRadius: BorderRadius.circular(10)),
          columnWidths: stacked
              ? const {0: FlexColumnWidth()}
              : const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        );
    TableRow paramRow(Parameter p) => row(
        p.nameWithUnit,
        HoneyRing(
            on: _ring(4) && p.id == _lesson!.dateParamId,
            radius: 8,
            child: _field(p)));
    final feedRows = <TableRow>[
        if (widget.stock.isNotEmpty)
          row(
            tr.feedFromStock,
            DropdownButton<String?>(
              value: _feedItem,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.popupBg,
              hint: _fitLeft(
                  Text(tr.dontWriteOff, style: TextStyle(color: AppColors.textMuted, fontSize: 14))),
              items: [
                DropdownMenuItem<String?>(
                    value: null,
                    child: _fitLeft(
                        Text(tr.dontWriteOff, style: TextStyle(color: AppColors.text, fontSize: 14)))),
                for (final s in widget.stock)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: _fitLeft(Text(
                        tr.stockItemHas(s.name, '${formatAmount(s.quantity ?? 0)} ${s.unit}'),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(color: AppColors.text, fontSize: 14))),
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
            tr.howMuch(feed.unit),
            TextField(
              key: const ValueKey('feed-amount'),
              controller: _feedAmount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: thousandsInput,
              style: TextStyle(color: AppColors.text, fontSize: 15),
              decoration: _cellInput,
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
    ];

    // параметри за групами, як на панелі «Характеристики»: спершу без групи,
    // далі кожна група під своєю плашкою (лише обрані для цього вулика)
    final byId = {for (final p in widget.params) p.id: p};
    final used = <String>{};
    final sections = <(String, List<Parameter>)>[];
    for (final g in widget.groups) {
      final items = [for (final id in g.ids) if (byId[id] != null && used.add(id)) byId[id]!];
      if (items.isNotEmpty) sections.add((g.name, items));
    }
    final loose = [for (final p in widget.params) if (!used.contains(p.id)) p];
    final head = <TableRow>[
      for (final (name, value) in widget.infoRows)
        row(
            name,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: Text(value,
                  style: TextStyle(
                      color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
            )),
      for (final p in loose) paramRow(p),
      if (sections.isEmpty) ...feedRows,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (head.isNotEmpty) table(head),
      for (final (name, items) in sections) ...[
        const SizedBox(height: 10),
        Container(
          height: 30,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: AppColors.hive, borderRadius: BorderRadius.circular(10)),
          child: Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF2B1A08), fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        table([for (final p in items) paramRow(p)]),
      ],
      if (sections.isNotEmpty && feedRows.isNotEmpty) ...[
        const SizedBox(height: 10),
        table(feedRows),
      ],
    ]);
  }

  /// Текст у клітинці списку: не переноситься й не обрізається «…» — зменшується.
  static Widget _fitLeft(Widget text) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: text);

  static const _cellInput = InputDecoration(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
    hintText: '-',
  );

  Widget _field(Parameter p) {
    switch (p.dataType) {
      case DataTypes.date:
        final dateText = _picked[p.id] ?? '';
        // уся клітинка — кнопка календаря
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          // урок: календар — лише на своєму кроці й лише в комірці дати огляду
          onTap: _lesson != null && !(_ring(4) && p.id == _lesson!.dateParamId)
              ? null
              : () async {
                  final r = await showAppDatePicker(context, dateText);
                  if (r != null) setState(() => _picked[p.id] = r);
                  _lessonCheck();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(children: [
              Expanded(
                child: Text(dateText.isEmpty ? tr.chooseDate : dateText,
                    style: TextStyle(
                        color: dateText.isEmpty ? AppColors.textMuted : AppColors.text,
                        fontSize: 15)),
              ),
              Icon(Icons.calendar_today, size: 16, color: AppColors.textMuted),
            ]),
          ),
        );
      case DataTypes.bool_:
        // «Так» / «Ні» — повторний тап знімає вибір
        final cur = _picked[p.id] ?? '';
        Widget opt(String v) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: PillButton(
                  text: v,
                  bg: cur == v ? AppColors.accent : AppColors.typeBtn,
                  fg: cur == v ? Colors.white : AppColors.text,
                  height: 34,
                  radius: 10,
                  fontSize: 14,
                  onPressed: () => setState(() => _picked[p.id] = cur == v ? '' : v),
                ),
              ),
            );
        return Row(children: [opt(DataTypes.yes), opt(DataTypes.no)]);
      case DataTypes.choice:
        final cur = _picked[p.id] ?? '';
        // старе значення, якого вже немає серед варіантів, — теж показуємо
        final items = [...p.options, if (cur.isNotEmpty && !p.options.contains(cur)) cur];
        return DropdownButton<String>(
          value: cur.isEmpty ? null : cur,
          isExpanded: true,
          isDense: true,
          underline: const SizedBox.shrink(),
          dropdownColor: AppColors.popupBg,
          hint: Text(tr.choose, style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
          items: [
            DropdownMenuItem<String>(
                value: '', child: Text('-', style: TextStyle(color: AppColors.textMuted))),
            for (final o in items)
              DropdownMenuItem<String>(
                  value: o,
                  child: Text(o,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.15))),
          ],
          onChanged: (v) => setState(() => _picked[p.id] = v ?? ''),
        );
      case DataTypes.color:
        final colorLabel = _picked[p.id] ?? '';
        return Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (label, c) in queenTagChoices)
            HoneyRing(
              on: _ring(3) && label == _lesson!.colorValue && p.id == _lesson!.colorParamId,
              child: ColorTagSwatch(
              fill: c,
              size: 28,
              selected: colorLabel == label,
              tooltip: label,
              // повторний тап по обраному кольору — зняти вибір
              // урок: лише той колір, який просять, і лише на цьому кроці
              onTap: _lesson != null && !(_ring(3) && label == _lesson!.colorValue)
                  ? null
                  : () {
                      setState(() => _picked[p.id] = colorLabel == label ? '' : label);
                      _lessonCheck();
                    },
            )),
        ]);
      default:
        return TextField(
          controller: _text[p.id],
          style: TextStyle(color: AppColors.text, fontSize: 15),
          decoration: _cellInput,
          // урок: у комірки нічого не вписують (лише колір і дата)
          readOnly: _lesson != null,
          onChanged: (_) => _lessonCheck(),
          keyboardType: p.dataType == DataTypes.int_
              ? TextInputType.number
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
    final dialog = _dialog();
    if (_lesson == null) return dialog;
    // урок: відкрита клавіатура — уся висота формі (інакше комірки не видно),
    // підказка повернеться, щойно клавіатуру сховають
    // (дерево віджетів те саме, інакше поле втрачає фокус і клавіатура блимає)
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    // урок: форма вище, унизу — пасічник або ведмежа-помічник (на тому ж місці)
    final line = _lessonLine;
    return PopScope(canPop: false, child: Stack(children: [
      Positioned.fill(
          child: Padding(padding: EdgeInsets.only(bottom: keyboard ? 0 : 270), child: dialog)),
      if (!keyboard) ...lessonScene(
        pose: line.bear ? LessonPose.bear : LessonPose.leaning,
        text: line.text,
        onTap: line.tapNext ? () => setState(() => _step = _step == 0 ? 2 : _step + 1) : null,
        onContinue: line.tapNext ? () => setState(() => _step = _step == 0 ? 2 : _step + 1) : null,
        bottomInset: MediaQuery.of(context).padding.bottom,
        toggleEditing: false,
        // «Завершити» - під кнопкою «Продовжити» (без кнопки - без неї)
        onFinish: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    ]));
  }

  // поки «Зберегти й далі» працює, форма не реагує на дотики
  Widget _dialog() => AbsorbPointer(absorbing: _saving, child: _dialogBody());

  Widget _dialogBody() {
    return AlertDialog(
      // назва вулика — видно, що «Зберегти й далі» перейшло до наступного
      title: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.title != null) Text(widget.title!),
            Text(widget.subtitle ?? tr.fillParams,
                style: widget.title == null
                    ? null
                    : TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w400)),
          ]),
        ),
        // швидка правка: історія цього параметра — іконкою вгорі праворуч
        if (widget.onHistory != null)
          IconButton(
            tooltip: tr.history,
            icon: Icon(Icons.history, color: AppColors.text),
            onPressed: widget.onHistory,
          ),
        // обхід: вийти з огляду (кнопки внизу ведуть до наступного вулика)
        if (widget.offerNext)
          IconButton(
            tooltip: tr.close,
            icon: Icon(Icons.close, color: AppColors.text),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
      ]),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _table(),
            if (widget.withNote) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('fill-note'),
                controller: _note,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: AppColors.text, fontSize: 14.5),
                decoration: InputDecoration(
                  labelText: tr.note,
                  hintText: tr.noteOptional,
                ),
              ),
            ],
          ],
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
          if (widget.offerNext || _lesson != null)
            // обхід: кожна кнопка записує своє й відкриває наступний вулик;
            // усі на сьогодні оглянуті — огляд закривається.
            // Урок показує ті самі кнопки, що й справжня форма: діє лише дискета.
            Row(children: [
              // «Зберегти» і «Пропустити» - значками (галочка й стрілка далі)
              // дискета замість галочки
              HoneyRing(
                on: _ring(5),
                child: Tooltip(
                  message: tr.save,
                  child: Material(
                    color: _saving ? AppColors.accent.withValues(alpha: 0.45) : AppColors.accent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _saving || (_lesson != null && _step < 5)
                          ? null
                          : _lesson != null
                              ? _save
                              : () => _save(next: true),
                      child: const SizedBox.square(
                          dimension: 50, child: Icon(Icons.save, color: Colors.white, size: 28)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: PillButton(
                      text: tr.noChanges,
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 50,
                      onPressed: _saving || _lesson != null ? null : () => _quick(FillAction.noChange))),
              const SizedBox(width: 10),
              CircleIconButton(
                  icon: 'arrow_right',
                  bg: AppColors.neutralBtn,
                  iconColor: AppColors.text,
                  size: 50,
                  tooltip: tr.skip,
                  onPressed: _saving || _lesson != null ? null : () => _quick(FillAction.skip)),
            ])
          else
            Row(children: [
              Expanded(
                child: PillButton(
                    text: tr.cancel,
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    // урок: поки огляд не завершено — не вийти
                    onPressed: _lesson != null ? null : () => Navigator.pop(context)),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: HoneyRing(
                      on: _ring(5),
                      radius: 14,
                      child: PillButton(
                          text: tr.save,
                          bg: AppColors.accent,
                          // урок: зберегти — лише коли комірки заповнено
                          onPressed: _saving || (_lesson != null && _step < 5) ? null : _save))),
            ]),
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
