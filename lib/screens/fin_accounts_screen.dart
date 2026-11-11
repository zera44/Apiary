import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fin_accounts.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/stock_format.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import '../ui/thousands_input.dart';
import 'fin_transfers_screen.dart';

/// Сума зі знаком із поля вводу («-120,5», «−120»); null - не число.
double? parseSignedAmount(String text) {
  final t = text.trim();
  final neg = t.startsWith('-') || t.startsWith('−');
  final v = parseAmount(neg ? t.substring(1) : t);
  if (v == null) return null;
  return neg ? -v : v;
}

/// Сума для поля вводу: «1 250,5» (з розрядами, зі знаком).
String amountFieldText(double v) {
  final s = formatMoney(v.abs()).split(',');
  final whole = ThousandsFormatter.group(s[0]);
  return '${v < 0 ? '-' : ''}$whole${s.length > 1 ? ',${s[1]}' : ''}';
}

/// Рахунки: «Загалом», історія й новий переказ, список рахунків із залишками.
/// Натиснути рахунок - змінити його (там же можна виправити суму), «+» -
/// новий рахунок.
class FinAccountsScreen extends StatefulWidget {
  final Repository repo;
  const FinAccountsScreen({super.key, required this.repo});

  @override
  State<FinAccountsScreen> createState() => _FinAccountsScreenState();
}

class _FinAccountsScreenState extends State<FinAccountsScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<FinAccount> _accounts = const [];
  Map<String, double> _balances = const {};
  bool _loaded = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    // перший вхід у фінанси без рахунків: одразу є «Готівка»
    await widget.repo.defaultFinAccountId();
    final list = await widget.repo.listFinAccounts();
    final bal = await widget.repo.finAccountBalances();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _balances = bal;
      _loaded = true;
    });
  }

  Future<void> _open({FinAccount? account}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FinAccountScreen(repo: widget.repo, account: account)));
    await _reload();
  }

  Future<void> _transfers({bool create = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => create
            ? FinTransferScreen(repo: widget.repo)
            : FinTransfersScreen(repo: widget.repo)));
    await _reload();
  }

  String _money(double v) => _hidden ? '••••• ₴' : uah(v);

  double get _total => [
        for (final a in _accounts)
          if (a.inTotal) _balances[a.id] ?? 0
      ].fold(0.0, (x, y) => x + y);

  Widget _action(IconData icon, String text, VoidCallback onTap) => Expanded(
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(children: [
                Icon(icon, color: AppColors.create, size: 28),
                const SizedBox(height: 6),
                Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text, fontSize: 13.5)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _scaffoldKey,
        drawer: FinDrawer(repo: widget.repo, current: FinSection.accounts),
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(
                title: tr.finAccounts,
                onBack: () => Navigator.pop(context),
                onTitleTap: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                          decoration: BoxDecoration(
                              color: AppColors.card, borderRadius: BorderRadius.circular(20)),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tr.finAccountsTotal,
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text(_money(_total),
                                    style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _hidden = !_hidden),
                              icon: Icon(
                                  _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: AppColors.create,
                                  size: 28),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          _action(Icons.history, tr.finTransfers, () => _transfers()),
                          const SizedBox(width: 12),
                          _action(Icons.swap_horiz, tr.finTransferNew, () => _transfers(create: true)),
                        ]),
                        const SizedBox(height: 14),
                        for (final a in _accounts)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                                color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _open(account: a),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  FinBadge(icon: a.icon, color: a.color, size: 44),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Text(a.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppColors.text, fontSize: 16))),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(_money(_balances[a.id] ?? 0),
                                        style: TextStyle(
                                            color: (_balances[a.id] ?? 0) < 0
                                                ? finColor('terra')
                                                : AppColors.text,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    if (!a.inTotal)
                                      Icon(Icons.visibility_off_outlined,
                                          size: 14, color: AppColors.textMuted),
                                  ]),
                                ]),
                              ),
                            ),
                          ),
                      ]),
              ),
            ]),
            Positioned(
              right: 20,
              bottom: 24,
              child: Material(
                color: const Color(0xFFFBC02D),
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _open(),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Tooltip(
                        message: tr.finAccountNew,
                        child: const Icon(Icons.add, size: 36, color: Color(0xFF1D1611))),
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      );
}

/// Новий або змінений рахунок: назва, значок, колір, сума. Для нового -
/// початкова сума; для наявного - поточний залишок, який можна виправити:
/// різниця запишеться коригуванням (мінус - витрата, плюс - дохід).
class FinAccountScreen extends StatefulWidget {
  final Repository repo;
  final FinAccount? account;
  const FinAccountScreen({super.key, required this.repo, this.account});

  @override
  State<FinAccountScreen> createState() => _FinAccountScreenState();
}

class _FinAccountScreenState extends State<FinAccountScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.account?.name ?? '');
  final _sum = TextEditingController();
  late String _icon = widget.account?.icon ?? 'payments';
  late String _color = widget.account?.color ?? 'honey';
  late bool _inTotal = widget.account?.inTotal ?? true;
  double _current = 0;
  bool _saving = false;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _loadBalance();
  }

  Future<void> _loadBalance() async {
    final b = (await widget.repo.finAccountBalances())[widget.account!.id] ?? 0;
    if (!mounted) return;
    setState(() {
      _current = b;
      _sum.text = amountFieldText(b);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _sum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      await showInfo(context, tr.enterAccountName);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = widget.repo;
      final value = _sum.text.trim().isEmpty ? 0.0 : (parseSignedAmount(_sum.text) ?? 0.0);
      if (_editing) {
        final id = widget.account!.id;
        await repo.updateFinAccount(id, name: name, icon: _icon, color: _color, inTotal: _inTotal);
        if ((value - _current).abs() >= 0.005) await repo.setFinAccountBalance(id, value);
      } else {
        await repo.addFinAccount(name,
            icon: _icon, color: _color, startBalance: value, inTotal: _inTotal);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await showInfo(context, tr.saveFailed('$e'), title: tr.error);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirm(context,
        title: tr.finAccountDeleteTitle, text: tr.finAccountDeleteText);
    if (!ok) return;
    await widget.repo.deleteFinAccount(widget.account!.id);
    if (mounted) Navigator.pop(context);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(t, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(
                  title: _editing ? tr.finAccount : tr.finAccountNew,
                  onBack: () => Navigator.pop(context)),
              Expanded(
                child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(children: [
                          FinBadge(icon: _icon, color: _color, size: 60),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _name,
                              style: TextStyle(color: AppColors.text, fontSize: 16),
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(labelText: tr.name),
                            ),
                          ),
                        ]),
                      ),
                      _label(_editing ? tr.finAccountBalance : tr.finStartBalance),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          key: const ValueKey('fin-account-sum'),
                          controller: _sum,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s\-−]')),
                          ],
                          style: TextStyle(color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            hintText: '0',
                            suffixText: '₴',
                            suffixStyle: TextStyle(color: AppColors.create, fontSize: 28),
                            filled: false,
                          ),
                        ),
                      ),
                      if (_editing)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text(tr.finBalanceHint,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _inTotal ? AppColors.create : AppColors.darkBtn),
                        ),
                        child: Row(children: [
                          Icon(Icons.functions, color: AppColors.create),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(tr.finInTotal,
                                  style: TextStyle(color: AppColors.text, fontSize: 15))),
                          Switch(value: _inTotal, onChanged: (v) => setState(() => _inTotal = v)),
                        ]),
                      ),
                      _label(tr.icon),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final e in kFinAccountIcons.entries)
                            GestureDetector(
                              onTap: () => setState(() => _icon = e.key),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: e.key == _icon ? finColor(_color) : AppColors.typeBtn,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(e.value,
                                    size: 22,
                                    color: e.key == _icon ? AppColors.bg : AppColors.textMuted),
                              ),
                            ),
                        ]),
                      ),
                      _label(tr.color),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final e in kFinColors.entries)
                            GestureDetector(
                              onTap: () => setState(() => _color = e.key),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: e.value,
                                  shape: BoxShape.circle,
                                  border: e.key == _color
                                      ? Border.all(color: AppColors.text, width: 3)
                                      : null,
                                ),
                              ),
                            ),
                        ]),
                      ),
                      if (_editing)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                          child: PillButton(
                            text: tr.finAccountDelete,
                            bg: AppColors.neutralBtn,
                            fg: AppColors.text,
                            height: 44,
                            width: double.infinity,
                            onPressed: _delete,
                          ),
                        ),
                    ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: PillButton(
                  text: _editing ? tr.save : tr.create,
                  bg: AppColors.accent,
                  height: 52,
                  radius: 26,
                  fontSize: 17,
                  width: double.infinity,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ]),
            const Positioned.fill(child: ScreenFrame()),
          ]),
        ),
      );
}
