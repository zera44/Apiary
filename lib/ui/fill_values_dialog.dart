import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'common.dart';
import 'date_picker.dart';
import 'icons.dart';
import 'theme.dart';

/// Форма "Заповнити": поле на кожен прив'язаний параметр. Тип даних
/// обмежує ввід (ціле / дробове), для "Дата" — календар, для "Колір" —
/// фіксовані зразки. Повертає {parameter_id: нове значення} лише для
/// змінених полів (порожній рядок — значення прибрали), або null, якщо
/// скасовано.
Future<FillResult?> showFillValuesDialog(
  BuildContext context, {
  required List<Parameter> params,
  required Map<String, String?> latest,
  bool offerNext = false,
}) {
  return showDialog<FillResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FillDialog(params: params, latest: latest, offerNext: offerNext),
  );
}

/// Результат форми: змінені значення й чи натиснули «Зберегти й далі»
/// (обхід ланцюжком — одразу наступний вулик).
class FillResult {
  final Map<String, String> values;
  final bool next;
  const FillResult(this.values, {this.next = false});
}

class _FillDialog extends StatefulWidget {
  final List<Parameter> params;
  final Map<String, String?> latest;
  final bool offerNext;
  const _FillDialog({required this.params, required this.latest, this.offerNext = false});
  @override
  State<_FillDialog> createState() => _FillDialogState();
}

class _FillDialogState extends State<_FillDialog> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _picked = {}; // для дати й кольору
  // ВИПРАВЛЕНО: фільтр вводу пропускав "напівготові" значення типу "-"
  // чи "," — без цієї перевірки вони зберігались в історію як нібито
  // числове значення.
  String? _error;

  static final _intFilter = WholeValueFormatter(RegExp(r'^-?\d*$'));
  static final _floatFilter = WholeValueFormatter(RegExp(r'^-?\d*[.,]?\d*$'));

  @override
  void initState() {
    super.initState();
    for (final p in widget.params) {
      final cur = widget.latest[p.id] ?? '';
      if (p.dataType == DataTypes.date || p.dataType == DataTypes.color) {
        _picked[p.id] = cur;
      } else {
        _text[p.id] = TextEditingController(text: cur);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save({bool next = false}) {
    final out = <String, String>{};
    for (final p in widget.params) {
      final raw = (_text[p.id]?.text ?? _picked[p.id] ?? '').trim();
      final before = (widget.latest[p.id] ?? '').trim();
      // поле не чіпали — не перевіряємо й не записуємо (навіть якщо старе
      // значення не відповідає типу, напр., з давніших версій)
      if (raw == before) continue;
      if (raw.isEmpty) {
        // поле спорожнили (або "Очистити" в календарі): якщо раніше значення
        // було — записуємо порожнє, тож у історії видно, що його прибрали
        if ((widget.latest[p.id] ?? '').isNotEmpty) out[p.id] = '';
        continue;
      }
      var v = raw;
      if (p.dataType == DataTypes.int_) {
        final n = int.tryParse(v);
        if (n == null) {
          setState(() => _error = '«${p.nameWithUnit}»: введіть ціле число');
          return;
        }
        v = n.toString();
      } else if (p.dataType == DataTypes.float_) {
        final n = double.tryParse(v.replaceAll(',', '.'));
        if (n == null) {
          setState(() => _error = '«${p.nameWithUnit}»: введіть число');
          return;
        }
        v = n.toString();
      }
      if (v != (widget.latest[p.id] ?? '')) out[p.id] = v;
    }
    Navigator.pop(context, FillResult(out, next: next));
  }

  Widget _field(Parameter p) {
    switch (p.dataType) {
      case DataTypes.date:
        final dateText = _picked[p.id] ?? '';
        return Row(children: [
          Expanded(
            child: Text(dateText.isEmpty ? 'Не обрано' : dateText,
                style: TextStyle(color: AppColors.text, fontSize: 14)),
          ),
          PillButton(
            text: 'Обрати дату',
            bg: AppColors.roundBtn,
            fg: AppColors.text,
            fontSize: 12,
            width: 124,
            height: 38,
            onPressed: () async {
              final r = await showAppDatePicker(context, dateText);
              if (r != null) setState(() => _picked[p.id] = r);
            },
          ),
        ]);
      case DataTypes.color:
        final colorLabel = _picked[p.id] ?? '';
        return Wrap(spacing: 8, children: [
          for (final (label, c) in queenTagChoices)
            ColorTagSwatch(
              fill: c,
              selected: colorLabel == label,
              tooltip: label,
              // повторний тап по обраному кольору — зняти вибір
              onTap: () => setState(() => _picked[p.id] = colorLabel == label ? '' : label),
            ),
        ]);
      default:
        return TextField(
          controller: _text[p.id],
          style: TextStyle(color: AppColors.text),
          keyboardType: p.dataType == DataTypes.int_
              ? const TextInputType.numberWithOptions(signed: true)
              : p.dataType == DataTypes.float_
                  ? const TextInputType.numberWithOptions(signed: true, decimal: true)
                  : TextInputType.text,
          inputFormatters: p.dataType == DataTypes.int_
              ? [_intFilter]
              : p.dataType == DataTypes.float_
                  ? [_floatFilter]
                  : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Заповнити параметри'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in widget.params) ...[
              Text(p.nameWithUnit,
                  style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(DataTypes.label(p.dataType),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 6),
              _field(p),
              const SizedBox(height: 14),
            ],
          ],
        )),
      ),
      actions: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          // помилка — біля кнопок, щоб її було видно при будь-якій кількості полів
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ),
          Row(children: [
            Expanded(
              child: PillButton(
                  text: 'Скасувати',
                  bg: AppColors.neutralBtn,
                  fg: AppColors.text,
                  onPressed: () => Navigator.pop(context)),
            ),
            const SizedBox(width: 8),
            Expanded(child: PillButton(text: 'Зберегти', bg: AppColors.accent, onPressed: _save)),
          ]),
          if (widget.offerNext) ...[
            const SizedBox(height: 8),
            // обхід ланцюжком: зберегти й одразу наступний вулик
            PillButton(
              text: 'Зберегти й далі →',
              bg: AppColors.create,
              width: double.infinity,
              onPressed: () => _save(next: true),
            ),
          ],
        ]),
      ],
    );
  }
}

/// Пропускає зміну поля, лише якщо ВЕСЬ новий текст відповідає [pattern];
/// інакше лишає попередній (раніше фільтр вирізав "зайве" й з "1.5" у
/// цілому полі виходило "15", а вставка " 25" очищала поле). Пробіли по
/// краях вставленого тексту прибираються.
class WholeValueFormatter extends TextInputFormatter {
  final RegExp pattern;
  WholeValueFormatter(this.pattern);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (pattern.hasMatch(newValue.text)) return newValue;
    final trimmed = newValue.text.trim();
    if (trimmed != newValue.text && pattern.hasMatch(trimmed)) {
      return TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    return oldValue;
  }
}
