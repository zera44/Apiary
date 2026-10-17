import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'assistant_tools.dart';

/// Посилання у відповідях помічника: [текст](екран) або [текст](екран:id),
/// напр. [склад](stock), [Вулик 100](hive:e:…). Екран - зі списку
/// [kAssistantScreens]; інше лишається звичайним текстом.
final _link = RegExp(r'\[([^\]\n]{1,80})\]\(([a-z_]+)(?::([^)\s]{1,120}))?\)');

class AssistantLink {
  final String text;
  final String screen;
  final String? id;
  const AssistantLink(this.text, this.screen, this.id);
}

/// Шматки відповіді: String (текст) або [AssistantLink].
List<Object> parseAssistantLinks(String s) {
  final out = <Object>[];
  var at = 0;
  for (final m in _link.allMatches(s)) {
    final screen = m[2]!;
    if (!kAssistantScreens.contains(screen)) continue;
    if (m.start > at) out.add(s.substring(at, m.start));
    out.add(AssistantLink(m[1]!, screen, m[3]));
    at = m.end;
  }
  if (at < s.length) out.add(s.substring(at));
  return out;
}

/// Текст без розмітки посилань (читання вголос, сповіщення).
String plainAssistantText(String s) => [
  for (final p in parseAssistantLinks(s)) p is AssistantLink ? p.text : p as String,
].join();

/// Відповідь із посиланнями: торкнулися - [onOpen].
class LinkedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextStyle linkStyle;
  final void Function(AssistantLink link) onOpen;
  const LinkedText(
    this.text, {
    super.key,
    required this.style,
    required this.linkStyle,
    required this.onOpen,
  });

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _taps) {
      r.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    return Text.rich(
      TextSpan(
        children: [
          for (final p in parseAssistantLinks(widget.text))
            if (p is AssistantLink)
              TextSpan(
                text: p.text,
                style: widget.linkStyle,
                recognizer: (TapGestureRecognizer()..onTap = () => widget.onOpen(p))
                  ..let(_taps.add),
              )
            else
              TextSpan(text: p as String),
        ],
      ),
      style: widget.style,
    );
  }
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
