import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/cell_value.dart';
import '../ui/guide_bubble.dart';
import 'lesson.dart';

/// Урок у плитках «Навчання».
class LessonDef {
  final String id;
  final String title;
  final String image;

  /// Ще не готовий (сценарій пишеться) - плитка з позначкою «скоро».
  final bool soon;

  final LessonScript? script;

  /// Пісочниця для уроку з уже зробленими кроками до [LessonController.step]
  /// (щоб «Продовжити» починало з того самого місця). Повертає карту уроку.
  final Future<Apiary> Function(Repository sandbox, LessonController c)? setup;

  /// З якого кроку відновлювати перерваний урок (крок, з якого видно, що
  /// робити, - а не посеред відкритого вікна).
  final int Function(int step) checkpoint;

  const LessonDef({
    required this.id,
    required this.title,
    required this.image,
    this.soon = false,
    this.script,
    this.setup,
    this.checkpoint = _same,
  });

  static int _same(int s) => s;
}

TextSpan _t(String s) => TextSpan(text: s);
TextSpan _h(String s) => GuideBubble.highlight(s);

/// Ключі медової підказки «Обходи» - три базові характеристики обходу.
const kVisitKeys = ['visit_period', 'visit_left', 'visit_start'];
const kVisitsGroup = 'Обходи';

// ---------------------------------------------------------------------------
// 1. Групи і параметри обходу
// ---------------------------------------------------------------------------

/// Кроки уроку «Групи і параметри обходу» (номери - як сцени в ТЗ).
LessonCue? paramsLessonScript(LessonController c) {
  final param = c.data['param'] ?? 'параметр';
  switch (c.step) {
    case 1:
      return LessonCue(screen: 'map', highlight: const ['hive'], text: [
        _t('Друже, вітаю тебе. Хочеш більше дізнатись про обходи вуликів? Ти вчасно, '),
        _h('натисни на вулик'),
        _t('!'),
      ]);
    case 2:
      // панель можна гортати (на малому екрані «Параметри» нижче)
      return LessonCue(screen: 'map', highlight: const ['panel-params'], allow: const ['panel'], text: [
        _t('Як бачиш - геть не густо. Додаймо нові '),
        _h('параметри'),
        _t('!'),
      ]);
    case 3:
      return LessonCue(screen: 'params', pic: LessonPic.blueprint, highlight: const ['param-create'], text: [
        _t('В цьому меню ти можеш створювати параметри й додавати їх до таблиці. Натисни на '),
        _h('«Створити параметр»'),
      ]);
    case 4:
      return LessonCue(
        screen: 'param-form',
        pic: LessonPic.blueprint,
        onContinue: () => c.go(5),
        text: [
          _t('Тут ти можеш назвати свій параметр, вказати його тип даних та за потреби '
              'одиниці виміру'),
        ],
      );
    case 5:
      return LessonCue(
        screen: 'param-form',
        pic: LessonPic.scheming,
        allowAll: true,
        deny: const ['form-cancel', 'form-save'],
        text: [
          _t('Створи свій параметр. Май на увазі, '),
          GuideBubble.task('назва та тип даних'),
          _t(' - обов\'язково вказуємо.'),
        ],
      );
    case 6:
      return LessonCue(
        screen: 'param-form',
        pic: LessonPic.scheming,
        allowAll: true,
        deny: const ['form-cancel'],
        highlight: const ['form-save'],
        text: [_t('Не забудь '), _h('зберегти'), _t('!')],
      );
    case 7:
      return LessonCue(screen: 'params', pic: LessonPic.scheming, highlight: const ['tab-constructor'], text: [
        _t('Молодець. '),
        _h('«$param»'),
        _t(' вже додано до конструктора таблиці. Відкрий його'),
      ]);
    case 8:
      return LessonCue(screen: 'params', pic: LessonPic.surprised, highlight: const ['new-group'], text: [
        _t('Боже, який безлад! Швиденько створи '),
        _h('нову групу'),
        _t('.'),
      ]);
    case 9:
      return LessonCue(
        screen: 'group-form',
        pic: LessonPic.thinking,
        allowAll: true,
        deny: const ['group-cancel'],
        highlight: const ['group-save'],
        text: [_t('Назви її '), _h('«$kVisitsGroup»'), _t(' та збережи свій прогрес!')],
      );
    case 10:
      return LessonCue(screen: 'params', pic: LessonPic.thinking, allow: const ['constructor'], text: [
        _t('Перетягни '),
        _h('«Періодичність обходу»'),
        _t(', '),
        _h('«Кількість днів до обходу»'),
        _t(' та '),
        _h('«Дату останнього обходу»'),
        _t(' до нової групи'),
      ]);
    case 11:
      return LessonCue(
        screen: 'params',
        pic: LessonPic.thinking,
        highlight: const ['apply-scope'],
        onContinue: () => c.go(12),
        text: [
          _t('За потреби можна застосувати зміни як лише до 1 вулика, так і до всіх '
              'загалом'),
        ],
      );
    case 12:
      // список можна гортати (на малому екрані параметр уроку нижче)
      return LessonCue(
          screen: 'params',
          pic: LessonPic.thinking,
          highlight: const ['lesson-param-check'],
          allow: const ['list'],
          text: [
        _t('Бачив, ми не все використали? '),
        _h('Вимкни все зайве'),
      ]);
    case 13:
      return LessonCue(screen: 'params', pic: LessonPic.thinking, highlight: const ['params-back'], text: [
        _t('Повернімось до '),
        _h('вулика'),
      ]);
    case 14:
      return LessonCue(
        screen: 'map',
        pic: LessonPic.surprised,
        allow: const ['panel'],
        onDone: c.complete,
        text: [_t('Ого! Глянь на таблицю — вона ідеальна!')],
      );
  }
  return null;
}

int _paramsCheckpoint(int s) => switch (s) {
      <= 2 => 1,
      >= 3 && <= 6 => 3,
      9 => 8,
      > 14 => 14,
      _ => s,
    };

/// Карта уроку 1: 3 вулики й 2 лежаки; зроблене до кроку - уже зроблено.
Future<Apiary> _paramsSetup(Repository repo, LessonController c) async {
  final aid = await repo.addApiary('Пасіка');
  final ts = await repo.listTemplates();
  final hiveT = ts.where((t) => t.name == 'Вулик').firstOrNull ?? ts.firstOrNull;
  final lezhak = ts.where((t) => t.name == 'Лежак').firstOrNull;
  if (hiveT != null) {
    for (final x in [0, 2, 4]) {
      await repo.placeTemplate(aid, hiveT.cells, x, 0, name: hiveT.name);
    }
  }
  if (lezhak != null) {
    for (final x in [0, 3]) {
      await repo.placeTemplate(aid, lezhak.cells, x, -2, name: lezhak.name);
    }
  }
  final els = await repo.listElements(aid);
  final hive = els.where((e) => e.isHive && e.label == '${hiveT?.name} 1').firstOrNull ??
      els.firstWhere((e) => e.isHive);
  c.data['hive'] = hive.id;
  final step = c.step;
  final name = c.data['param'];
  if (step >= 7 && name != null) {
    final pid = await repo.addParameter(name,
        unit: c.data['param_unit'], dataType: c.data['param_type'] ?? DataTypes.text);
    c.data['param_id'] = pid;
    if (step < 13) {
      final ids = await repo.attachedParameterIds(hive.entity, elType: 'hive');
      await repo.setAttachedParameters([...ids, pid], hive.entity);
    }
  }
  if (step >= 10) {
    final ids = <String>[];
    if (step >= 11) {
      for (final k in kVisitKeys) {
        final id = await repo.baseParameterId('hive', k);
        if (id != null) ids.add(id);
      }
    }
    await repo.setParamGroups([ParamGroup(id: 'lesson-visits', name: kVisitsGroup, ids: ids)]);
  }
  return (await repo.getApiary(aid))!;
}

// ---------------------------------------------------------------------------
// 2. Налаштування (шаблони і параметри)
// ---------------------------------------------------------------------------

LessonCue? templatesLessonScript(LessonController c) {
  final tpl = c.data['template'] ?? 'шаблон';
  switch (c.step) {
    case 1:
      return LessonCue(screen: 'map', onContinue: () => c.go(2), text: [
        _t('Друже, це знову ти. Мені подобається твоя жага до знань. Сьогодні поговоримо '
            'про створення нових вуликів та перешкод.'),
      ]);
    case 2:
      return LessonCue(screen: 'map', highlight: const ['gear'], text: [
        _t('Натисни на '),
        _h('налаштування'),
      ]);
    case 3:
      return LessonCue(screen: 'settings', onContinue: () => c.go(4), text: [
        _t('Це '),
        _h('«Головна»'),
        _t(', тут загальні налаштування додатку'),
      ]);
    case 4:
      return LessonCue(screen: 'settings', pic: LessonPic.blueprint, highlight: const ['template-create'], text: [
        _t('Те що треба! Давай '),
        _h('створимо новий шаблон'),
      ]);
    case 5:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-add'], text: [
        _t('Пора створювати щось нове! Натисни на '),
        _h('«+»'),
      ]);
    case 6:
      return LessonCue(screen: 'editor-picker', pic: LessonPic.scheming, highlight: const ['picker-obstacle'], text: [
        _t('Як бачиш, тут можна створити як вулик, так і перешкоду. Створимо '),
        _h('перешкоду'),
        _t(' спочатку'),
      ]);
    case 7:
      return LessonCue(screen: 'editor', pic: LessonPic.scheming, allow: const ['grid'], text: [
        _t('Тепер '),
        GuideBubble.task('постав на карту одну плитку'),
        _t(' перешкоди'),
      ]);
    case 8:
      return LessonCue(screen: 'editor', pic: LessonPic.scheming, highlight: const ['square'], text: [
        _t('А тепер постав впритул ще '),
        GuideBubble.task('3 перешкоди'),
        _t(' - заповни квадрат'),
      ]);
    case 9:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-add'], text: [
        _t('Добре. Заверши створення. Як? '),
        _h('Червоною кнопкою'),
        _t(', звісно! А і зберегти не забудь'),
      ]);
    case 10:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-save'], text: [
        _t('А тепер - '),
        _h('зберегти'),
      ]);
    case 11:
      return LessonCue(
        screen: 'template-name',
        pic: LessonPic.blueprint,
        allowAll: true,
        deny: const ['name-cancel'],
        highlight: const ['name-save'],
        text: [_t('Назви свій шаблон і '), _h('збережи'), _t(' його')],
      );
    case 12:
      return LessonCue(screen: 'settings', onDone: c.complete, text: [
        _t('Вау, швидко вчишся. Молодець. Тепер ти можеш розмістити '),
        _h('«$tpl»'),
        _t(' на карті, але це вже сам'),
      ]);
  }
  return null;
}

int _templatesCheckpoint(int s) => switch (s) {
      < 1 => 1,
      >= 5 && <= 11 => 5,
      > 12 => 12,
      _ => s,
    };

/// Перешкода «2×2», як у шаблоні з уроку (для відновлення після кроку 12).
Map<String, dynamic> lessonSquareCells() => {
      for (final k in ['0,0', '1,0', '0,1', '1,1'])
        k: const CellValue(type: 'obstacle', variant: 'mountain').toJson(),
    };

Future<Apiary> _templatesSetup(Repository repo, LessonController c) async {
  final aid = await repo.addApiary('Пасіка');
  final name = c.data['template'];
  if (c.step >= 12 && name != null) await repo.addTemplate(name, 2, 2, lessonSquareCells());
  return (await repo.getApiary(aid))!;
}

// ---------------------------------------------------------------------------

/// Уроки в плитках «Навчання» (після «Базових понять»).
final kLessons = <LessonDef>[
  LessonDef(
    id: 'params',
    title: 'Групи і параметри обходу',
    image: 'assets/guide/beekeeper_thinking.webp',
    script: paramsLessonScript,
    setup: _paramsSetup,
    checkpoint: _paramsCheckpoint,
  ),
  LessonDef(
    id: 'templates',
    title: 'Налаштування (шаблони і параметри)',
    image: 'assets/guide/beekeeper_blueprint.webp',
    script: templatesLessonScript,
    setup: _templatesSetup,
    checkpoint: _templatesCheckpoint,
  ),
  const LessonDef(id: 'qr', title: 'QR-код', image: 'assets/guide/beekeeper_professor.webp', soon: true),
  const LessonDef(id: 'stock', title: 'Склад', image: 'assets/guide/beekeeper_laptop.webp', soon: true),
  const LessonDef(
      id: 'history', title: 'Історія', image: 'assets/guide/beekeeper_newspaper.webp', soon: true),
];
