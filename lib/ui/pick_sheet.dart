import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import 'theme.dart';

/// Варіант у списку вибору.
typedef PickOption<T> = ({T value, String label});

/// Вибір одного значення зі списку - нижня панель, як вибір рахунку: ручка,
/// заголовок, рядки; обраний обведено медовим. Один спосіб вибору в усьому
/// додатку. null - закрили без вибору (значення-null загорнуте в запис).
Future<({T value})?> showPickSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickOption<T>> options,
  T? selected,
}) =>
    showModalBottomSheet<({T value})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(
                width: 44,
                height: 5,
                decoration:
                    BoxDecoration(color: AppColors.darkBtn, borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final o in options)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(ctx, (value: o.value)),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: o.value == selected ? AppColors.create : Colors.transparent,
                              width: 1.5),
                        ),
                        child: Text(o.label, style: TextStyle(color: AppColors.text, fontSize: 16)),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );

/// Поле вибору: показує обране значення (або [hint]) зі стрілкою ⌄; дотик
/// відкриває [showPickSheet]. Замість випадних списків.
class PickField<T> extends StatelessWidget {
  final String title;
  final List<PickOption<T>> options;
  final T? value;
  final String hint;
  final ValueChanged<T?>? onChanged;
  const PickField({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String? label;
    for (final o in options) {
      if (o.value == value) label = o.label;
    }
    final on = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: on
          ? () async {
              final r = await showPickSheet<T>(context, title: title, options: options, selected: value);
              if (r != null) onChanged!(r.value);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Text(label ?? hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: label == null || !on ? AppColors.textMuted : AppColors.text, fontSize: 15)),
          ),
          Icon(TablerIcons.chevron_down, size: 18, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}
