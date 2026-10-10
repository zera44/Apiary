import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../data/sync_service.dart';
import '../l10n/l10n.dart';
import 'theme.dart';

/// Текст стану синхронізації (null - показувати нічого).
String? syncStatusText(SyncInfo i, {DateTime? now}) {
  if (i.disabled) return i.needsSignIn ? tr.syncNeedsSignIn : tr.syncDisabled;
  if (i.running) return tr.syncRunning;
  if (i.error != null) return tr.syncError(i.error!);
  if (i.waitingWifi) return tr.syncWaitingWifi;
  if (i.offline) return tr.syncOffline;
  if (i.rejected > 0) return tr.syncRejected(i.rejected);
  if (i.pending > 0) return tr.syncPending(i.pending);
  if (i.lastOk != null) return tr.syncLastOk(formatWhen(i.lastOk!, now: now));
  return null;
}

/// «сьогодні 14:05» або «09.10 14:05».
String formatWhen(DateTime t, {DateTime? now}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final n = now ?? clock.now();
  final hm = '${two(t.hour)}:${two(t.minute)}';
  return (t.year == n.year && t.month == n.month && t.day == n.day)
      ? tr.todayAt(hm)
      : '${two(t.day)}.${two(t.month)} $hm';
}

/// Рядок стану синхронізації (головний екран, Налаштування → «Головне»).
class SyncStatusLine extends StatelessWidget {
  final TextAlign textAlign;
  final double fontSize;
  const SyncStatusLine({super.key, this.textAlign = TextAlign.center, this.fontSize = 12});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncInfo>(
        valueListenable: SyncService.info,
        builder: (_, i, _) {
          final text = syncStatusText(i);
          if (text == null) return const SizedBox.shrink();
          return Text(text,
              textAlign: textAlign,
              style: TextStyle(color: AppColors.textMuted, fontSize: fontSize));
        },
      );
}
