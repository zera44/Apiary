import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../logic/visit_reminders.dart';
import '../services/auth.dart';
import '../ui/app_drawer.dart';
import '../ui/app_logo.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'apiary_list_screen.dart';
import 'feedback_screen.dart';
import 'map_screen.dart';
import 'splash_screen.dart';
import 'stock_screen.dart';
import 'tutorial_screen.dart';

/// Головний екран (після «Почати» на заставці): назва застосунку й кнопки
/// «Почати» (мої пасіки), «Сканувати QR-код» (відкрити вулик за наліпкою),
/// «Склад», «Пройти навчання», «Зворотний зв'язок». Внизу — хто увійшов і
/// «Вийти» (назад на екран входу).
/// «Почати»: остання відкрита (або єдина) пасіка — одразу її карта («назад» —
/// на головний екран; список пасік — через меню ☰); інакше — список.
Future<void> openStart(NavigatorState nav, Repository repo) async {
  final a = await repo.startApiary();
  if (!nav.mounted) return;
  await nav.push(MaterialPageRoute(
    builder: (_) => a == null ? ApiaryListScreen(repo: repo) : MapScreen(repo: repo, apiary: a),
  ));
}

class HomeScreen extends StatelessWidget {
  final Repository repo;
  final AuthService auth;
  const HomeScreen({super.key, required this.repo, required this.auth});

  /// Гість входить пізніше: дані на пристрої лишаються, головний екран
  /// оновлюється (пошта й «Вийти»).
  Future<void> _signIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.signIn();
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HomeScreen(repo: repo, auth: auth),
      ));
    } on SignInCancelled {
      // передумали
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Не вдалося увійти. Перевірте інтернет і спробуйте ще раз.')));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showConfirm(context,
        title: 'Вийти?',
        text: 'Дані пасік лишаються на цьому пристрої. Далі — знову увійти або продовжити без входу.',
        confirmText: 'Вийти');
    if (!ok || !context.mounted) return;
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SplashScreen(repo: repo, auth: auth)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget button(String text, Color bg, VoidCallback onPressed, {Color fg = Colors.white}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PillButton(
            text: text,
            bg: bg,
            fg: fg,
            width: 240,
            height: 52,
            radius: 18,
            fontSize: 16,
            onPressed: onPressed,
          ),
        );

    final user = auth.user;
    return Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Center(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const AppLogo(size: 128),
                  const SizedBox(height: 20),
                  Text('Vulyk',
                      style: TextStyle(
                          color: AppColors.text, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Моя пасіка', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                  const SizedBox(height: 28),
                  _DueToday(repo: repo),
                  _BuySoon(repo: repo),
                  const SizedBox(height: 12),
                  button('Почати', AppColors.accent, () => openStart(Navigator.of(context), repo)),
                  button('Сканувати QR-код', AppColors.darkBtn,
                      () => AppDrawer.openHiveByQr(Navigator.of(context), repo),
                      fg: AppColors.text),
                  button('Склад', AppColors.darkBtn, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StockScreen(repo: repo), // вкладка «Прихід»
                    ));
                  }, fg: AppColors.text),
                  button('Пройти навчання', AppColors.darkBtn, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TutorialScreen(),
                    ));
                  }, fg: AppColors.text),
                  button("Зворотний зв'язок", AppColors.darkBtn, () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const FeedbackScreen(),
                    ));
                  }, fg: AppColors.text),
                  if (user != null) ...[
                    const SizedBox(height: 18),
                    Text(user.email,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    TextButton(
                      onPressed: () => _signOut(context),
                      child: Text('Вийти', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ] else if (auth.configured) ...[
                    // гість: увійти пізніше, щоб синхронізувати (дані лишаються)
                    const SizedBox(height: 18),
                    Text('Дані лише на цьому пристрої',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    TextButton(
                      onPressed: () => _signIn(context),
                      child: Text('Увійти через Google для синхронізації',
                          style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              ),
            ),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
    );
  }
}

/// «Сьогодні оглянути: N» — вулики, у яких настав час огляду (за
/// періодичністю обходу). Тап — найдавніший із них одразу з формою; далі
/// «Зберегти й далі» веде до наступного простроченого.
class _DueToday extends StatefulWidget {
  final Repository repo;
  const _DueToday({required this.repo});
  @override
  State<_DueToday> createState() => _DueTodayState();
}

class _DueTodayState extends State<_DueToday> {
  List<({VisitTarget t, DateTime at})> _due = const [];

  @override
  void initState() {
    super.initState();
    widget.repo.remindersChanged.addListener(_load);
    widget.repo.mapChanges.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repo.remindersChanged.removeListener(_load);
    widget.repo.mapChanges.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final due = [
      for (final t in await widget.repo.visitTargets())
        if (dueReminder(t, now: now) case final d?) (t: t, at: d.when)
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (mounted) setState(() => _due = due);
  }

  Future<void> _openFirst() async {
    final nav = Navigator.of(context);
    final el = await widget.repo.getElement(_due.first.t.elementId);
    final aid = el?.apiaryId;
    if (el == null || aid == null) return;
    final a = await widget.repo.getApiary(aid);
    if (a == null || !nav.mounted) return;
    AppDrawer.openHive(nav, widget.repo, a, el.id, fill: true, next: NextHive.overdue);
  }

  @override
  Widget build(BuildContext context) {
    if (_due.isEmpty) return const SizedBox.shrink();
    return Material(
      color: AppColors.danger.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openFirst,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Сьогодні оглянути: ${_due.length}',
                style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('Почати →', style: TextStyle(color: AppColors.create, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// «Час докупити: N» — номенклатура, що дійшла до мінімального залишку.
/// Тап — склад (вкладка «Прихід»).
class _BuySoon extends StatefulWidget {
  final Repository repo;
  const _BuySoon({required this.repo});
  @override
  State<_BuySoon> createState() => _BuySoonState();
}

class _BuySoonState extends State<_BuySoon> {
  List<String> _names = const [];

  @override
  void initState() {
    super.initState();
    widget.repo.stockChanges.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repo.stockChanges.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final low = [for (final it in await widget.repo.listStockItems()) if (it.low) it.name];
    if (mounted) setState(() => _names = low);
  }

  @override
  Widget build(BuildContext context) {
    if (_names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: AppColors.create.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => StockScreen(repo: widget.repo))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                'Час докупити: ${_names.join(', ')}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
