import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../tutorial/lesson.dart';
import 'settings_main_tab.dart';
import 'templates_screen.dart';

/// Шестерня «Налаштування» (карта й головний екран).
class GearButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;
  final Color? bg;
  const GearButton({super.key, required this.onPressed, this.size = 48, this.bg});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tr.settingsTitle,
        child: Material(
          color: bg ?? AppColors.roundBtn,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
                dimension: size,
                child: Icon(Icons.settings, size: size * 0.55, color: AppColors.text)),
          ),
        ),
      );
}

/// «Налаштування»: вкладки «Головне» (розмір шрифту), «Шаблони» і «Акаунт»
/// (вхід, синхронізація, резервні копії, видалення акаунта; свайпом теж).
/// В уроці вкладки «Акаунт» немає (там - справжні дані). Параметри створюються й перейменовуються в
/// «Таблиці параметрів» вулика. Історії тут немає - вона лише по картах.
class SettingsScreen extends StatefulWidget {
  final Repository repo;

  /// Урок «Шаблони».
  final LessonController? lesson;
  const SettingsScreen({super.key, required this.repo, this.lesson});

  static Future<void> open(NavigatorState nav, Repository repo, {LessonController? lesson}) =>
      nav.push(MaterialPageRoute(builder: (_) => SettingsScreen(repo: repo, lesson: lesson)));

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tab = 0;
  final _templates = GlobalKey<TemplatesScreenState>();

  LessonController? get _lesson => widget.lesson;

  @override
  void initState() {
    super.initState();
    final l = _lesson;
    if (l != null) {
      _tab = l.step >= 4 ? 1 : 0;
      l.addListener(_onLesson);
      // продовжений урок: шаблон малювали - знову редактор
      if (l.step >= 5 && l.step <= 11) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _templates.currentState?.openNew());
      }
    }
  }

  @override
  void dispose() {
    _lesson?.removeListener(_onLesson);
    super.dispose();
  }

  /// Урок сам гортає вкладки: «Головне» → «Шаблони».
  void _onLesson() {
    final want = (_lesson?.step ?? 0) >= 4 ? 1 : 0;
    if (mounted && want != _tab) setState(() => _tab = want);
  }

  void _back() {
    if (_lesson != null) {
      _lesson!.exit();
      return;
    }
    Navigator.maybePop(context);
  }

  Widget _tabButton(String text, int i) => Expanded(
        child: PillButton(
          text: text,
          bg: _tab == i ? AppColors.accent : AppColors.darkBtn,
          fg: _tab == i ? Colors.white : AppColors.text,
          height: 40,
          fontSize: 13,
          onPressed: () => setState(() => _tab = i),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = _lesson;
    return PopScope(
      canPop: l == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              TopBar(title: tr.settingsTitle, onBack: _back),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(children: [
                  _tabButton(tr.settingsTabMain, 0),
                  const SizedBox(width: 8),
                  _tabButton(tr.settingsTabTemplates, 1),
                  if (l == null) ...[
                    const SizedBox(width: 8),
                    _tabButton(tr.settingsTabAccount, 2),
                  ],
                ]),
              ),
              Expanded(
                child: TabSwipe(
                  index: _tab,
                  count: l == null ? 3 : 2,
                  // в уроці вкладку веде урок - свайп не збиває крок
                  onChanged: (i) {
                    if (l == null) setState(() => _tab = i);
                  },
                  child: switch (_tab) {
                    0 => MainSettingsTab(repo: widget.repo),
                    1 => TemplatesScreen(key: _templates, repo: widget.repo, embedded: true, lesson: l),
                    _ => AccountSettingsTab(repo: widget.repo),
                  },
                ),
              ),
              // місце під пасічника з хмаркою
              if (l != null) const SizedBox(height: kLessonReserve),
            ]),
            const Positioned.fill(child: ScreenFrame()),
            if (l != null) Positioned.fill(child: LessonLayer(lesson: l, screen: 'settings')),
          ]),
        ),
      ),
    );
  }
}
