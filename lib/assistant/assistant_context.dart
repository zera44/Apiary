import 'package:flutter/material.dart';

import '../screens/apiary_list_screen.dart';
import '../screens/backups_screen.dart';
import '../screens/feedback_chat_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/fin_add_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/helpers_screen.dart';
import '../screens/history_hub_screen.dart';
import '../screens/map_screen.dart';
import '../screens/parameters_screen.dart';
import '../screens/receipt_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stock_screen.dart';
import '../screens/templates_screen.dart';
import '../screens/tutorial_screen.dart';
import 'assistant_tools.dart';

/// Про яку вкладку (екран) зараз говоримо з помічником: її показує плашка
/// над полем чату, її ж модель вважає головною (рядок «[Екран: …]» у
/// повідомленні людини).
class ScreenContext {
  /// Назва екрана з [kAssistantScreens] (finance, stock, map…).
  final String screen;

  /// Як називається вкладка людині: «Фінанси», «Склад», «Карта: Пасіка 1».
  final String label;
  final String? apiaryId;
  final String? elementId;
  const ScreenContext(this.screen, this.label, {this.apiaryId, this.elementId});

  NavTarget get target => NavTarget(screen, label, apiaryId: apiaryId, elementId: elementId);

  /// З екрана, який відкрив помічник («відкрий Фінанси»).
  factory ScreenContext.fromTarget(NavTarget t) => ScreenContext(
        t.screen,
        kScreenLabels[t.screen] ?? t.label,
        apiaryId: t.apiaryId,
        elementId: t.elementId,
      );

  /// Для моделі: «[Екран: finance (Фінанси)]»; для карти ще й id пасіки.
  String get promptLine =>
      '[Екран: $screen ($label)${apiaryId == null ? '' : ', пасіка: $apiaryId'}'
      '${elementId == null ? '' : ', вулик: $elementId'}]';

  /// Для зберігання разом із повідомленням (черга без інтернету).
  Map<String, dynamic> toJson() => {
        'screen': screen,
        'label': label,
        if (apiaryId != null) 'apiary': apiaryId,
        if (elementId != null) 'element': elementId,
      };

  static ScreenContext? fromJson(Object? j) => j is Map && j['screen'] is String
      ? ScreenContext(j['screen'] as String, '${j['label'] ?? j['screen']}',
          apiaryId: j['apiary'] as String?, elementId: j['element'] as String?)
      : null;

  @override
  bool operator ==(Object o) =>
      o is ScreenContext &&
      o.screen == screen &&
      o.apiaryId == apiaryId &&
      o.elementId == elementId &&
      o.label == label;

  @override
  int get hashCode => Object.hash(screen, apiaryId, elementId, label);
}

/// Як називаються вкладки людині (плашка в чаті).
const kScreenLabels = {
  'finance': 'Фінанси',
  'finance_add': 'Новий запис',
  'stock': 'Склад',
  'apiaries': 'Мої пасіки',
  'history': 'Історія',
  'parameters': 'Параметри',
  'templates': 'Шаблони',
  'settings': 'Налаштування',
  'helpers': 'Помічники',
  'backups': 'Резервні копії',
  'receipt': 'Чек',
  'lessons': 'Навчання',
  'lesson': 'Навчання',
  'feedback': 'Відгук',
};

/// Екрани, на яких знайомий екран розпізнано. Новий екран тут - і в чаті
/// з'явиться плашка «Фінанси», а в моделі - рядок «[Екран: …]».
ScreenContext? screenContextOf(Widget w) {
  if (w is FinanceScreen) return const ScreenContext('finance', 'Фінанси');
  if (w is FinAddScreen) return const ScreenContext('finance_add', 'Новий запис');
  if (w is StockScreen) return const ScreenContext('stock', 'Склад');
  if (w is ApiaryListScreen) return const ScreenContext('apiaries', 'Мої пасіки');
  if (w is HistoryHubScreen) return const ScreenContext('history', 'Історія');
  if (w is ParametersScreen) return const ScreenContext('parameters', 'Параметри');
  if (w is TemplatesScreen) return const ScreenContext('templates', 'Шаблони');
  if (w is SettingsScreen) return const ScreenContext('settings', 'Налаштування');
  if (w is HelpersScreen) return const ScreenContext('helpers', 'Помічники');
  if (w is BackupsScreen) return const ScreenContext('backups', 'Резервні копії');
  if (w is ReceiptScreen) return const ScreenContext('receipt', 'Чек');
  if (w is TutorialScreen) return const ScreenContext('lessons', 'Навчання');
  if (w is FeedbackScreen || w is FeedbackChatScreen) {
    return const ScreenContext('feedback', 'Відгук');
  }
  if (w is MapScreen && !w.tutorial && !w.backdrop) {
    return ScreenContext('map', 'Карта: ${w.apiary.name}',
        apiaryId: w.apiary.id, elementId: w.focusElementId);
  }
  return null;
}

/// Екран, що його видно в піддереві маршруту (перший знайомий).
ScreenContext? detectScreen(BuildContext ctx) {
  ScreenContext? found;
  var visited = 0;
  void visit(Element e) {
    if (found != null || visited++ > 160) return;
    final s = screenContextOf(e.widget);
    if (s != null) {
      found = s;
      return;
    }
    e.visitChildren(visit);
  }

  (ctx as Element).visitChildren(visit);
  return found;
}

/// Відстежує, яка вкладка зараз зверху (крім самого чату): від неї плашка
/// в чаті й підказки.
class AssistantContext {
  /// Знайома вкладка зверху; null - головний екран чи невідомий екран.
  static final current = ValueNotifier<ScreenContext?>(null);

  /// Плашку виклику ховаємо: зверху чат або вікно / нижній аркуш.
  static final chatOnTop = ValueNotifier<bool>(false);

  static const chatRouteName = 'assistant-chat';

  static final observer = _ContextObserver();
}

class _ContextObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _refresh();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _refresh();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _refresh();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _routes[i] = newRoute;
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _refresh();
  }

  void _refresh([int tries = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PageRoute<dynamic>? top;
      for (final r in _routes.reversed) {
        if (r is PageRoute) {
          top = r;
          break;
        }
      }
      AssistantContext.chatOnTop.value = top?.settings.name == AssistantContext.chatRouteName ||
          (_routes.isNotEmpty && _routes.last is! PageRoute);
      for (final r in _routes.reversed) {
        if (r.settings.name == AssistantContext.chatRouteName) continue;
        if (r is! ModalRoute) continue;
        final ctx = r.subtreeContext;
        if (ctx == null || !ctx.mounted) {
          // маршрут ще будується
          if (tries < 6) _refresh(tries + 1);
          return;
        }
        final s = detectScreen(ctx);
        if (s != null) {
          AssistantContext.current.value = s;
          return;
        }
        if (r is PageRoute) {
          // повноекранний, але невідомий (головний, сканер…): говоримо про весь застосунок
          AssistantContext.current.value = null;
          return;
        }
        // вікно чи нижній аркуш поверх екрана - дивимось нижче
      }
      AssistantContext.current.value = null;
    });
  }
}
