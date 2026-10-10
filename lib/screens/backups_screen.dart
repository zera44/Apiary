import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../services/backups.dart';
import '../ui/common.dart';
import '../ui/sync_status.dart' show formatWhen;
import '../ui/theme.dart';

/// Налаштування → «Головне» → «Резервні копії»: список копій на цьому
/// телефоні, «Відновити» (з підтвердженням) і «Зберегти у файл».
class BackupsScreen extends StatefulWidget {
  final Repository repo;
  const BackupsScreen({super.key, required this.repo});

  static Future<void> open(BuildContext context, Repository repo) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => BackupsScreen(repo: repo)));

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  BackupService? _service;
  List<LocalBackup>? _list;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _service = await BackupService.of(widget.repo);
    } catch (e) {
      // без теки копій - порожній список і пояснення, а не вічне завантаження
      if (!mounted) return;
      setState(() => _list = const []);
      _say(tr.backupFailed('$e'));
      return;
    }
    await _reload();
  }

  Future<void> _reload() async {
    final s = _service;
    List<LocalBackup> l = const [];
    if (s != null) {
      try {
        l = await s.list();
      } catch (e) {
        if (mounted) _say(tr.backupFailed('$e'));
      }
    }
    if (mounted) setState(() => _list = l);
  }

  void _say(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() => _guard(() async {
        try {
          await (_service ??= await BackupService.of(widget.repo)).create();
          _say(tr.backupMade);
        } catch (e) {
          _say(tr.backupFailed('$e'));
        }
        await _reload();
      });

  Future<void> _restore(LocalBackup b) => _guard(() async {
        final ok = await showConfirm(context,
            title: tr.backupRestoreTitle,
            text: tr.backupRestoreText(_when(b)),
            confirmText: tr.backupRestore,
            cancelText: tr.cancel);
        if (!ok || !mounted) return;
        final service = _service!;
        final messenger = ScaffoldMessenger.of(context);
        final nav = Navigator.of(context);
        try {
          final before = await service.restore(b);
          // усі відкриті екрани показували старі дані - на головний
          nav.popUntil((r) => r.isFirst);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(tr.backupRestored),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: tr.undo,
                onPressed: () async {
                  try {
                    await service.restoreFrom(before.path);
                    messenger.showSnackBar(SnackBar(content: Text(tr.backupUndone)));
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text(tr.backupRestoreFailed('$e'))));
                  }
                },
              ),
            ));
        } catch (e) {
          _say(tr.backupRestoreFailed('$e'));
          await _reload();
        }
      });

  Future<void> _export(LocalBackup b) async {
    final share = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.popupBg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.save_alt, color: AppColors.text),
            title: Text(tr.backupSaveToFile, style: TextStyle(color: AppColors.text)),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: Icon(Icons.share, color: AppColors.text),
            title: Text(tr.backupShare, style: TextStyle(color: AppColors.text)),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ]),
      ),
    );
    if (share == null) return;
    final name = exportFileName(b.time);
    try {
      if (share) {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(b.path, mimeType: 'application/vnd.sqlite3', name: name)],
          fileNameOverrides: [name],
        ));
        return;
      }
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: await File(b.path).readAsBytes(),
        dialogTitle: tr.backupSaveDialog,
      );
      _say(uri == null ? tr.backupSaveCancelled : tr.backupSaved);
    } catch (e) {
      _say(tr.backupSaveFailed('$e'));
    }
  }

  static String _when(LocalBackup b) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = b.time;
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  static String _kind(BackupKind k) => switch (k) {
        BackupKind.auto => tr.backupKindAuto,
        BackupKind.manual => tr.backupKindManual,
        BackupKind.beforeRestore => tr.backupKindBeforeRestore,
      };

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar(title: tr.backupsSection, onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(tr.backupsHint, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 12),
                PillButton(
                  text: tr.backupNow,
                  bg: AppColors.accent,
                  height: 44,
                  width: double.infinity,
                  onPressed: _busy || _service == null ? null : _backupNow,
                ),
                const SizedBox(height: 16),
                if (list == null)
                  const Center(child: CircularProgressIndicator())
                else if (list.isEmpty)
                  Text(tr.backupsNone,
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))
                else
                  for (final b in list) _tile(b),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tile(LocalBackup b) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hive.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_when(b),
              style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${_kind(b.kind)} · ${tr.fileSize(b.size)}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: PillButton(
                text: tr.backupRestore,
                bg: AppColors.accent,
                height: 36,
                onPressed: _busy ? null : () => _restore(b),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                text: tr.backupSaveToFile,
                bg: AppColors.darkBtn,
                fg: AppColors.text,
                height: 36,
                onPressed: _busy ? null : () => _export(b),
              ),
            ),
          ]),
        ]),
      );
}

/// Назва файлу копії для збереження: `vulyk-2026-10-10-1405.db`.
String exportFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'vulyk-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}.db';
}

/// «Остання копія: …» для розділу налаштувань.
String backupsSummary(LocalBackup? latest) =>
    latest == null ? tr.backupsNone : tr.backupsLast(formatWhen(latest.time));
