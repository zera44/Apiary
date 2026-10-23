import 'dart:convert';

import '../logic/unit_convert.dart';
import '../data/finance.dart';
import '../data/models.dart';
import '../data/notes.dart';
import '../data/repository.dart';
import '../data/user_reminders.dart';
import '../logic/visit_reminders.dart';
import '../ui/fin_style.dart' show kFinStockCategoryName;
import '../ui/icons.dart' show queenTagChoices;
import 'assistant_links.dart';
import 'assistant_session.dart';

/// Інструменти помічника «Пасічник» - виконує їх застосунок (дані на
/// телефоні). Опис для моделі - supabase/functions/assistant/tools.ts
/// (назви й поля мають збігатися).
///
/// Моделі повертається мінімум: лише те, що потрібно для відповіді.
/// Запис - лише після картки «Записати так?» ([ConfirmWrite]); без «Так»
/// нічого не змінюється. Після запису - [UndoEntry] для «Скасувати».

/// Екрани навігатора (той самий список - SCREENS у prompt.ts).
const kAssistantScreens = [
  'home',
  'apiaries',
  'map',
  'hive',
  'parameters',
  'templates',
  'stock',
  'finance',
  'finance_add',
  'history',
  'scanner',
  'receipt',
  'settings',
  'helpers',
  'backups',
  'lessons',
  'lesson',
  'feedback',
  'whats_new',
];

/// Куди відкрити.
class NavTarget {
  final String screen;
  final String? apiaryId;

  /// Вулик на карті (для групи - перший її вулик).
  final String? elementId;
  final String? lessonId;

  /// Для кнопки «Відкрити …».
  final String label;
  const NavTarget(this.screen, this.label, {this.apiaryId, this.elementId, this.lessonId});
}

/// Поле картки «Записати так?».
class WriteField {
  final String key;
  final String label;
  final String value;
  final bool editable;

  /// Значення на вибір (напр., колір мітки матки) - кнопками, а не текстом.
  final List<String> choices;
  const WriteField(this.key, this.label, this.value,
      {this.editable = true, this.choices = const []});
}

/// Запис, що чекає на «Так» / «Ні».
class PendingWrite {
  final String tool;
  final String title;
  final List<WriteField> fields;
  const PendingWrite(this.tool, this.title, this.fields);
}

/// Показати картку; «Так» - значення полів (можливо, виправлені),
/// «Ні» - null.
typedef ConfirmWrite = Future<Map<String, String>?> Function(PendingWrite write);

/// Відкласти запис: чат не відкрито (відповідь із черги, фон) - картка
/// чекатиме в чаті; [tool] і [input] - щоб виконати після «Так».
typedef DeferWrite =
    Future<void> Function(String tool, Map<String, dynamic> input, PendingWrite card);

/// Відкрити екран; false - не вдалося.
typedef Navigate = Future<bool> Function(NavTarget target);

/// Те, що можна скасувати після запису.
class UndoEntry {
  final String label;
  final Future<void> Function() undo;
  const UndoEntry(this.label, this.undo);
}

/// Помилка в даних від моделі: повертається їй текстом (is_error).
class _Bad implements Exception {
  final String message;
  const _Bad(this.message);
}

class _Hive {
  final EntityRef ref;
  final String id;
  final String name;
  final String apiaryName;
  final String? apiaryId;
  final String elementId;
  const _Hive(this.ref, this.id, this.name, this.apiaryName, this.apiaryId, this.elementId);
}

class AssistantTools {
  final Repository repo;

  /// null - відповідь на повідомлення з черги: екран не відкривається сам,
  /// а пропонується кнопкою ([offeredNav]).
  final Navigate? navigate;
  final ConfirmWrite confirm;

  /// Є - запис не підтверджується одразу, а відкладається карткою.
  final DeferWrite? defer;
  final void Function(UndoEntry entry)? onUndoable;
  final DateTime Function() now;

  AssistantTools(
    this.repo, {
    this.navigate,
    required this.confirm,
    this.defer,
    this.onUndoable,
    this.searchBooks,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  /// Пошук у книгах (справжня модель через посередника); null - немає.
  final Future<Map<String, dynamic>> Function(String query, int limit)? searchBooks;

  /// Запропоновані (не відкриті) екрани - для кнопок «Відкрити …».
  final List<NavTarget> offeredNav = [];

  String? _tool;
  Map<String, dynamic>? _input;

  /// Виконати відкладений запис після «Так» у картці ([values] - поля
  /// картки, можливо виправлені). Дані перевіряються наново - на момент «Так».
  static Future<ToolOutcome> applyDeferred(
    Repository repo,
    String tool,
    Map<String, dynamic> input,
    Map<String, String> values, {
    void Function(UndoEntry entry)? onUndoable,
    DateTime Function()? now,
  }) {
    return AssistantTools(
      repo,
      confirm: (_) async => values,
      onUndoable: onUndoable,
      now: now,
    ).run(tool, input);
  }

  /// Зроблені записи (для «Скасувати»).
  final List<UndoEntry> undoable = [];

  static const readTools = {
    'open_screen',
    'apiaries_list',
    'find_hives',
    'hive_history',
    'stock_list',
    'finance_summary',
    'search_books',
    'convert_units',
  };
  static const writeTools = {
    'record_inspection',
    'stock_receive',
    'stock_issue',
    'add_finance_entry',
    'create_reminder',
  };

  /// Для [AssistantSession.ask].
  Future<ToolOutcome> run(String name, Map<String, dynamic> input) async {
    _tool = name;
    _input = input;
    try {
      final out = switch (name) {
        'open_screen' => await _openScreen(input),
        'apiaries_list' => await _apiariesList(),
        'find_hives' => await _findHives(input),
        'hive_history' => await _hiveHistory(input),
        'stock_list' => await _stockList(input),
        'finance_summary' => await _financeSummary(input),
        'search_books' => await _searchBooks(input),
        'convert_units' => await _convertUnits(input),
        'record_inspection' => await _recordInspection(input),
        'stock_receive' => await _stockMove(input, receive: true),
        'stock_issue' => await _stockMove(input, receive: false),
        'add_finance_entry' => await _addFinance(input),
        'create_reminder' => await _createReminder(input),
        _ => throw _Bad('Невідомий інструмент $name'),
      };
      return ToolOutcome(jsonEncode(out));
    } on _Bad catch (e) {
      return ToolOutcome(e.message, isError: true);
    } on ArgumentError catch (e) {
      return ToolOutcome('${e.message}', isError: true);
    } on StateError catch (e) {
      return ToolOutcome(e.message, isError: true);
    }
  }

  // ---------------------------------------------------------------------
  // спільне

  static String _s(Map<String, dynamic> m, String k) => (m[k] ?? '').toString().trim();

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _date(DateTime d) => Repository.formatVisitDate(d);

  static String _num(double v) => Repository.fmtQty(v);

  static double? _parseNum(String s) =>
      double.tryParse(s.trim().replaceAll(' ', '').replaceAll(',', '.'));

  /// Дата: 2026-05-05 або 05.05.2026.
  static DateTime? _parseDate(String s) {
    final t = s.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (iso != null) {
      return _validDate(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    }
    final ua = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(t);
    if (ua != null) {
      return _validDate(int.parse(ua[3]!), int.parse(ua[2]!), int.parse(ua[1]!));
    }
    return null;
  }

  static DateTime? _validDate(int y, int m, int d) {
    final v = DateTime(y, m, d);
    return v.year == y && v.month == m && v.day == d ? v : null;
  }

  /// Вибрати один запис за назвою: точний збіг, інакше єдиний «містить».
  static T _pick<T>(Iterable<T> all, String query, String Function(T) name, String what) {
    final q = _norm(query);
    if (q.isEmpty) throw _Bad('Не вказано: $what');
    final exact = [
      for (final x in all)
        if (_norm(name(x)) == q) x,
    ];
    if (exact.length == 1) return exact.first;
    final part = [
      for (final x in all)
        if (_norm(name(x)).contains(q)) x,
    ];
    if (part.length == 1) return part.first;
    final names = [for (final x in (part.isEmpty ? all : part).take(15)) name(x)];
    throw _Bad(
      part.isEmpty
          ? '$what «$query» не знайдено. Є: ${names.join(', ')}'
          : '$what «$query»: кілька збігів - ${names.join(', ')}. Уточніть.',
    );
  }

  /// Як [_pick], але нічого схожого - null (а не помилка).
  static T? _maybe<T>(Iterable<T> all, String query, String Function(T) name, String what) {
    final q = _norm(query);
    if (q.isEmpty) return null;
    if (!all.any((x) => _norm(name(x)) == q || _norm(name(x)).contains(q))) return null;
    return _pick<T>(all, query, name, what);
  }

  Future<List<_Hive>> _allHives() async {
    final apiaries = await repo.listApiaries();
    final byElement = <String, String>{
      for (final e in (await repo.listElementsByApiary([for (final a in apiaries) a.id])).entries)
        for (final el in e.value) el.id: e.key,
    };
    return [
      for (final t in await repo.visitTargets())
        _Hive(
          t.key.startsWith('g:')
              ? EntityRef.group(t.key.substring(2))
              : EntityRef.element(t.elementId),
          t.key,
          t.name,
          t.apiaryName,
          byElement[t.elementId],
          t.elementId,
        ),
    ];
  }

  /// Вулик за id (e:… / g:…) або за назвою («5», «Вулик 5»).
  Future<_Hive> _hive(String raw) async {
    final id = raw.trim();
    final all = await _allHives();
    for (final h in all) {
      if (h.id == id) return h;
    }
    final q = _norm(id).replaceFirst(RegExp(r'^вулик\s*(№\s*)?'), '');
    final hits = [
      for (final h in all)
        if (_norm(h.name) == q || _norm(h.name).replaceFirst(RegExp(r'^вулик\s*(№\s*)?'), '') == q)
          h,
    ];
    if (hits.length == 1) return hits.first;
    if (hits.length > 1) {
      throw _Bad(
        'Вулик «$raw» є в кількох пасіках: '
        '${[for (final h in hits) '${h.id} (${h.apiaryName})'].join(', ')}',
      );
    }
    throw _Bad('Вулик «$raw» не знайдено');
  }

  Map<String, dynamic> _hiveJson(_Hive h) => {'id': h.id, 'name': h.name, 'apiary': h.apiaryName};

  /// Записати після «Так»: [build] - картка, [apply] - запис зі
  /// значеннями полів (після можливого виправлення).
  Future<Map<String, dynamic>> _write(
    PendingWrite w,
    Future<(Map<String, dynamic>, UndoEntry)> Function(Map<String, String> values) apply,
  ) async {
    final d = defer;
    if (d != null) {
      await d(_tool!, Map<String, dynamic>.from(_input!), w);
      return {
        'status': 'очікує підтвердження',
        'note': 'Людина побачить картку в чаті й вирішить сама',
      };
    }
    final values = await confirm(w);
    if (values == null) return {'status': 'відхилено'};
    final (result, undo) = await apply(values);
    undoable.add(undo);
    onUndoable?.call(undo);
    return {'status': 'підтверджено', ...result};
  }

  // ---------------------------------------------------------------------
  // без підтвердження

  Future<Map<String, dynamic>> _openScreen(Map<String, dynamic> input) async {
    final target = await _target(_s(input, 'screen'), _s(input, 'id'));
    final nav = navigate;
    if (nav == null) {
      offeredNav.add(target);
      return {'status': 'запропоновано', 'note': 'Людина побачить кнопку «Відкрити»'};
    }
    return {'status': await nav(target) ? 'відкрито' : 'не вдалося відкрити'};
  }

  /// Куди відкрити екран [screen] з [id] (пасіка, вулик, урок) - і для
  /// open_screen, і для посилань у відповідях. Не вийшло - null.
  /// Номер вулика -> id (лише однозначні): посилання на «вулик 14» у
  /// відповідях, які модель написала без розмітки.
  Future<Map<String, String>> hiveLinks() async {
    final by = <String, List<String>>{};
    for (final h in await _allHives()) {
      final k = hiveKey(h.name);
      if (k.isNotEmpty) (by[k] ??= []).add(h.id);
    }
    return {
      for (final e in by.entries)
        if (e.value.length == 1) e.key: e.value.single,
    };
  }

  Future<NavTarget?> targetFor(String screen, String? id) async {
    try {
      return await _target(screen, id ?? '');
    } on _Bad {
      return null;
    }
  }

  Future<NavTarget> _target(String screen, String id) async {
    if (!kAssistantScreens.contains(screen)) {
      throw _Bad('Немає екрана «$screen». Є: ${kAssistantScreens.join(', ')}');
    }
    switch (screen) {
      case 'hive':
        if (id.isEmpty) throw const _Bad('Для hive потрібен id вулика (з find_hives)');
        final h = await _hive(id);
        return NavTarget('hive', h.name, apiaryId: h.apiaryId, elementId: h.elementId);
      case 'map':
        final apiaries = await repo.listApiaries();
        if (apiaries.isEmpty) throw const _Bad('Пасік ще немає');
        final a = id.isEmpty
            ? (apiaries.length == 1
                  ? apiaries.first
                  : throw _Bad(
                      'Пасік кілька - вкажіть id: '
                      '${[for (final a in apiaries) '${a.id} (${a.name})'].join(', ')}',
                    ))
            : apiaries.firstWhere(
                (a) => a.id == id,
                orElse: () => _pick(apiaries, id, (a) => a.name, 'Пасіку'),
              );
        return NavTarget('map', a.name, apiaryId: a.id);
      case 'lesson':
        return NavTarget('lesson', 'урок', lessonId: id.isEmpty ? null : id);
      default:
        return NavTarget(screen, screen);
    }
  }

  Future<Map<String, dynamic>> _apiariesList() async {
    final apiaries = await repo.listApiaries();
    final hives = await _allHives();
    return {
      'apiaries': [
        for (final a in apiaries)
          {
            'id': a.id,
            'name': a.name,
            // група вуликів (лежак) - один вулик, як у find_hives
            'hives': hives.where((h) => h.apiaryId == a.id).length,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _findHives(Map<String, dynamic> input) async {
    final apiary = _s(input, 'apiary');
    final name = _norm(_s(input, 'name'));
    final due = _s(input, 'due');
    final param = _s(input, 'parameter');
    final value = _norm(_s(input, 'value'));
    final hasQr = input['has_qr'];
    final limit = ((input['limit'] as num?)?.toInt() ?? 20).clamp(1, 50);
    if (due.isNotEmpty && !const ['overdue', 'week'].contains(due)) {
      throw _Bad('due: overdue або week');
    }

    var hives = await _allHives();
    if (apiary.isNotEmpty) {
      final apiaries = await repo.listApiaries();
      final a =
          apiaries.where((a) => a.id == apiary).firstOrNull ??
          _pick<Apiary>(apiaries, apiary, (a) => a.name, 'Пасіку');
      hives = [
        for (final h in hives)
          if (h.apiaryId == a.id) h,
      ];
    }
    if (name.isNotEmpty) {
      hives = [
        for (final h in hives)
          if (_norm(h.name).contains(name)) h,
      ];
    }

    final targets = {for (final t in await repo.visitTargets()) t.key: t};
    final today = now();
    int? daysLeft(_Hive h) => targets[h.id] == null ? null : visitDaysLeft(targets[h.id]!, today);
    if (due.isNotEmpty) {
      hives = [
        for (final h in hives)
          if (daysLeft(h) != null && daysLeft(h)! <= (due == 'overdue' ? 0 : 7)) h,
      ];
    }

    if (hasQr is bool) {
      final kept = <_Hive>[];
      for (final h in hives) {
        if ((await repo.qrFor(h.ref) != null) == hasQr) kept.add(h);
      }
      hives = kept;
    }

    final p = param.isEmpty
        ? null
        : _pick(
            (await repo.listParameters()).where((x) => !x.deleted),
            param,
            (x) => x.name,
            'Параметр',
          );
    final values = <String, String?>{};
    if (p != null) {
      final kept = <_Hive>[];
      for (final h in hives) {
        final v = (await repo.latestParameterValues(h.ref))[p.id];
        if (v == null || v.trim().isEmpty) continue;
        if (value.isNotEmpty && !_norm(v).contains(value)) continue;
        values[h.id] = v;
        kept.add(h);
      }
      hives = kept;
    }

    return {
      'count': hives.length,
      'hives': [
        for (final h in hives.take(limit))
          {
            ..._hiveJson(h),
            if (daysLeft(h) != null) 'days_to_visit': daysLeft(h),
            if (targets[h.id]?.lastVisit != null) 'last_visit': targets[h.id]!.lastVisit,
            if (p != null) p.name: values[h.id],
          },
      ],
      if (hives.length > limit) 'more': hives.length - limit,
    };
  }

  Future<Map<String, dynamic>> _hiveHistory(Map<String, dynamic> input) async {
    final h = await _hive(_s(input, 'hive_id'));
    final days = ((input['days'] as num?)?.toInt() ?? 30).clamp(1, 365);
    final from = now().subtract(Duration(days: days)).microsecondsSinceEpoch / 1e6;
    final owner = h.ref.isGroup ? 'r.group_id = ?' : 'r.element_id = ?';
    final rows = await repo.db.rawQuery(
      'SELECT p.name, p.unit, r.value, r.created_at FROM parameter_records r '
      'JOIN parameters p ON p.id = r.parameter_id '
      "WHERE $owner AND r.created_at >= ? AND p.base_key IS NOT 'visit_left' "
      'ORDER BY r.created_at DESC, r.rowid DESC LIMIT 60',
      [h.ref.groupId ?? h.ref.elementId, from],
    );
    DateTime at(num s) => DateTime.fromMicrosecondsSinceEpoch((s * 1e6).round());
    final notes = [
      for (final n in await repo.listHiveNotes(h.ref))
        if (n.date >= from) n,
    ];
    return {
      'hive': _hiveJson(h),
      'days': days,
      'records': [
        for (final r in rows)
          {
            'date': _date(at(r['created_at'] as num)),
            'parameter': r['name'],
            'value': [r['value'], if (r['unit'] != null) r['unit']].join(' '),
          },
      ],
      'notes': [
        for (final n in notes.take(20)) {'date': _date(at(n.date)), 'text': n.text},
      ],
    };
  }

  /// Уривки з книг для порад; без книг чи пошуку - зрозуміла примітка, щоб
  /// модель не відповідала з власних знань.
  Future<Map<String, dynamic>> _searchBooks(Map<String, dynamic> input) async {
    final q = _s(input, 'query');
    if (q.isEmpty) throw const _Bad('Потрібен запит: кілька ключових слів');
    final limit = (input['limit'] is num ? (input['limit'] as num).toInt() : 5).clamp(1, 8);
    final search = searchBooks;
    if (search == null) {
      return {'results': [], 'note': 'Книг у базі ще немає - порадити не можу.'};
    }
    final r = await search(q, limit);
    final results = [for (final x in (r['results'] as List? ?? const [])) x];
    if (r['books'] != true) {
      return {'results': [], 'note': 'Книг у базі ще немає - порадити не можу.'};
    }
    if (results.isEmpty) {
      return {'results': [], 'note': 'У книгах про це нічого не знайдено - порадити не можу.'};
    }
    return {'results': results};
  }

  Future<Map<String, dynamic>> _stockList(Map<String, dynamic> input) async {
    final q = _norm(_s(input, 'query'));
    final items = [
      for (final i in await repo.listStockItems())
        if (q.isEmpty || _norm(i.name).contains(q)) i,
    ];
    return {
      'items': [
        for (final i in items.take(50))
          {
            'name': i.name,
            'quantity': _num(i.quantity ?? 0),
            'unit': i.unit,
            if (i.minQuantity != null && (i.quantity ?? 0) <= i.minQuantity!) 'low': true,
          },
      ],
      if (items.length > 50) 'more': items.length - 50,
    };
  }

  /// Переведення одиниць (кг <-> л через густину) і, за бажанням, сума за ціною.
  Future<Map<String, dynamic>> _convertUnits(Map<String, dynamic> input) async {
    final value = double.tryParse(_s(input, 'value').replaceAll(',', '.').replaceAll(RegExp(r'\s'), ''));
    if (value == null) throw const _Bad('value: число');
    final density = double.tryParse(_s(input, 'density').replaceAll(',', '.'));
    final substance = _s(input, 'substance');
    final d = density ?? densityOf(substance);
    final r = convertUnits(value, _s(input, 'from'), _s(input, 'to'), density: d);
    final out = <String, dynamic>{
      'value': _round(value),
      'from': normalizeUnit(_s(input, 'from')),
      'result': _round(r.value),
      'unit': r.unit,
      if (r.density != null)
        'density_kg_per_l': r.density,
      if (r.density != null)
        'note': 'Через густину ${r.density} кг/л'
            '${substance.isEmpty ? '' : ' (' + substance + ')'}: це наближення - скажи людині, яку густину взято',
    };
    // сума: ціна за одиницю price_unit
    final priceText = _s(input, 'price');
    if (priceText.isNotEmpty) {
      final price = double.tryParse(priceText.replaceAll(',', '.').replaceAll(RegExp(r'\s'), ''));
      if (price == null) throw const _Bad('price: число');
      final pu = _s(input, 'price_unit');
      final qty = pu.isEmpty
          ? r.value
          : convertUnits(value, _s(input, 'from'), pu, density: d).value;
      out['price'] = price;
      out['price_unit'] = pu.isEmpty ? r.unit : normalizeUnit(pu);
      out['total'] = (qty * price * 100).roundToDouble() / 100;
    }
    return out;
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  Future<Map<String, dynamic>> _financeSummary(Map<String, dynamic> input) async {
    final today = now();
    final from = _s(input, 'from').isEmpty
        ? DateTime(today.year, today.month)
        : (_parseDate(_s(input, 'from')) ?? (throw const _Bad('from: дата YYYY-MM-DD')));
    final toDay = _s(input, 'to').isEmpty
        ? today
        : (_parseDate(_s(input, 'to')) ?? (throw const _Bad('to: дата YYYY-MM-DD')));
    final to = DateTime(toDay.year, toDay.month, toDay.day + 1);
    final s = FinSummary.of(await repo.listFinEntries(from: from, to: to));
    final cats = await repo.finCategoryMap();
    Map<String, String> named(Map<String?, double> m) => {
      for (final e in m.entries)
        (e.key == null ? kFinStockCategoryName : cats[e.key]?.name ?? 'Інше'): _num(e.value),
    };
    return {
      'from': _date(from),
      'to': _date(toDay),
      'income': _num(s.income),
      'expense': _num(s.expense),
      'balance': _num(s.balance),
      'expense_by_category': named(s.expenseByCategory),
      'income_by_category': named(s.incomeByCategory),
    };
  }

  // ---------------------------------------------------------------------
  // з підтвердженням

  /// Значення параметра у форматі застосунку або [_Bad].
  static String _valueFor(Parameter p, String raw) {
    final v = raw.trim();
    if (v.isEmpty) throw _Bad('«${p.name}»: порожнє значення');
    switch (p.dataType) {
      case DataTypes.int_:
        final n = _parseNum(v);
        if (n == null || n != n.roundToDouble()) throw _Bad('«${p.name}»: потрібне ціле число');
        return n.toInt().toString();
      case DataTypes.float_:
        final n = _parseNum(v);
        if (n == null) throw _Bad('«${p.name}»: потрібне число');
        return _num(n);
      case DataTypes.bool_:
        final l = _norm(v);
        if (const ['так', 'є', 'yes', 'true', '1'].contains(l)) return DataTypes.yes;
        if (const ['ні', 'немає', 'нема', 'no', 'false', '0'].contains(l)) return DataTypes.no;
        throw _Bad('«${p.name}»: Так або Ні');
      case DataTypes.date:
        final d = _parseDate(v);
        if (d == null) throw _Bad('«${p.name}»: дата YYYY-MM-DD');
        return _date(d);
      case DataTypes.choice:
        return _pick(p.options, v, (o) => o, '«${p.name}»: значення');
      case DataTypes.color:
        final l = _norm(v);
        for (final (label, _) in queenTagChoices) {
          final stem = _norm(label).substring(0, 3);
          if (_norm(label) == l || (l.length >= 3 && l.startsWith(stem))) return label;
        }
        if (l.startsWith('без') || l == 'немає' || l == 'нема') return queenTagChoices.first.$1;
        throw _Bad('«${p.name}»: ${[for (final c in queenTagChoices) c.$1].join(', ')}');
      default:
        return v;
    }
  }

  Future<String?> _lastRecordId(String parameterId, EntityRef e) async {
    final rows = await repo.db.query(
      'parameter_records',
      columns: ['id'],
      where: 'parameter_id = ? AND ${e.isGroup ? 'group_id' : 'element_id'} = ?',
      whereArgs: [parameterId, e.groupId ?? e.elementId],
      orderBy: 'created_at DESC, rowid DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<Map<String, dynamic>> _recordInspection(Map<String, dynamic> input) async {
    final h = await _hive(_s(input, 'hive_id'));
    final raw = input['values'];
    final given = raw is Map
        ? {for (final e in raw.entries) '${e.key}': '${e.value}'}
        : <String, String>{};
    final note = _s(input, 'note');
    final visited = input['mark_visited'] != false;
    if (given.isEmpty && note.isEmpty) throw const _Bad('Немає що записати: values або note');

    final attached = [
      for (final p in await repo.attachedParameters(h.ref, elType: 'hive'))
        if (p.baseKey != 'visit_left' && p.baseKey != 'visit_start') p,
    ];
    final params = <Parameter, String>{};
    for (final e in given.entries) {
      final p = _pick(attached, e.key, (x) => x.name, 'Параметр вулика');
      params[p] = _valueFor(p, e.value);
    }

    final card = PendingWrite('record_inspection', 'Огляд: ${h.name} (${h.apiaryName})', [
      for (final e in params.entries)
        WriteField(
          'p:${e.key.id}',
          [e.key.name, if (e.key.unit != null) '(${e.key.unit})'].join(' '),
          e.value,
          choices: switch (e.key.dataType) {
            DataTypes.color => [for (final c in queenTagChoices) c.$1],
            DataTypes.choice => e.key.options,
            DataTypes.bool_ => const [DataTypes.yes, DataTypes.no],
            _ => const [],
          },
        ),
      if (note.isNotEmpty) WriteField('note', 'Нотатка', note),
      if (visited) WriteField('visit', 'Дата обходу', _date(now()), editable: false),
    ]);

    return _write(card, (v) async {
      // виправлене в картці - знову перевірити
      final fixed = {for (final p in params.keys) p: _valueFor(p, v['p:${p.id}'] ?? params[p]!)};
      final before = await repo.latestParameterValues(h.ref);
      final written = <(String recordId, String parameterId, String? prev)>[];
      for (final e in fixed.entries) {
        await repo.addParameterRecord(e.key.id, e.value, h.ref);
        written.add(((await _lastRecordId(e.key.id, h.ref))!, e.key.id, before[e.key.id]));
      }
      if (visited) {
        final vid = await repo.baseParameterId('hive', 'visit_start');
        final prev = vid == null ? null : before[vid];
        await repo.markVisited(h.ref, when: now());
        if (vid != null && (await repo.latestParameterValues(h.ref))[vid] != prev) {
          written.add(((await _lastRecordId(vid, h.ref))!, vid, prev));
        }
      }
      final text = (v['note'] ?? note).trim();
      final noteId = text.isEmpty ? null : await repo.addInspectionNote(h.ref, text);

      return (
        {'hive': _hiveJson(h), 'written': fixed.length, if (noteId != null) 'note': true},
        UndoEntry('Огляд: ${h.name}', () async {
          // історія значень на сервері лише дописується: ще не надіслане -
          // прибираємо, надіслане - повертаємо попереднє значення новим записом
          for (final (rid, pid, prev) in written.reversed) {
            final rows = await repo.db.query(
              'parameter_records',
              columns: ['synced'],
              where: 'id = ?',
              whereArgs: [rid],
            );
            if (rows.isNotEmpty && rows.first['synced'] == 0) {
              await repo.db.delete('parameter_records', where: 'id = ?', whereArgs: [rid]);
            } else if (prev != null) {
              await repo.addParameterRecord(pid, prev, h.ref);
            }
          }
          if (noteId != null) await repo.deleteHiveNote(noteId);
          repo.remindersChanged.value++;
        }),
      );
    });
  }

  Future<Map<String, dynamic>> _stockMove(
    Map<String, dynamic> input, {
    required bool receive,
  }) async {
    final items = await repo.listStockItems();
    final name = _s(input, 'item');
    if (name.isEmpty) throw const _Bad('item: назва номенклатури');
    final found = _maybe(items, name, (i) => i.name, 'Номенклатуру');
    if (found == null && !receive) {
      throw _Bad(
        'На складі немає «$name». Є: ${[for (final i in items.take(15)) i.name].join(', ')}',
      );
    }
    final amount = _parseNum(_s(input, 'amount'));
    if (amount == null || amount <= 0) throw const _Bad('amount: кількість більше 0');
    if (found == null) return _receiveNew(name, amount, input);
    final item = found;
    final comment = _s(input, 'comment');
    final have = item.quantity ?? 0;
    if (!receive && amount > have) {
      throw _Bad('На складі лише ${_num(have)} ${item.unit} «${item.name}»');
    }
    var total = _parseNum(_s(input, 'total'));
    if (receive && total == null) {
      final price = (await repo.lastStockPrices())[item.id];
      total = price == null ? 0 : price * amount;
    }
    final card = PendingWrite(
      receive ? 'stock_receive' : 'stock_issue',
      '${receive ? 'Прихід' : 'Списання'}: ${item.name}',
      [
        WriteField('amount', 'Кількість (${item.unit})', _num(amount)),
        if (receive) WriteField('total', 'Сума, грн', _num(total!)),
        if (comment.isNotEmpty) WriteField('comment', 'Коментар', comment),
      ],
    );
    return _write(card, (v) async {
      final a = _parseNum(v['amount'] ?? '') ?? (throw const _Bad('Кількість: число більше 0'));
      final c = (v['comment'] ?? comment).trim();
      final left = receive
          ? await repo.receiveStock(
              item.id,
              a,
              total: _parseNum(v['total'] ?? '') ?? total!,
              comment: c.isEmpty ? null : c,
            )
          : await repo.writeOffStock(item.id, a, comment: c.isEmpty ? null : c);
      final moveId =
          (await repo.db.query(
                'stock_moves',
                columns: ['id'],
                where: 'item_id = ?',
                whereArgs: [item.id],
                orderBy: 'created_at DESC, rowid DESC',
                limit: 1,
              )).first['id']
              as String;
      return (
        {'item': item.name, 'quantity_now': _num(left), 'unit': item.unit},
        UndoEntry(
          '${receive ? 'Прихід' : 'Списання'}: ${item.name}',
          () async => repo.cancelStockMove(moveId),
        ),
      );
    });
  }

  /// Прихід того, чого на складі ще немає: картка показує, що позицію
  /// буде створено (назву й одиницю можна виправити).
  Future<Map<String, dynamic>> _receiveNew(
    String name,
    double amount,
    Map<String, dynamic> input,
  ) async {
    final unit = _s(input, 'unit').isEmpty ? 'шт' : _s(input, 'unit');
    final total = _parseNum(_s(input, 'total')) ?? 0;
    final comment = _s(input, 'comment');
    final card = PendingWrite('stock_receive', 'Прихід: $name (нова позиція складу)', [
      WriteField('name', 'Назва', name),
      WriteField('unit', 'Одиниця', unit),
      WriteField('amount', 'Кількість', _num(amount)),
      WriteField('total', 'Сума, грн', _num(total)),
      if (comment.isNotEmpty) WriteField('comment', 'Коментар', comment),
    ]);
    return _write(card, (v) async {
      final n = (v['name'] ?? name).trim();
      final u = (v['unit'] ?? unit).trim();
      if (n.isEmpty || u.isEmpty) throw const _Bad('Потрібні назва й одиниця');
      final a = _parseNum(v['amount'] ?? '') ?? (throw const _Bad('Кількість: число більше 0'));
      final c = (v['comment'] ?? comment).trim();
      final id = await repo.addStockItem(n, u);
      final left = await repo.receiveStock(
        id,
        a,
        total: _parseNum(v['total'] ?? '') ?? total,
        comment: c.isEmpty ? null : c,
      );
      return (
        {'item': n, 'created': true, 'quantity_now': _num(left), 'unit': u},
        UndoEntry('Прихід: $n', () async => repo.deleteStockItem(id)),
      );
    });
  }

  Future<Map<String, dynamic>> _addFinance(Map<String, dynamic> input) async {
    final kind = _s(input, 'kind');
    if (kind != kFinIncome && kind != kFinExpense) throw const _Bad('kind: income або expense');
    final amount = _parseNum(_s(input, 'amount'));
    if (amount == null || amount <= 0) throw const _Bad('amount: сума більше 0');
    final catName = _s(input, 'category');
    final cats = await repo.listFinCategories(kind: kind);
    final cat = _maybe(cats, catName, (c) => c.name, 'Категорію');
    // такої категорії немає - буде створена (картка це показує)
    final newCat = cat == null && catName.isNotEmpty ? catName : null;
    final date = _s(input, 'date').isEmpty
        ? now()
        : (_parseDate(_s(input, 'date')) ?? (throw const _Bad('date: YYYY-MM-DD')));
    final comment = _s(input, 'comment');
    final card = PendingWrite('add_finance_entry', kind == kFinIncome ? 'Дохід' : 'Витрата', [
      WriteField('amount', 'Сума, грн', _num(amount)),
      newCat != null
          ? WriteField('category', 'Нова категорія', newCat)
          : WriteField('category', 'Категорія', cat?.name ?? '-', editable: false),
      WriteField('date', 'Дата', _date(date)),
      if (comment.isNotEmpty) WriteField('comment', 'Коментар', comment),
    ]);
    return _write(card, (v) async {
      final a = _parseNum(v['amount'] ?? '') ?? (throw const _Bad('Сума: число більше 0'));
      final d = _parseDate(v['date'] ?? '') ?? date;
      final c = (v['comment'] ?? comment).trim();
      final created = newCat == null
          ? null
          : await repo.addFinCategory(
              (v['category'] ?? newCat).trim().isEmpty ? newCat : (v['category'] ?? newCat).trim(),
              kind,
            );
      final catId = created ?? cat?.id;
      final id = await repo.addFinOp(
        kind: kind,
        categoryId: catId,
        amount: a,
        date: d,
        comment: c.isEmpty ? null : c,
      );
      return (
        {
          'kind': kind,
          'amount': _num(a),
          'date': _date(d),
          if (created != null) 'new_category': true,
        },
        UndoEntry(kind == kFinIncome ? 'Дохід ${_num(a)} грн' : 'Витрата ${_num(a)} грн', () async {
          await repo.cancelFinEntry(
            FinEntry(
              id: id,
              kind: kind,
              categoryId: catId,
              amount: a,
              date: d,
              title: '',
              lineCount: 0,
              cancelled: false,
              fromStock: false,
            ),
          );
          if (created != null) await repo.deleteFinCategory(created);
        }),
      );
    });
  }

  Future<Map<String, dynamic>> _createReminder(Map<String, dynamic> input) async {
    final text = _s(input, 'text');
    if (text.isEmpty) throw const _Bad('text: що нагадати');
    final day = _parseDate(_s(input, 'date')) ?? (throw const _Bad('date: YYYY-MM-DD'));
    final tm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_s(input, 'time'));
    final due = DateTime(
      day.year,
      day.month,
      day.day,
      tm == null ? 9 : int.parse(tm[1]!).clamp(0, 23),
      tm == null ? 0 : int.parse(tm[2]!).clamp(0, 59),
    );
    if (!due.isAfter(now())) throw const _Bad('Цей час уже минув');
    final hiveId = _s(input, 'hive_id');
    final h = hiveId.isEmpty ? null : await _hive(hiveId);
    String when(DateTime d) =>
        '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final card = PendingWrite('create_reminder', 'Нагадування', [
      WriteField('text', 'Текст', text),
      WriteField('when', 'Коли', when(due)),
      if (h != null) WriteField('hive', 'Вулик', '${h.name} (${h.apiaryName})', editable: false),
    ]);
    return _write(card, (v) async {
      final t = (v['text'] ?? text).trim();
      if (t.isEmpty) throw const _Bad('Порожній текст нагадування');
      final m = RegExp(
        r'^(\d{1,2}\.\d{1,2}\.\d{4})(?:\s+(\d{1,2}):(\d{2}))?$',
      ).firstMatch((v['when'] ?? '').trim());
      final d = m == null ? null : _parseDate(m[1]!);
      final at = d == null
          ? due
          : DateTime(
              d.year,
              d.month,
              d.day,
              m![2] == null ? due.hour : int.parse(m[2]!),
              m[3] == null ? due.minute : int.parse(m[3]!),
            );
      final id = await repo.addUserReminder(t, at, hive: h?.ref);
      return (
        {'when': when(at)},
        UndoEntry('Нагадування', () async => repo.deleteUserReminder(id)),
      );
    });
  }
}
