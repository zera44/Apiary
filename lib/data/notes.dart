import 'models.dart';
import 'repository.dart';

/// Нотатки вуликів: вільний текст із датою (можна заднім числом) і власною
/// міткою. Прив'язка - як в історії значень: група (весь вулик) або окремий
/// об'єкт ([EntityRef]). У «Історію» та Excel нотатки поки не потрапляють.

/// Назва мітки для нотатки, написаної у вікні «Оглянути».
const kInspectionNoteLabel = 'Огляд';

class NoteLabel {
  final String id;
  final String name;
  const NoteLabel({required this.id, required this.name});

  factory NoteLabel.fromRow(Map<String, Object?> r) =>
      NoteLabel(id: r['id'] as String, name: r['name'] as String);
}

class HiveNote {
  final String id;
  final String text;

  /// Дата нотатки (секунди від епохи).
  final double date;
  final String? labelId;
  final double createdAt;
  const HiveNote({
    required this.id,
    required this.text,
    required this.date,
    this.labelId,
    required this.createdAt,
  });

  DateTime get day => DateTime.fromMicrosecondsSinceEpoch((date * 1e6).round());

  factory HiveNote.fromRow(Map<String, Object?> r) => HiveNote(
        id: r['id'] as String,
        text: r['text'] as String,
        date: (r['note_date'] as num).toDouble(),
        labelId: r['label_id'] as String?,
        createdAt: (r['created_at'] as num).toDouble(),
      );
}

(String, List<Object?>) _owner(EntityRef e) => e.isGroup
    ? ('group_id = ?', [e.groupId])
    : ('element_id = ? AND group_id IS NULL', [e.elementId]);

extension RepositoryNotes on Repository {
  // ---------------------------------------------------------------- мітки

  Future<List<NoteLabel>> listNoteLabels() async {
    final rows = await db.query('note_labels',
        where: 'deleted = 0', orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map(NoteLabel.fromRow).toList();
  }

  /// Нова мітка; якщо мітка з такою назвою вже є - повертає її id.
  Future<String> addNoteLabel(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'порожня назва');
    final same = await db.rawQuery(
        'SELECT id FROM note_labels WHERE deleted = 0 AND name = ? COLLATE NOCASE LIMIT 1',
        [clean]);
    if (same.isNotEmpty) return same.first['id'] as String;
    final r = await db.rawQuery('SELECT MAX(sort_order) AS m FROM note_labels');
    final id = Repository.newId();
    await db.insert('note_labels', {
      'id': id,
      'name': clean,
      'sort_order': ((r.first['m'] as int?) ?? -1) + 1,
      'updated_at': Repository.now(),
      'synced': 0,
    });
    notesChanges.value++;
    return id;
  }

  Future<void> renameNoteLabel(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError.value(name, 'name', 'порожня назва');
    await db.update('note_labels', {'name': clean, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
    notesChanges.value++;
  }

  /// Видалити мітку: нотатки лишаються, просто без мітки.
  Future<void> deleteNoteLabel(String id) async {
    final t = Repository.now();
    await db.transaction((txn) async {
      await txn.update('note_labels', {'deleted': 1, 'updated_at': t, 'synced': 0},
          where: 'id = ?', whereArgs: [id]);
      await txn.update('hive_notes', {'label_id': null, 'updated_at': t, 'synced': 0},
          where: 'label_id = ?', whereArgs: [id]);
    });
    notesChanges.value++;
  }

  // -------------------------------------------------------------- нотатки

  /// Нотатки вулика, найновіші зверху. [labelId] - лише з цією міткою.
  Future<List<HiveNote>> listHiveNotes(EntityRef e, {String? labelId}) async {
    final (w, args) = _owner(e);
    final rows = await db.rawQuery(
      'SELECT * FROM hive_notes WHERE deleted = 0 AND $w'
      '${labelId != null ? ' AND label_id = ?' : ''} '
      'ORDER BY note_date DESC, created_at DESC',
      [...args, if (labelId != null) labelId],
    );
    return rows.map(HiveNote.fromRow).toList();
  }

  Future<int> countHiveNotes(EntityRef e) async {
    final (w, args) = _owner(e);
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM hive_notes WHERE deleted = 0 AND $w', args);
    return (r.first['n'] as int?) ?? 0;
  }

  /// [date] - день нотатки (за замовчуванням зараз).
  Future<String> addHiveNote(EntityRef e, String text, {DateTime? date, String? labelId}) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError.value(text, 'text', 'порожня нотатка');
    final t = Repository.now();
    final id = Repository.newId();
    await db.insert('hive_notes', {
      'id': id,
      'group_id': e.groupId,
      'element_id': e.isGroup ? null : e.elementId,
      'text': clean,
      'note_date': date == null ? t : date.microsecondsSinceEpoch / 1e6,
      'label_id': labelId,
      'created_at': t,
      'updated_at': t,
      'synced': 0,
    });
    notesChanges.value++;
    return id;
  }

  Future<void> updateHiveNote(String id,
      {required String text, required DateTime date, String? labelId}) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError.value(text, 'text', 'порожня нотатка');
    await db.update(
        'hive_notes',
        {
          'text': clean,
          'note_date': date.microsecondsSinceEpoch / 1e6,
          'label_id': labelId,
          'updated_at': Repository.now(),
          'synced': 0,
        },
        where: 'id = ?',
        whereArgs: [id]);
    notesChanges.value++;
  }

  Future<void> deleteHiveNote(String id) async {
    await db.update('hive_notes', {'deleted': 1, 'updated_at': Repository.now(), 'synced': 0},
        where: 'id = ?', whereArgs: [id]);
    notesChanges.value++;
  }

  /// Нотатка з вікна «Оглянути» - з міткою «Огляд» (створюється за потреби).
  Future<String?> addInspectionNote(EntityRef e, String text) async {
    if (text.trim().isEmpty) return null;
    final label = await addNoteLabel(kInspectionNoteLabel);
    return addHiveNote(e, text, labelId: label);
  }
}
