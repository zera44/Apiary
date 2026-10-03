import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/visit_reminders.dart';
import '../services/auth.dart';
import '../ui/app_drawer.dart';
import '../ui/app_logo.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/hive_postbox.dart';
import '../ui/theme.dart';
import 'apiary_list_screen.dart';
import 'feedback_screen.dart';
import 'map_screen.dart';
import 'splash_screen.dart';
import 'stock_screen.dart';
import '../ui/pill_choice.dart';
import 'tutorial_screen.dart';
import 'whats_new_screen.dart';

/// Головний екран (після «Почати» на заставці): назва застосунку й кнопки
/// «Почати» (мої пасіки), «Сканувати QR-код» (відкрити вулик за наліпкою),
/// «Склад», «Пройти навчання», «Зворотний зв'язок». Внизу — хто увійшов і
/// «Вийти» (назад на екран входу).
/// «Почати»: остання відкрита (або єдина) пасіка — одразу її карта («назад» —
/// на головний екран; список пасік — через меню ☰); інакше — список.
Future<void> openStart(NavigatorState nav, Repository repo, {bool instant = false}) async {
  // перший «Почати» на щойно встановленому застосунку: пасічник пропонує вибір
  // (червона - навчання, синя - без нього); показується один раз
  if (await repo.getMeta('intro_done') == null && (await repo.listApiaries()).isEmpty) {
    if (!nav.mounted) return;
    // червона: урок одразу стає на місце сторінки вибору (без проміжних екранів)
    final learn = await showPillChoice(nav,
        onLearn: (_) => TutorialScreen(realRepo: repo, autoStart: true));
    if (learn == null || !nav.mounted) return; // передумали - лишились на головному
    // червона: позначка ставиться лише в кінці навчання (TutorialScreen) —
    // вийшли посеред уроку, і наступне «Почати» знову пропонує вибір
    if (!learn) await repo.setMeta('intro_done', '1');
    if (learn) return; // урок уже відкрито замість сторінки вибору
  }
  final a = await repo.startApiary();
  if (!nav.mounted) return;
  Widget page(BuildContext _) =>
      a == null ? ApiaryListScreen(repo: repo) : MapScreen(repo: repo, apiary: a);
  // меню лежало поверх цієї ж карти — «зникає» без переходу
  await nav.push(instant
      ? PageRouteBuilder<void>(
          pageBuilder: (c, _, __) => page(c),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero)
      : MaterialPageRoute(builder: page));
}

class HomeScreen extends StatefulWidget {
  final Repository repo;
  final AuthService auth;

  /// Показувати під меню останню карту (неклікабельну); тести вимикають.
  static bool mapBackdrop = true;
  const HomeScreen({super.key, required this.repo, required this.auth});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Repository get repo => widget.repo;
  AuthService get auth => widget.auth;
  Apiary? _backdrop;

  @override
  void initState() {
    super.initState();
    if (HomeScreen.mapBackdrop) _loadBackdrop();
  }

  Future<void> _loadBackdrop() async {
    final a = await repo.startApiary();
    if (a != null && mounted) setState(() => _backdrop = a);
  }

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
        text: 'Дані пасік лишаються на цьому пристрої. Далі - знову увійти або продовжити без входу.',
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
    final user = auth.user;
    final nav = Navigator.of(context);
    void push(Widget w) => nav.push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          if (_backdrop == null)
            const Positioned.fill(child: _HoneycombBackdrop())
          else ...[
            // остання карта під меню: видно, але не реагує на дотики
            Positioned.fill(
                child: IgnorePointer(child: MapScreen(repo: repo, apiary: _backdrop!))),
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.5))),
          ],
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const AppLogo(size: 104),
                  const SizedBox(height: 10),
                  Text('Vulyk',
                      style: TextStyle(
                          color: AppColors.text, fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  // панель у стилі вулика: медова рамка, пасічник-порадник,
                  // «Почати» і піктограми решти розділів
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    decoration: BoxDecoration(
                      color: AppColors.popupBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.hive, width: 2.5),
                    ),
                    child: Column(children: [
                      _Banner(text: _greeting()),
                      const SizedBox(height: 10),
                      _Advisor(repo: repo),
                      const SizedBox(height: 14),
                      PillButton(
                        text: 'Почати',
                        bg: AppColors.accent,
                        width: double.infinity,
                        height: 56,
                        radius: 18,
                        fontSize: 18,
                        onPressed: () => openStart(nav, repo, instant: _backdrop != null),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        _Tile(
                            icon: AppIcon('box', size: 30, color: AppColors.text),
                            label: 'Склад',
                            onTap: () => push(StockScreen(repo: repo))), // вкладка «Прихід»
                        _Tile(
                            icon: Icon(Icons.school_outlined, size: 30, color: AppColors.text),
                            label: 'Навчання',
                            onTap: () => push(TutorialScreen(realRepo: repo))),
                        _Tile(
                            icon: AppIcon('pencil', size: 28, color: AppColors.text),
                            label: 'Відгук',
                            onTap: () => push(const FeedbackScreen())),
                        _Tile(
                            icon: Icon(Icons.new_releases_outlined,
                                size: 30, color: AppColors.text),
                            label: 'Що нового',
                            onTap: () => WhatsNewScreen.open(nav)),
                      ]),
                    ]),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 14),
                    Text(user.email,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    TextButton(
                      onPressed: () => _signOut(context),
                      child: Text('Вийти', style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ] else if (auth.configured) ...[
                    // гість: увійти пізніше, щоб синхронізувати (дані лишаються)
                    const SizedBox(height: 14),
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
          ),
          // сканер QR — значком у правому верхньому куті
          Positioned(
            top: 12,
            right: 12,
            child: CircleIconButton(
              icon: 'qr',
              bg: AppColors.darkBtn,
              iconColor: AppColors.text,
              size: 48,
              tooltip: 'Сканувати QR-код',
              onPressed: () => AppDrawer.openHiveByQr(nav, repo),
            ),
          ),
          const Positioned.fill(child: ScreenFrame()),
          _StartupPrompts(repo: repo),
        ]),
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Доброї ночі, пасічнику!';
    if (h < 12) return 'Доброго ранку, пасічнику!';
    if (h < 18) return 'Доброго дня, пасічнику!';
    return 'Доброго вечора, пасічнику!';
  }
}

/// Стрічка-заголовок панелі (як табличка на вулику).
class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.hive,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF3A2410), fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

/// Піктограма розділу: значок і підпис, уся плитка натискається.
class _Tile extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: AppColors.darkBtn,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                height: 78,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hive.withValues(alpha: 0.35)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconTheme(data: IconThemeData(color: AppColors.text), child: icon),
                  const SizedBox(height: 6),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Ледь помітні медові соти на тлі.
class _HoneycombBackdrop extends StatelessWidget {
  const _HoneycombBackdrop();
  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _HoneycombPainter(AppColors.hive)));
}

class _HoneycombPainter extends CustomPainter {
  final Color color;
  _HoneycombPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const r = 26.0;
    final w = r * 1.7320508; // √3·r — ширина шестикутника
    final paint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    var row = 0;
    for (var y = 0.0; y < size.height + r; y += r * 1.5, row++) {
      for (var x = (row.isOdd ? w / 2 : 0.0); x < size.width + w; x += w) {
        final path = Path();
        for (var k = 0; k < 6; k++) {
          final a = (60 * k - 30) * 3.1415926535 / 180;
          final p = Offset(x + r * math.cos(a), y + r * math.sin(a));
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HoneycombPainter old) => old.color != color;
}

/// Пасічник-порадник і вулик-поштомат: спершу важливе (прострочені огляди, що докупити) —
/// натискання веде туди; далі — поради. Натискання на пораду — наступна.
class _Advisor extends StatefulWidget {
  final Repository repo;
  const _Advisor({required this.repo});
  @override
  State<_Advisor> createState() => _AdvisorState();
}

class _AdvisorState extends State<_Advisor> {
  static const _tips = [
    'Утримайте вулик на карті - і одразу перетягуйте його на нове місце.',
    'В огляді «Зберегти», «Змін немає» і «Пропустити» одразу відкривають наступний вулик.',
    'Обрали новий параметр зі списку і не знаходите кнопку «Зберегти»? Це тому, що всі зміни зберігаються автоматично.',
    'Наклейте QR-наліпки - і вулик відкриється з камери за секунду.',
    'Задайте мінімальний залишок на складі - я нагадаю, коли час докупити.',
    'Звіт по пасіці в Excel - у меню ☰ → «Історія».',
    'Періодичність обходу задається одна на всю пасіку - у її налаштуваннях.',
    'Якщо для вулика треба інший час обходу - торкніться «Періодичність обходу» на його панелі.',
  ];

  List<({VisitTarget t, DateTime at})> _due = const [];
  List<String> _low = const [];
  int _i = 0;

  @override
  void initState() {
    super.initState();
    widget.repo.remindersChanged.addListener(_load);
    widget.repo.mapChanges.addListener(_load);
    widget.repo.stockChanges.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repo.remindersChanged.removeListener(_load);
    widget.repo.mapChanges.removeListener(_load);
    widget.repo.stockChanges.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final due = [
      for (final t in await widget.repo.visitTargets())
        if (dueReminder(t, now: now) case final d?) (t: t, at: d.when)
    ]..sort((a, b) => a.at.compareTo(b.at));
    final low = [for (final it in await widget.repo.listStockItems()) if (it.low) it.name];
    if (mounted) {
      setState(() {
        _due = due;
        _low = low;
      });
    }
  }

  Future<void> _openFirstDue() async {
    final nav = Navigator.of(context);
    final el = await widget.repo.getElement(_due.first.t.elementId);
    final aid = el?.apiaryId;
    if (el == null || aid == null) return;
    final a = await widget.repo.getApiary(aid);
    if (a == null || !nav.mounted) return;
    AppDrawer.openHive(nav, widget.repo, a, el.id, fill: true, next: NextHive.overdue);
  }

  /// Повідомлення по черзі: спершу важливе (з дією) — це «пошта» у
  /// вулику-поштоматі, далі поради пасічника.
  List<({String text, VoidCallback? action})> get _messages => [
        if (_due.isNotEmpty) (text: 'Сьогодні оглянути: ${_due.length}', action: _openFirstDue),
        if (_low.isNotEmpty)
          (
            text: 'Час докупити: ${_low.join(', ')}',
            action: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => StockScreen(repo: widget.repo))),
          ),
        for (final t in _tips) (text: t, action: null),
      ];

  int get _mail => (_due.isNotEmpty ? 1 : 0) + (_low.isNotEmpty ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final list = _messages;
    final m = list[_i % list.length];
    final action = m.action;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Image.asset('assets/guide/beekeeper.webp',
          height: 100, width: 72, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      const SizedBox(width: 4),
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: action ?? () => setState(() => _i++),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            // фіксована висота: довша репліка не розсуває екран
            height: 116,
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 7),
            decoration: BoxDecoration(
              color: AppColors.card,
              // гострий кут — до пасічника (говорить він)
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(
                  color: action != null ? AppColors.danger : AppColors.create, width: 1.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Align(
                alignment: Alignment.topLeft,
                child: Text.rich(
                  // **слово** — медовим напівжирним
                  TextSpan(children: [
                    for (final (i, part) in m.text.split('**').indexed)
                      i.isOdd
                          ? TextSpan(
                              text: part,
                              style: TextStyle(
                                  color: AppColors.create, fontWeight: FontWeight.w600))
                          : TextSpan(text: part),
                  ]),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: action != null ? 15 : 13,
                      height: 1.3,
                      fontWeight: action != null ? FontWeight.w700 : FontWeight.w400)),
              )),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(action != null ? 'Натисніть - перейти' : 'Натисніть - далі',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ),
                // наступне повідомлення, навіть коли це — з дією
                if (action != null)
                  InkWell(
                    onTap: () => setState(() => _i++),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 4),
      // вулик-поштомат: значок — скільки важливих повідомлень; натиснули —
      // пасічник показує першу «пошту»
      Tooltip(
        message: 'Пошта',
        child: HivePostbox(
          count: _mail,
          height: 104,
          // «пошта» - одразу дія (відкрити вулик / склад); якщо зараз порада - показати пошту
          onTap: () {
            if (action != null) {
              action();
            } else {
              setState(() => _i = _mail > 0 ? 0 : _i + 1);
            }
          },
        ),
      ),
    ]);
  }
}

class _StartupPrompts extends StatefulWidget {
  final Repository repo;
  const _StartupPrompts({required this.repo});
  @override
  State<_StartupPrompts> createState() => _StartupPromptsState();
}

class _StartupPromptsState extends State<_StartupPrompts> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // підказки головного екрана немає: новачка зустрічає пасічник із вибором
      await WhatsNewScreen.maybeShow(context, widget.repo);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
