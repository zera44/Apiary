import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/whats_new.dart';
import '../ui/common.dart';
import '../ui/first_hints.dart';
import '../ui/theme.dart';
import 'feedback_screen.dart';

/// «Що нового» як дошка кайдзен: головна цифра оновлення, далі картки
/// «яку втрату прибрали — як було → як стало». Внизу — запрошення
/// подати свою ідею (у Toyota покращення пропонують ті, хто робить роботу).
class WhatsNewScreen extends StatelessWidget {
  final Release release;
  const WhatsNewScreen({super.key, required this.release});

  /// Вимикач для тестів.
  static bool enabled = true;

  /// Показати один раз після оновлення. Нове встановлення — нічого не
  /// показує (новачку допоможуть підказки), лише запам'ятовує версію.
  static Future<void> maybeShow(BuildContext context, Repository repo) async {
    if (!enabled || kReleases.isEmpty) return;
    final current = kReleases.first;
    final seen = await repo.getMeta('whats_new_seen');
    if (seen == current.version) return;
    await repo.setMeta('whats_new_seen', current.version);
    if (seen == null && (await repo.listApiaries()).isEmpty) return; // нове встановлення
    // досвідчений пасічник знає головний екран — без підказки про нього
    await repo.setMeta('hint:${Hints.home}', '1');
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WhatsNewScreen(release: current)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  Text('Що нового · ${release.version}',
                      style: TextStyle(
                          color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Кайдзен — маленькі кроки щодня. Ось які зайві дії ми прибрали.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  const SizedBox(height: 18),
                  _headline(),
                  for (final g in release.groups) ...[
                    const SizedBox(height: 22),
                    Text(g.title.toUpperCase(),
                        style: TextStyle(
                            color: AppColors.create,
                            fontSize: 13,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final it in g.items) _KaizenCard(item: it),
                  ],
                  const SizedBox(height: 22),
                  _suggest(context),
                  const SizedBox(height: 20),
                  Center(
                    child: PillButton(
                      text: 'До роботи',
                      bg: AppColors.accent,
                      width: 220,
                      height: 52,
                      radius: 18,
                      fontSize: 16,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: ScreenFrame())),
        ]),
      ),
    );
  }

  Widget _headline() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.addObject.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.addObject.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          Text(release.headline,
              style: TextStyle(color: AppColors.text, fontSize: 40, fontWeight: FontWeight.w900)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(release.headlineNote,
                style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.3)),
          ),
        ]),
      );

  Widget _suggest(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.popupBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Наступний кайдзен — ваш',
              style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Помітили зайвий крок, пошук чи повтор? Напишіть — приберемо в наступному оновленні.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.3)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
            child: Text('Запропонувати покращення →',
                style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

class _KaizenCard extends StatelessWidget {
  final KaizenItem item;
  const _KaizenCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hive.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.title,
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(item.before,
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                    decoration: TextDecoration.lineThrough)),
            Text('→', style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            Text(item.after,
                style: TextStyle(
                    color: AppColors.addObject, fontSize: 14, fontWeight: FontWeight.w800)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('прибрано: ${item.muda.toLowerCase()}',
                  style: TextStyle(color: AppColors.text, fontSize: 12)),
            ),
          ],
        ),
      ]),
    );
  }
}
