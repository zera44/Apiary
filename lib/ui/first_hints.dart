import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'common.dart';
import 'guide_bubble.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// P19: обов'язкове навчання першого запуску — по ОДНІЙ підказці пасічника
/// на ключовий екран, у ту мить, коли людина вперше туди потрапила
/// (навчання «на робочому місці», без окремого курсу). Кожна показується
/// один раз (позначка `hint:<ключ>` в app_meta). Розширені уроки —
/// «Пройти навчання» на головному екрані, за бажанням.
class Hints {
  /// Глобальний вимикач (у тестах — false, щоб підказки не заважали).
  /// Вимкнено: застосунок без спливних підказок (навчання — окремо).
  static bool enabled = false;

  /// Уже показані в цьому запуску (щоб не чекати базу двічі).
  static final _shownNow = <String>{};

  static const home = 'home';
  static const map = 'map';
  static const panel = 'panel';
  static const fill = 'fill';
  static const edit = 'edit';
  static const stock = 'stock';

  static Map<String, List<InlineSpan>> get _texts => {
    home: [
      TextSpan(text: tr.hintHomeA),
      GuideBubble.highlight(tr.start),
      TextSpan(text: tr.hintHomeB),
      GuideBubble.highlight(tr.dueToday),
      TextSpan(text: tr.hintHomeC),
    ],
    map: [
      TextSpan(text: tr.hintMapA),
      GuideBubble.highlight(tr.editing),
      TextSpan(text: tr.hintMapB),
    ],
    panel: [
      TextSpan(text: tr.hintPanelA),
      GuideBubble.highlight(tr.inspect),
      TextSpan(text: tr.hintPanelB),
      GuideBubble.highlight(tr.noChanges),
      TextSpan(text: tr.hintPanelC),
    ],
    fill: [
      TextSpan(text: tr.hintFillA),
      GuideBubble.highlight(tr.saveAndNext),
      TextSpan(text: tr.hintFillB),
    ],
    edit: [
      TextSpan(text: tr.hintEditA),
      GuideBubble.highlight(tr.undoDelete),
      TextSpan(text: tr.hintEditB),
      GuideBubble.highlight(tr.workMode),
      TextSpan(text: tr.hintEditC),
    ],
    stock: [
      TextSpan(text: tr.hintStockA),
      GuideBubble.highlight(tr.stockIn),
      TextSpan(text: tr.hintStockB),
      GuideBubble.highlight(tr.stocktake),
      TextSpan(text: tr.hintStockC),
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
                    child: Text(tr.skip,
                        style: TextStyle(
                            color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PillButton(
                      text: tr.gotIt,
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
