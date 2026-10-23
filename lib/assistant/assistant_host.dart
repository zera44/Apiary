import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/theme.dart';
import 'assistant_chat_screen.dart';
import 'assistant_context.dart';
import 'assistant_nav.dart';
import 'assistant_queue.dart';
import 'assistant_tools.dart';

/// Помічник на екранах застосунку: кругла плашка виклику на кожній вкладці
/// (як на карті) і, коли екран широкий (планшет), чат збоку від вкладки.
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

  /// Чат збоку відкрито (лише на широкому екрані).
  static final dockOpen = ValueNotifier<bool>(false);

  /// Екрани, де плашки немає: навчання й відгук - свій потік. На решті
  /// (разом з картою) іконка завжди в одному місці.
  static const hiddenOn = {'lessons', 'feedback'};

  @override
  State<AssistantHost> createState() => _AssistantHostState();
}

class _AssistantHostState extends State<AssistantHost> {
  static const _size = 52.0;

  /// Місце іконки однакове на всіх екранах і не переміщується.
  static const _right = 12.0;
  static const _bottom = 96.0;

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
          ]),
          builder: (context, _) {
            final q = AssistantQueue.current;
            final docked = wide && AssistantHost.dockOpen.value && q != null;
            final mq = MediaQuery.of(context);
            final panel = docked ? AssistantHost.dockWidth : 0.0;
            final ctx = AssistantContext.current.value;
            final showFab =
                q != null &&
                !docked &&
                ctx != null &&
                !AssistantHost.hiddenOn.contains(ctx.screen) &&
                !AssistantContext.chatOnTop.value;
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
                if (showFab) _fab(box, wide),
              ],
            );
          },
        );
      },
    );
  }

  Widget _fab(BoxConstraints box, bool wide) {
    return Positioned(
      right: _right,
      bottom: _bottom,
      child: Material(
        key: const ValueKey('assistant-fab'),
        type: MaterialType.transparency,
        child: AssistantButton(repo: widget.repo, size: _size, onTap: () => _toggleOrOpen(wide)),
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
