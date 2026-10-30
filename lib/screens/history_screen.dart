import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/excel_export.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/theme.dart';
import '../l10n/l10n.dart';

/// Екран "Історія" — усі значення ОДНОГО параметра, найновіші першими.
/// Без [entity] — по всіх об'єктах (з каталогу параметрів), з [entity] —
/// лише цього вулика/групи (тап на рядок параметра в панелі на карті).
class HistoryScreen extends StatefulWidget {
  final Repository repo;
  final Parameter parameter;
  final EntityRef? entity;
  const HistoryScreen({super.key, required this.repo, required this.parameter, this.entity});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ParameterRecord>? rows;
  String? scopeName;

  // фільтр «Об'єкт»: задається з вулика, його видно зверху - можна змінити чи очистити
  late EntityRef? _entity = widget.entity;
  List<({EntityRef ref, String label})> _choices = const [];

  bool get scoped => _entity != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.repo.parameterHistory(widget.parameter.id, entity: _entity);
    String? name;
    if (_entity != null) name = await widget.repo.entityLabel(_entity!);
    // варіанти фільтра - об'єкти, у яких є записи цього параметра
    if (_choices.isEmpty) {
      final all = _entity == null
          ? r
          : await widget.repo.parameterHistory(widget.parameter.id);
      final seen = <String>{};
      _choices = [
        for (final x in all)
          if (seen.add(x.groupId ?? x.elementId ?? ''))
            (
              ref: x.groupId != null
                  ? EntityRef.group(x.groupId!)
                  : EntityRef.element(x.elementId ?? ''),
              label: x.entityLabel
            )
      ];
    }
    if (!mounted) return;
    setState(() {
      rows = r;
      scopeName = name;
    });
  }

  Future<void> _pickFilter() async {
    final res = await showDialog<({EntityRef? ref})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr.filterObject),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (ref: null)),
              child: Text(tr.allObjects)),
          for (final c in _choices)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, (ref: c.ref)), child: Text(c.label)),
        ],
      ),
    );
    if (res == null || !mounted) return;
    _entity = res.ref;
    await _load();
  }

  Widget _filterBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(children: [
          Expanded(
            child: PillButton(
              text: scoped ? tr.objectOf(scopeName ?? '') : tr.allObjects,
              bg: scoped ? AppColors.accent : AppColors.darkBtn,
              fg: scoped ? Colors.white : AppColors.text,
              height: 38,
              onPressed: _pickFilter,
            ),
          ),
          if (scoped) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: tr.clearFilter,
              icon: Icon(Icons.close, color: AppColors.text),
              onPressed: () async {
                _entity = null;
                await _load();
              },
            ),
          ],
        ]),
      );

  Future<void> _export() async {
    final list = rows ?? const <ParameterRecord>[];
    if (list.isEmpty) {
      await showInfo(context, tr.nothingToExport);
      return;
    }
    final result = await exportHistoryToExcel(
      parameter: widget.parameter,
      rows: list,
      scopeName: scopeName,
    );
    if (!mounted) return;
    await showInfo(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final title = tr.historyOf(widget.parameter.nameWithUnit);
    final list = rows;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: title, onBack: () => Navigator.pop(context)),
            _filterBar(),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              tr.paramHistoryEmpty(scoped),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _row(list[i]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PillButton(
                text: tr.exportExcel,
                bg: AppColors.accent,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: _export,
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _row(ParameterRecord r) {
    final date = formatDateTime(r.createdAt);
    return ListCard(
      height: 62,
      child: Row(children: [
        Expanded(
          child: scoped
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(date, style: TextStyle(color: AppColors.text, fontSize: 14)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(r.entityLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(date, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(
            (r.value == null || r.value!.isEmpty) ? '-' : r.value!,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ]),
    );
  }
}
