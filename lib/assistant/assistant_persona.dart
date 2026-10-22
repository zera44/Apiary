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

/// Глибина міркувань (output_config.effort): низька, середня, висока.
/// Вищі рівні для «відкрий / знайди / запиши» лише довше думають.
const kAssistantEfforts = ['low', 'medium', 'high'];

String effortLabel(String e) => switch (e) {
      'low' => tr.assistantEffortLow,
      'high' => tr.assistantEffortHigh,
      _ => tr.assistantEffortMedium,
    };

/// Вибір людини: на телефоні, іде з кожним запитом (сервер може його
/// вимкнути - секрет ASSISTANT_CLIENT_CHOICE = off).
class AssistantPrefs {
  static const modelKey = 'assistant_model';
  static const effortKey = 'assistant_effort';

  static const defaultPersona = AssistantPersona.bear;
  static const defaultEffort = 'medium';

  /// Поточний вибір (чат, кнопка на карті).
  static final persona = ValueNotifier<AssistantPersona>(defaultPersona);
  static final effort = ValueNotifier<String>(defaultEffort);

  static Future<void> load(Repository repo) async {
    persona.value = AssistantPersona.of(await repo.getMeta(modelKey));
    final e = await repo.getMeta(effortKey);
    effort.value = kAssistantEfforts.contains(e) ? e! : defaultEffort;
  }

  static Future<void> setPersona(Repository repo, AssistantPersona p) async {
    persona.value = p;
    await repo.setMeta(modelKey, p.model);
  }

  static Future<void> setEffort(Repository repo, String e) async {
    if (!kAssistantEfforts.contains(e)) return;
    effort.value = e;
    await repo.setMeta(effortKey, e);
  }

  /// Що додати до запиту (з бази - працює й у фоновому завданні).
  static Future<Map<String, String>> requestOptions(Repository repo) async {
    await load(repo);
    return {'model': persona.value.model, 'effort': effort.value};
  }
}
