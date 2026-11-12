import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/fin_import_repo.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/fin_import.dart';
import '../ui/common.dart';
import '../ui/theme.dart';

/// Імпорт фінансів з Excel: вибрати файл, побачити, що в ньому знайдено й
/// що буде створено, підтвердити.
class FinImportScreen extends StatefulWidget {
  final Repository repo;
  const FinImportScreen({super.key, required this.repo});

  @override
  State<FinImportScreen> createState() => _FinImportScreenState();
}

class _FinImportScreenState extends State<FinImportScreen> {
  bool _busy = false;
  FinImportData? _data;
  FinImportPlan? _plan;
  FinImportResult? _result;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file =
          await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final data = parseFinWorkbook(bytes);
      if (data.isEmpty) {
        if (mounted) {
          setState(() => _busy = false);
          await showInfo(context, tr.finImportEmpty);
        }
        return;
      }
      final plan = await widget.repo.planFinImport(data);
      if (!mounted) return;
      setState(() {
        _data = data;
        _plan = plan;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showInfo(context, '${tr.finImportBad}: $e', title: tr.error);
      }
    }
  }

  Future<void> _run() async {
    final data = _data;
    if (data == null || _busy) return;
    setState(() => _busy = true);
    try {
      final r = await widget.repo.importFinData(data);
      if (mounted) {
        setState(() {
          _result = r;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showInfo(context, tr.saveFailed('$e'), title: tr.error);
      }
    }
  }

  Widget _card(String title, List<String> items) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title (${items.length})',
              style: TextStyle(color: AppColors.create, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(items.join(', '), style: TextStyle(color: AppColors.text, fontSize: 14)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final data = _data, plan = _plan, result = _result;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: tr.finImport, onBack: () => Navigator.pop(context)),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                if (result != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration:
                        BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                    child: Text(tr.finImportDone(result.added, result.duplicates),
                        style: TextStyle(color: AppColors.text, fontSize: 16)),
                  )
                else if (data == null)
                  Text(tr.finImportHint,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.4))
                else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration:
                        BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                        tr.finImportFound(data.expenses, data.incomes, data.transfers.length, data.skipped),
                        style: TextStyle(color: AppColors.text, fontSize: 16, height: 1.5)),
                  ),
                  if (plan != null && plan.newAccounts.isNotEmpty)
                    _card(tr.finImportNewAccounts, plan.newAccounts),
                  if (plan != null && plan.newCategories.isNotEmpty)
                    _card(tr.finImportNewCategories, plan.newCategories),
                ],
                if (_busy)
                  const Padding(
                      padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: PillButton(
                text: result != null
                    ? tr.close
                    : (data == null ? tr.finImportPick : tr.finImportStart),
                bg: AppColors.accent,
                height: 52,
                radius: 26,
                fontSize: 17,
                width: double.infinity,
                onPressed: _busy
                    ? null
                    : (result != null ? () => Navigator.pop(context) : (data == null ? _pick : _run)),
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
