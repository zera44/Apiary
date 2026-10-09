import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import '../logic/spoken_numbers.dart';
import '../services/voice_input.dart';
import 'theme.dart';

/// Висота смужки з мікрофоном над клавіатурою.
const double kVoiceBarHeight = 46;

/// Висота панелі диктування (замість клавіатури), без системної панелі навігації.
const double kVoicePanelHeight = 176;

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

/// Стерти слово перед курсором (виділене - стирається саме воно).
TextEditingValue deleteWordBefore(TextEditingValue v) {
  final text = v.text;
  final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
  if (!sel.isCollapsed) {
    return TextEditingValue(
      text: text.substring(0, sel.start) + text.substring(sel.end),
      selection: TextSelection.collapsed(offset: sel.start),
    );
  }
  var i = sel.start;
  while (i > 0 && text[i - 1].trim().isEmpty) {
    i--;
  }
  while (i > 0 && text[i - 1].trim().isNotEmpty) {
    i--;
  }
  return TextEditingValue(
    text: text.substring(0, i) + text.substring(sel.end),
    selection: TextSelection.collapsed(offset: i),
  );
}

bool _isNumeric(EditableText w) => w.keyboardType.index == TextInputType.number.index;

/// «Клавіатура» застосунку: замість системної (Gboard) при дотику до поля
/// з'являється панель диктування. Поки вона встановлена, Flutter підключає
/// поле до системи з типом «без клавіатури», тож Gboard не з'являється.
class _VoiceControl with TextInputControl {
  _VoiceControl(this.host);
  final _VoiceInputHostState host;

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) => host._onAttach();

  @override
  void show() => host._onShow();

  @override
  void hide() => host._onHide();
}

/// «Назад», поки відкрита панель диктування: ховає панель, а не закриває
/// екран (як «назад» при відкритій клавіатурі).
class _PanelPopEntry extends PopEntry<Object?> {
  _PanelPopEntry(this.onBack);
  final VoidCallback onBack;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(false);

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) onBack();
  }
}

/// Голосовий ввід для ВСІХ текстових полів застосунку. Дотик до поля
/// відкриває замість клавіатури панель диктування (великий мікрофон,
/// «Клавіатура», «Стерти», «Готово»). «Клавіатура» відкриває Gboard для
/// цього поля; над Gboard - смужка з мікрофоном. Сказане вставляється в поле
/// з фокусом (у числові - цифрами: «два кома п'ять» -> 2,5).
/// Обгортає весь застосунок (MaterialApp.builder). Не на Android - нічого не
/// змінює.
class VoiceInputHost extends StatefulWidget {
  final Widget child;
  const VoiceInputHost({super.key, required this.child});

  @override
  State<VoiceInputHost> createState() => _VoiceInputHostState();
}

class _VoiceInputHostState extends State<VoiceInputHost> with WidgetsBindingObserver {
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

  late final _VoiceControl _control = _VoiceControl(this);

  /// Flutter просить показати «клавіатуру» (панель диктування).
  bool _panelShown = false;

  /// Для поля [_kbField] обрано Gboard (до переходу на інше поле).
  bool _keyboardMode = false;
  EditableTextState? _kbField;

  /// Поле перепідключається до системи (перемикання на Gboard): тимчасова
  /// втрата фокуса - не «перехід на інше поле».
  bool _refocusing = false;

  /// Поле підключене до системи ще зі справжнім типом клавіатури (після
  /// повернення з Gboard): показ системної клавіатури треба гасити.
  bool _staleConfig = false;

  _PanelPopEntry? _popEntry;
  ModalRoute<Object?>? _popRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VoiceInput.instance.available().then((ok) {
      if (!mounted || !ok) return;
      setState(() => _available = true);
      // наша панель замість системної клавіатури
      _staleConfig = _editable() != null;
      TextInput.setInputControl(_control);
      FocusManager.instance.addListener(_onFocus);
      _onFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocus);
    if (_available) TextInput.restorePlatformInputControl();
    _unregisterBack();
    _sub?.cancel();
    _limit?.cancel();
    if (_target != null) Vosk.cancel();
    super.dispose();
  }

  /// Застосунок пішов у фон - мікрофон вимикається одразу (без вставки).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused || _target == null) return;
    _limit?.cancel();
    Vosk.cancel();
    setState(() {
      _target = null;
      _partial = '';
    });
  }

  /// setState, безпечний для виклику з будь-якої фази кадру (команди
  /// клавіатури приходять і посеред побудови).
  void _update(VoidCallback fn) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      fn();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(fn);
    }
  }

  /// Нове підключення поля (вже з типом «без клавіатури»).
  void _onAttach() => _staleConfig = false;

  void _onShow() {
    // поле підключене ще з типом Gboard - системна клавіатура теж отримала
    // «показати» (вона в списку першою): одразу ховаємо її
    if (_staleConfig) SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _update(() => _panelShown = true);
  }

  void _onHide() => _update(() => _panelShown = false);

  /// «Клавіатура»: Gboard для цього поля замість панелі. Поле треба
  /// перепідключити до системи вже зі справжнім типом клавіатури - коротко
  /// знімаємо й повертаємо фокус.
  void _toKeyboard() {
    final t = _focused;
    if (t == null || !t.mounted) return;
    if (_target != null) _stop();
    final node = t.widget.focusNode;
    setState(() {
      _keyboardMode = true;
      _kbField = t;
      _panelShown = false;
      _refocusing = true;
    });
    TextInput.restorePlatformInputControl();
    node.unfocus();
    // фокус повертається після того, як зняття застосовано (окремий цикл)
    Timer.run(() {
      if (!mounted) return;
      if (t.mounted && node.canRequestFocus) {
        node.requestFocus();
      } else {
        _refocusing = false;
        _leaveKeyboardMode();
      }
      // запобіжник: фокус так і не повернувся
      Timer(const Duration(milliseconds: 500), () {
        if (mounted && _refocusing) {
          _refocusing = false;
          _onFocus();
        }
      });
    });
  }

  /// Gboard обирали для іншого поля - знову наша панель.
  void _leaveKeyboardMode() {
    if (!_keyboardMode) return;
    _keyboardMode = false;
    _kbField = null;
    // поле, що вже має фокус, підключене зі справжнім типом - Gboard
    // ховається, а наступні «показати» гаситимемо
    _staleConfig = _editable() != null;
    TextInput.setInputControl(_control);
  }

  /// «Готово»: як клавіша дії на клавіатурі (однорядкове поле - «готово» /
  /// «далі»), у багаторядковому - просто сховати панель.
  void _done() {
    final t = _focused;
    if (_target != null) _stop();
    if (t == null || !t.mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final w = t.widget;
    if (w.maxLines == 1) {
      t.performAction(w.textInputAction ?? TextInputAction.done);
    } else {
      w.focusNode.unfocus();
    }
  }

  void _deleteWord() {
    final t = _focused;
    if (t == null || !t.mounted) return;
    t.userUpdateTextEditingValue(
        deleteWordBefore(t.widget.controller.value), SelectionChangedCause.keyboard);
  }

  /// «Назад» при відкритій панелі - сховати її (зареєстровано на екрані поля).
  void _syncBack(bool panel) {
    final t = _focused;
    final route = panel && t != null && t.mounted ? ModalRoute.of(t.context) : null;
    if (route == _popRoute) return;
    _unregisterBack();
    if (route == null) return;
    final e = _PanelPopEntry(() {
      if (_target != null) _stop();
      FocusManager.instance.primaryFocus?.unfocus();
    });
    route.registerPopEntry(e);
    _popEntry = e;
    _popRoute = route;
  }

  void _unregisterBack() {
    final e = _popEntry, r = _popRoute;
    _popEntry = null;
    _popRoute = null;
    if (e != null && r != null) r.unregisterPopEntry(e);
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
    if (_refocusing) {
      // перемикання на Gboard: чекаємо, доки фокус повернеться на поле
      if (f == null || f != _kbField) return;
      _refocusing = false;
    } else if (_keyboardMode && f != _kbField) {
      _leaveKeyboardMode();
    }
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
    // одразу «зайнято»: подвійний дотик не запускає все вдруге
    setState(() => _busy = true);
    try {
      if (!await VoiceInput.instance.modelOnPhone()) {
        _offer = true;
        _say('Для голосу один раз скачайте модель ~$kVoskModelMb МБ (краще через Wi-Fi)');
        return;
      }
      _say('Готую розпізнавання…');
      await VoiceInput.instance.ensureReady();
      if (!await Vosk.permission()) {
        _say('Немає дозволу на мікрофон (Налаштування телефону → Дозволи)');
        return;
      }
      if (!mounted || !t.mounted) return;
      // поки готувались, застосунок пішов у фон - мікрофон не вмикаємо
      // (inactive - це й системне вікно дозволу, тоді вмикаємо)
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.paused ||
          life == AppLifecycleState.hidden ||
          life == AppLifecycleState.detached) {
        setState(() => _message = null);
        return;
      }
      _sub ??= Vosk.events.listen(_onEvent);
      // ціль - до запуску: перші результати можуть прийти одразу
      setState(() {
        _target = t;
        _partial = '';
        _message = null;
      });
      try {
        await Vosk.start();
      } catch (_) {
        if (mounted) setState(() => _target = null);
        rethrow;
      }
      // запобіжник: мікрофон не лишається увімкненим назавжди
      _limit?.cancel();
      _limit = Timer(const Duration(minutes: 2), _stop);
    } on PlatformException catch (e) {
      if (e.code == 'NOMODEL' || e.code == 'MODEL') {
        // моделі немає або вона пошкоджена (плагін її прибрав) - скачати знову
        _offer = true;
        _say('Модель голосу пошкоджена - скачайте її ще раз');
      } else {
        _say('Голосовий ввід недоступний: ${e.message ?? e.code}');
      }
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
    final listening = _target != null;
    final panel = _available && _panelShown && !_keyboardMode && _focused != null;
    // «назад» ховає панель - реєструється на екрані поля після кадру
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBack(panel);
    });
    if (panel) {
      // панель - як клавіатура: застосунок бачить її у viewInsets
      final nav = mq.viewPadding.bottom;
      final h = kVoicePanelHeight + nav;
      return Stack(alignment: Alignment.topLeft, children: [
        MediaQuery(
          data: mq.copyWith(
            viewInsets: mq.viewInsets.copyWith(bottom: h),
            padding: mq.padding.copyWith(bottom: 0),
          ),
          child: widget.child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: h,
          child: TextFieldTapRegion(child: _panel(listening, nav)),
        ),
      ]);
    }
    final kb = mq.viewInsets.bottom;
    final show = _available && (listening || (_focused != null && kb > 0));
    // смужка над клавіатурою - для застосунку клавіатура вища на смужку; без
    // клавіатури (диктування триває) - смужка внизу як системна панель, щоб
    // «клавіатура відкрита» (viewInsets) не вмикалось хибно
    MediaQueryData data = mq;
    if (show && kb > 0) {
      data = mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: kb + kVoiceBarHeight));
    } else if (show) {
      data = mq.copyWith(
        padding: mq.padding.copyWith(bottom: mq.padding.bottom + kVoiceBarHeight),
        viewPadding: mq.viewPadding.copyWith(bottom: mq.viewPadding.bottom + kVoiceBarHeight),
      );
    }
    // будова завжди та сама (Stack -> MediaQuery -> застосунок): інакше
    // навігатор зі всіма відкритими екранами перебудувався б з нуля
    return Stack(alignment: Alignment.topLeft, children: [
      // застосунок бачить клавіатуру вищою на смужку - нічого не перекривається
      MediaQuery(data: data, child: widget.child),
      if (show)
        Positioned(
          left: 0,
          right: 0,
          bottom: kb > 0 ? kb : mq.padding.bottom,
          height: kVoiceBarHeight,
          // торкання смужки - «всередині» поля: фокус не губиться
          child: TextFieldTapRegion(child: _bar(listening)),
        ),
    ]);
  }

  String _status(bool listening, {required String idle}) {
    final dl = _downloading;
    return listening
        ? (_partial.isEmpty ? 'Говоріть…' : _partial)
        : dl != null
            ? (dl >= 1 ? 'Розпаковую модель…' : 'Скачую модель голосу: ${(dl * 100).round()} %')
            : (_message ?? (_focused != null && _isNumeric(_focused!.widget) ? 'Скажіть число' : idle));
  }

  /// Панель диктування замість клавіатури.
  Widget _panel(bool listening, double navBar) {
    final dl = _downloading;
    final text = _status(listening, idle: 'Натисніть мікрофон і говоріть');
    Widget side(String label, IconData icon, VoidCallback onTap, Key key) => Expanded(
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: 64,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: AppColors.text, size: 24),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ]),
            ),
          ),
        );
    return Material(
      color: AppColors.popupBg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 8 + navBar),
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 4),
            Expanded(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: listening && _partial.isNotEmpty ? AppColors.text : AppColors.textMuted,
                      fontSize: 15)),
            ),
            if (_offer && dl == null)
              TextButton(
                key: const ValueKey('voice-download'),
                onPressed: _download,
                child: Text('Скачати',
                    style: TextStyle(color: AppColors.create, fontWeight: FontWeight.bold)),
              ),
          ]),
          const Spacer(),
          // мікрофон посередині: зліва «Клавіатура» і «Стерти», справа «Готово»
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Row(children: [
                side('Клавіатура', Icons.keyboard_outlined, _toKeyboard, const ValueKey('voice-keyboard')),
                side('Стерти', Icons.backspace_outlined, _deleteWord, const ValueKey('voice-delete')),
              ]),
            ),
            GestureDetector(
              key: const ValueKey('voice-mic'),
              behavior: HitTestBehavior.opaque,
              onTap: listening ? _stop : _start,
              child: Container(
                width: 76,
                height: 76,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: listening || dl != null ? AppColors.danger : AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Icon(listening || dl != null ? Icons.stop : Icons.mic,
                        color: Colors.white, size: 36),
              ),
            ),
            Expanded(
              child: Row(children: [
                side('Готово', Icons.check, _done, const ValueKey('voice-done')),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _bar(bool listening) {
    final dl = _downloading;
    final text = _status(listening, idle: 'Голосовий ввід');
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
