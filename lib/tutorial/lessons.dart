import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
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
  final param = c.data['param'] ?? tr.lessonParamFallback;
  switch (c.step) {
    case 1:
      return LessonCue(screen: 'map', highlight: const ['hive'], text: [
        _t(tr.lp1a),
        _h(tr.lp1b),
        _t('!'),
      ]);
    case 2:
      // панель можна гортати (на малому екрані «Параметри» нижче)
      return LessonCue(screen: 'map', highlight: const ['panel-params'], allow: const ['panel'], text: [
        _t(tr.lp2a),
        _h(tr.lp2b),
        _t('!'),
      ]);
    case 3:
      return LessonCue(screen: 'params', pic: LessonPic.blueprint, highlight: const ['param-create'], text: [
        _t(tr.lp3a),
        _h(tr.lp3b),
      ]);
    case 4:
      return LessonCue(
        screen: 'param-form',
        pic: LessonPic.blueprint,
        onContinue: () => c.go(5),
        text: [
          _t(tr.lp4),
        ],
      );
    case 5:
      return LessonCue(
        screen: 'param-form',
        pic: LessonPic.scheming,
        allowAll: true,
        deny: const ['form-cancel', 'form-save'],
        text: [
          _t(tr.lp5a),
          GuideBubble.task(tr.lp5b),
          _t(tr.lp5c),
        ],
      );
    case 6:
      return LessonCue(
        screen: 'param-form',
        pic: LessonPic.scheming,
        allowAll: true,
        deny: const ['form-cancel'],
        highlight: const ['form-save'],
        text: [_t(tr.lp6a), _h(tr.lp6b), _t('!')],
      );
    case 7:
      return LessonCue(screen: 'params', pic: LessonPic.scheming, highlight: const ['tab-constructor'], text: [
        _t(tr.lp7a),
        _h(tr.quoted(param)),
        _t(tr.lp7b),
      ]);
    case 8:
      return LessonCue(screen: 'params', pic: LessonPic.surprised, highlight: const ['new-group'], text: [
        _t(tr.lp8a),
        _h(tr.lp8b),
        _t('.'),
      ]);
    case 9:
      return LessonCue(
        screen: 'group-form',
        pic: LessonPic.thinking,
        allowAll: true,
        deny: const ['group-cancel'],
        highlight: const ['group-save'],
        text: [_t(tr.lp9a), _h(tr.quoted(kVisitsGroup)), _t(tr.lp9b)],
      );
    case 10:
      return LessonCue(screen: 'params', pic: LessonPic.thinking, allow: const ['constructor'], text: [
        _t(tr.lp10a),
        _h('«Періодичність обходу»'),
        _t(', '),
        _h('«Кількість днів до обходу»'),
        _t(tr.lp10b),
        _h('«Дату останнього обходу»'),
        _t(tr.lp10c),
      ]);
    case 11:
      return LessonCue(
        screen: 'params',
        pic: LessonPic.thinking,
        highlight: const ['apply-scope'],
        onContinue: () => c.go(12),
        text: [
          _t(tr.lp11),
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
        _t(tr.lp12a),
        _h(tr.lp12b),
      ]);
    case 13:
      return LessonCue(screen: 'params', pic: LessonPic.thinking, highlight: const ['params-back'], text: [
        _t(tr.lp13a),
        _h(tr.lp13b),
      ]);
    case 14:
      return LessonCue(
        screen: 'map',
        pic: LessonPic.surprised,
        allow: const ['panel'],
        onDone: c.complete,
        text: [_t(tr.lp14)],
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
// 2. Шаблони
// ---------------------------------------------------------------------------

LessonCue? templatesLessonScript(LessonController c) {
  final tpl = c.data['template'] ?? tr.lessonTemplateFallback;
  switch (c.step) {
    case 1:
      return LessonCue(screen: 'map', onContinue: () => c.go(2), text: [
        _t(tr.lt1),
      ]);
    case 2:
      // налаштування - у меню ☰; в уроці меню немає, тож відкриваємо самі
      return LessonCue(screen: 'map', onContinue: () => c.go(3), text: [
        _t(tr.lt2a),
        _h(tr.settingsQuoted),
        _t(tr.lt2b),
      ]);
    case 3:
      return LessonCue(screen: 'settings', onContinue: () => c.go(4), text: [
        _t(tr.lt3a),
        _h(tr.quoted(tr.settingsTabMain)),
        _t(tr.lt3b),
      ]);
    case 4:
      return LessonCue(screen: 'settings', pic: LessonPic.blueprint, highlight: const ['template-create'], text: [
        _t(tr.lt4a),
        _h(tr.templateCreateQuoted),
      ]);
    case 5:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-add'], text: [
        _t(tr.lt5),
        _h('«+»'),
      ]);
    case 6:
      return LessonCue(
          screen: 'editor-picker',
          pic: LessonPic.scheming,
          highlight: const ['picker-pages'],
          allow: const ['picker-tabs'],
          text: [
            _t(tr.lt6a),
            _h(tr.lt6b),
          ]);
    case 7:
      return LessonCue(
          screen: 'editor-picker',
          pic: LessonPic.scheming,
          highlight: const ['picker-obstacle'],
          allow: const ['picker-tabs'],
          text: [
        _t(tr.lt7a),
        _h(tr.lt7b),
      ]);
    case 8:
      return LessonCue(screen: 'editor', pic: LessonPic.scheming, allow: const ['grid'], text: [
        _t(tr.lt8a),
        GuideBubble.task(tr.lt8b),
        _t(tr.lt8c),
      ]);
    case 9:
      return LessonCue(screen: 'editor', pic: LessonPic.scheming, highlight: const ['square'], text: [
        _t(tr.lt9a),
        GuideBubble.task(tr.lt9b),
        _t(tr.lt9c),
      ]);
    case 10:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-add'], text: [
        _t(tr.lt10a),
        _h(tr.lt10b),
      ]);
    case 11:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-move'], text: [
        _t(tr.lt11a),
        _h(tr.lt11b),
      ]);
    case 12:
      return LessonCue(screen: 'editor', pic: LessonPic.thinking, allow: const ['grid'], text: [
        _t(tr.lt12a),
        GuideBubble.task(tr.lt12b),
      ]);
    case 13:
      return LessonCue(screen: 'editor', pic: LessonPic.blueprint, highlight: const ['editor-save'], text: [
        _t(tr.lt13a),
        _h(tr.lt13b),
        _t(tr.lt13c),
      ]);
    case 14:
      return LessonCue(
        screen: 'template-name',
        pic: LessonPic.blueprint,
        allowAll: true,
        deny: const ['name-cancel'],
        highlight: const ['name-save'],
        text: [_t(tr.lt14a), _h(tr.lt13b), _t(tr.lt14b)],
      );
    case 15:
      return LessonCue(screen: 'settings', onDone: c.complete, text: [
        _t(tr.lt15a),
        _h(tr.quoted(tpl)),
        _t(tr.lt15b),
      ]);
  }
  return null;
}

int _templatesCheckpoint(int s) => switch (s) {
      < 1 => 1,
      >= 5 && <= 14 => 5,
      > 15 => 15,
      _ => s,
    };

/// Перешкода «2×2», як у шаблоні з уроку (для відновлення після кроку 15).
Map<String, dynamic> lessonSquareCells() => {
      for (final k in ['0,0', '1,0', '0,1', '1,1'])
        k: const CellValue(type: 'obstacle', variant: 'mountain').toJson(),
    };

Future<Apiary> _templatesSetup(Repository repo, LessonController c) async {
  final aid = await repo.addApiary('Пасіка');
  final name = c.data['template'];
  if (c.step >= 15 && name != null) await repo.addTemplate(name, 2, 2, lessonSquareCells());
  return (await repo.getApiary(aid))!;
}

// ---------------------------------------------------------------------------

/// Уроки в плитках «Навчання» (після «Базових понять»).
List<LessonDef> get kLessons => [
  LessonDef(
    id: 'params',
    title: tr.lessonParamsTitle,
    image: 'assets/guide/beekeeper_thinking.webp',
    script: paramsLessonScript,
    setup: _paramsSetup,
    checkpoint: _paramsCheckpoint,
  ),
  LessonDef(
    id: 'templates',
    title: tr.templates,
    image: 'assets/guide/beekeeper_blueprint.webp',
    script: templatesLessonScript,
    setup: _templatesSetup,
    checkpoint: _templatesCheckpoint,
  ),
  LessonDef(id: 'qr', title: tr.qrCode, image: 'assets/guide/beekeeper_professor.webp', soon: true),
  LessonDef(id: 'stock', title: tr.stock, image: 'assets/guide/beekeeper_laptop.webp', soon: true),
  LessonDef(id: 'history', title: tr.history, image: 'assets/guide/beekeeper_newspaper.webp', soon: true),
];
