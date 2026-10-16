import 'models.dart';
import 'repository.dart';

/// Разове нагадування: текст і момент (системне сповіщення, див.
/// ReminderService), за потреби - вулик. Лише на цьому телефоні.
class UserReminder {
  final String id;
  final String text;
  final DateTime due;
  final EntityRef? hive;
  const UserReminder(this.id, this.text, this.due, this.hive);
}

extension RepositoryUserReminders on Repository {
  Future<String> addUserReminder(String text, DateTime due, {EntityRef? hive}) async {
    if (text.trim().isEmpty) throw ArgumentError.value(text, 'text', 'порожній текст');
    final id = Repository.newId();
    await db.insert('user_reminders', {
      'id': id,
      'text': text.trim(),
      'due_at': due.microsecondsSinceEpoch / 1e6,
      'group_id': hive?.groupId,
      'element_id': hive?.elementId,
      'created_at': Repository.now(),
    });
    remindersChanged.value++;
    return id;
  }

  /// Ще не видалені нагадування від [from] (за замовчуванням - усі), за часом.
  Future<List<UserReminder>> listUserReminders({DateTime? from}) async {
    final rows = await db.query('user_reminders',
        where: from == null ? 'deleted = 0' : 'deleted = 0 AND due_at >= ?',
        whereArgs: from == null ? null : [from.microsecondsSinceEpoch / 1e6],
        orderBy: 'due_at ASC');
    return [
      for (final r in rows)
        UserReminder(
          r['id'] as String,
          r['text'] as String,
          DateTime.fromMicrosecondsSinceEpoch(((r['due_at'] as num) * 1e6).round()),
          r['group_id'] != null
              ? EntityRef.group(r['group_id'] as String)
              : r['element_id'] != null
                  ? EntityRef.element(r['element_id'] as String)
                  : null,
        ),
    ];
  }

  Future<void> deleteUserReminder(String id) async {
    await db.update('user_reminders', {'deleted': 1}, where: 'id = ?', whereArgs: [id]);
    remindersChanged.value++;
  }
}
