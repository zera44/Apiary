import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/whats_new.dart';
import '../ui/common.dart';
import '../ui/first_hints.dart';
import '../ui/theme.dart';
import 'feedback_screen.dart';

/// «Що нового» за Парето: одразу — 20% головних змін (дають основний
/// виграш), решта — у стрічці, яку гортають пальцем. Усе на одному екрані:
/// закрити — одне натискання «До роботи».
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
    final others = release.otherItems;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              // усе на одному екрані: головне, стрічка «ще», «До роботи» —
              // без прокрутки; решту гортають пальцем (не натисканнями)
              child: Column(children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Text('Що нового · ${release.version}',
                              style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ),
                        Text(release.headline,
                            style: TextStyle(
                                color: AppColors.addObject,
                                fontSize: 22,
                                fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 2),
                      Text('${release.headline} ${release.headlineNote}',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 14),
                      Text('ГОЛОВНЕ',
                          style: TextStyle(
                              color: AppColors.create,
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      for (final it in release.keyItems) _KaizenCard(item: it),
                      if (others.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _MoreStrip(items: others),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    PillButton(
                      text: 'До роботи',
                      bg: AppColors.accent,
                      width: 220,
                      height: 52,
                      radius: 18,
                      fontSize: 16,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
                      child: Text('Бачите зайвий крок? Запропонуйте покращення',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    ),
                  ]),
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

/// Решта змін — стрічка, яку гортають убік (без натискань). Сусідня
/// картка визирає з краю — видно, що є що гортати.
class _MoreStrip extends StatefulWidget {
  final List<KaizenItem> items;
  const _MoreStrip({required this.items});
  @override
  State<_MoreStrip> createState() => _MoreStripState();
}

class _MoreStripState extends State<_MoreStrip> {
  final _ctrl = PageController(viewportFraction: 0.86);
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('ЩЕ $n ПОКРАЩЕНЬ',
            style: TextStyle(
                color: AppColors.create,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${_page + 1} / $n  гортайте →',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 104,
        child: PageView.builder(
          controller: _ctrl,
          padEnds: false,
          itemCount: n,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _KaizenCard(item: widget.items[i], compact: true),
          ),
        ),
      ),
    ]);
  }
}

class _KaizenCard extends StatelessWidget {
  final KaizenItem item;
  final bool compact;
  const _KaizenCard({required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hive.withValues(alpha: compact ? 0.25 : 0.45)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: item.before,
                    style: TextStyle(
                        color: AppColors.textMuted, decoration: TextDecoration.lineThrough)),
                const TextSpan(text: '  →  '),
                TextSpan(
                    text: item.after,
                    style: TextStyle(color: AppColors.addObject, fontWeight: FontWeight.w800)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ]),
    );
  }
}
