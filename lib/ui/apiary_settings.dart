import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'apiary_report.dart';
import 'common.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Налаштування пасіки: назва й періодичність обходу всієї пасіки (вулик із
/// власною періодичністю її перекриває). Відкривається з карти - торкнутися
/// назви чи олівця біля неї. Повертає true, якщо щось змінили.
Future<bool> editApiarySettings(BuildContext context, Repository repo, Apiary a) async {
    final nameCtrl = TextEditingController(text: a.name);
    final periodCtrl = TextEditingController(text: a.visitPeriod?.toString() ?? '');
    final res = await showDialog<(String, int?)>(
      context: context,
      builder: (ctx) {
        void save() {
          final n = nameCtrl.text.trim();
          final p = int.tryParse(periodCtrl.text.trim());
          Navigator.pop(ctx, (n.isEmpty ? a.name : n, (p != null && p > 0) ? p : null));
        }

        return AlertDialog(
          title: Text(tr.apiarySettings),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(labelText: tr.name),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: periodCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.text),
              decoration: InputDecoration(labelText: tr.roundEvery, hintText: tr.roundEveryHint),
              onSubmitted: (_) => save(),
            ),
            const SizedBox(height: 8),
            Text(tr.roundEveryNote,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: Icon(Icons.table_chart_outlined, color: AppColors.accent),
              label: Text(tr.apiaryReportExcel, style: TextStyle(color: AppColors.accent)),
              onPressed: () {
                Navigator.pop(ctx);
                showApiaryReport(context, repo, a);
              },
            ),
          ]),
          actions: [
            Row(children: [
              Expanded(
                child: PillButton(
                    text: tr.cancel,
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    onPressed: () => Navigator.pop(ctx)),
              ),
              const SizedBox(width: 8),
              Expanded(child: PillButton(text: tr.save, bg: AppColors.accent, onPressed: save)),
            ]),
          ],
        );
      },
    );
    if (res == null) return false;
    final name = res.$1 == a.name ? null : res.$1;
    final period = res.$2 == a.visitPeriod ? null : (res.$2,);
    if (name == null && period == null) return false;
    await repo.updateApiary(a.id, name: name, visitPeriod: period);
    return true;
}
