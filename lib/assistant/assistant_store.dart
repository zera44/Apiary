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

  /// Розмова, до якої належить рядок.
  final int conv;
  const ChatItem(this.seq, this.id, this.role, this.text, this.status, this.attempts, this.nextTry,
      this.error, this.data, this.queued, this.unread, [this.conv = 1]);

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
                editable: f['editable'] as bool? ?? true,
                choices: [for (final c in (f['choices'] as List? ?? const [])) '$c']),
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
        (r['conv'] as int?) ?? 1,
      );
}

/// Розмова зі списку «Розмови».
class Conversation {
  final int id;
  final String title;
  final DateTime updatedAt;
  final int messages;
  const Conversation(this.id, this.title, this.updatedAt, this.messages);
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

  /// Поточна розмова (її показує чат). Нові рядки йдуть у неї, якщо не
  /// вказано іншу (відповідь на повідомлення зі старої розмови).
  int conv = 1;

  static const _convKey = 'assistant_conv';

  /// Прочитати поточну розмову з бази й подбати, щоб вона існувала.
  Future<void> load() async {
    final m = await db.query('app_meta', where: 'key = ?', whereArgs: [_convKey]);
    final saved = m.isEmpty ? null : int.tryParse('${m.first['value']}');
    final has = saved == null
        ? <Map<String, Object?>>[]
        : await db.query('assistant_convs', where: 'id = ?', whereArgs: [saved]);
    if (has.isNotEmpty) {
      conv = saved!;
      return;
    }
    // перший запуск після оновлення: усе старе - розмова 1
    final first = await db.query('assistant_convs', orderBy: 'id', limit: 1);
    conv = first.isEmpty ? await _createConv(id: 1) : first.first['id'] as int;
    await _saveCurrent();
  }

  Future<int> _createConv({int? id}) async => db.insert('assistant_convs', {
        'id': ?id,
        'title': '',
        'created_at': Repository.now(),
        'updated_at': Repository.now(),
      });

  Future<void> _saveCurrent() async => db.insert('app_meta', {'key': _convKey, 'value': '$conv'},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<ChatItem>> items() async => [
        for (final r in await db.query('assistant_chat',
            where: 'conv = ?', whereArgs: [conv], orderBy: 'seq'))
          ChatItem.fromRow(r)
      ];

  /// Усі розмови, нові зверху (порожні не показуємо, крім поточної).
  Future<List<Conversation>> conversations() async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.title, c.updated_at,
             (SELECT COUNT(*) FROM assistant_chat m WHERE m.conv = c.id AND m.role != 'card') AS n
      FROM assistant_convs c ORDER BY c.updated_at DESC, c.id DESC''');
    return [
      for (final r in rows)
        if ((r['n'] as int) > 0 || r['id'] == conv)
          Conversation(
              r['id'] as int,
              r['title'] as String,
              DateTime.fromMicrosecondsSinceEpoch(((r['updated_at'] as num) * 1e6).round()),
              r['n'] as int),
    ];
  }

  /// Відкрити іншу розмову.
  Future<void> switchTo(int id) async {
    if (id == conv) return;
    conv = id;
    await _saveCurrent();
    changes.value++;
  }

  /// «Нова розмова»: стара лишається в списку, чат - з чистого аркуша.
  /// Якщо поточна ще порожня - нова не потрібна. Повертає true, якщо
  /// створено.
  Future<bool> newConversation() async {
    final n = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM assistant_chat WHERE conv = ? AND role != 'card'", [conv]);
    if ((n.first['n'] as int) == 0) return false;
    conv = await _createConv();
    await _saveCurrent();
    changes.value++;
    return true;
  }

  /// Нова розмова сама, якщо в поточній давно ([idle]) тиша: нове питання -
  /// з чистого аркуша, стара лишається в «Розмови». Не чіпаємо, поки
  /// повідомлення людини ще в дорозі чи картка чекає на відповідь.
  Future<bool> freshIfIdle(Duration idle) async {
    final c = await db.query('assistant_convs',
        columns: ['updated_at'], where: 'id = ?', whereArgs: [conv]);
    if (c.isEmpty) return false;
    final at = (c.first['updated_at'] as num).toDouble();
    if (Repository.now() - at < idle.inMicroseconds / 1e6) return false;
    final busy = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM assistant_chat WHERE conv = ? AND '
        "((role = 'user' AND status IN ('queued', 'sending')) OR (role = 'card' AND status = 'pending'))",
        [conv]);
    if ((busy.first['n'] as int) > 0) return false;
    return newConversation();
  }

  /// Видалити розмову разом з історією; поточну - переходимо на іншу чи нову.
  Future<void> deleteConversation(int id) async {
    await db.delete('assistant_chat', where: 'conv = ?', whereArgs: [id]);
    await db.delete('assistant_history', where: 'conv = ?', whereArgs: [id]);
    await db.delete('assistant_convs', where: 'id = ?', whereArgs: [id]);
    if (id == conv) {
      final rest = await db.query('assistant_convs', orderBy: 'updated_at DESC', limit: 1);
      conv = rest.isEmpty ? await _createConv() : rest.first['id'] as int;
      await _saveCurrent();
    }
    changes.value++;
  }

  /// Назва розмови - початок першого питання; час - останнє повідомлення.
  Future<void> _touch(int c, {String? firstText}) async {
    final one = firstText?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final named = one != null && one.isNotEmpty;
    await db.rawUpdate(
        'UPDATE assistant_convs SET updated_at = ?'
        '${named ? ", title = CASE WHEN title = '' THEN ? ELSE title END" : ''}'
        ' WHERE id = ?',
        [
          Repository.now(),
          if (named) one.length > 60 ? '${one.substring(0, 57)}…' : one,
          c,
        ]);
  }

  Future<ChatItem?> item(String id) async {
    final r = await db.query('assistant_chat', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : ChatItem.fromRow(r.first);
  }

  Future<ChatItem> _add(String role, String text,
      {String status = '',
      Map<String, dynamic>? data,
      bool queued = false,
      bool unread = false,
      int? inConv}) async {
    final id = Repository.newId();
    final c = inConv ?? conv;
    await db.insert('assistant_chat', {
      'conv': c,
      'id': id,
      'role': role,
      'text': text,
      'status': status,
      'data': data == null ? null : jsonEncode(data),
      'queued': queued ? 1 : 0,
      'unread': unread ? 1 : 0,
      'created_at': Repository.now(),
    });
    await _touch(c, firstText: role == ChatRole.user ? text : null);
    changes.value++;
    return (await item(id))!;
  }

  Future<ChatItem> addUser(String text, {Map<String, dynamic>? data}) =>
      _add(ChatRole.user, text, status: ChatStatus.queued, data: data);

  Future<ChatItem> addAssistant(String text,
          {List<NavTarget> nav = const [],
          bool unread = false,
          String? replyTo,
          String? model,
          Map<String, dynamic> extra = const {},
          int? inConv}) =>
      _add(ChatRole.assistant, text,
          data: {
            if (nav.isNotEmpty) 'nav': [for (final n in nav) navJson(n)],
            'reply_to': ?replyTo,
            'model': ?model,
            ...extra,
          },
          unread: unread,
          inConv: inConv);

  Future<ChatItem> addCard(String tool, Map<String, dynamic> input, PendingWrite card,
          {bool unread = false, int? inConv}) =>
      _add(ChatRole.card, card.title,
          inConv: inConv,
          status: ChatStatus.pending,
          data: {
            'tool': tool,
            'input': input,
            'fields': [
              for (final f in card.fields)
                {
                  'key': f.key,
                  'label': f.label,
                  'value': f.value,
                  'editable': f.editable,
                  if (f.choices.isNotEmpty) 'choices': f.choices,
                }
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

  Future<List<Map<String, dynamic>>> history({int? inConv}) async => [
        for (final r in await db.query('assistant_history',
            where: 'conv = ?', whereArgs: [inConv ?? conv], orderBy: 'seq'))
          jsonDecode(r['msg'] as String) as Map<String, dynamic>
      ];

  Future<void> appendHistory(Iterable<Map<String, dynamic>> messages, {int? inConv}) async {
    for (final m in messages) {
      await db.insert('assistant_history', {'msg': jsonEncode(m), 'conv': inConv ?? conv});
    }
  }
}
