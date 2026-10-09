import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import '../logic/spoken_numbers.dart';
import '../services/voice_input.dart';
import 'theme.dart';

/// Висота смужки з мікрофоном над клавіатурою.
const double kVoiceBarHeight = 46;

/// Вставити сказане [spoken] у поле на місце курсора (виділене - замінюється).
/// Між словами - пробіл; на початку речення - велика літера, якщо [capitalize].
TextEditingValue insertSpoken(TextEditingValue v, String spoken, {bool capitalize = false}) {
  var add = spoken.trim();
  if (add.isEmpty) return v;
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final before = text.substring(0, sel.start);
  final after = text.substring(sel.end);
  final trimmed = before.trimRight();
  final sentenceStart = trimmed.isEmpty || RegExp(r'[.!?]$').hasMatch(trimmed);
  if (capitalize && sentenceStart) add = add[0].toUpperCase() + add.substring(1);
  final lead = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
  final trail = after.isEmpty || RegExp(r'^[\s.,!?;:]').hasMatch(after) ? '' : ' ';
  final ins = '$lead$add$trail';
  final caret = before.length + lead.length + add.length;
  return TextEditingValue(
    text: '$before$ins$after',
    selection: TextSelection.collapsed(offset: caret),
  );
}

bool _isNumeric(EditableText w) => w.keyboardType.index == TextInputType.number.index;

/// Голосовий ввід для ВСІХ текстових полів застосунку: коли відкрита
/// клавіатура для поля, над нею - смужка з мікрофоном. Сказане вставляється
/// в поле з фокусом (у числові - цифрами: «два кома п'ять» -> 2,5).
/// Обгортає весь застосунок (MaterialApp.builder). Без моделі або не на
/// Android - нічого не додає.
class VoiceInputHost extends StatefulWidget {
  final Widget child;
  const VoiceInputHost({super.key, required this.child});

  @override
  State<VoiceInputHost> createState() => _VoiceInputHostState();
}

class _VoiceInputHostState extends State<VoiceInputHost> {
  bool _available = false;
  EditableTextState? _focused;

  /// Поле, у яке зараз диктуємо (null - не слухаємо).
  EditableTextState? _target;
  bool _busy = false; // готуємо модель / запускаємо
  String _partial = '';
  String? _message;
  StreamSubscription<VoskEvent>? _sub;
  Timer? _limit;

  /// Моделі ще немає на телефоні - на смужці кнопка «Скачати».
  bool _offer = false;

  /// Скачування моделі: частка 0..1 (null - не скачуємо).
  double? _downloading;
  bool _cancelDownload = false;

  @override
  void initState() {
    super.initState();
    VoiceInput.instance.available().then((ok) {
      if (!mounted || !ok) return;
      setState(() => _available = true);
      FocusManager.instance.addListener(_onFocus);
      _onFocus();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    _sub?.cancel();
    _limit?.cancel();
    if (_target != null) Vosk.cancel();
    super.dispose();
  }

  EditableTextState? _editable() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return null;
    final s = ctx is StatefulElement && ctx.state is EditableTextState
        ? ctx.state as EditableTextState
        : ctx.findAncestorStateOfType<EditableTextState>();
    if (s == null || s.widget.readOnly) return null;
    return s;
  }

  void _onFocus() {
    final f = _editable();
    if (f == _focused) return;
    // фокус перейшов на інше поле - диктування в старе завершується
    if (_target != null && f != _target) _stop();
    setState(() {
      _focused = f;
      _message = null;
    });
  }

  Future<void> _start() async {
    if (_downloading != null) {
      _cancelDownload = true; // мікрофон під час скачування - «зупинити»
      return;
    }
    final t = _focused;
    if (t == null || _busy || _target != null) return;
    if (!await VoiceInput.instance.modelOnPhone()) {
      _offer = true;
      _say('Для голосу один раз скачайте модель ~$kVoskModelMb МБ (краще через Wi-Fi)');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Готую розпізнавання…';
    });
    try {
      await VoiceInput.instance.ensureReady();
      if (!await Vosk.permission()) {
        _say('Немає дозволу на мікрофон (Налаштування телефону → Дозволи)');
        return;
      }
      _sub ??= Vosk.events.listen(_onEvent);
      await Vosk.start();
      if (!mounted) return;
      setState(() {
        _target = t;
        _partial = '';
        _message = null;
      });
      // запобіжник: мікрофон не лишається увімкненим назавжди
      _limit?.cancel();
      _limit = Timer(const Duration(minutes: 2), _stop);
    } catch (e) {
      _say('Голосовий ввід недоступний: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_downloading != null) return;
    setState(() {
      _offer = false;
      _cancelDownload = false;
      _downloading = 0;
      _message = null;
    });
    try {
      await VoiceInput.instance.download(
        onProgress: (p) {
          if (mounted) setState(() => _downloading = p);
        },
        cancelled: () => _cancelDownload || !mounted,
      );
      _say('Модель готова - натисніть мікрофон і говоріть');
    } catch (e) {
      if (isVoiceDownloadCancelled(e)) {
        _say('Скачування зупинено - наступного разу докачається');
      } else {
        _offer = true;
        _say('Не вдалося скачати модель: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  void _say(String m) {
    if (mounted) setState(() => _message = m);
  }

  void _stop() {
    _limit?.cancel();
    if (_target == null) return;
    Vosk.stop();
    // остаточний текст має прийти одразу; якщо ні - не висіти в «слухаю»
    _limit = Timer(const Duration(seconds: 3), () {
      if (!mounted || _target == null) return;
      Vosk.cancel();
      setState(() {
        _target = null;
        _partial = '';
      });
    });
  }

  void _onEvent(VoskEvent e) {
    final t = _target;
    if (!mounted) return;
    if (e.isPartial) {
      setState(() => _partial = e.text);
      return;
    }
    if (e.isError) {
      setState(() {
        _target = null;
        _partial = '';
        _message = 'Помилка розпізнавання: ${e.text}';
      });
      return;
    }
    if (t != null && t.mounted && e.text.isNotEmpty) _insert(t, e.text);
    if (e.isFinal) _limit?.cancel();
    setState(() {
      _partial = '';
      if (e.isFinal) _target = null;
    });
  }

  void _insert(EditableTextState t, String spoken) {
    final w = t.widget;
    var add = spoken;
    if (_isNumeric(w)) {
      final n = spokenToNumber(spoken, decimal: w.keyboardType.decimal ?? false);
      if (n == null) {
        _say('Не число: «$spoken»');
        return;
      }
      add = n;
      // число замінює вміст поля, якщо там нічого не виділено частково
      final v = w.controller.value;
      final whole = !v.selection.isValid ||
          v.selection.isCollapsed ||
          (v.selection.start == 0 && v.selection.end == v.text.length);
      if (whole) {
        t.userUpdateTextEditingValue(
            TextEditingValue(text: add, selection: TextSelection.collapsed(offset: add.length)),
            SelectionChangedCause.keyboard);
        return;
      }
    }
    final cap = w.textCapitalization == TextCapitalization.sentences;
    t.userUpdateTextEditingValue(
        insertSpoken(w.controller.value, add, capitalize: cap), SelectionChangedCause.keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final listening = _target != null;
    final show = _available && (listening || (_focused != null && kb > 0));
    // будова завжди та сама (Stack -> MediaQuery -> застосунок): інакше
    // навігатор зі всіма відкритими екранами перебудувався б з нуля
    return Stack(alignment: Alignment.topLeft, children: [
      // застосунок бачить клавіатуру вищою на смужку - нічого не перекривається
      MediaQuery(
        data: show
            ? mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: kb + kVoiceBarHeight))
            : mq,
        child: widget.child,
      ),
      if (show)
        Positioned(
          left: 0,
          right: 0,
          bottom: kb,
          height: kVoiceBarHeight,
          // торкання смужки - «всередині» поля: фокус не губиться
          child: TextFieldTapRegion(child: _bar(listening)),
        ),
    ]);
  }

  Widget _bar(bool listening) {
    final dl = _downloading;
    final text = listening
        ? (_partial.isEmpty ? 'Говоріть…' : _partial)
        : dl != null
            ? (dl >= 1 ? 'Розпаковую модель…' : 'Скачую модель голосу: ${(dl * 100).round()} %')
            : (_message ??
            (_focused != null && _isNumeric(_focused!.widget) ? 'Скажіть число' : 'Голосовий ввід'));
    return Material(
      color: AppColors.popupBg,
      child: Row(children: [
        const SizedBox(width: 14),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: listening && _partial.isNotEmpty ? AppColors.text : AppColors.textMuted,
                  fontSize: 14)),
        ),
        if (_offer && dl == null)
          TextButton(
            key: const ValueKey('voice-download'),
            onPressed: _download,
            child: Text('Скачати', style: TextStyle(color: AppColors.create, fontWeight: FontWeight.bold)),
          ),
        GestureDetector(
          key: const ValueKey('voice-mic'),
          behavior: HitTestBehavior.opaque,
          onTap: listening ? _stop : _start,
          child: Container(
            width: 64,
            height: kVoiceBarHeight,
            alignment: Alignment.center,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: listening || dl != null ? AppColors.danger : AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(listening || dl != null ? Icons.stop : Icons.mic,
                      color: Colors.white, size: 22),
            ),
          ),
        ),
      ]),
    );
  }
}
