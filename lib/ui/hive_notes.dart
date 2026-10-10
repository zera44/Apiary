import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/notes.dart';
import '../data/repository.dart';
import 'common.dart';
import 'date_picker.dart';
import 'theme.dart';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// «Сьогодні», «Вчора» або дд.мм.рррр.
String noteDayText(DateTime d) {
  final today = DateTime.now();
  if (_sameDay(d, today)) return 'Сьогодні';
  if (_sameDay(d, today.subtract(const Duration(days: 1)))) return 'Вчора';
  return formatDdMmYyyy(d);
}

/// Вкладка «Нотатки» панелі вулика: фільтр за мітками, кнопка «Нотатка» і
/// список (найновіші зверху). Тап по нотатці - змінити, ⋯ - змінити/видалити.
class HiveNotesView extends StatefulWidget {
  final Repository repo;
  final EntityRef entity;
  const HiveNotesView({super.key, required this.repo, required this.entity});

  @override
  State<HiveNotesView> createState() => _HiveNotesViewState();
}

class _HiveNotesViewState extends State<HiveNotesView> {
  List<HiveNote> _notes = const [];
  Map<String, NoteLabel> _labels = const {};
  final Set<String> _hidden = {};
  String? _filter;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.repo.notesChanges.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(HiveNotesView old) {
    super.didUpdateWidget(old);
    if (old.repo != widget.repo) {
      old.repo.notesChanges.removeListener(_load);
      widget.repo.notesChanges.addListener(_load);
    }
    if (old.entity != widget.entity || old.repo != widget.repo) {
      _filter = null;
      _hidden.clear();
      _load();
    }
  }

  @override
  void dispose() {
    widget.repo.notesChanges.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final entity = widget.entity;
    final notes = await widget.repo.listHiveNotes(entity);
    final labels = await widget.repo.listNoteLabels();
    if (!mounted || entity != widget.entity) return;
    setState(() {
      _notes = notes;
      _labels = {for (final l in labels) l.id: l};
      if (_filter != null && !_labels.containsKey(_filter)) _filter = null;
      _loaded = true;
    });
  }

  Future<void> _edit([HiveNote? note]) async {
    await showNoteEditor(context, widget.repo, widget.entity, note: note);
  }

  Future<void> _delete(HiveNote n) async {
    await deleteWithUndo(
      context,
      message: 'Нотатку видалено',
      hide: () => setState(() => _hidden.add(n.id)),
      restore: () {
        if (mounted) setState(() => _hidden.remove(n.id));
      },
      commit: () async {
        await widget.repo.deleteHiveNote(n.id);
        _hidden.remove(n.id);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = [for (final n in _notes) if (!_hidden.contains(n.id)) n];
    // у фільтрі - лише мітки, що є в нотатках цього вулика
    final used = <String>{for (final n in visible) if (n.labelId != null) n.labelId!};
    final chips = [for (final l in _labels.values) if (used.contains(l.id)) l];
    // мітки фільтра вже немає в нотатках (видалили нотатку чи зняли мітку) -
    // показуємо всі, інакше решта нотаток «зникла б» без кнопки «Усі»
    final filter = used.contains(_filter) ? _filter : null;
    final shown = filter == null ? visible : [for (final n in visible) if (n.labelId == filter) n];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      children: [
        PillButton(
          key: const ValueKey('note-add'),
          text: '+ Нотатка',
          bg: AppColors.accent,
          height: 38,
          fontSize: 13,
          width: double.infinity,
          onPressed: () => _edit(),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _FilterChip(text: 'Усі', on: filter == null, onTap: () => setState(() => _filter = null)),
            for (final l in chips)
              _FilterChip(
                  text: l.name,
                  on: filter == l.id,
                  onTap: () => setState(() => _filter = filter == l.id ? null : l.id)),
          ]),
        ],
        const SizedBox(height: 10),
        if (_loaded && shown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              visible.isEmpty
                  ? 'Нотаток ще немає.\nЗапишіть, що помітили біля вулика.'
                  : 'Немає нотаток із цією міткою.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3),
            ),
          ),
        for (final n in shown) _noteCard(n),
      ],
    );
  }

  Widget _noteCard(HiveNote n) {
    final label = n.labelId == null ? null : _labels[n.labelId];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.roundBtn,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBtn),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 0, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(noteDayText(n.day),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(child: _LabelTag(label.name)),
              ],
              const Spacer(),
              SizedBox(
                width: 34,
                height: 34,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Дії',
                  icon: Icon(Icons.more_horiz, size: 20, color: AppColors.textMuted),
                  color: AppColors.popupBg,
                  onSelected: (v) => v == 'edit' ? _edit(n) : _delete(n),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text('Змінити', style: TextStyle(color: AppColors.text))),
                    PopupMenuItem(value: 'delete', child: Text('Видалити', style: TextStyle(color: AppColors.danger))),
                  ],
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(n.text, style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.3)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  const _FilterChip({required this.text, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.create : AppColors.darkBtn,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              style: TextStyle(
                  color: on ? AppColors.bg : AppColors.text,
                  fontSize: 12,
                  fontWeight: on ? FontWeight.bold : FontWeight.w500)),
        ),
      );
}

class _LabelTag extends StatelessWidget {
  final String text;
  const _LabelTag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.hive.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.hive, fontSize: 11.5, fontWeight: FontWeight.bold)),
      );
}

/// Вікно нотатки: текст, дата (за замовчуванням сьогодні, можна заднім
/// числом) і власна мітка. [note] - змінити наявну. Повертає true, якщо
/// збережено.
Future<bool> showNoteEditor(BuildContext context, Repository repo, EntityRef entity,
    {HiveNote? note}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => _NoteEditor(repo: repo, entity: entity, note: note),
  );
  return res ?? false;
}

class _NoteEditor extends StatefulWidget {
  final Repository repo;
  final EntityRef entity;
  final HiveNote? note;
  const _NoteEditor({required this.repo, required this.entity, this.note});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _text = TextEditingController(text: widget.note?.text ?? '');
  late DateTime _date = widget.note?.day ?? DateTime.now();
  late String? _label = widget.note?.labelId;
  List<NoteLabel> _labels = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadLabels() async {
    final l = await widget.repo.listNoteLabels();
    if (mounted) setState(() => _labels = l);
  }

  Future<void> _pickDate() async {
    final res = await showAppDatePicker(context, formatDdMmYyyy(_date));
    final d = parseDdMmYyyy(res);
    if (d == null || !mounted) return;
    // день із вибору, час - поточний (порядок нотаток одного дня)
    final n = DateTime.now();
    setState(() => _date = DateTime(d.year, d.month, d.day, n.hour, n.minute, n.second));
  }

  Future<void> _newLabel() async {
    final name = await showTextPrompt(context, title: 'Нова мітка', initial: '');
    if (name == null || name.trim().isEmpty) return;
    final id = await widget.repo.addNoteLabel(name);
    await _loadLabels();
    if (mounted) setState(() => _label = id);
  }

  /// Довгий тап по мітці: перейменувати або видалити (нотатки лишаються).
  Future<void> _labelMenu(NoteLabel l) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.name),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'rename'),
              child: Text('Перейменувати', style: TextStyle(color: AppColors.text))),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text('Видалити мітку', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await showTextPrompt(context, title: 'Мітка', initial: l.name);
      if (name == null || name.trim().isEmpty || name.trim() == l.name) return;
      final other = await widget.repo.findNoteLabel(name);
      if (other != null && other.id != l.id) {
        if (mounted) await showInfo(context, 'Мітка «${other.name}» вже є.');
        return;
      }
      await widget.repo.renameNoteLabel(l.id, name);
    } else {
      final ok = await showConfirm(context,
          title: 'Видалити мітку?', text: 'Нотатки з цією міткою залишаться, але без мітки.');
      if (!ok) return;
      await widget.repo.deleteNoteLabel(l.id);
      if (_label == l.id) _label = null;
    }
    await _loadLabels();
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _text.text.trim();
    if (text.isEmpty) {
      await showInfo(context, 'Напишіть текст нотатки.');
      return;
    }
    setState(() => _saving = true);
    final note = widget.note;
    if (note == null) {
      await widget.repo.addHiveNote(widget.entity, text, date: _date, labelId: _label);
    } else {
      await widget.repo.updateHiveNote(note.id, text: text, date: _date, labelId: _label);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _chip(String text, bool on, VoidCallback onTap, {VoidCallback? onLong, Key? key}) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        onLongPress: onLong,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.create : AppColors.darkBtn,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text,
              style: TextStyle(
                  color: on ? AppColors.bg : AppColors.text,
                  fontSize: 13,
                  fontWeight: on ? FontWeight.bold : FontWeight.w500)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.bold);
    final today = _sameDay(_date, DateTime.now());
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.note == null ? 'Нова нотатка' : 'Нотатка'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              key: const ValueKey('note-text'),
              controller: _text,
              autofocus: widget.note == null,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppColors.text, fontSize: 15),
              decoration: const InputDecoration(hintText: 'Що помітили біля вулика'),
            ),
            const SizedBox(height: 14),
            Text('Дата', style: muted),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Сьогодні', today, () {
                final n = DateTime.now();
                setState(() => _date = n);
              }),
              _chip(today ? 'Інша дата' : formatDdMmYyyy(_date), !today, _pickDate,
                  key: const ValueKey('note-date')),
            ]),
            const SizedBox(height: 14),
            Text('Мітка', style: muted),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Без мітки', _label == null, () => setState(() => _label = null)),
              for (final l in _labels)
                _chip(l.name, _label == l.id, () => setState(() => _label = l.id),
                    onLong: () => _labelMenu(l)),
              _chip('+ Мітка', false, _newLabel, key: const ValueKey('note-new-label')),
            ]),
            if (_labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Утримуйте мітку, щоб перейменувати чи видалити.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ),
          ]),
        ),
      ),
      actions: [
        Row(children: [
          Expanded(
            child: PillButton(
                text: 'Скасувати',
                bg: AppColors.neutralBtn,
                fg: AppColors.text,
                onPressed: () => Navigator.pop(context, false)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PillButton(
                key: const ValueKey('note-save'),
                text: 'Зберегти',
                bg: AppColors.accent,
                onPressed: _saving ? null : _save),
          ),
        ]),
      ],
    );
  }
}
