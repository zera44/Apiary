import 'package:flutter/material.dart';

import '../data/sharing.dart';
import '../l10n/l10n.dart';
import '../services/sharing.dart';
import 'common.dart';
import 'theme.dart';

/// Вулик-скринька → вхідні запрошення: від кого, до яких пасік,
/// «Прийняти» / «Відхилити».
Future<void> showInvitations(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.popupBg,
      builder: (_) => const _InvitationsSheet(),
    );

class _InvitationsSheet extends StatefulWidget {
  const _InvitationsSheet();
  @override
  State<_InvitationsSheet> createState() => _InvitationsSheetState();
}

class _InvitationsSheetState extends State<_InvitationsSheet> {
  List<Invitation>? _list;
  bool _busy = false;

  /// Помилка відповіді - у самому вікні (SnackBar сховався б під ним).
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await SharingService.current.incoming();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _respond(Invitation inv, bool accept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    String? error;
    try {
      await SharingService.current.respond(inv, accept: accept);
    } catch (e) {
      error = tr.inviteFailed('$e');
    }
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && (_list ?? const []).isEmpty) {
      Navigator.pop(context);
      // вікно закрилось - повідомлення вже видно
      messenger.showSnackBar(
          SnackBar(content: Text(accept ? tr.inviteAccepted : tr.inviteDeclined)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr.invitationsTitle,
              style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13.5)),
            const SizedBox(height: 8),
          ],
          if (list == null)
            const Center(child: CircularProgressIndicator())
          else if (list.isEmpty)
            Text(tr.invitationsNone, style: TextStyle(color: AppColors.textMuted))
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [for (final i in list) _tile(i)]),
            ),
        ]),
      ),
    );
  }

  Widget _tile(Invitation i) {
    final who = i.fromName.isEmpty ? i.fromEmail : '${i.fromName} (${i.fromEmail})';
    final where =
        i.allApiaries ? tr.invitationAllApiaries : tr.invitationApiaries(i.apiaryNames.join(', '));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hive.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr.invitationFrom(who),
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(where, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        if (i.stockAccess)
          Text(tr.invitationWithStock, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: PillButton(
                text: tr.accept,
                bg: AppColors.accent,
                height: 38,
                onPressed: _busy ? null : () => _respond(i, true)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PillButton(
                text: tr.decline,
                bg: AppColors.darkBtn,
                fg: AppColors.text,
                height: 38,
                onPressed: _busy ? null : () => _respond(i, false)),
          ),
        ]),
      ]),
    );
  }
}
