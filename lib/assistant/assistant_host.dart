import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'assistant_chat_screen.dart';
import 'assistant_context.dart';
import 'assistant_nav.dart';
import 'assistant_queue.dart';
import 'assistant_tools.dart';

/// Помічник на екранах застосунку: кругла плашка виклику у верхньому правому
/// куті кожного екрана (на місці колишньої шестерні; шапки лишають під неї
/// місце, [AssistantSlot]) і, коли екран широкий (планшет), чат збоку від вкладки.
///
/// Вкладається в `MaterialApp.builder` над навігатором.
class AssistantHost extends StatefulWidget {
  final Repository repo;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  /// Від якої ширини чат відкривається збоку (dp).
  final double dockFrom;
  const AssistantHost({
    super.key,
    required this.repo,
    required this.navigator,
    required this.child,
    this.dockFrom = AssistantHost.defaultDockFrom,
  });

  static const defaultDockFrom = 840.0;
  static const dockWidth = 400.0;

  /// Показувати плашку помічника (налаштування; вимкнули - помічник у меню).
  static final showBubble = ValueNotifier<bool>(true);
  static const bubbleKey = 'assistant_bubble';
  static const bubblePosKey = 'assistant_bubble_pos';

  static Future<void> setShowBubble(Repository repo, bool v) async {
    showBubble.value = v;
    await repo.setMeta(bubbleKey, v ? '1' : '0');
  }

  /// Чат збоку відкрито (лише на широкому екрані).
  static final dockOpen = ValueNotifier<bool>(false);

  /// Екрани, де плашки немає: навчання (і самі уроки), відгук - свій потік,
  /// заставка входу, сканер QR-коду. На решті (разом з головним і картою) іконка завжди в
  /// одному місці.
  static const hiddenOn = {'lessons', 'lesson', 'feedback', 'splash', 'scanner'};

  @override
  State<AssistantHost> createState() => _AssistantHostState();
}

class _AssistantHostState extends State<AssistantHost> {
  /// Де плашку залишили: true - біля правого краю; [_yFrac] - висота (0..1).
  /// Немає - стандартне місце в куті шапки.
  bool _right = true;
  double _yFrac = 0;
  bool _moved = false;

  /// Положення пальця, поки плашку тягнуть (лівий верхній кут).
  Offset? _drag;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    try {
      final on = await widget.repo.getMeta(AssistantHost.bubbleKey);
      final pos = await widget.repo.getMeta(AssistantHost.bubblePosKey);
      if (!mounted) return;
      AssistantHost.showBubble.value = on != '0';
      final m = RegExp(r'^([LR]):([0-9.]+)$').firstMatch(pos ?? '');
      if (m != null) {
        setState(() {
          _moved = true;
          _right = m.group(1) == 'R';
          _yFrac = (double.tryParse(m.group(2)!) ?? 0).clamp(0.0, 1.0);
        });
      }
    } catch (_) {}
  }

  void _toggleOrOpen(bool wide) {
    if (wide) {
      AssistantHost.dockOpen.value = !AssistantHost.dockOpen.value;
      return;
    }
    final nav = widget.navigator.currentState;
    if (nav != null) unawaited(AssistantChatScreen.open(nav, widget.repo));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= widget.dockFrom;
        return ListenableBuilder(
          listenable: Listenable.merge([
            AssistantContext.current,
            AssistantContext.chatOnTop,
            AssistantHost.dockOpen,
            AssistantHost.showBubble,
          ]),
          builder: (context, _) {
            final q = AssistantQueue.current;
            final docked = wide && AssistantHost.dockOpen.value && q != null;
            final mq = MediaQuery.of(context);
            final panel = docked ? AssistantHost.dockWidth : 0.0;
            final ctx = AssistantContext.current.value;
            // місце в шапці лишається й під вікном (щоб шапка не стрибала)
            final slot =
                q != null && !docked && !AssistantHost.hiddenOn.contains(ctx?.screen);
            final bubbleOn = AssistantHost.showBubble.value;
            final showFab = slot && bubbleOn && !AssistantContext.chatOnTop.value;
            // місце в шапці потрібне, лише поки плашка стоїть у куті
            final reserve = slot && bubbleOn && !_moved && _drag == null;
            if (AssistantSlot.shown.value != reserve) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => AssistantSlot.shown.value = reserve);
            }
            return Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MediaQuery(
                        data: mq.copyWith(size: Size(box.maxWidth - panel, mq.size.height)),
                        child: widget.child,
                      ),
                    ),
                    if (docked)
                      SizedBox(
                        key: const ValueKey('assistant-dock'),
                        width: AssistantHost.dockWidth,
                        child: MediaQuery(
                          data: mq.copyWith(size: Size(AssistantHost.dockWidth, mq.size.height)),
                          child: _DockedChat(
                            repo: widget.repo,
                            queue: q,
                            navigator: widget.navigator,
                          ),
                        ),
                      ),
                  ],
                ),
                if (showFab) _fab(mq, box, wide),
              ],
            );
          },
        );
      },
    );
  }

  /// Плашку можна перетягнути (як у Telegram): відпустили - прилипає до
  /// лівого чи правого краю; куток шапки (стандартне місце) вільний, поки вона там.
  Widget _fab(MediaQueryData mq, BoxConstraints box, bool wide) {
    const s = AssistantSlot.size;
    const gap = 8.0;
    final topMin = mq.padding.top + AssistantSlot.top;
    final topMax = math.max(topMin, box.maxHeight - mq.padding.bottom - s - gap);
    final leftEdge = mq.padding.left + gap;
    final rightEdge = box.maxWidth - mq.padding.right - AssistantSlot.right - s;
    double left, top;
    if (_drag != null) {
      left = _drag!.dx;
      top = _drag!.dy;
    } else if (_moved) {
      left = _right ? rightEdge : leftEdge;
      top = topMin + (topMax - topMin) * _yFrac;
    } else {
      left = rightEdge;
      top = topMin;
    }
    return AnimatedPositioned(
      duration: _drag != null ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: left,
      top: top,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _drag = Offset(left, top)),
        onPanUpdate: (d) => setState(() {
          final p = (_drag ?? Offset(left, top)) + d.delta;
          _drag = Offset(p.dx.clamp(0.0, box.maxWidth - s), p.dy.clamp(topMin, topMax));
        }),
        onPanEnd: (_) {
          final p = _drag;
          if (p == null) return;
          final right = p.dx + s / 2 > box.maxWidth / 2;
          final home = right && p.dy <= topMin + 14;
          setState(() {
            _drag = null;
            _right = right;
            _yFrac = topMax <= topMin ? 0 : ((p.dy - topMin) / (topMax - topMin)).clamp(0.0, 1.0);
            _moved = !home;
          });
          unawaited(widget.repo
              .setMeta(AssistantHost.bubblePosKey,
                  home ? '' : '${right ? 'R' : 'L'}:${_yFrac.toStringAsFixed(3)}')
              .catchError((Object _) {}));
        },
        onPanCancel: () => setState(() => _drag = null),
        child: Material(
          key: const ValueKey('assistant-fab'),
          type: MaterialType.transparency,
          child: AssistantButton(repo: widget.repo, size: s, onTap: () => _toggleOrOpen(wide)),
        ),
      ),
    );
  }
}

/// Чат збоку: свій навігатор (вікна й аркуші - у межах панелі), «Назад» -
/// закрити панель; екрани відкриває головний навігатор.
class _DockedChat extends StatelessWidget {
  final Repository repo;
  final AssistantQueue queue;
  final GlobalKey<NavigatorState> navigator;
  const _DockedChat({required this.repo, required this.queue, required this.navigator});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.hive, width: 2)),
        ),
        // герої (переходи між екранами) - лише в основному навігаторі
        child: HeroControllerScope.none(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => AssistantChatScreen(
                repo: repo,
                queue: queue,
                docked: true,
                onClose: () => AssistantHost.dockOpen.value = false,
                navigate: (NavTarget t) async {
                  final nav = navigator.currentState;
                  return nav == null ? false : openAssistantTarget(nav, repo, t);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
