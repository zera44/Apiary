import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/sync_api.dart';
import '../data/sync_service.dart';
import '../l10n/l10n.dart';
import '../services/background.dart';
import '../services/auth.dart';
import '../services/backups.dart';
import '../services/server.dart';
import '../services/server_backups.dart';
import '../ui/common.dart';
import '../ui/sync_status.dart';
import '../ui/text_scale.dart';
import '../ui/theme.dart';
import 'backups_screen.dart';
import 'splash_screen.dart';

/// Налаштування → «Головне». Тут - усе про дані користувача: синхронізація,
/// резервні копії (а далі - мобільний інтернет, акаунт, політика
/// конфіденційності).
///
/// [lesson] - вкладку показує урок (пісочниця): лише перегляд, без кнопок,
/// що чіпають справжні дані.
class MainSettingsTab extends StatefulWidget {
  final Repository repo;
  final bool lesson;
  const MainSettingsTab({super.key, required this.repo, this.lesson = false});

  @override
  State<MainSettingsTab> createState() => _MainSettingsTabState();
}

class _MainSettingsTabState extends State<MainSettingsTab> {
  String? _backups;
  bool? _mobile;
  bool _busy = false;

  SyncService? get _sync => SyncService.current;

  @override
  void initState() {
    super.initState();
    if (!widget.lesson) {
      _loadBackups();
      _loadMobile();
    }
  }

  Future<void> _loadMobile() async {
    final s = _sync;
    if (s == null || !s.configured) return;
    final v = await s.mobileAllowed();
    if (mounted) setState(() => _mobile = v);
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _syncNow() async {
    final s = _sync;
    if (s == null || _busy) return;
    setState(() => _busy = true);
    try {
      final r = await s.syncNow();
      final i = SyncService.info.value;
      if (!mounted) return;
      if (r != null) {
        _say(tr.syncDone);
      } else if (i.error != null) {
        _say(tr.syncError(i.error!));
      } else if (i.waitingWifi) {
        _say(tr.syncWaitingWifi);
      } else if (i.offline) {
        _say(tr.syncOffline);
      } else {
        _say(tr.syncRunning); // саме синхронізує фонове завдання
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Перемикач мобільного інтернету: перше ввімкнення - з поясненням про
  /// трафік (один раз).
  Future<void> _setMobile(bool on) async {
    final s = _sync;
    if (s == null) return;
    if (on && (await s.repo.getMeta(SyncService.mobileWarnedKey)) != '1') {
      if (!mounted) return;
      final ok = await showConfirm(context,
          title: tr.syncMobileWarnTitle,
          text: tr.syncMobileWarnText,
          confirmText: tr.syncMobile,
          danger: false,
          cancelText: tr.cancel);
      if (!ok) return;
      await s.repo.setMeta(SyncService.mobileWarnedKey, '1');
    }
    await s.setMobileAllowed(on);
    unawaited(BackgroundTasks.registerSync(mobile: on).catchError((Object _) {}));
    if (mounted) setState(() => _mobile = on);
  }

  /// «Завантажити з сервера»: вибір однієї з двох копій, підтвердження,
  /// копія поточного стану на телефоні, потім - дані з сервера.
  Future<void> _serverRestore() async {
    final api = Server.api ?? _sync?.api;
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      final local = await BackupService.of(widget.repo);
      final server = ServerBackups(widget.repo, api, local);
      final List<ServerBackup> list;
      try {
        list = await server.list();
      } catch (e) {
        if (mounted) _say(tr.serverRestoreFailed('$e'));
        return;
      }
      if (!mounted) return;
      if (list.isEmpty) {
        _say(tr.serverBackupsNone);
        return;
      }
      final b = await showModalBottomSheet<ServerBackup>(
        context: context,
        backgroundColor: AppColors.popupBg,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(tr.serverRestoreChoose,
                  style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final x in list)
              ListTile(
                leading: Icon(Icons.cloud_download_outlined, color: AppColors.text),
                title: Text(tr.serverBackupItem(formatWhen(x.createdAt), tr.fileSize(x.size)),
                    style: TextStyle(color: AppColors.text)),
                onTap: () => Navigator.pop(ctx, x),
              ),
          ]),
        ),
      );
      if (b == null || !mounted) return;
      final ok = await showConfirm(context,
          title: tr.serverRestoreTitle,
          text: tr.serverRestoreText(formatWhen(b.createdAt)),
          confirmText: tr.serverRestore,
          cancelText: tr.cancel);
      if (!ok || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      messenger.showSnackBar(SnackBar(content: Text(tr.serverRestoring)));
      try {
        final before = await server.restore(b);
        // усі відкриті екрани показували старі дані - на головний
        nav.popUntil((r) => r.isFirst);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(tr.serverRestored),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: tr.undo,
              onPressed: () async {
                try {
                  await local.restoreFrom(before.path);
                  messenger.showSnackBar(SnackBar(content: Text(tr.backupUndone)));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(tr.backupRestoreFailed('$e'))));
                }
              },
            ),
          ));
        unawaited(SyncService.now());
      } catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tr.serverRestoreFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _signInAgain = false;

  Future<void> _loadSignInAgain() async {
    final v = await Server.needsSignInAgain(widget.repo);
    if (mounted && v != _signInAgain) setState(() => _signInAgain = v);
  }

  Future<void> _doSignInAgain() async {
    final auth = Server.auth;
    if (auth == null || _busy) return;
    setState(() => _busy = true);
    try {
      await auth.signIn();
      await Server.connect(widget.repo, auth);
    } catch (e) {
      if (mounted) _say(tr.syncError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadSignInAgain();
    }
  }

  List<Widget> _syncControls() {
    final s = _sync;
    if (widget.lesson || s == null || !s.configured) return const [];
    unawaited(_loadSignInAgain());
    final on = s.enabled && !_busy;
    return [
      if (_signInAgain && !s.enabled) ...[
        const SizedBox(height: 8),
        Text(tr.syncSignInAgainHint, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 8),
        PillButton(
          text: tr.syncSignInAgain,
          bg: AppColors.accent,
          height: 40,
          width: double.infinity,
          onPressed: _busy ? null : _doSignInAgain,
        ),
      ],
      const SizedBox(height: 10),
      PillButton(
        text: tr.syncNow,
        bg: AppColors.accent,
        height: 40,
        width: double.infinity,
        onPressed: on ? _syncNow : null,
      ),
      const SizedBox(height: 8),
      PillButton(
        text: tr.serverRestore,
        bg: AppColors.darkBtn,
        fg: AppColors.text,
        height: 40,
        width: double.infinity,
        onPressed: on ? _serverRestore : null,
      ),
      if (_mobile != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr.syncMobile, style: TextStyle(color: AppColors.text, fontSize: 14)),
          value: _mobile!,
          onChanged: _setMobile,
        ),
    ];
  }

  Future<void> _loadBackups() async {
    try {
      final latest = await (await BackupService.of(widget.repo)).latest();
      if (mounted) setState(() => _backups = backupsSummary(latest));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!widget.lesson) _TextSizeSection(repo: widget.repo),
          SettingsSection(
            title: tr.syncSection,
            children: [
              const SyncStatusLine(textAlign: TextAlign.start, fontSize: 13.5),
              // вхід на сервер міг завершитися вже після відкриття вкладки
              ValueListenableBuilder<SyncInfo>(
                valueListenable: SyncService.info,
                builder: (_, _, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _syncControls(),
                ),
              ),
            ],
          ),
          if (!widget.lesson)
            SettingsSection(
              title: tr.backupsSection,
              children: [
                Text(_backups ?? '',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
                const SizedBox(height: 10),
                PillButton(
                  text: tr.backupsSection,
                  bg: AppColors.darkBtn,
                  fg: AppColors.text,
                  height: 40,
                  width: double.infinity,
                  onPressed: () async {
                    await BackupsScreen.open(context, widget.repo);
                    await _loadBackups();
                  },
                ),
              ],
            ),
          if (!widget.lesson)
            SettingsSection(
              title: tr.accountSection,
              children: [
                if (Server.auth?.user case final u?) ...[
                  _AccountCard(user: u),
                  const SizedBox(height: 12),
                  PillButton(
                    text: tr.accountSignOut,
                    bg: AppColors.darkBtn,
                    fg: AppColors.text,
                    height: 40,
                    width: double.infinity,
                    onPressed: _busy ? null : _signOut,
                  ),
                ] else
                  Text(tr.accountGuest, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
                const SizedBox(height: 4),
                _AccountLink(
                  icon: Icons.privacy_tip_outlined,
                  text: tr.privacyPolicy,
                  color: AppColors.text,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.popupBg,
                      title: Text(tr.privacyPolicy, style: TextStyle(color: AppColors.text)),
                      content: Text(tr.privacySoon, style: TextStyle(color: AppColors.text)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.close)),
                      ],
                    ),
                  ),
                ),
                if (Server.auth?.user != null)
                  _AccountLink(
                    icon: Icons.delete_outline,
                    text: tr.accountDelete,
                    color: AppColors.danger,
                    onTap: _busy ? null : _deleteAccount,
                  ),
              ],
            ),
        ],
      );

  /// «Вийти»: з підтвердженням; дані лишаються на телефоні, далі - екран
  /// входу.
  Future<void> _signOut() async {
    final auth = Server.auth;
    if (auth == null) return;
    final ok = await showConfirm(context,
        title: tr.accountSignOutTitle,
        text: tr.accountSignOutText,
        confirmText: tr.accountSignOut,
        cancelText: tr.cancel);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await Server.signOut(widget.repo);
    await auth.signOut();
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SplashScreen(repo: widget.repo, auth: auth)),
      (_) => false,
    );
  }

  /// «Видалити акаунт і всі дані»: два підтвердження (друге - написати
  /// слово), потім сервер, телефон і вихід.
  Future<void> _deleteAccount() async {
    final first = await showConfirm(context,
        title: tr.accountDeleteTitle,
        text: tr.accountDeleteText,
        confirmText: tr.accountDeleteContinue,
        cancelText: tr.cancel);
    if (!first || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (_) => const _TypeToConfirm(),
    );
    if (second != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    messenger.showSnackBar(SnackBar(content: Text(tr.accountDeleting)));
    try {
      await Server.deleteAccount(widget.repo);
      final auth = Server.auth;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr.accountDeleted)));
      if (auth != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => SplashScreen(repo: widget.repo, auth: auth)),
          (_) => false,
        );
      }
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr.accountDeleteFailed('$e'))));
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// «Розмір шрифту»: чотири кнопки «А» зростаючого розміру, назва рівня й
/// зразок тексту (одразу в новому розмірі).
class _TextSizeSection extends StatelessWidget {
  final Repository repo;
  const _TextSizeSection({required this.repo});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: AppTextScale.value,
        builder: (context, current, _) {
          final levels = AppTextScale.levels;
          final i = levels.indexOf(current);
          return SettingsSection(
            title: tr.textSizeSection,
            children: [
              Text(tr.textSizeHint, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
              const SizedBox(height: 10),
              Row(children: [
                for (var j = 0; j < levels.length; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: j == i,
                      label: tr.textSizeLevels[j],
                      child: InkWell(
                        key: ValueKey('text-size-$j'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => AppTextScale.set(repo, levels[j]),
                        child: Container(
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: j == i ? AppColors.create : AppColors.darkBtn,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          // «А» - завжди однаковий крок, незалежно від обраного
                          child: Text('А',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: j == i ? AppColors.bg : AppColors.text,
                                fontSize: 16 + j * 6.0,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 10),
              Text(tr.textSizeLevels[i < 0 ? 0 : i],
                  style: TextStyle(color: AppColors.create, fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(tr.textSizePreview, style: TextStyle(color: AppColors.text, fontSize: 15)),
            ],
          );
        },
      );
}

/// Хто увійшов: кружечок із першою літерою, ім'я, пошта.
class _AccountCard extends StatelessWidget {
  final AppUser user;
  const _AccountCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = user.name.trim().isEmpty ? user.email.split('@').first : user.name.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkBtn,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
            border: Border.all(color: AppColors.hive, width: 2),
          ),
          child: Text(name.characters.first.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.verified_user_outlined, size: 14, color: AppColors.create),
              const SizedBox(width: 4),
              Text(tr.accountSignedInVia, style: TextStyle(color: AppColors.create, fontSize: 12)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Рядок-посилання розділу «Акаунт» (політика, видалення).
class _AccountLink extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const _AccountLink({required this.icon, required this.text, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 14.5))),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ]),
        ),
      );
}

/// Друге підтвердження: написати слово [AppStrings.accountDeleteWord].
class _TypeToConfirm extends StatefulWidget {
  const _TypeToConfirm();
  @override
  State<_TypeToConfirm> createState() => _TypeToConfirmState();
}

class _TypeToConfirmState extends State<_TypeToConfirm> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _ok => _c.text.trim().toUpperCase() == tr.accountDeleteWord;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppColors.popupBg,
        title: Text(tr.accountDeleteFinalTitle, style: TextStyle(color: AppColors.text)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr.accountDeleteFinalText, style: TextStyle(color: AppColors.text)),
          const SizedBox(height: 10),
          TextField(
            controller: _c,
            autofocus: true,
            style: TextStyle(color: AppColors.text),
            decoration: InputDecoration(hintText: tr.accountDeleteWord),
            onChanged: (_) => setState(() {}),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
          PillButton(
            text: tr.accountDelete,
            bg: AppColors.danger,
            height: 38,
            onPressed: _ok ? () => Navigator.pop(context, true) : null,
          ),
        ],
      );
}

/// Розділ налаштувань: заголовок і вміст у рамці.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hive.withValues(alpha: 0.35)),
        ),
        // свій шар Material: перемикачі й кнопки малюють відгук поверх тла
        child: Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}
