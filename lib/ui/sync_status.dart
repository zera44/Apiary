import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../data/sync_service.dart';
import '../l10n/l10n.dart';
import 'theme.dart';

/// Текст стану синхронізації (null - показувати нічого).
/// [googleSignedIn] - у Google вже увійшли (тоді бракує лише сервера).
String? syncStatusText(SyncInfo i, {DateTime? now, bool googleSignedIn = false}) {
  if (i.disabled) {
    if (!i.needsSignIn) return tr.syncDisabled;
    return googleSignedIn ? tr.serverNotConnected : tr.syncNeedsSignIn;
  }
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
  final bool googleSignedIn;
  const SyncStatusLine(
      {super.key, this.textAlign = TextAlign.center, this.fontSize = 12, this.googleSignedIn = false});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncInfo>(
        valueListenable: SyncService.info,
        builder: (_, i, _) {
          final text = syncStatusText(i, googleSignedIn: googleSignedIn);
          if (text == null) return const SizedBox.shrink();
          return Text(text,
              textAlign: textAlign,
              style: TextStyle(color: AppColors.textMuted, fontSize: fontSize));
        },
      );
}
