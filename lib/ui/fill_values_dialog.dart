import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../logic/stock_format.dart';
import 'common.dart';
import 'date_picker.dart';
import 'guide_bubble.dart';
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
  FillLesson? lesson,
  String subtitle = 'Заповнити параметри',
  VoidCallback? onHistory,
}) {
  Widget host() => _FillHost(
        first: FillPage(params: params, latest: latest, stock: stock, title: title),
        offerNext: lesson == null && offerNext,
        onNext: onNext,
        lesson: lesson,
        subtitle: subtitle,
        onHistory: onHistory,
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
  final String periodParamId;
  final String periodValue;
  final String colorParamId;
  final String colorValue;
  const FillLesson({
    required this.periodParamId,
    required this.colorParamId,
    this.periodValue = '3',
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
  final String subtitle;
  final VoidCallback? onHistory;
  const _FillHost(
      {required this.first,
      required this.offerNext,
      this.onNext,
      this.lesson,
      this.subtitle = 'Заповнити параметри',
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
  const FillResult(this.values, {this.next = false, this.feed, this.action = FillAction.save});
}

class _FillDialog extends StatefulWidget {
  final String? title;
  final List<Parameter> params;
  final Map<String, String?> latest;
  final bool offerNext;
  final List<StockItem> stock;
  final Future<void> Function(FillResult result)? onNext;
  final FillLesson? lesson;
  final String subtitle;
  final VoidCallback? onHistory;
  const _FillDialog(
      {super.key,
      this.lesson,
      this.subtitle = 'Заповнити параметри',
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

  static final _intFilter = WholeValueFormatter(RegExp(r'^-?\d*$'));
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
    super.dispose();
  }

  String? _feedItem;
  final _feedAmount = TextEditingController();

  bool _saving = false;

  // ---- урок «Базові поняття»: кроки в самій формі ----
  // 0 пасічник пояснює; (1 пропущено); 2 — з'являється ведмежа; 3 — «матка біла»;
  // 4 — «через 3 дні»; 5 — «Збережи»
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
    if (_step == 4 && (_text[l.periodParamId]?.text.trim() ?? '') == l.periodValue) {
      setState(() => _step = 5);
    }
  }

  ({List<InlineSpan> text, bool bear, bool tapNext}) get _lessonLine {
    final l = _lesson!;
    return switch (_step) {
      0 => (
          text: [
            const TextSpan(
                text: 'Це параметри вулика. Зараз тут тільки обов\'язкові, але ти зможеш '),
            GuideBubble.highlight('додати нові згодом'),
            const TextSpan(text: '.'),
          ],
          bear: false,
          tapNext: true
        ),
      1 => (
          text: const [
            TextSpan(text: 'Мій помічник перевірив вулик за тебе, тож запиши дані в комірки.')
          ],
          bear: false,
          tapNext: true
        ),
      2 => (
          text: [
            const TextSpan(text: 'Кхе, кхе... Я допоможу зі '),
            GuideBubble.highlight('внесенням інформації'),
            const TextSpan(text: ' до твого вулика.'),
          ],
          bear: true,
          tapNext: true
        ),
      3 => (
          text: [
            const TextSpan(text: 'В тебе матка '),
            // матка — вона: «біла», «жовта»…
            GuideBubble.task(const {
                  'Білий': 'біла',
                  'Жовтий': 'жовта',
                  'Червоний': 'червона',
                  'Зелений': 'зелена',
                  'Синій': 'синя',
                }[l.colorValue] ??
                l.colorValue.toLowerCase()),
            const TextSpan(text: '.'),
          ],
          bear: true,
          tapNext: false
        ),
      4 => (
          text: [
            const TextSpan(text: 'Заглянеш сам через '),
            GuideBubble.task('${l.periodValue} дні'),
            const TextSpan(text: '.'),
          ],
          bear: true,
          tapNext: false
        ),
      _ => (
          text: const [TextSpan(text: 'Збережи, бо я більше туди не полізу.')],
          bear: true,
          tapNext: false
        ),
    };
  }

  /// «Змін немає» / «Пропустити»: без перевірки полів, одразу наступний вулик.
  Future<void> _quick(FillAction action) async {
    if (_saving) return;
    final onNext = widget.onNext;
    final result = FillResult(const {}, next: true, action: action);
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
        for (final p in widget.params)
          row(
              p.nameWithUnit,
              HoneyRing(
                  on: _ring(4) && p.id == _lesson!.periodParamId,
                  radius: 8,
                  child: _field(p))),
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
    hintText: '-',
  );

  Widget _field(Parameter p) {
    switch (p.dataType) {
      case DataTypes.date:
        final dateText = _picked[p.id] ?? '';
        // уся клітинка — кнопка календаря
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _lesson != null ? null : () async {
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
          hint: Text('Обрати', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
          items: [
            DropdownMenuItem<String>(
                value: '', child: Text('-', style: TextStyle(color: AppColors.textMuted))),
            for (final o in items)
              DropdownMenuItem<String>(
                  value: o,
                  child: Text(o,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 15))),
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
          // урок: вписати можна лише на своєму кроці й лише в ту комірку
          readOnly: _lesson != null && !(_ring(4) && p.id == _lesson!.periodParamId),
          onChanged: (_) => _lessonCheck(),
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
        below: line.tapNext
            ? PillButton(
                text: 'Продовжити',
                bg: AppColors.accent,
                height: 38,
                fontSize: 13,
                width: double.infinity,
                onPressed: () => setState(() => _step = _step == 0 ? 2 : _step + 1))
            : null,
        bottomInset: MediaQuery.of(context).padding.bottom,
        toggleEditing: false,
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
            Text(widget.subtitle,
                style: widget.title == null
                    ? null
                    : TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w400)),
          ]),
        ),
        // швидка правка: історія цього параметра — іконкою вгорі праворуч
        if (widget.onHistory != null)
          IconButton(
            tooltip: 'Історія',
            icon: Icon(Icons.history, color: AppColors.text),
            onPressed: widget.onHistory,
          ),
        // обхід: вийти з огляду (кнопки внизу ведуть до наступного вулика)
        if (widget.offerNext)
          IconButton(
            tooltip: 'Закрити',
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
          if (widget.offerNext)
            // обхід: кожна кнопка записує своє й відкриває наступний вулик;
            // усі на сьогодні оглянуті — огляд закривається
            Row(children: [
              // «Зберегти» і «Пропустити» - значками (галочка й стрілка далі)
              CircleIconButton(
                  icon: 'check',
                  bg: AppColors.accent,
                  size: 50,
                  tooltip: 'Зберегти',
                  onPressed: _saving ? null : () => _save(next: true)),
              const SizedBox(width: 10),
              Expanded(
                  child: PillButton(
                      text: 'Змін немає',
                      bg: AppColors.darkBtn,
                      fg: AppColors.text,
                      height: 50,
                      onPressed: _saving ? null : () => _quick(FillAction.noChange))),
              const SizedBox(width: 10),
              CircleIconButton(
                  icon: 'arrow_right',
                  bg: AppColors.neutralBtn,
                  iconColor: AppColors.text,
                  size: 50,
                  tooltip: 'Пропустити',
                  onPressed: _saving ? null : () => _quick(FillAction.skip)),
            ])
          else
            Row(children: [
              Expanded(
                child: PillButton(
                    text: 'Скасувати',
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
                          text: 'Зберегти',
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
