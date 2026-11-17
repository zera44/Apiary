import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter/services.dart';

import '../data/fin_accounts.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/stock_format.dart';
import '../ui/common.dart';
import '../ui/fin_drawer.dart';
import '../ui/nav_drawer.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import '../ui/thousands_input.dart';
import 'fin_import_screen.dart';
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
  Map<String, double> _rates = const {kFinUah: 1};
  bool _loaded = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _reload();
    // курси НБУ: коли є інтернет, оновлюємо; без нього лишаються останні
    widget.repo.refreshFinRates().then((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    // перший вхід у фінанси без рахунків: одразу є «Готівка»
    await widget.repo.defaultFinAccountId();
    final list = await widget.repo.listFinAccounts();
    final bal = await widget.repo.finAccountBalances();
    final rates = await widget.repo.finRates();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _balances = bal;
      _rates = rates;
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

  Future<void> _import() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => FinImportScreen(repo: widget.repo)));
    await _reload();
  }

  String _money(double v, [String currency = kFinUah]) =>
      _hidden ? '••••• ${currencySymbol(currency)}' : money(v, currency);

  /// Загалом у гривнях: рахунки в іншій валюті - за курсом НБУ (якщо курсу ще
  /// немає, такий рахунок у суму не входить).
  double get _total => [
        for (final a in _accounts)
          if (a.inTotal) (_balances[a.id] ?? 0) * (_rates[a.currency] ?? 0)
      ].fold(0.0, (x, y) => x + y);

  /// Усі рахунки в гривнях, разом з тими, що не входять у «Загалом».
  double get _totalAll => [
        for (final a in _accounts) (_balances[a.id] ?? 0) * (_rates[a.currency] ?? 0)
      ].fold(0.0, (x, y) => x + y);

  /// Аркуш «Деталі балансу»: усі рахунки, включені й невключені в загальну суму.
  void _showDetails() {
    final all = _totalAll, inc = _total;
    Widget row(String label, double v, [IconData? icon]) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 2),
            Row(children: [
              if (icon != null) ...[Icon(icon, color: AppColors.create, size: 22), const SizedBox(width: 10)],
              Text(_money(v),
                  style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w600)),
            ]),
          ]),
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(tr.finBalanceDetails,
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w700)),
            row(tr.finBalanceAll, all),
            row(tr.finBalanceIncluded, inc, TablerIcons.eye),
            row(tr.finBalanceExcluded, all - inc, TablerIcons.eye_off),
          ]),
        ),
      ),
    );
  }

  bool get _hasForeign => _accounts.any((a) => a.inTotal && a.foreign);

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

  Future<void> _reorder(int from, int to) async {
    if (to > from) to--;
    if (from == to) return;
    setState(() => _accounts.insert(to, _accounts.removeAt(from)));
    await widget.repo.reorderFinAccounts([for (final a in _accounts) a.id]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _scaffoldKey,
        drawer: NavDrawer(repo: widget.repo, current: NavSection.finances, finSection: FinSection.accounts),
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
                        Material(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            key: const ValueKey('fin-total-card'),
                            borderRadius: BorderRadius.circular(20),
                            onTap: _showDetails,
                            child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
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
                                // усі рахунки разом з невключеними: значок монет і сума
                                Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(TablerIcons.coins, size: 18, color: AppColors.textMuted),
                                      const SizedBox(width: 6),
                                      Text(_money(_totalAll),
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                                    ]),
                                  ),
                                if (_hasForeign)
                                  Text(tr.finRateNote,
                                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ]),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _hidden = !_hidden),
                              icon: Icon(
                                  _hidden ? TablerIcons.eye_off : TablerIcons.eye,
                                  color: AppColors.create,
                                  size: 28),
                            ),
                          ]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          _action(TablerIcons.history, tr.finTransfers, () => _transfers()),
                          const SizedBox(width: 12),
                          _action(TablerIcons.arrows_left_right, tr.finTransferNew, () => _transfers(create: true)),
                          const SizedBox(width: 12),
                          _action(TablerIcons.file_upload, tr.finImport, _import),
                        ]),
                        const SizedBox(height: 14),
                        // довге натискання - перетягнути рахунок на нове місце
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: true,
                          onReorder: _reorder,
                          proxyDecorator: (child, _, _) => Material(
                              color: Colors.transparent, elevation: 6, child: child),
                          children: [
                            for (final a in _accounts)
                            Container(
                            key: ValueKey(a.id),
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
                                      child: Text.rich(
                                          TextSpan(children: [
                                            TextSpan(text: a.name),
                                            // не враховується в загальній сумі
                                            if (!a.inTotal)
                                              WidgetSpan(
                                                  alignment: PlaceholderAlignment.middle,
                                                  child: Padding(
                                                      padding: const EdgeInsets.only(left: 6),
                                                      child: Icon(TablerIcons.eye_off,
                                                          size: 18, color: AppColors.textMuted))),
                                          ]),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppColors.text, fontSize: 16))),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(_money(_balances[a.id] ?? 0, a.currency),
                                        style: TextStyle(
                                            color: (_balances[a.id] ?? 0) < 0
                                                ? finColor('terra')
                                                : AppColors.text,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    if (a.foreign && _rates[a.currency] != null)
                                      Text('≈ ${_money((_balances[a.id] ?? 0) * _rates[a.currency]!)}',
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                  ]),
                                ]),
                              ),
                            ),
                          ),
                          ],
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
                        child: const Icon(TablerIcons.plus, size: 36, color: Color(0xFF1D1611))),
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
  bool _adjustInStats = true;
  late String _currency = widget.account?.currency ?? kFinUah;
  double _current = 0;

  /// Залишок у вибраній валюті (після зміни валюти - перерахований за курсом).
  double _expected = 0;
  Map<String, double> _rates = const {};
  bool _saving = false;

  bool get _editing => widget.account != null;

  /// Суму змінено: з'явиться коригування, і можна вирішити, чи йде воно в статистику.
  bool get _balanceChanged {
    if (!_editing) return false;
    final value = _sum.text.trim().isEmpty ? 0.0 : (parseSignedAmount(_sum.text) ?? 0.0);
    return (value - _expected).abs() >= 0.005;
  }

  /// Інша валюта: у полі одразу видно перерахований залишок.
  void _pickCurrency(String c) {
    setState(() {
      _currency = c;
      if (!_editing) return;
      final r0 = _rates[widget.account!.currency], r1 = _rates[c];
      if (r0 == null || r1 == null || r1 <= 0) return;
      _expected = double.parse((_current * r0 / r1).toStringAsFixed(2));
      _sum.text = amountFieldText(_expected);
    });
  }

  @override
  void initState() {
    super.initState();
    if (_editing) _loadBalance();
  }

  Future<void> _loadBalance() async {
    final b = (await widget.repo.finAccountBalances())[widget.account!.id] ?? 0;
    final rates = await widget.repo.finRates();
    if (!mounted) return;
    setState(() {
      _rates = rates;
      _current = b;
      _expected = b;
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
        final old = widget.account!.currency;
        if (_currency != old) {
          final r0 = _rates[old], r1 = _rates[_currency];
          if (r0 == null || r1 == null) {
            await showInfo(context, tr.finCurrencyNoRate);
            setState(() => _saving = false);
            return;
          }
          final ok = await showConfirm(context,
              title: tr.finCurrencyChangeTitle,
              text: tr.finCurrencyChangeText(money(_current, old), money(_expected, _currency),
                  '1 ${currencySymbol(_currency)} = ${(r1 / r0).toStringAsFixed(2)} ${currencySymbol(old)}'),
              confirmText: tr.finCurrencyChangeBtn,
              cancelText: tr.cancel,
              danger: false);
          if (!ok || !mounted) {
            if (mounted) setState(() => _saving = false);
            return;
          }
          if (!await repo.changeFinAccountCurrency(id, _currency)) {
            if (mounted) await showInfo(context, tr.finCurrencyNoRate);
            setState(() => _saving = false);
            return;
          }
        }
        await repo.updateFinAccount(id, name: name, icon: _icon, color: _color, inTotal: _inTotal);
        if ((value - _expected).abs() >= 0.005) await repo.setFinAccountBalance(id, value, inStats: _adjustInStats);
      } else {
        await repo.addFinAccount(name,
            icon: _icon, color: _color, startBalance: value, inTotal: _inTotal, currency: _currency);
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
                          onChanged: (_) => setState(() {}),
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s\-−]')),
                          ],
                          style: TextStyle(color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            hintText: '0',
                            // валюта: дотик по символу відкриває вибір (₴ / $ / €)
                            suffixIcon: PopupMenuButton<String>(
                              key: const ValueKey('fin-account-currency'),
                              tooltip: tr.finCurrency,
                              onSelected: _pickCurrency,
                              color: AppColors.card,
                              itemBuilder: (_) => [
                                for (final c in kFinCurrencies)
                                  PopupMenuItem<String>(
                                      value: c,
                                      child: Text('${currencySymbol(c)}  $c',
                                          style: TextStyle(
                                              color: c == _currency ? AppColors.create : AppColors.text,
                                              fontWeight: c == _currency ? FontWeight.w700 : FontWeight.w400))),
                              ],
                              // символ лишається на місці, але в рамці - видно, що його можна торкнутися
                              child: Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.create, width: 1.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(currencySymbol(_currency),
                                    style: TextStyle(color: AppColors.create, fontSize: 28)),
                              ),
                            ),
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
                          Icon(TablerIcons.sum, color: AppColors.create),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(tr.finInTotal,
                                  style: TextStyle(color: AppColors.text, fontSize: 15))),
                          Switch(value: _inTotal, onChanged: (v) => setState(() => _inTotal = v)),
                        ]),
                      ),
                      if (_balanceChanged)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _adjustInStats ? AppColors.addObject : AppColors.darkBtn),
                          ),
                          child: Row(children: [
                            Icon(TablerIcons.chart_bar, color: AppColors.addObject),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(tr.finAdjustInStats,
                                    style: TextStyle(color: AppColors.text, fontSize: 15))),
                            Switch(
                                key: const ValueKey('fin-adjust-in-stats'),
                                activeThumbColor: AppColors.addObject,
                                activeTrackColor: AppColors.addObject.withValues(alpha: 0.45),
                                value: _adjustInStats,
                                onChanged: (v) => setState(() => _adjustInStats = v)),
                          ]),
                        ),
                      _label(tr.icon),
                      FinIconPicker(
                          selected: _icon,
                          color: finColor(_color),
                          onPick: (k) => setState(() => _icon = k)),
                      _label(tr.color),
                      FinColorGrid(selected: _color, onPick: (k) => setState(() => _color = k)),
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
