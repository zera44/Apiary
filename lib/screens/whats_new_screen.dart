import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/whats_new.dart';
import '../ui/common.dart';
import '../ui/first_hints.dart';
import '../ui/theme.dart';

/// «Що нового»: останнє оновлення; 20% найзначніших нових функцій, решта й виправлені помилки — у «Ще».
/// Закрити — одне натискання «До роботи» (кнопка завжди на екрані).
class WhatsNewScreen extends StatelessWidget {
  final Release release;
  const WhatsNewScreen({super.key, required this.release});

  /// Вимикач для тестів.
  static bool enabled = true;

  /// Показати один раз після оновлення — лише останнє оновлення (пропущені
  /// раніше не накопичуються). Нове встановлення — нічого
  /// не показує (новачку допоможуть підказки), лише запам'ятовує.
  static Future<void> maybeShow(BuildContext context, Repository repo) async {
    if (!enabled) return;
    final news = await loadNews();
    if (news.isEmpty) return;
    final last = news.map((e) => e.n).reduce((a, b) => a > b ? a : b);
    var seen = int.tryParse(await repo.getMeta('whats_new_seen_n') ?? '');
    if (seen == null) {
      // 0.3.0 запам'ятовувала версію, а не номер запису
      final oldVersion = await repo.getMeta('whats_new_seen');
      if (oldVersion != null) {
        seen = 0;
        for (final e in news) {
          if (compareVersions(e.version, oldVersion) <= 0 && e.n > seen!) seen = e.n;
        }
      }
    }
    await repo.setMeta('whats_new_seen_n', '$last');
    if (seen == null && (await repo.listApiaries()).isEmpty) return; // нове встановлення
    if (last <= (seen ?? 0)) return;
    final release = Release.fromEntries(news.where((e) => e.n == last));
    // досвідчений пасічник знає головний екран — без підказки про нього
    await repo.setMeta('hint:${Hints.home}', '1');
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WhatsNewScreen(release: release)));
  }

  /// З меню чи головного екрана: лише останнє оновлення.
  static Future<void> open(NavigatorState nav) async {
    final news = await loadNews();
    final last = news.isEmpty ? 0 : news.map((e) => e.n).reduce((a, b) => a > b ? a : b);
    final release = Release.fromEntries(news.where((e) => e.n == last));
    if (!nav.mounted) return;
    await nav.push(MaterialPageRoute(builder: (_) => WhatsNewScreen(release: release)));
  }

  @override
  Widget build(BuildContext context) {
    Widget line(String t, {bool muted = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 10),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: muted ? AppColors.textMuted : AppColors.create,
                    shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Text(t,
                  style: TextStyle(
                      color: muted ? AppColors.textMuted : AppColors.text,
                      fontSize: 15,
                      height: 1.3)),
            ),
          ]),
        );

    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                    children: [
                      Text(release.version.isEmpty ? 'Що нового' : 'Що нового · ${release.version}',
                          style: TextStyle(
                              color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      for (final f in release.topFeatures) line(f),
                      if (release.moreFeatures.isNotEmpty || release.fixes.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            iconColor: AppColors.textMuted,
                            collapsedIconColor: AppColors.textMuted,
                            title: Text(
                                'Ще: ${release.moreFeatures.length} змін і виправлення помилок',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                            expandedCrossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final f in release.moreFeatures) line(f, muted: true),
                              if (release.fixes.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                                  child: Text('Виправлено',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                ),
                                for (final f in release.fixes) line(f, muted: true),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
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
              ]),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: ScreenFrame())),
        ]),
      ),
    );
  }
}
