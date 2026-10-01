import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/whats_new.dart';
import '../ui/common.dart';
import '../ui/first_hints.dart';
import '../ui/theme.dart';

/// «Що нового»: перелік нових функцій, у «Ще» — виправлені помилки.
/// Закрити — одне натискання «До роботи» (кнопка завжди на екрані).
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
                      Text('Що нового · ${release.version}',
                          style: TextStyle(
                              color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      for (final f in release.features) line(f),
                      if (release.fixes.isNotEmpty)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            iconColor: AppColors.textMuted,
                            collapsedIconColor: AppColors.textMuted,
                            title: Text('Ще: виправлені помилки (${release.fixes.length})',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                            children: [for (final f in release.fixes) line(f, muted: true)],
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
