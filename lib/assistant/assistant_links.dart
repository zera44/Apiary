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

/// «вулик 14», «вулика 1», «вуликом №3», «вулики 1, 5 та 14»: слово й
/// номер (з літерою: 14а), далі - ще номери через кому / і / й / та.
final _hiveRef = RegExp(
  r'(?<![\p{L}\d])(вулик[\p{L}]{0,3})(\s*(?:№\s*)?)(\d{1,5}[\p{L}]?)(?![\p{L}\d])'
  r'((?:\s*(?:,|і|й|та)\s*(?:№\s*)?\d{1,5}[\p{L}]?(?![\p{L}\d]))*)',
  caseSensitive: false,
  unicode: true,
);
final _hiveNum = RegExp(r'\d{1,5}[\p{L}]?(?![\p{L}\d])', unicode: true);

/// Згадки вуликів, які модель написала звичайним текстом, - посиланнями.
/// [known]: номер вулика (як у [hiveKey]) -> id; лише вулики, що є й
/// однозначні. Готові посилання [..](..) не чіпаємо.
String linkHiveMentions(String s, Map<String, String> known) {
  if (known.isEmpty) return s;
  String link(String text, String number) {
    final id = known[number.toLowerCase()];
    return id == null ? text : '[$text](hive:$id)';
  }

  String plain(String t) => t.replaceAllMapped(_hiveRef, (m) {
        final rest = m[4] ?? '';
        return link('${m[1]}${m[2]}${m[3]}', m[3]!) +
            rest.replaceAllMapped(_hiveNum, (n) => link(n[0]!, n[0]!));
      });

  final out = StringBuffer();
  var at = 0;
  for (final m in _link.allMatches(s)) {
    out
      ..write(plain(s.substring(at, m.start)))
      ..write(m[0]);
    at = m.end;
  }
  out.write(plain(s.substring(at)));
  return out.toString();
}

/// Номер вулика з його назви: «Вулик №14» -> «14», «14а» -> «14а».
String hiveKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceFirst(RegExp(r'^вулик\s*(№\s*)?'), '');

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
