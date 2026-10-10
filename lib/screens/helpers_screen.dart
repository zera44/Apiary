import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/sharing.dart';
import '../l10n/l10n.dart';
import '../services/sharing.dart';
import '../ui/common.dart';
import '../ui/theme.dart';

/// «Мої пасіки» → «Додати помічника»: форма запрошення (логін - пошта
/// Google; доступ до всіх пасік чи до однієї; склад і фінанси), мої
/// помічники («Забрати доступ») і запрошення, що ще чекають відповіді.
class HelpersScreen extends StatefulWidget {
  final Repository repo;

  /// Відкрили з певної пасіки - її й запропонувати для «Лише до цієї пасіки».
  final String? apiaryId;
  const HelpersScreen({super.key, required this.repo, this.apiaryId});

  static Future<void> open(BuildContext context, Repository repo, {String? apiaryId}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HelpersScreen(repo: repo, apiaryId: apiaryId),
        ),
      );

  @override
  State<HelpersScreen> createState() => _HelpersScreenState();
}

class _HelpersScreenState extends State<HelpersScreen> {
  SharingService get _sharing => SharingService.current;
  final _email = TextEditingController();
  bool _all = true;
  bool _stock = false;
  String? _apiary;
  List<Apiary> _apiaries = const [];
  List<Member> _members = const [];
  List<Invitation> _sent = const [];
  String? _result;
  bool _resultOk = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _apiary = widget.apiaryId;
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final mine = [
      for (final a in await widget.repo.listApiaries())
        if (a.isMine) a,
    ];
    final members = await _sharing.helpers();
    final sent = await _sharing.sent();
    if (!mounted) return;
    setState(() {
      _apiaries = mine;
      if (_apiary == null || !mine.any((a) => a.id == _apiary)) {
        _apiary = mine.isEmpty ? null : mine.first.id;
      }
      _members = members;
      _sent = sent;
    });
  }

  String _apiaryName(String? id) =>
      _apiaries.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? '';

  Future<void> _invite() async {
    if (_busy) return;
    final email = _email.text;
    setState(() {
      _busy = true;
      _result = null;
    });
    final one = !_all && _apiary != null;
    final (outcome, details) = await _sharing.invite(
      email,
      apiaryIds: one ? [_apiary!] : null,
      apiaryNames: one ? [_apiaryName(_apiary)] : const [],
      stockAccess: _stock,
    );
    final e = normalizeEmail(email);
    final text = switch (outcome) {
      InviteOutcome.sent => tr.inviteSent(e),
      InviteOutcome.noSuchUser => tr.inviteNoSuchUser(e),
      InviteOutcome.alreadyHasAccess => tr.inviteAlready(e),
      InviteOutcome.self => tr.inviteSelf,
      InviteOutcome.invalidEmail => tr.inviteInvalidEmail,
      InviteOutcome.unavailable => tr.sharingUnavailable,
      InviteOutcome.failed => tr.inviteFailed(details ?? ''),
    };
    if (outcome == InviteOutcome.sent) _email.clear();
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = text;
      _resultOk = outcome == InviteOutcome.sent;
    });
  }

  Future<void> _revoke(Member m) async {
    final ok = await showConfirm(
      context,
      title: tr.revokeTitle,
      text: tr.revokeText(m.email),
      confirmText: tr.revokeAccess,
      cancelText: tr.cancel,
    );
    if (!ok) return;
    await _guarded(() => _sharing.revoke(m));
  }

  Future<void> _guarded(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.inviteFailed('$e'))));
      }
    }
    await _load();
  }

  String _scope(String? apiaryId, List<String> names) {
    if (apiaryId == null && names.isEmpty) return tr.helperAllApiaries;
    return apiaryId != null ? _apiaryName(apiaryId) : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final on = _sharing.available;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(title: tr.helpersTitle, onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (!on) ...[
                    Text(
                      tr.sharingUnavailable,
                      style: TextStyle(color: AppColors.danger, fontSize: 13.5),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _section(tr.addHelper, [
                    TextField(
                      controller: _email,
                      enabled: on,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: TextStyle(color: AppColors.text),
                      decoration: InputDecoration(
                        labelText: tr.helperLogin,
                        hintText: tr.helperLoginHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _choice(
                            tr.accessAll,
                            _all,
                            on ? () => setState(() => _all = true) : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _choice(
                            tr.accessOne,
                            !_all,
                            on && _apiaries.isNotEmpty ? () => setState(() => _all = false) : null,
                          ),
                        ),
                      ],
                    ),
                    if (!_all && _apiaries.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _apiary,
                        hint: Text(tr.chooseApiary),
                        dropdownColor: AppColors.popupBg,
                        style: TextStyle(color: AppColors.text),
                        items: [
                          for (final a in _apiaries)
                            DropdownMenuItem(value: a.id, child: Text(a.name)),
                        ],
                        onChanged: on ? (v) => setState(() => _apiary = v) : null,
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr.accessStock, style: TextStyle(color: AppColors.text)),
                      value: _stock,
                      onChanged: on ? (v) => setState(() => _stock = v) : null,
                    ),
                    PillButton(
                      text: tr.sendInvite,
                      bg: AppColors.accent,
                      height: 44,
                      width: double.infinity,
                      onPressed: on && !_busy ? _invite : null,
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _result!,
                        style: TextStyle(
                          color: _resultOk ? AppColors.grass : AppColors.danger,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ]),
                  _section(tr.helpersTitle, [
                    if (_members.isEmpty)
                      Text(tr.helpersNone, style: TextStyle(color: AppColors.textMuted)),
                    for (final m in _members) _memberTile(m),
                  ]),
                  if (_sent.isNotEmpty)
                    _section(tr.invitesSentTitle, [
                      for (final i in _sent)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(i.toEmail, style: TextStyle(color: AppColors.text)),
                          subtitle: Text(
                            _scope(null, i.apiaryNames),
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                          ),
                          trailing: IconButton(
                            tooltip: tr.inviteCancel,
                            icon: Icon(Icons.close, color: AppColors.textMuted),
                            onPressed: () => _guarded(() => _sharing.cancel(i)),
                          ),
                        ),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(Member m) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(color: AppColors.bgLight, borderRadius: BorderRadius.circular(12)),
    // свій шар Material: перемикач і кнопки малюють відгук на дотик поверх тла
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.email,
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Text(
            _scope(m.apiaryId, const []),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr.helperWithStock,
                    style: TextStyle(color: AppColors.text, fontSize: 13),
                  ),
                  value: m.stockAccess,
                  onChanged: (v) => _guarded(() => _sharing.setStockAccess(m, on: v)),
                ),
              ),
              TextButton(
                onPressed: () => _revoke(m),
                child: Text(tr.revokeAccess, style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _choice(String text, bool selected, VoidCallback? onTap) => PillButton(
    text: text,
    bg: selected ? AppColors.accent : AppColors.darkBtn,
    fg: selected ? Colors.white : AppColors.text,
    height: 38,
    fontSize: 13,
    onPressed: onTap,
  );

  Widget _section(String title, List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hive.withValues(alpha: 0.35)),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}
