import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';

/// Хто допомагає в чаті: три персонажі на трьох моделях. Людина обирає
/// плашкою під полем чату (як вибір моделі в Claude).
enum AssistantPersona {
  /// Haiku 5.5 - швидкий і дешевий.
  bear('haiku', 'Haiku 5.5', 'assets/guide/bear_on_toggle.webp'),

  /// Sonnet 5.5 - кмітливіший, дорожчий. Прості прохання (відкрий, запиши,
  /// скільки) сервер помітно передає Ведмедику: швидше й дешевше.
  beekeeper('sonnet', 'Sonnet 5.5', 'assets/guide/beekeeper.webp'),

  /// Opus 5.5 - найрозумніший і найдорожчий (книги, складні поради).
  robo('opus', 'Opus 5.5', 'assets/guide/robot.webp');

  /// Як модель називає сервер (поле model у запиті й відповіді). Людині
  /// показуємо лише персонажа - без назв моделей.
  final String model;
  final String modelLabel;
  final String image;
  const AssistantPersona(this.model, this.modelLabel, this.image);

  /// Робопасічника обрати не можна: до нього переходить сама система, коли
  /// Пасічник не впорався, і повертається, щойно задача стає простою.
  bool get locked => this == robo;

  /// Назва в знахідному відмінку («переходжу на …»).
  String get nameAcc => switch (this) {
        bear => tr.assistantBearAcc,
        beekeeper => tr.assistantBeekeeperAcc,
        robo => tr.assistantRoboAcc,
      };

  String get name => switch (this) {
        bear => tr.assistantBear,
        beekeeper => tr.assistantBeekeeper,
        robo => tr.assistantRobo,
      };
  String get hint => switch (this) {
        bear => tr.assistantBearHint,
        beekeeper => tr.assistantBeekeeperHint,
        robo => tr.assistantRoboHint,
      };

  /// За назвою моделі з сервера; невідома (старі відповіді) - [bear].
  static AssistantPersona of(String? model) => switch (model) {
        'sonnet' => beekeeper,
        'opus' => robo,
        _ => bear,
      };

  /// Голос персонажа (синтезатор телефона): Ведмедик - вищий і жвавіший,
  /// Пасічник - нижчий і розміреніший, Робопасічник - рівний і повільний.
  /// 1.0 / 0.5 - звичайні.
  double get pitch => switch (this) {
        bear => 1.35,
        beekeeper => 0.8,
        robo => 0.6,
      };
  double get rate => switch (this) {
        bear => 0.55,
        beekeeper => 0.45,
        robo => 0.4,
      };
}

/// Глибина міркувань (output_config.effort) однакова для всіх помічників - середня.
const kAssistantEffort = 'medium';

/// Вибір людини: на телефоні, іде з кожним запитом (сервер може його
/// вимкнути - секрет ASSISTANT_CLIENT_CHOICE = off).
class AssistantPrefs {
  static const modelKey = 'assistant_model';

  static const defaultPersona = AssistantPersona.bear;

  /// Поточний вибір (чат, кнопка на карті).
  static final persona = ValueNotifier<AssistantPersona>(defaultPersona);

  /// Хто відповідає ЗАРАЗ: обраний людиною або той, на кого систему перемкнуло
  /// (Робопасічник, коли складно; Ведмедик, коли просто). Його показують
  /// аватар і заголовок, його ж сервер дізнається з кожним запитом.
  static final active = ValueNotifier<AssistantPersona>(defaultPersona);
  static const activeKey = 'assistant_active';

  static Future<void> load(Repository repo) async {
    final chosen = AssistantPersona.of(await repo.getMeta(modelKey));
    // Робопасічника обирати не можна (у старих збереженнях міг бути обраний)
    persona.value = chosen.locked ? AssistantPersona.beekeeper : chosen;
    final a = AssistantPersona.of(await repo.getMeta(activeKey));
    active.value = a;
  }

  static Future<void> setPersona(Repository repo, AssistantPersona p) async {
    if (p.locked) return;
    persona.value = p;
    await repo.setMeta(modelKey, p.model);
    await setActive(repo, p); // людина обрала сама - далі відповідає цей
  }

  /// Систему перемкнуло на іншого помічника (або знову на обраного).
  static Future<void> setActive(Repository repo, AssistantPersona p) async {
    active.value = p;
    await repo.setMeta(activeKey, p.model);
  }

  /// Що додати до запиту (з бази - працює й у фоновому завданні).
  static Future<Map<String, String>> requestOptions(Repository repo) async {
    await load(repo);
    return {'model': persona.value.model, 'active': active.value.model, 'effort': kAssistantEffort};
  }
}
