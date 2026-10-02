import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'common.dart';
import 'guide_bubble.dart';
import 'theme.dart';

/// P19: обов'язкове навчання першого запуску — по ОДНІЙ підказці пасічника
/// на ключовий екран, у ту мить, коли людина вперше туди потрапила
/// (навчання «на робочому місці», без окремого курсу). Кожна показується
/// один раз (позначка `hint:<ключ>` в app_meta). Розширені уроки —
/// «Пройти навчання» на головному екрані, за бажанням.
class Hints {
  /// Глобальний вимикач (у тестах — false, щоб підказки не заважали).
  static bool enabled = true;

  /// Уже показані в цьому запуску (щоб не чекати базу двічі).
  static final _shownNow = <String>{};

  static const home = 'home';
  static const map = 'map';
  static const panel = 'panel';
  static const fill = 'fill';
  static const edit = 'edit';
  static const stock = 'stock';

  static final Map<String, List<InlineSpan>> _texts = {
    home: [
      const TextSpan(text: 'Вітаю на пасіці! '),
      GuideBubble.highlight('Почати'),
      const TextSpan(text: ' відкриває карту вашої пасіки. Коли настане час огляду, тут з\'явиться '),
      GuideBubble.highlight('Сьогодні оглянути'),
      const TextSpan(text: ' - одне натискання, і ви вже біля потрібного вулика.'),
    ],
    map: [
      const TextSpan(text: 'Це карта пасіки. Натисніть на вулик - праворуч відкриються його значення. '),
      GuideBubble.highlight('Редагувати'),
      const TextSpan(text: ' - щоб додати вулики чи переставити їх. Утримання вулика одразу відкриває огляд.'),
    ],
    panel: [
      const TextSpan(text: 'Тут останні значення вулика. Натисніть на рядок - побачите історію. '),
      GuideBubble.highlight('Оглянути'),
      const TextSpan(text: ' - записати огляд; '),
      GuideBubble.highlight('Змін немає'),
      const TextSpan(text: ' - якщо змін немає.'),
    ],
    fill: [
      const TextSpan(text: 'Заповніть лише те, що змінилось - решта лишиться як була. '),
      GuideBubble.highlight('Зберегти й далі'),
      const TextSpan(text: ' одразу відкриє наступний вулик.'),
    ],
    edit: [
      const TextSpan(text: 'Режим редагування: оберіть шаблон і натисніть на вільну клітинку. '
          'Вулик можна перетягнути, повернути кнопкою над ним. Видалили помилково - '),
      GuideBubble.highlight('Відмінити'),
      const TextSpan(text: ' внизу. '),
      GuideBubble.highlight('Готово'),
      const TextSpan(text: ' - вийти.'),
    ],
    stock: [
      const TextSpan(text: 'Склад: '),
      GuideBubble.highlight('Прихід'),
      const TextSpan(text: ' - що купили, '),
      GuideBubble.highlight('Переоблік'),
      const TextSpan(text: ' - звірити залишки. Задайте мінімальний залишок, і застосунок підкаже, коли час докупити.'),
    ],
  };

  /// Показати підказку [key], якщо її ще не бачили. Чекає, поки людина
  /// натисне «Зрозуміло».
  static Future<void> show(BuildContext context, Repository repo, String key) async {
    if (!enabled || _shownNow.contains(key)) return;
    final text = _texts[key];
    if (text == null) return;
    _shownNow.add(key);
    if (await repo.getMeta('hints_off') == '1') return;
    if (await repo.getMeta('hint:$key') != null) return;
    if (!context.mounted) return;
    await repo.setMeta('hint:$key', '1');
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, _, __) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // «Пропустити» — під хмаркою, «Зрозуміло» — праворуч унизу
                GuideBubble(
                  text: text,
                  below: TextButton(
                    onPressed: () async {
                      await repo.setMeta('hints_off', '1');
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Text('Пропустити',
                        style: TextStyle(
                            color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PillButton(
                      text: 'Зрозуміло',
                      bg: AppColors.accent,
                      width: 170,
                      height: 50,
                      radius: 18,
                      fontSize: 16,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Для «Що нового» й тестів: забути показане в цьому запуску.
  static void resetSession() => _shownNow.clear();
}
