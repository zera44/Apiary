import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../data/repository.dart';
import 'app_config.dart';

/// Повідомлення розмови з розробником.
class FeedbackMsg {
  final int id;
  final int? remoteSeq;
  final bool fromDev;
  final String body;
  final DateTime at;

  /// Ще не дійшло до сервера (без інтернету) - піде саме.
  final bool pending;
  final bool unread;
  const FeedbackMsg(this.id, this.remoteSeq, this.fromDev, this.body, this.at, this.pending, this.unread);
}

/// Чим закінчилася відправка.
enum FeedbackSend {
  sent,

  /// Не вдалося зараз - збережено, надішлеться, щойно буде зв'язок.
  queued,
}

/// Розмова з розробником (Налаштування → «Відгук»): людина пише, розробник
/// відповідає зі своєї адмін-сторінки - відповідь приходить сюди як нове
/// повідомлення, а на вулику-поштоматі з'являється значок.
///
/// Без входу: застосунок сам створює `device_id` і `secret` (лише на цьому
/// телефоні, у резервну копію не потрапляють), сервер зберігає хеш `secret`.
/// Сервер - функція `feedback` (supabase/functions/feedback). Розмова
/// зберігається й на телефоні (таблиця feedback_chat).
class FeedbackChat {
  final Repository repo;
  final http.Client? client;
  final Uri? endpoint;
  final DateTime Function() now;

  FeedbackChat(this.repo, {this.client, Uri? endpoint, DateTime Function()? now})
      : endpoint = endpoint ?? serverEndpoint(AppConfig.current),
        now = now ?? DateTime.now;

  /// Поточна розмова застосунку (екран, поштомат, фонове завдання).
  static FeedbackChat? current;

  static const idKey = 'device_feedback_id';
  static const secretKey = 'device_feedback_secret';

  /// Найбільший номер повідомлення сервера, який уже забрано опитуванням.
  /// Власні надіслані сюди не входять: інакше відповідь розробника, що
  /// з'явилася, поки відгук чекав на інтернет, лишилася б позаду.
  static const afterKey = 'device_feedback_after';

  /// Адреса функції; null - сервера в збірці немає (тоді старий лист через
  /// форму, див. FeedbackService).
  static Uri? serverEndpoint(AppConfig c) {
    final base = c.supabaseBase;
    return base == null ? null : base.replace(path: '${base.path}/functions/v1/feedback');
  }

  bool get available => endpoint != null;

  /// Нових відповідей розробника, яких людина ще не бачила (значок на
  /// поштоматі).
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Змінилася розмова (нове повідомлення, стан).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------
  // дані на телефоні

  Future<List<FeedbackMsg>> messages() async => [
        for (final r in await repo.db.query('feedback_chat', orderBy: 'id'))
          FeedbackMsg(
            r['id'] as int,
            r['remote_seq'] as int?,
            r['from_dev'] == 1,
            r['body'] as String,
            DateTime.fromMillisecondsSinceEpoch(((r['at'] as num) * 1000).round()),
            r['pending'] == 1,
            r['unread'] == 1,
          ),
      ];

  /// Чи людина вже писала (є що опитувати).
  Future<bool> hasThread() async => await repo.getMeta(idKey) != null;

  Future<void> refreshUnread() async {
    final r = await repo.db.rawQuery('SELECT COUNT(*) AS n FROM feedback_chat WHERE unread = 1');
    unread.value = (r.first['n'] as int?) ?? 0;
  }

  Future<void> markRead() async {
    final n = await repo.db.rawUpdate('UPDATE feedback_chat SET unread = 0 WHERE unread = 1');
    if (n > 0) changes.value++;
    await refreshUnread();
  }

  Future<({String id, String secret})> _identity() async {
    var id = await repo.getMeta(idKey);
    var secret = await repo.getMeta(secretKey);
    if (id == null || secret == null) {
      const u = Uuid();
      id = u.v4();
      secret = '${u.v4()}${u.v4()}'.replaceAll('-', '');
      await repo.setMeta(idKey, id);
      await repo.setMeta(secretKey, secret);
    }
    return (id: id, secret: secret);
  }

  Future<int> _lastSeq() async => int.tryParse(await repo.getMeta(afterKey) ?? '') ?? 0;

  // ---------------------------------------------------------------------
  // сервер

  Future<Map<String, dynamic>?> _call(Map<String, dynamic> body) async {
    final e = endpoint;
    if (e == null) return null;
    final c = client ?? http.Client();
    try {
      final id = await _identity();
      final r = await c
          .post(e,
              headers: const {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode({...body, 'device_id': id.id, 'secret': id.secret}))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  static String _platform() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Надіслати відгук: одразу у стрічку; не вдалося - лишається «чекає» і
  /// піде при наступному опитуванні.
  Future<FeedbackSend> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return FeedbackSend.queued;
    final id = await repo.db.insert('feedback_chat', {
      'from_dev': 0,
      'body': body,
      'at': now().millisecondsSinceEpoch / 1000,
      'pending': 1,
      'unread': 0,
    });
    changes.value++;
    await _identity();
    return await _push(id, body) ? FeedbackSend.sent : FeedbackSend.queued;
  }

  Future<bool> _push(int localId, String body) async {
    final r = await _call({'action': 'send', 'body': body, 'platform': _platform()});
    final m = r?['message'] as Map<String, dynamic>?;
    if (m == null) return false;
    await repo.db.update('feedback_chat', {'remote_seq': m['seq'], 'pending': 0},
        where: 'id = ? AND remote_seq IS NULL', whereArgs: [localId]);
    changes.value++;
    return true;
  }

  /// Надіслати те, що чекало; потім забрати нові повідомлення. Повертає
  /// відповіді розробника, що з'явилися зараз (для сповіщення).
  Future<List<FeedbackMsg>> poll() async {
    if (!available || !await hasThread()) return const [];
    for (final r in await repo.db.query('feedback_chat', where: 'pending = 1', orderBy: 'id')) {
      if (!await _push(r['id'] as int, r['body'] as String)) break;
    }
    final res = await _call({'action': 'poll', 'after_seq': await _lastSeq()});
    final list = res?['messages'] as List?;
    final fresh = <FeedbackMsg>[];
    var top = await _lastSeq();
    for (final m in list ?? const []) {
      final seq = (m['seq'] as num).toInt();
      if (seq > top) top = seq;
      final exists = await repo.db.query('feedback_chat',
          columns: ['id'], where: 'remote_seq = ?', whereArgs: [seq], limit: 1);
      if (exists.isNotEmpty) continue;
      final fromDev = m['from_dev'] == true;
      final at = DateTime.tryParse('${m['at']}') ?? now();
      final localId = await repo.db.insert('feedback_chat', {
        'remote_seq': seq,
        'from_dev': fromDev ? 1 : 0,
        'body': m['body'] as String,
        'at': at.millisecondsSinceEpoch / 1000,
        'pending': 0,
        'unread': fromDev ? 1 : 0,
      });
      if (fromDev) {
        fresh.add(FeedbackMsg(localId, seq, true, m['body'] as String, at, false, true));
      }
    }
    if (list != null && list.isNotEmpty) {
      await repo.setMeta(afterKey, '$top');
      changes.value++;
    }
    await refreshUnread();
    return fresh;
  }

  // ---------------------------------------------------------------------
  // поки застосунок відкритий

  Timer? _timer;

  /// Опитувати раз на кілька хвилин (лише якщо людина вже писала).
  Future<void> start() async {
    current = this;
    await refreshUnread();
    unawaited(poll());
    _timer ??= Timer.periodic(const Duration(minutes: 3), (_) => unawaited(poll()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (identical(current, this)) current = null;
  }
}
