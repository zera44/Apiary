import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/excel_export.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/theme.dart';

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

  bool get scoped => widget.entity != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.repo.parameterHistory(widget.parameter.id, entity: widget.entity);
    String? name;
    if (widget.entity != null) name = await widget.repo.entityLabel(widget.entity!);
    if (!mounted) return;
    setState(() {
      rows = r;
      scopeName = name;
    });
  }

  Future<void> _export() async {
    final list = rows ?? const <ParameterRecord>[];
    if (list.isEmpty) {
      await showInfo(context, 'Немає жодного запису для експорту.');
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
    var title = 'Історія: ${widget.parameter.nameWithUnit}';
    if (scopeName != null) title += ' - $scopeName';
    final list = rows;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: title, onBack: () => Navigator.pop(context)),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Ще немає жодного запису для цього параметра'
                              '${scoped ? " у цього об'єкта" : ''}.\n'
                              'Записи з\'являються після кнопки «Оглянути» на карті.',
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
                text: 'Експортувати в Excel',
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
                        maxLines: 1,
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
