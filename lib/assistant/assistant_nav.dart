import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
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
import '../screens/whats_new_screen.dart';
import '../services/feedback_chat.dart';
import '../ui/app_drawer.dart';
import 'assistant_tools.dart';

/// Екран для open_screen ([kAssistantScreens]); null - відкривається
/// по-своєму (головний, сканер, «Що нового») або даних уже немає.
Future<Widget?> assistantScreen(Repository repo, NavTarget t) async {
  switch (t.screen) {
    case 'apiaries':
      return ApiaryListScreen(repo: repo);
    case 'map':
    case 'hive':
      final a = t.apiaryId == null ? null : await repo.getApiary(t.apiaryId!);
      if (a == null) return null;
      return MapScreen(repo: repo, apiary: a, focusElementId: t.elementId);
    case 'parameters':
      return ParametersScreen.catalog(repo: repo);
    case 'templates':
      return TemplatesScreen(repo: repo);
    case 'stock':
      return StockScreen(repo: repo);
    case 'finance':
      return FinanceScreen(repo: repo);
    case 'finance_add':
      return FinAddScreen(repo: repo);
    case 'history':
      return HistoryHubScreen(repo: repo);
    case 'receipt':
      return ReceiptScreen(repo: repo);
    case 'settings':
      return SettingsScreen(repo: repo);
    case 'helpers':
      return HelpersScreen(repo: repo);
    case 'backups':
      return BackupsScreen(repo: repo);
    case 'lessons':
    case 'lesson':
      return TutorialScreen(realRepo: repo);
    case 'feedback':
      return FeedbackChat.current?.available == true
          ? FeedbackChatScreen(chat: FeedbackChat.current!)
          : const FeedbackScreen();
  }
  return null;
}

/// Відкрити екран поверх чату (кнопка «Назад» повертає в чат).
Future<bool> openAssistantTarget(NavigatorState nav, Repository repo, NavTarget t) async {
  switch (t.screen) {
    case 'home':
      nav.popUntil((r) => r.isFirst);
      return true;
    case 'scanner':
      unawaited(AppDrawer.openHiveByQr(nav, repo));
      return true;
    case 'whats_new':
      unawaited(WhatsNewScreen.open(nav));
      return true;
  }
  final w = await assistantScreen(repo, t);
  if (w == null || !nav.mounted) return false;
  unawaited(nav.push(MaterialPageRoute(builder: (_) => w)));
  return true;
}
