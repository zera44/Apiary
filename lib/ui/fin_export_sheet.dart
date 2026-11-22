import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/finance.dart';
import '../l10n/l10n.dart';
import '../services/fin_export.dart';
import 'common.dart';
import 'fin_style.dart';
import 'theme.dart';

/// Вибір для експорту.
typedef FinExportChoice = ({FinExportKind kind, bool summary, bool comment, bool account});

/// Нижня панель «Експорт в Excel»: Витрати, Доходи чи Усі операції, назва
/// файлу й кількість рядків, три прапорці й кнопка. null - закрили.
Future<FinExportChoice?> showFinExportSheet(
  BuildContext context, {
  required List<FinEntry> entries,
  required String periodTitle,
  required DateTime from,
  required DateTime lastDay,
  FinExportKind initial = FinExportKind.all,
}) =>
    showModalBottomSheet<FinExportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExportSheet(
          entries: entries,
          periodTitle: periodTitle,
          from: from,
          lastDay: lastDay,
          initial: initial),
    );

class _ExportSheet extends StatefulWidget {
  final List<FinEntry> entries;
  final String periodTitle;
  final DateTime from, lastDay;
  final FinExportKind initial;
  const _ExportSheet(
      {required this.entries,
      required this.periodTitle,
      required this.from,
      required this.lastDay,
      required this.initial});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late FinExportKind _kind = widget.initial;
  bool _summary = true;
  bool _comment = true;
  bool _account = true;

  static const _kinds = [FinExportKind.expenses, FinExportKind.income, FinExportKind.all];

  @override
  Widget build(BuildContext context) {
    final rows = finExportEntries(widget.entries, _kind).length;
    final name = finExportFileName(widget.from, widget.lastDay, _kind);
    Widget check(String text, bool v, ValueChanged<bool> on) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => on(!v),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              CheckToggle(checked: v, onChanged: on),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: AppColors.text, fontSize: 15))),
            ]),
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: AppColors.darkBtn, borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(height: 12),
            Text(tr.finExportTitle,
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FinSegment(
              labels: [tr.expenses, tr.incomes, tr.finExportAll],
              selected: _kinds.indexOf(_kind),
              onChanged: (i) => setState(() => _kind = _kinds[i]),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: finColor('green'), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(TablerIcons.file_spreadsheet, color: Color(0xFF1D1611)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(tr.finExportRows(rows, widget.periodTitle),
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            check(tr.finExportWithSummary, _summary, (v) => setState(() => _summary = v)),
            check(tr.finExportWithComment, _comment, (v) => setState(() => _comment = v)),
            check(tr.finExportWithAccount, _account, (v) => setState(() => _account = v)),
            const SizedBox(height: 10),
            if (rows == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(tr.finExportNothing,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
            PillButton(
              text: tr.finExportAction,
              bg: AppColors.accent,
              height: 48,
              width: double.infinity,
              onPressed: rows == 0
                  ? null
                  : () => Navigator.pop(context, (kind: _kind, summary: _summary, comment: _comment, account: _account)),
            ),
          ]),
        ),
      ),
    );
  }
}
