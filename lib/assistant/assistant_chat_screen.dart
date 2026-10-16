import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/common.dart';
import '../ui/guide_bubble.dart';
import '../ui/theme.dart';
import 'assistant_nav.dart';
import 'assistant_queue.dart';
import 'assistant_store.dart';
import 'assistant_tools.dart';

/// Чат із помічником «Пасічник»: відповіді - хмарками пасічника,
/// повідомлення людини - праворуч зі станом черги, картки «Записати так?».
/// Історія - лише на цьому телефоні; «Нова розмова» - з чистого аркуша.
class AssistantChatScreen extends StatefulWidget {
  final Repository repo;
  final AssistantQueue queue;

  /// Відкрити екран (тести підставляють свій).
  final Navigate? navigate;
  const AssistantChatScreen({super.key, required this.repo, required this.queue, this.navigate});

  /// Відкрити чат (з головного, карти, поштомату). Без черги (сервер ще не
  /// запущено) - нічого.
  static Future<void> open(NavigatorState nav, Repository repo) async {
    final q = AssistantQueue.current;
    if (q == null) return;
    await nav.push(MaterialPageRoute(builder: (_) => AssistantChatScreen(repo: repo, queue: q)));
  }

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  AssistantStore get store => widget.queue.store;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _firstUnreadKey = GlobalKey();
  List<ChatItem> _items = const [];
  String? _firstUnread;
  bool _busy = false;
  bool _offline = false;

  /// Картки, що чекають відповіді просто зараз (жива розмова).
  final _live = <String, Completer<Map<String, String>?>>{};

  /// Виправлені значення полів карток: id картки -> ключ поля -> текст.
  final _edits = <String, Map<String, TextEditingController>>{};

  /// Що можна скасувати (лише поки чат відкрито): id картки -> запис.
  final _undo = <String, UndoEntry>{};
  final _undone = <String>{};
  UndoEntry? _lastUndo;

  @override
  void initState() {
    super.initState();
    final q = widget.queue;
    q.presenter = _present;
    q.navigator = widget.navigate ?? (t) => openAssistantTarget(Navigator.of(context), widget.repo, t);
    q.onUndoable = (u) => _lastUndo = u;
    store.changes.addListener(_reload);
    unawaited(_start());
  }

  Future<void> _start() async {
    // живі картки з минулого разу (застосунок закрили, не відповівши) -
    // запис не зроблено
    for (final c in await store.items()) {
      if (c.isCard && c.status == ChatStatus.pending && c.data['input']?['_live'] == true) {
        await store.update(c.id, {'status': ChatStatus.rejected});
      }
    }
    _firstUnread = (await store.firstUnread())?.id;
    await _reload();
    await widget.queue.markAllRead();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _firstUnreadKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.1);
      } else {
        _toBottom();
      }
    });
    unawaited(widget.queue.process());
  }

  @override
  void dispose() {
    final q = widget.queue;
    if (q.presenter == _present) {
      q.presenter = null;
      q.navigator = null;
      q.onUndoable = null;
    }
    store.changes.removeListener(_reload);
    for (final c in _live.values) {
      if (!c.isCompleted) c.complete(null);
    }
    for (final m in _edits.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await store.items();
    if (!mounted) return;
    final grew = items.length > _items.length;
    setState(() => _items = items);
    if (widget.queue.chatVisible) unawaited(widget.queue.markAllRead());
    if (grew) _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  /// Жива картка: показати в стрічці й чекати «Так» / «Ні».
  Future<Map<String, String>?> _present(PendingWrite w) async {
    final card = await store.addCard(w.tool, {'_live': true}, w);
    final done = Completer<Map<String, String>?>();
    _live[card.id] = done;
    final values = await done.future;
    _live.remove(card.id);
    await store.update(card.id, {'status': values == null ? ChatStatus.rejected : ChatStatus.confirmed});
    if (values != null) {
      // «Скасувати» з'явиться, щойно інструмент запише (onUndoable)
      _pendingUndoCard = card.id;
    }
    return values;
  }

  String? _pendingUndoCard;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _busy = true;
      _offline = false;
    });
    _lastUndo = null;
    final online = await widget.queue.submit(text);
    _bindUndo();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _offline = !online;
    });
  }

  void _bindUndo() {
    final card = _pendingUndoCard, u = _lastUndo;
    if (card != null && u != null) _undo[card] = u;
    _pendingUndoCard = null;
    _lastUndo = null;
  }

  Map<String, String> _values(ChatItem c) => {
        for (final f in c.card!.fields) f.key: _edits[c.id]?[f.key]?.text ?? f.value,
      };

  Future<void> _answer(ChatItem c, bool yes) async {
    final live = _live[c.id];
    if (live != null) {
      live.complete(yes ? _values(c) : null);
      return;
    }
    _lastUndo = null;
    final out = await widget.queue.answerCard(c.id, yes ? _values(c) : null);
    if (out != null && !out.isError && _lastUndo != null) _undo[c.id] = _lastUndo!;
    _lastUndo = null;
    if (out != null && out.isError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(out.content)));
    }
  }

  Future<void> _undoCard(ChatItem c) async {
    final u = _undo[c.id];
    if (u == null) return;
    try {
      await u.undo();
      setState(() => _undone.add(c.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _newChat() async {
    final ok = await showConfirm(context,
        title: tr.assistantNewChat,
        text: tr.assistantNewChatConfirm,
        confirmText: tr.assistantNewChat,
        danger: false);
    if (!ok) return;
    _undo.clear();
    _undone.clear();
    await store.newConversation();
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          _header(),
          if (!widget.queue.model.isRemote) Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CapsuleLabel(tr.assistantDemo),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              children: [
                _assistantBubble(tr.assistantGreeting),
                for (final it in _items)
                  KeyedSubtree(
                    key: it.id == _firstUnread ? _firstUnreadKey : ValueKey(it.id),
                    child: switch (it.role) {
                      ChatRole.user => _userBubble(it),
                      ChatRole.card => _card(it),
                      _ => _reply(it),
                    },
                  ),
                if (_busy && !_offline)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, top: 4),
                    child: Text(tr.assistantThinking,
                        style: TextStyle(color: AppColors.textMuted, fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
          ),
          if (_offline)
            Container(
              width: double.infinity,
              color: AppColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(tr.assistantOffline,
                  key: const ValueKey('assistant-offline'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          _inputBar(),
        ]),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
        child: Row(children: [
          CircleIconButton(
              icon: 'back_arrow',
              bg: AppColors.roundBtn,
              iconColor: AppColors.text,
              size: 44,
              tooltip: 'Назад',
              onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr.assistantTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            key: const ValueKey('assistant-new-chat'),
            tooltip: tr.assistantNewChat,
            onPressed: _newChat,
            icon: Icon(Icons.add_comment_outlined, color: AppColors.create, size: 28),
          ),
        ]),
      );

  Widget _avatar() => Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(right: 2, bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hive, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset('assets/guide/beekeeper.webp',
            fit: BoxFit.cover, alignment: Alignment.topCenter, filterQuality: FilterQuality.medium),
      );

  Widget _assistantBubble(String text, {List<Widget> below = const []}) => Padding(
        padding: const EdgeInsets.only(bottom: 10, right: 32),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _avatar(),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SpeechBubble(
                child: Text(text,
                    style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.35)),
              ),
              ...below,
            ]),
          ),
        ]),
      );

  Widget _reply(ChatItem it) => _assistantBubble(it.text, below: [
        for (final n in it.offeredNav)
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 4),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.create, side: BorderSide(color: AppColors.create)),
              onPressed: () => openAssistantTarget(Navigator.of(context), widget.repo, n),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(tr.assistantOpenTarget(n.label)),
            ),
          ),
      ]);

  Widget _userBubble(ChatItem it) {
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    final failed = it.status == ChatStatus.failed;
    final waiting = it.status == ChatStatus.queued;
    final error = switch (it.error) {
      'unauthorized' => tr.assistantUnauthorized,
      'server' => tr.assistantServerError,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(3),
            ),
            border: failed ? Border.all(color: AppColors.danger, width: 1.5) : null,
          ),
          child: Text(it.text, style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.3)),
        ),
        if (waiting || failed || it.status == ChatStatus.sending)
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Icon(failed ? Icons.error_outline : Icons.schedule,
                  size: 14, color: failed ? AppColors.danger : AppColors.textMuted),
              Text(
                  failed
                      ? [tr.assistantFailed, ?error].join(': ')
                      : waiting
                          ? tr.assistantWaiting
                          : tr.assistantSending,
                  style: failed ? muted.copyWith(color: AppColors.danger) : muted),
              if (failed)
                TextButton(
                    onPressed: () => widget.queue.retry(it.id), child: Text(tr.assistantRetry)),
              if (failed || waiting)
                TextButton(
                    onPressed: () => widget.queue.remove(it.id),
                    child: Text(tr.assistantDelete, style: TextStyle(color: AppColors.danger))),
            ],
          ),
      ]),
    );
  }

  Widget _card(ChatItem it) {
    final w = it.card!;
    final pending = it.status == ChatStatus.pending;
    final edits = _edits.putIfAbsent(
        it.id, () => {for (final f in w.fields) if (f.editable) f.key: TextEditingController(text: f.value)});
    final label = TextStyle(color: AppColors.textMuted, fontSize: 13);
    final value = TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(left: 46, bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pending ? AppColors.hive : AppColors.neutralBtn, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr.assistantCardTitle, style: label),
          Text(w.title,
              style: TextStyle(color: AppColors.create, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final f in w.fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: pending && f.editable
                  ? TextField(
                      key: ValueKey('card-${it.id}-${f.key}'),
                      controller: edits[f.key],
                      style: value,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: f.label,
                        labelStyle: label,
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.input,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    )
                  : Text.rich(TextSpan(children: [
                      TextSpan(text: '${f.label}: ', style: label),
                      TextSpan(text: edits[f.key]?.text ?? f.value, style: value),
                    ])),
            ),
          if (it.error != null && pending)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(it.error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
          const SizedBox(height: 8),
          if (pending)
            Row(children: [
              Expanded(
                child: PillButton(
                    key: ValueKey('card-yes-${it.id}'),
                    text: tr.assistantYes,
                    bg: AppColors.accent,
                    onPressed: () => _answer(it, true)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                    key: ValueKey('card-no-${it.id}'),
                    text: tr.assistantNo,
                    bg: AppColors.neutralBtn,
                    fg: AppColors.text,
                    onPressed: () => _answer(it, false)),
              ),
            ])
          else
            Row(children: [
              Icon(
                  it.status == ChatStatus.confirmed && !_undone.contains(it.id)
                      ? Icons.check_circle
                      : Icons.remove_circle_outline,
                  size: 18,
                  color: it.status == ChatStatus.confirmed ? AppColors.addObject : AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    _undone.contains(it.id)
                        ? tr.assistantUndone
                        : it.status == ChatStatus.confirmed
                            ? tr.assistantSaved
                            : tr.assistantRejected,
                    style: label),
              ),
              if (_undo.containsKey(it.id) && !_undone.contains(it.id))
                TextButton(
                    key: ValueKey('card-undo-${it.id}'),
                    onPressed: () => _undoCard(it),
                    child: Text(tr.assistantUndo)),
            ]),
        ]),
      ),
    );
  }

  Widget _inputBar() => Container(
        color: AppColors.panel,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              key: const ValueKey('assistant-input'),
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: TextStyle(color: AppColors.text, fontSize: 16),
              decoration: InputDecoration(
                hintText: tr.assistantHint,
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                hintMaxLines: 2,
                filled: true,
                fillColor: AppColors.input,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            key: const ValueKey('assistant-send'),
            tooltip: tr.assistantSend,
            style: IconButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send, color: Colors.white),
          ),
        ]),
      );
}

/// Кнопка виклику пасічника (карта): кругла, з його обличчям.
class AssistantButton extends StatelessWidget {
  final Repository repo;
  final double size;
  const AssistantButton({super.key, required this.repo, this.size = 48});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tr.assistantOpen,
        child: Semantics(
          button: true,
          label: tr.assistantOpen,
          child: GestureDetector(
            onTap: () => AssistantChatScreen.open(Navigator.of(context), repo),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.roundBtn,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hive, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/guide/beekeeper.webp',
                  fit: BoxFit.cover, alignment: Alignment.topCenter, filterQuality: FilterQuality.medium),
            ),
          ),
        ),
      );
}
