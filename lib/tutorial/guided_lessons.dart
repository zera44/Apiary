import 'package:flutter/widgets.dart';

import '../data/finance.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../screens/finance_screen.dart';
import '../screens/history_hub_screen.dart';
import '../screens/qr_generate_screen.dart';
import '../screens/stock_screen.dart';
import 'guided.dart';
import 'lesson.dart';

/// Тексти кроку [i] уроку (з l10n; розмітка - див. [guideSpans]).
String _t(List<String> texts, int i) => i < texts.length ? texts[i] : '';

// ---------------------------------------------------------------------------
// Склад
// ---------------------------------------------------------------------------

List<GuideStep> _stockSteps() {
  final t = tr.guideStock;
  return [
    GuideStep.look(_t(t, 0), target: 'stock-tile-0', pic: LessonPic.laptop),
    GuideStep.tap('stock-add', _t(t, 1), pic: LessonPic.laptop),
    GuideStep.free(_t(t, 2), waitFor: 'stock-tile-3', pic: LessonPic.scheming),
    GuideStep.tap('stock-out-0', _t(t, 3)),
    GuideStep.look(_t(t, 4), target: 'stock-in-0', pic: LessonPic.thinking),
    GuideStep.tap('stock-tab-inventory', _t(t, 5), pic: LessonPic.thinking),
    GuideStep.tap('stock-mode-list', _t(t, 6), pic: LessonPic.thinking),
    GuideStep.look(_t(t, 7), target: 'stock-take-save', pic: LessonPic.thinking),
    GuideStep.done(_t(t, 8), pic: LessonPic.laptop),
  ];
}

/// Три позиції; ліків менше за мінімум (за назвою «Апістан» - перша плитка).
Future<void> _seedStock(Repository repo) async {
  if ((await repo.listStockItems()).isNotEmpty) return;
  final meds = await repo.addStockItem('Апістан', 'уп');
  await repo.receiveStock(meds, 6, total: 900);
  await repo.writeOffStock(meds, 1, comment: 'Осіння обробка');
  await repo.updateStockItem(meds, minQuantity: (10,));
  final frames = await repo.addStockItem('Рамки', 'шт');
  await repo.receiveStock(frames, 40, total: 1600);
  final sugar = await repo.addStockItem('Цукор', 'кг');
  await repo.receiveStock(sugar, 12, total: 480);
}

// ---------------------------------------------------------------------------
// Історія
// ---------------------------------------------------------------------------

List<GuideStep> _historySteps() {
  final t = tr.guideHistory;
  return [
    GuideStep.free(_t(t, 0), waitFor: 'history-filter', target: 'history-param-0', pic: LessonPic.newspaper),
    GuideStep.look(_t(t, 1), target: 'history-filter', pic: LessonPic.newspaper),
    GuideStep.look(_t(t, 2), target: 'history-export', pic: LessonPic.newspaper),
    GuideStep.free(_t(t, 3), waitFor: 'history-report'),
    GuideStep.look(_t(t, 4), target: 'history-report', pic: LessonPic.scheming),
    GuideStep.tap('history-tab-stock', _t(t, 5), pic: LessonPic.newspaper),
    GuideStep.tap('history-item-0', _t(t, 6), pic: LessonPic.newspaper),
    GuideStep.done(_t(t, 7), target: 'history-cancel', pic: LessonPic.stung),
  ];
}

/// Записи огляду (кількість вуличок) у кожного вулика.
Future<void> _seedHistory(Repository repo) async {
  final apiary = await seedGuideApiary(repo);
  await _seedStock(repo);
  String? frames;
  for (final p in await repo.listParameters()) {
    if (p.name == Repository.kBeeFramesName) frames = p.id;
  }
  if (frames == null) return;
  var n = 7;
  for (final e in await repo.listElements(apiary.id)) {
    if (!e.isHive) continue;
    await repo.addParameterRecord(frames, '${n++}', e.entity);
  }
}

// ---------------------------------------------------------------------------
// QR-код
// ---------------------------------------------------------------------------

List<GuideStep> _qrSteps() {
  final t = tr.guideQr;
  return [
    GuideStep.look(_t(t, 0), target: 'qr-legend', pic: LessonPic.professor),
    GuideStep.tap('qr-generate', _t(t, 1), pic: LessonPic.professor),
    GuideStep.look(_t(t, 2), target: 'qr-print', pic: LessonPic.blueprint),
    GuideStep.look(_t(t, 3), pic: LessonPic.scheming),
    GuideStep.done(_t(t, 4), pic: LessonPic.surprised),
  ];
}

// ---------------------------------------------------------------------------
// Фінанси
// ---------------------------------------------------------------------------

List<GuideStep> _financeSteps() {
  final t = tr.guideFinance;
  return [
    GuideStep.look(_t(t, 0), target: 'fin-segment', pic: LessonPic.scheming),
    GuideStep.look(_t(t, 1), target: 'fin-period', pic: LessonPic.scheming),
    GuideStep.look(_t(t, 2), target: 'fin-donut', pic: LessonPic.surprised),
    GuideStep.tap('fin-add', _t(t, 3), pic: LessonPic.scheming),
    GuideStep.free(_t(t, 4), waitFor: 'fin-donut', pic: LessonPic.scheming),
    GuideStep.look(_t(t, 5), target: 'fin-menu', pic: LessonPic.thinking),
    GuideStep.done(_t(t, 6)),
  ];
}

/// Кілька витрат і дохід цього місяця - щоб кільце не було порожнім.
Future<void> _seedFinance(Repository repo) async {
  final now = DateTime.now();
  final exp = await repo.listFinCategories(kind: kFinExpense);
  final inc = await repo.listFinCategories(kind: kFinIncome);
  final amounts = [4350.0, 1200.0, 900.0];
  for (var i = 0; i < amounts.length && i < exp.length; i++) {
    await repo.addFinOp(kind: kFinExpense, categoryId: exp[i].id, amount: amounts[i], date: now);
  }
  if (inc.isNotEmpty) {
    await repo.addFinOp(kind: kFinIncome, categoryId: inc.first.id, amount: 14000, date: now);
  }
}

// ---------------------------------------------------------------------------

/// Уроки-екскурсії в плитках «Навчання» (після уроків з [kLessons]).
List<GuidedLesson> get kGuidedLessons => [
      GuidedLesson(
        id: 'qr',
        title: () => tr.qrCode,
        image: 'assets/guide/beekeeper_professor.webp',
        steps: _qrSteps,
        start: (repo) async {
          final a = await seedGuideApiary(repo);
          return QrGenerateScreen(repo: repo, apiary: a);
        },
      ),
      GuidedLesson(
        id: 'stock',
        title: () => tr.stock,
        image: 'assets/guide/beekeeper_laptop.webp',
        steps: _stockSteps,
        start: (repo) async {
          await _seedStock(repo);
          return StockScreen(repo: repo);
        },
      ),
      GuidedLesson(
        id: 'history',
        title: () => tr.history,
        image: 'assets/guide/beekeeper_newspaper.webp',
        steps: _historySteps,
        start: (repo) async {
          await _seedHistory(repo);
          return HistoryHubScreen(repo: repo, apiary: (await repo.listApiaries()).first);
        },
      ),
      GuidedLesson(
        id: 'finance',
        title: () => tr.finances,
        image: 'assets/guide/beekeeper_scheming.webp',
        steps: _financeSteps,
        start: (repo) async {
          await _seedFinance(repo);
          return FinanceScreen(repo: repo);
        },
      ),
    ];

/// Для тестів: перший екран уроку без пісочниці.
@visibleForTesting
Future<Widget> startGuided(GuidedLesson l, Repository repo) => l.start(repo);
