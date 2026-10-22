import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import 'assistant_context.dart';
import 'assistant_model.dart';
import 'assistant_session.dart';
import 'assistant_store.dart';
import 'assistant_tools.dart';

/// Черга повідомлень помічнику: без зв'язку повідомлення не губиться -
/// чекає в базі телефона (переживає закриття застосунку) і йде, щойно
/// з'явився інтернет, по порядку. Збій сервера - повтор із паузою; після
/// [maxAttempts] невдач - «не надіслано» («Повторити» / «Видалити»).
///
/// Відповідь на повідомлення, що йшло не одразу (з черги):
/// * екран не відкривається сам - у відповіді кнопка «Відкрити …»;
/// * записи - лише карткою «Так» / «Ні»: чат закрито - картка чекає в
///   чаті;
/// * інструменти читання бачать дані на момент відповіді.
class AssistantQueue {
  final Repository repo;
  final AssistantStore store;
  final AssistantModel model;
  final Future<bool> Function() isOnline;
  final DateTime Function() now;

  /// Фонове завдання дошле, коли застосунок закриють (Android).
  final Future<void> Function()? scheduleBackground;

  AssistantQueue(this.repo, this.store, this.model,
      {Future<bool> Function()? isOnline,
      Stream<bool>? onlineChanges,
      DateTime Function()? now,
      this.scheduleBackground})
      : isOnline = isOnline ?? deviceOnline,
        _onlineChanges = onlineChanges,
        now = now ?? DateTime.now;

  final Stream<bool>? _onlineChanges;

  /// Зв'язок з'явився / зник (за замовчуванням - з системи).
  Stream<bool> get onlineChanges =>
      _onlineChanges ??
      Connectivity().onConnectivityChanged.map((r) => r.any((c) => c != ConnectivityResult.none));

  /// Поточна черга застосунку (для чату й поштомату).
  static AssistantQueue? current;

  static const maxAttempts = 5;

  /// Паузи між повторами після збою.
  static const backoff = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  /// Пауза, якщо зв'язок зник посеред відправки (перевіримо знову).
  static const offlinePause = Duration(seconds: 30);

  /// Чат відкрито: картки - одразу на екрані, навігація - одразу.
  ConfirmWrite? presenter;
  Navigate? navigator;
  void Function(UndoEntry entry)? onUndoable;

  bool get chatVisible => presenter != null;

  /// Скасовані кнопкою «Скасувати» записи: модель дізнається про них із
  /// наступним повідомленням («[Скасовано: …]») - інакше вважала б їх
  /// зробленими.
  final List<String> _undone = [];

  void noteUndone(String label) => _undone.add(label);

  /// Нових відповідей і карток, яких людина не бачила (значок на поштоматі).
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  Future<void> refreshUnread() async => unread.value = await store.unreadCount();

  static Future<bool> deviceOnline() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.any((c) => c != ConnectivityResult.none);
    } catch (_) {
      return true; // без плагіна (тести, комп'ютер) - пробуємо
    }
  }

  Timer? _timer;
  StreamSubscription<bool>? _net;

  /// Поки застосунок відкритий: щойно з'явився інтернет і щохвилини
  /// (повтори після паузи) - дослати чергу.
  Future<void> start() async {
    current = this;
    await store.load();
    await store.releaseStuck();
    await refreshUnread();
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(process()));
    try {
      _net ??= onlineChanges.listen((on) {
        if (on) unawaited(process());
      }, onError: (Object _) {}); // без плагіна - лише щохвилини
    } catch (_) {}
    unawaited(process());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_net?.cancel());
    _net = null;
    if (identical(current, this)) current = null;
  }

  /// Нове повідомлення людини. Повертає false, якщо зв'язку немає (у чаті -
  /// «Немає зв'язку - надішлю, щойно з'явиться»).
  Future<bool> submit(String text, {ScreenContext? context}) async {
    final t = text.trim();
    if (t.isEmpty) return true;
    final online = await isOnline();
    final item = await store.addUser(t, data: context == null ? null : {'ctx': context.toJson()});
    if (!online) {
      await store.update(item.id, {'queued': 1});
      await _scheduleBackground();
      return false;
    }
    await process();
    return true;
  }

  Future<void> retry(String id) async {
    await store.update(id, {'status': ChatStatus.queued, 'attempts': 0, 'next_try': null, 'error': null});
    await process();
  }

  /// Видалити з черги до відправки (чи «не надіслане»).
  Future<bool> remove(String id) async {
    final it = await store.item(id);
    if (it == null || !it.isUser || it.status == ChatStatus.sending || it.status == ChatStatus.sent) {
      return false;
    }
    await store.delete(id);
    return true;
  }

  Future<void>? _running;

  /// Дослати все, що пора. Одночасно - одна відправка.
  Future<void> process() {
    return _running ??= _process().whenComplete(() => _running = null);
  }

  Future<void> _process() async {
    while (true) {
      final item = await store.nextDue(now());
      if (item == null) break;
      if (!await isOnline()) {
        await _scheduleBackground();
        break;
      }
      if (!await store.claim(item.id)) continue;
      final ok = await _send(item);
      if (!ok) break; // зв'язок зник - решта почекає (порядок важливий)
    }
    await refreshUnread();
  }

  /// Одне повідомлення; false - зв'язку немає (далі не йти).
  Future<bool> _send(ChatItem item) async {
    // одразу й у відкритому чаті - як звичайна розмова; інакше - відповідь
    // із черги
    final live = chatVisible && !item.queued && item.attempts == 0;
    final cards = <String>[];
    final tools = AssistantTools(
      repo,
      now: now,
      navigate: live ? navigator : null,
      confirm: presenter ?? (_) async => null,
      defer: live
          ? null
          : (tool, input, card) async =>
              cards.add((await store.addCard(tool, input, card,
                      unread: !chatVisible, inConv: item.conv))
                  .id),
      onUndoable: onUndoable,
    );
    final history = await store.history(inConv: item.conv);
    final start = history.length;
    final session = AssistantSession(model, history: history);
    try {
      final notes = [..._undone];
      // вкладка, про яку людина говорила, коли писала (модель вважає її головною)
      final ctx = ScreenContext.fromJson(item.data['ctx']);
      final base = ctx == null ? item.text : '${item.text}\n\n${ctx.promptLine}';
      final text = notes.isEmpty
          ? base
          : '$base\n\n${[for (final n in notes) '[Скасовано: $n]'].join('\n')}';
      final reply = await session.ask(text, tools: tools.run, today: now());
      _undone.removeRange(0, notes.length);
      await store.appendHistory(session.messages.sublist(start), inConv: item.conv);
      await store.update(item.id, {'status': ChatStatus.sent, 'error': null});
      await store.addAssistant(reply.text,
          nav: tools.offeredNav,
          unread: !chatVisible,
          replyTo: item.id,
          model: reply.model,
          extra: {'routed_from': ?reply.routedFrom},
          inConv: item.conv);
      // картки - після відповіді, що про них каже
      for (final id in cards) {
        final c = (await store.item(id))!;
        await store.delete(id);
        await store.addCard(c.data['tool'] as String, Map<String, dynamic>.from(c.data['input'] as Map),
            c.card!, unread: !chatVisible, inConv: item.conv);
      }
      return true;
    } on AssistantException catch (e) {
      for (final id in cards) {
        await store.delete(id); // повтор створить їх знову
      }
      if (e.kind == AssistantFailure.offline) {
        await store.update(item.id, {
          'status': ChatStatus.queued,
          'queued': 1,
          'next_try': _secs(now().add(offlinePause)),
        });
        await _scheduleBackground();
        return false;
      }
      final attempts = item.attempts + 1;
      if (e.retryable && attempts < maxAttempts) {
        await store.update(item.id, {
          'status': ChatStatus.queued,
          'queued': 1,
          'attempts': attempts,
          'next_try': _secs(now().add(backoff[(attempts - 1).clamp(0, backoff.length - 1)])),
          'error': e.kind.name,
        });
        await _scheduleBackground();
      } else {
        await store.update(item.id,
            {'status': ChatStatus.failed, 'queued': 1, 'attempts': attempts, 'error': e.kind.name});
      }
      return true;
    }
  }

  /// Людина відповіла на картку з черги: «Так» ([values] - поля, можливо
  /// виправлені) чи «Ні» (null).
  Future<ToolOutcome?> answerCard(String id, Map<String, String>? values) async {
    final c = await store.item(id);
    if (c == null || !c.isCard || c.status != ChatStatus.pending) return null;
    if (values == null) {
      await store.update(id, {'status': ChatStatus.rejected, 'unread': 0});
      await refreshUnread();
      return null;
    }
    final out = await AssistantTools.applyDeferred(
        repo, c.data['tool'] as String, Map<String, dynamic>.from(c.data['input'] as Map), values,
        onUndoable: onUndoable, now: now);
    await store.update(id, {
      'status': out.isError ? ChatStatus.pending : ChatStatus.confirmed,
      'error': out.isError ? out.content : null,
      'unread': 0,
    });
    await refreshUnread();
    return out;
  }

  Future<void> markAllRead() async {
    await store.markAllRead();
    await refreshUnread();
  }

  Future<void> _scheduleBackground() async {
    try {
      await scheduleBackground?.call();
    } catch (e) {
      debugPrint('Помічник, фонова відправка: $e');
    }
  }

  static double _secs(DateTime d) => d.microsecondsSinceEpoch / 1e6;
}
