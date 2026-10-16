import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repository.dart';
import 'assistant_tools.dart';

/// Ролі рядків стрічки чату.
class ChatRole {
  static const user = 'user';
  static const assistant = 'assistant';

  /// Картка «Записати так?», що чекає на людину.
  static const card = 'card';
}

/// Стани повідомлення людини.
class ChatStatus {
  /// у черзі: чекає на інтернет чи на повтор
  static const queued = 'queued';
  static const sending = 'sending';
  static const sent = 'sent';

  /// «не надіслано»: «Повторити» / «Видалити»
  static const failed = 'failed';

  // картки
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const rejected = 'rejected';
}

class ChatItem {
  final int seq;
  final String id;
  final String role;
  final String text;
  final String status;
  final int attempts;
  final DateTime? nextTry;
  final String? error;
  final Map<String, dynamic> data;

  /// Повідомлення людини пішло не одразу (було в черзі).
  final bool queued;
  final bool unread;
  const ChatItem(this.seq, this.id, this.role, this.text, this.status, this.attempts, this.nextTry,
      this.error, this.data, this.queued, this.unread);

  bool get isUser => role == ChatRole.user;
  bool get isCard => role == ChatRole.card;

  /// Екрани, запропоновані кнопками «Відкрити …» (відповідь із черги).
  List<NavTarget> get offeredNav => [
        for (final n in (data['nav'] as List? ?? const []))
          NavTarget(n['screen'] as String, n['label'] as String,
              apiaryId: n['apiary'] as String?,
              elementId: n['element'] as String?,
              lessonId: n['lesson'] as String?),
      ];

  /// Картка: що записати.
  PendingWrite? get card => !isCard
      ? null
      : PendingWrite(data['tool'] as String, text, [
          for (final f in (data['fields'] as List))
            WriteField(f['key'] as String, f['label'] as String, f['value'] as String,
                editable: f['editable'] as bool? ?? true),
        ]);

  static ChatItem fromRow(Map<String, Object?> r) => ChatItem(
        r['seq'] as int,
        r['id'] as String,
        r['role'] as String,
        r['text'] as String,
        r['status'] as String,
        r['attempts'] as int,
        r['next_try'] == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(((r['next_try'] as num) * 1e6).round()),
        r['error'] as String?,
        r['data'] == null ? const {} : jsonDecode(r['data'] as String) as Map<String, dynamic>,
        r['queued'] == 1,
        r['unread'] == 1,
      );
}

Map<String, dynamic> navJson(NavTarget t) => {
      'screen': t.screen,
      'label': t.label,
      if (t.apiaryId != null) 'apiary': t.apiaryId,
      if (t.elementId != null) 'element': t.elementId,
      if (t.lessonId != null) 'lesson': t.lessonId,
    };

/// Стрічка чату й розмова для моделі - у базі телефона (переживають
/// закриття застосунку).
class AssistantStore {
  final DatabaseExecutor db;
  AssistantStore(this.db);

  /// Змінилася стрічка (новий рядок, стан, прочитано).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<List<ChatItem>> items() async =>
      [for (final r in await db.query('assistant_chat', orderBy: 'seq')) ChatItem.fromRow(r)];

  Future<ChatItem?> item(String id) async {
    final r = await db.query('assistant_chat', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : ChatItem.fromRow(r.first);
  }

  Future<ChatItem> _add(String role, String text,
      {String status = '', Map<String, dynamic>? data, bool queued = false, bool unread = false}) async {
    final id = Repository.newId();
    await db.insert('assistant_chat', {
      'id': id,
      'role': role,
      'text': text,
      'status': status,
      'data': data == null ? null : jsonEncode(data),
      'queued': queued ? 1 : 0,
      'unread': unread ? 1 : 0,
      'created_at': Repository.now(),
    });
    changes.value++;
    return (await item(id))!;
  }

  Future<ChatItem> addUser(String text) => _add(ChatRole.user, text, status: ChatStatus.queued);

  Future<ChatItem> addAssistant(String text,
          {List<NavTarget> nav = const [], bool unread = false, String? replyTo, String? model}) =>
      _add(ChatRole.assistant, text,
          data: {
            if (nav.isNotEmpty) 'nav': [for (final n in nav) navJson(n)],
            'reply_to': ?replyTo,
            'model': ?model,
          },
          unread: unread);

  Future<ChatItem> addCard(String tool, Map<String, dynamic> input, PendingWrite card,
          {bool unread = false}) =>
      _add(ChatRole.card, card.title,
          status: ChatStatus.pending,
          data: {
            'tool': tool,
            'input': input,
            'fields': [
              for (final f in card.fields)
                {'key': f.key, 'label': f.label, 'value': f.value, 'editable': f.editable}
            ],
          },
          unread: unread);

  Future<void> update(String id, Map<String, Object?> fields) async {
    await db.update('assistant_chat', fields, where: 'id = ?', whereArgs: [id]);
    changes.value++;
  }

  /// Наступне повідомлення людини, яке пора надіслати. Строго за порядком:
  /// поки перше в черзі чекає паузу, наступні його не обганяють.
  Future<ChatItem?> nextDue(DateTime now) async {
    final r = await db.query('assistant_chat',
        where: "role = 'user' AND status = 'queued'", orderBy: 'seq', limit: 1);
    if (r.isEmpty) return null;
    final it = ChatItem.fromRow(r.first);
    return it.nextTry == null || !it.nextTry!.isAfter(now) ? it : null;
  }

  /// Чи є ще що надсилати (зокрема пізніше - після паузи).
  Future<bool> hasQueued() async => (await db.query('assistant_chat',
          columns: ['seq'], where: "role = 'user' AND status IN ('queued', 'sending')", limit: 1))
      .isNotEmpty;

  /// Взяти повідомлення на відправку; false - його вже взяв інший
  /// (застосунок і фонове завдання).
  Future<bool> claim(String id) async {
    final n = await db.rawUpdate(
        "UPDATE assistant_chat SET status = 'sending' WHERE id = ? AND status = 'queued'", [id]);
    if (n > 0) changes.value++;
    return n > 0;
  }

  /// Після аварійного закриття «sending» лишається назавжди - повернути в чергу.
  Future<void> releaseStuck() async {
    final n = await db.rawUpdate(
        "UPDATE assistant_chat SET status = 'queued', queued = 1 WHERE status = 'sending'");
    if (n > 0) changes.value++;
  }

  Future<void> delete(String id) async {
    await db.delete('assistant_chat', where: 'id = ?', whereArgs: [id]);
    changes.value++;
  }

  /// Нових відповідей і карток, яких людина ще не бачила.
  Future<int> unreadCount() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM assistant_chat WHERE unread = 1');
    return (r.first['n'] as int?) ?? 0;
  }

  /// Перша непрочитана (чат відкривається на ній).
  Future<ChatItem?> firstUnread() async {
    final r = await db.query('assistant_chat', where: 'unread = 1', orderBy: 'seq', limit: 1);
    return r.isEmpty ? null : ChatItem.fromRow(r.first);
  }

  Future<void> markAllRead() async {
    final n = await db.rawUpdate('UPDATE assistant_chat SET unread = 0 WHERE unread = 1');
    if (n > 0) changes.value++;
  }

  // розмова для моделі (лише дописується)

  Future<List<Map<String, dynamic>>> history() async => [
        for (final r in await db.query('assistant_history', orderBy: 'seq'))
          jsonDecode(r['msg'] as String) as Map<String, dynamic>
      ];

  Future<void> appendHistory(Iterable<Map<String, dynamic>> messages) async {
    for (final m in messages) {
      await db.insert('assistant_history', {'msg': jsonEncode(m)});
    }
  }

  /// «Нова розмова»: стрічка й розмова - з чистого аркуша (черга лишається).
  Future<void> newConversation() async {
    await db.delete('assistant_history');
    await db.delete('assistant_chat', where: "NOT (role = 'user' AND status IN ('queued', 'sending', 'failed'))");
    changes.value++;
  }
}
