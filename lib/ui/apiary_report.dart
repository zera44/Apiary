import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/excel_export.dart';
import 'common.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// «Звіт по пасіці» (P14): один Excel-файл з останніми значеннями всіх
/// вуликів і всією історією. Одне натискання — і вибір: зберегти у теку
/// чи одразу поділитися (месенджер, пошта, диск).
Future<void> showApiaryReport(BuildContext context, Repository repo, Apiary apiary) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.card,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(tr.apiaryReportOf(apiary.name),
              style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(tr.apiaryReportHint,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        ListTile(
          leading: Icon(Icons.share, color: AppColors.accent),
          title: Text(tr.backupShare, style: TextStyle(color: AppColors.text)),
          onTap: () => Navigator.of(ctx).pop('share'),
        ),
        ListTile(
          leading: Icon(Icons.save_alt, color: AppColors.accent),
          title: Text(tr.backupSaveToFile, style: TextStyle(color: AppColors.text)),
          onTap: () => Navigator.of(ctx).pop('save'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final report = await repo.apiaryReport(apiary.id);
  if (!context.mounted) return;
  if (report.hives.isEmpty) {
    await showInfo(context, tr.apiaryReportEmpty);
    return;
  }
  if (choice == 'share') {
    final err = await shareApiaryReport(report, apiary.name);
    if (err != null && context.mounted) await showInfo(context, err);
  } else {
    final msg = await saveApiaryReport(report, apiary.name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
