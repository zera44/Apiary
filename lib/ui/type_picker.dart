import 'package:flutter/material.dart';

import '../data/models.dart';
import 'theme.dart';

/// Вибір типу даних параметра: картки по дві в рядку — значок або приклад
/// значення й назва. Обрана — медова.
class DataTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged; // null — тип змінювати не можна
  const DataTypePicker({super.key, required this.value, this.onChanged});

  /// Що показати ліворуч у картці: приклад значення або значок.
  static Widget glyph(String type, Color color) {
    Widget t(String s) => Text(s,
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800, height: 1));
    Widget i(IconData d) => Icon(d, size: 18, color: color);
    return switch (type) {
      DataTypes.int_ => t('123'),
      DataTypes.float_ => t('1,5'),
      DataTypes.date => i(Icons.calendar_today),
      DataTypes.bool_ => i(Icons.toggle_on_outlined),
      DataTypes.choice => i(Icons.arrow_drop_down_circle_outlined),
      DataTypes.color => i(Icons.palette_outlined),
      _ => t('Аа'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (key, label) in DataTypes.all)
          SizedBox(
            width: w,
            height: 44,
            child: _card(key, label, enabled),
          ),
      ]);
    });
  }

  Widget _card(String key, String label, bool enabled) {
    final selected = key == value;
    final fg = selected ? Colors.white : (enabled ? AppColors.text : AppColors.textMuted);
    return Material(
      color: selected ? AppColors.accent : AppColors.typeBtn,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled && !selected ? () => onChanged!(key) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppColors.create : AppColors.hive.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            SizedBox(width: 30, child: Center(child: glyph(key, fg))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Варіанти для типу «Список»: плашки з хрестиком і поле «Додати варіант»
/// (Enter або «+» — додати).
class OptionsEditor extends StatefulWidget {
  final List<String> options;
  final ValueChanged<List<String>> onChanged;

  /// Поле «Додати варіант» — ззовні, щоб недописаний варіант не загубився
  /// при «Зберегти».
  final TextEditingController controller;

  /// Червона рамка поля, коли «Зберегти» натиснули без варіантів.
  final bool error;
  const OptionsEditor(
      {super.key,
      required this.options,
      required this.onChanged,
      required this.controller,
      this.error = false});
  @override
  State<OptionsEditor> createState() => _OptionsEditorState();
}

class _OptionsEditorState extends State<OptionsEditor> {
  TextEditingController get _ctrl => widget.controller;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    if (!widget.options.any((o) => o.toLowerCase() == v.toLowerCase())) {
      widget.onChanged([...widget.options, v]);
    }
    _ctrl.clear();
    _focus.requestFocus(); // одразу наступний варіант
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.options.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in widget.options)
            InputChip(
              label: Text(o, style: TextStyle(color: AppColors.text, fontSize: 13)),
              backgroundColor: AppColors.darkBtn,
              side: BorderSide(color: AppColors.hive.withValues(alpha: 0.4)),
              deleteIconColor: AppColors.textMuted,
              onDeleted: () => widget.onChanged([...widget.options]..remove(o)),
            ),
        ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            style: TextStyle(color: AppColors.text),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
                isDense: true,
                hintText: 'Додати варіант (наприклад, «Сильна»)',
                enabledBorder: widget.error ? redFieldBorder() : null,
                focusedBorder: widget.error ? redFieldBorder() : null),
            onSubmitted: (_) => _add(),
          ),
        ),
        IconButton(
          tooltip: 'Додати варіант',
          icon: Icon(Icons.add_circle, color: AppColors.create),
          onPressed: _add,
        ),
      ]),
    ]);
  }
}

/// Червона рамка поля введення - «так не можна».
OutlineInputBorder redFieldBorder() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.danger, width: 2.5),
    );
