import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../services/voice_input.dart';
import '../ui/common.dart';
import '../ui/guide_bubble.dart';
import '../ui/icons.dart' show queenTagChoices;
import '../ui/theme.dart';
import '../ui/voice_input_bar.dart';
import 'assistant_links.dart';
import 'assistant_nav.dart';
import 'assistant_persona.dart';
import 'assistant_queue.dart';
import 'assistant_store.dart';
import 'assistant_tools.dart';
import 'assistant_voice.dart';

/// Чат із помічником «Пасічник»: відповіді - хмарками пасічника,
/// повідомлення людини - праворуч зі станом черги, картки «Записати так?».
/// Історія - лише на цьому телефоні; «Нова розмова» - з чистого аркуша.
class AssistantChatScreen extends StatefulWidget {
  final Repository repo;
  final AssistantQueue queue;

  /// Відкрити екран (тести підставляють свій).
  final Navigate? navigate;

  /// Голос (тести підставляють свій): розпізнавання й читання вголос.
  final ChatVoice? voice;
  final ReplySpeaker? speaker;
  const AssistantChatScreen({
    super.key,
    required this.repo,
    required this.queue,
    this.navigate,
    this.voice,
    this.speaker,
  });

  /// Відкрити чат (з головного, карти, поштомату). Без черги (сервер ще не
  /// запущено) - нічого.
  static Future<void> open(NavigatorState nav, Repository repo) async {
    final q = AssistantQueue.current;
    if (q == null) return;
    await nav.push(
      MaterialPageRoute(
        builder: (_) => AssistantChatScreen(repo: repo, queue: q),
      ),
    );
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

  // голос
  late final ChatVoice _voice = widget.voice ?? PhoneVoice();
  late final ReplySpeaker _speaker = widget.speaker ?? PhoneSpeaker();
  final _dictation = Dictation();
  bool _listening = false;
  bool _starting = false;
  Timer? _stopLimit;
  double? _download;
  bool _speak = false;
  bool _noUkVoice = false;

  /// Відповіді, що вже були на екрані (читаємо вголос лише нові).
  int _seenSeq = 1 << 62;

  @override
  void initState() {
    super.initState();
    final q = widget.queue;
    // свій великий мікрофон - без загальної смужки «Голосовий ввід»
    VoiceInputHost.ownMicrophone(_input);
    q.presenter = _present;
    q.navigator =
        widget.navigate ?? (t) => openAssistantTarget(Navigator.of(context), widget.repo, t);
    q.onUndoable = (u) => _lastUndo = u;
    store.changes.addListener(_reload);
    unawaited(_start());
  }

  Future<void> _start() async {
    await store.load();
    // відкрили з поштомата: непрочитана відповідь може бути в іншій розмові
    final unread = await store.firstUnread();
    if (unread != null && unread.conv != store.conv) await store.switchTo(unread.conv);
    // живі картки з минулого разу (застосунок закрили, не відповівши) -
    // запис не зроблено
    for (final c in await store.items()) {
      if (c.isCard && c.status == ChatStatus.pending && c.data['input']?['_live'] == true) {
        await store.update(c.id, {'status': ChatStatus.rejected});
      }
    }
    _firstUnread = (await store.firstUnread())?.id;
    _speak = await AssistantVoiceSettings.speak(widget.repo);
    await _reload();
    _seenSeq = _items.isEmpty ? 0 : _items.last.seq;
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
    _stopLimit?.cancel();
    if (_listening) unawaited(_voice.cancel());
    unawaited(_speaker.stop());
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
    // нові відповіді, поки чат відкрито - уголос (якщо ввімкнено)
    final fresh = [
      for (final i in items)
        if (i.role == ChatRole.assistant && i.seq > _seenSeq) i,
    ];
    if (items.isNotEmpty && items.last.seq > _seenSeq) _seenSeq = items.last.seq;
    if (_speak && fresh.isNotEmpty && !_noUkVoice) {
      final ok = await _speaker.speak(
        plainAssistantText(fresh.last.text),
        persona: AssistantPersona.of(fresh.last.data['model'] as String?),
      );
      if (!ok && mounted) {
        _noUkVoice = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.assistantNoUkVoice)));
      }
    }
    if (widget.queue.chatVisible) unawaited(widget.queue.markAllRead());
    if (grew) _toBottom();
  }

  /// Торкнулися посилання у відповіді - відкрити екран (вулик, пасіку…).
  Future<void> _openLink(AssistantLink l) async {
    final t = await AssistantTools(
      widget.repo,
      confirm: (_) async => null,
    ).targetFor(l.screen, l.id);
    if (t == null || !mounted) return;
    final nav = widget.navigate;
    if (nav != null) {
      await nav(t);
    } else {
      await openAssistantTarget(Navigator.of(context), widget.repo, t);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
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
    await store.update(card.id, {
      'status': values == null ? ChatStatus.rejected : ChatStatus.confirmed,
    });
    if (values != null) {
      // «Скасувати» з'явиться, щойно інструмент запише (onUndoable)
      _pendingUndoCard = card.id;
    }
    return values;
  }

  String? _pendingUndoCard;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (_busy) return;
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
      widget.queue.noteUndone(u.label);
      setState(() => _undone.add(c.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ---------------------------------------------------------------------
  // голос: дотик - слухаю, ще дотик (або пауза) - стоп; сказане пишеться в
  // поле вводу - видно, що розпізнано, можна виправити й надіслати.
  // (Утримувати кнопку не треба: розпізнавач вмикається із затримкою, і
  // коротке натискання вимикало його раніше, ніж людина почала говорити.)

  void _say(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Питання чи відповідь - у буфер обміну (без розмітки посилань).
  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: plainAssistantText(text)));
    _say(tr.assistantCopied);
  }

  Widget _copyButton(ChatItem it) => SizedBox(
    height: 30,
    child: IconButton(
      key: ValueKey('assistant-copy-${it.id}'),
      tooltip: tr.assistantCopy,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: () => _copy(it.text),
      icon: Icon(Icons.copy_rounded, size: 18, color: AppColors.textMuted),
    ),
  );

  /// Що було в полі до диктування (сказане дописується після).
  String _prefix = '';

  Future<void> _micTap() async {
    if (_starting || _download != null) return;
    if (_listening) {
      await _stopVoice();
      return;
    }
    unawaited(_speaker.stop());
    if (await widget.repo.getMeta(AssistantVoiceSettings.micExplainedKey) != '1') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.popupBg,
          title: Text(tr.assistantMicExplainTitle, style: TextStyle(color: AppColors.text)),
          content: Text(tr.assistantMicExplain, style: TextStyle(color: AppColors.text)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.assistantMicExplainOk)),
          ],
        ),
      );
      await widget.repo.setMeta(AssistantVoiceSettings.micExplainedKey, '1');
      return;
    }
    setState(() => _starting = true);
    _dictation.clear();
    _prefix = _input.text.trimRight();
    final r = await _voice.start(_onVoice);
    if (!mounted) return;
    setState(() {
      _starting = false;
      _listening = r == VoiceStart.ok;
    });
    switch (r) {
      case VoiceStart.ok:
        break;
      case VoiceStart.needModel:
        await _offerModel();
      case VoiceStart.noPermission:
        _say(tr.assistantNoMic);
      case VoiceStart.offlineUnavailable:
        _say(tr.assistantVoiceOffline);
      case VoiceStart.unavailable:
        _say(tr.assistantVoiceUnavailable);
    }
  }

  Future<void> _stopVoice() async {
    await _voice.stop();
    // остаточний текст має прийти одразу; ні - лишаємо, що є
    _stopLimit?.cancel();
    _stopLimit = Timer(const Duration(seconds: 3), _finishVoice);
  }

  void _onVoice(VoiceText t) {
    if (!mounted || !_listening) return;
    setState(() => _voice.phrases ? _dictation.add(t) : _dictation.replace(t));
    _showDictation();
    if (t.isFinal) _finishVoice();
  }

  /// Сказане - у поле вводу (одразу, поки людина говорить).
  void _showDictation() {
    final d = _dictation.text;
    final text = [if (_prefix.isNotEmpty) _prefix, if (d.isNotEmpty) d].join(' ');
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _finishVoice() {
    _stopLimit?.cancel();
    if (!mounted || !_listening) return;
    final heard = _dictation.text.trim();
    _dictation.clear();
    setState(() => _listening = false);
    if (heard.isEmpty) _say(tr.assistantNotHeard);
  }

  Future<void> _offerModel() async {
    final go = await showConfirm(
      context,
      title: tr.assistantTitle,
      text: tr.assistantVoiceModel(kVoskModelMb),
      confirmText: tr.assistantVoiceDownload,
      danger: false,
    );
    if (!go || !mounted) return;
    setState(() => _download = 0);
    try {
      await VoiceInput.instance.download(
        onProgress: (p) {
          if (mounted) setState(() => _download = p);
        },
        cancelled: () => !mounted,
      );
      _say(tr.assistantVoiceReady);
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) setState(() => _download = null);
    }
  }

  /// «Нова розмова»: стара лишається в списку «Розмови».
  Future<void> _newChat() async {
    _undo.clear();
    _undone.clear();
    if (!await store.newConversation()) _say(tr.assistantConvEmpty);
  }

  Future<void> _conversations() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      builder: (_) => _ConversationsSheet(
        store: store,
        onSwitched: () {
          _undo.clear();
          _undone.clear();
        },
      ),
    );
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (!widget.queue.model.isRemote)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: CapsuleLabel(tr.assistantDemo),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                children: [
                  ValueListenableBuilder<AssistantPersona>(
                    valueListenable: AssistantPrefs.persona,
                    builder: (_, _, _) => _assistantBubble(tr.assistantGreeting),
                  ),
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
                      child: Text(
                        tr.assistantThinking(AssistantPrefs.persona.value.name),
                        style: TextStyle(color: AppColors.textMuted, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
            if (_offline)
              Container(
                width: double.infinity,
                color: AppColors.warning,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  tr.assistantOffline,
                  key: const ValueKey('assistant-offline'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            if (_listening || _starting || _download != null) _voiceStrip(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
    child: Row(
      children: [
        CircleIconButton(
          icon: 'back_arrow',
          bg: AppColors.roundBtn,
          iconColor: AppColors.text,
          size: 44,
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ValueListenableBuilder<AssistantPersona>(
            valueListenable: AssistantPrefs.persona,
            builder: (_, p, _) => Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('assistant-conversations'),
          tooltip: tr.assistantConversations,
          onPressed: _conversations,
          icon: Icon(Icons.forum_outlined, color: AppColors.create, size: 26),
        ),
        IconButton(
          key: const ValueKey('assistant-new-chat'),
          tooltip: tr.assistantNewChat,
          onPressed: _newChat,
          icon: Icon(Icons.add_comment_outlined, color: AppColors.create, size: 28),
        ),
      ],
    ),
  );

  Widget _avatar(AssistantPersona p) => Container(
    width: 44,
    height: 44,
    margin: const EdgeInsets.only(right: 2, bottom: 2),
    decoration: BoxDecoration(
      color: AppColors.card,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.hive, width: 1.5),
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.asset(
      p.image,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
    ),
  );

  Widget _assistantBubble(
    String text, {
    List<Widget> below = const [],
    AssistantPersona? persona,
    VoidCallback? onLongPress,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10, right: 32),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _avatar(persona ?? AssistantPrefs.persona.value),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: SpeechBubble(
                  child: LinkedText(
                    text,
                    style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.35),
                    linkStyle: TextStyle(
                      color: AppColors.create,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.create,
                    ),
                    onOpen: _openLink,
                  ),
                ),
              ),
              ...below,
            ],
          ),
        ),
      ],
    ),
  );

  Widget _reply(ChatItem it) => _assistantBubble(
    it.text,
    persona: AssistantPersona.of(it.data['model'] as String?),
    below: [
      for (final n in it.offeredNav)
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 4),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.create,
              side: BorderSide(color: AppColors.create),
            ),
            onPressed: () => openAssistantTarget(Navigator.of(context), widget.repo, n),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(tr.assistantOpenTarget(n.label)),
          ),
        ),
      Padding(padding: const EdgeInsets.only(left: 4), child: _copyButton(it)),
    ],
    onLongPress: () => _copy(it.text),
  );

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onLongPress: () => _copy(it.text),
            child: Container(
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
              child: Text(
                it.text,
                style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.3),
              ),
            ),
          ),
          if (!(waiting || failed || it.status == ChatStatus.sending)) _copyButton(it),
          if (waiting || failed || it.status == ChatStatus.sending)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.schedule,
                  size: 14,
                  color: failed ? AppColors.danger : AppColors.textMuted,
                ),
                Text(
                  failed
                      ? [tr.assistantFailed, ?error].join(': ')
                      : waiting
                      ? tr.assistantWaiting
                      : tr.assistantSending,
                  style: failed ? muted.copyWith(color: AppColors.danger) : muted,
                ),
                if (failed)
                  TextButton(
                    onPressed: () => widget.queue.retry(it.id),
                    child: Text(tr.assistantRetry),
                  ),
                if (failed || waiting)
                  TextButton(
                    onPressed: () => widget.queue.remove(it.id),
                    child: Text(tr.assistantDelete, style: TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _card(ChatItem it) {
    final w = it.card!;
    final pending = it.status == ChatStatus.pending;
    final edits = _edits.putIfAbsent(
      it.id,
      () => {
        for (final f in w.fields)
          if (f.editable) f.key: TextEditingController(text: f.value),
      },
    );
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.assistantCardTitle, style: label),
            Text(
              w.title,
              style: TextStyle(color: AppColors.create, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final f in w.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: pending && f.editable && f.choices.isNotEmpty
                    ? _choiceField(it, f, edits[f.key]!, label)
                    : pending && f.editable
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
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${f.label}: ', style: label),
                            TextSpan(text: edits[f.key]?.text ?? f.value, style: value),
                          ],
                        ),
                      ),
              ),
            if (it.error != null && pending)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(it.error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            const SizedBox(height: 8),
            if (pending)
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      key: ValueKey('card-yes-${it.id}'),
                      text: tr.assistantYes,
                      bg: AppColors.accent,
                      onPressed: () => _answer(it, true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PillButton(
                      key: ValueKey('card-no-${it.id}'),
                      text: tr.assistantNo,
                      bg: AppColors.neutralBtn,
                      fg: AppColors.text,
                      onPressed: () => _answer(it, false),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(
                    it.status == ChatStatus.confirmed && !_undone.contains(it.id)
                        ? Icons.check_circle
                        : Icons.remove_circle_outline,
                    size: 18,
                    color: it.status == ChatStatus.confirmed
                        ? AppColors.addObject
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _undone.contains(it.id)
                          ? tr.assistantUndone
                          : it.status == ChatStatus.confirmed
                          ? tr.assistantSaved
                          : tr.assistantRejected,
                      style: label,
                    ),
                  ),
                  if (_undo.containsKey(it.id) && !_undone.contains(it.id))
                    TextButton(
                      key: ValueKey('card-undo-${it.id}'),
                      onPressed: () => _undoCard(it),
                      child: Text(tr.assistantUndo),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _voiceStrip() {
    final text = _download != null
        ? tr.assistantVoiceDownloading((_download! * 100).round())
        : tr.assistantListening;
    return Container(
      key: const ValueKey('assistant-voice-strip'),
      width: double.infinity,
      color: AppColors.popupBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(_download != null ? Icons.download : Icons.mic, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Велика кнопка-мікрофон (зручно й у рукавицях): дотик - слухаю, ще
  /// дотик - стоп.
  Widget _micButton() => Tooltip(
    message: tr.assistantMicHold,
    child: Semantics(
      button: true,
      label: tr.assistantMicHold,
      child: GestureDetector(
        key: const ValueKey('assistant-mic'),
        onTap: _micTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _listening ? 76 : 64,
          height: _listening ? 76 : 64,
          decoration: BoxDecoration(
            color: _listening ? AppColors.danger : AppColors.hive,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.frame, width: 2),
          ),
          child: Icon(
            _listening ? Icons.stop : Icons.mic,
            color: Colors.white,
            size: _listening ? 40 : 34,
          ),
        ),
      ),
    ),
  );

  /// Поле картки з вибором: колір мітки матки - кольоровими кружечками,
  /// список і Так/Ні - кнопками.
  Widget _choiceField(ChatItem it, WriteField f, TextEditingController c, TextStyle label) {
    final colors = {for (final q in queenTagChoices) q.$1: q.$2};
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (_, v, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label, style: label),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ch in f.choices)
                ChoiceChip(
                  key: ValueKey('card-${it.id}-${f.key}-$ch'),
                  label: Text(ch),
                  avatar: colors.containsKey(ch)
                      ? CircleAvatar(
                          radius: 9,
                          backgroundColor: colors[ch] ?? Colors.transparent,
                          child: colors[ch] == null ? const Icon(Icons.block, size: 14) : null,
                        )
                      : null,
                  selected: v.text == ch,
                  onSelected: (_) => c.text = ch,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputBar() => Container(
    color: AppColors.panel,
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, v, _) => v.text.trim().isEmpty || _listening
                        ? const SizedBox.shrink()
                        : IconButton(
                            key: const ValueKey('assistant-mic-more'),
                            tooltip: tr.assistantMicHold,
                            onPressed: _micTap,
                            icon: Icon(Icons.mic, color: AppColors.create),
                          ),
                  ),
                  filled: true,
                  fillColor: AppColors.input,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // слухаю або поле порожнє - великий мікрофон; є текст - «Надіслати»
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, v, _) => _listening || _starting || (v.text.trim().isEmpty && !_busy)
                  ? _micButton()
                  : IconButton.filled(
                      key: const ValueKey('assistant-send'),
                      tooltip: tr.assistantSend,
                      style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                      onPressed: _busy ? null : _send,
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: _chooserChip()),
      ],
    ),
  );

  /// Плашка «Ведмедик · Середня»: хто допомагає й наскільки глибоко думає.
  Widget _chooserChip() => ListenableBuilder(
    listenable: Listenable.merge([AssistantPrefs.persona, AssistantPrefs.effort]),
    builder: (_, _) {
      final p = AssistantPrefs.persona.value;
      return Semantics(
        button: true,
        label: '${tr.assistantWhoHelps}: ${p.name}',
        child: InkWell(
          key: const ValueKey('assistant-chooser'),
          borderRadius: BorderRadius.circular(20),
          onTap: _choose,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: Image.asset(
                    p.image,
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: p.name,
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: '  ${effortLabel(AssistantPrefs.effort.value)}',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Icon(Icons.expand_more, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// Знизу - хто допомагає (Ведмедик / Пасічник) і глибина міркувань.
  Future<void> _choose() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.popupBg,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([AssistantPrefs.persona, AssistantPrefs.effort]),
        builder: (_, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.assistantWhoHelps,
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final p in AssistantPersona.values)
                _option(
                  key: ValueKey('persona-${p.model}'),
                  selected: AssistantPrefs.persona.value == p,
                  leading: ClipOval(
                    child: Image.asset(
                      p.image,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  title: p.name,
                  subtitle: p.hint,
                  onTap: () => AssistantPrefs.setPersona(widget.repo, p),
                ),
              const SizedBox(height: 14),
              Text(
                tr.assistantEffort,
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700),
              ),
              Text(
                tr.assistantEffortHintText,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              for (final e in kAssistantEfforts)
                _option(
                  key: ValueKey('effort-$e'),
                  selected: AssistantPrefs.effort.value == e,
                  title: effortLabel(e),
                  onTap: () => AssistantPrefs.setEffort(widget.repo, e),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _option({
    required Key key,
    required bool selected,
    required String title,
    String? subtitle,
    Widget? leading,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.hive : AppColors.neutralBtn, width: 1.5),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: AppColors.create),
          ],
        ),
      ),
    ),
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
          child: ValueListenableBuilder<AssistantPersona>(
            valueListenable: AssistantPrefs.persona,
            builder: (_, p, _) => Image.asset(
              p.image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Список розмов: відкрити стару, видалити.
class _ConversationsSheet extends StatefulWidget {
  final AssistantStore store;
  final VoidCallback onSwitched;
  const _ConversationsSheet({required this.store, required this.onSwitched});

  @override
  State<_ConversationsSheet> createState() => _ConversationsSheetState();
}

class _ConversationsSheetState extends State<_ConversationsSheet> {
  List<Conversation> _list = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final l = await widget.store.conversations();
    if (mounted) setState(() => _list = l);
  }

  String _when(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                tr.assistantConversations,
                style: TextStyle(color: AppColors.text, fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in _list)
                    ListTile(
                      key: ValueKey('assistant-conv-${c.id}'),
                      selected: c.id == store.conv,
                      selectedTileColor: AppColors.card,
                      leading: Icon(
                        c.id == store.conv ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        color: AppColors.create,
                      ),
                      title: Text(
                        c.title.isEmpty ? tr.assistantConvUntitled : c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${_when(c.updatedAt)} · ${c.messages}',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                      trailing: IconButton(
                        key: ValueKey('assistant-conv-delete-${c.id}'),
                        tooltip: tr.assistantConvDelete,
                        icon: Icon(Icons.delete_outline, color: AppColors.textMuted),
                        onPressed: () async {
                          final ok = await showConfirm(
                            context,
                            title: tr.assistantConvDelete,
                            text: tr.assistantConvDeleteText,
                          );
                          if (!ok) return;
                          await store.deleteConversation(c.id);
                          widget.onSwitched();
                          await _load();
                        },
                      ),
                      onTap: () async {
                        widget.onSwitched();
                        await store.switchTo(c.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
