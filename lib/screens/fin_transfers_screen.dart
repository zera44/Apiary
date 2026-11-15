import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/fin_accounts.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/stock_format.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/fin_account_field.dart';
import '../ui/fin_date_row.dart';
import '../ui/fin_style.dart';
import '../ui/theme.dart';
import '../ui/thousands_input.dart';

/// Історія переказів між рахунками за місяць; «+» - новий переказ,
/// кошик - видалити переказ.
class FinTransfersScreen extends StatefulWidget {
  final Repository repo;
  const FinTransfersScreen({super.key, required this.repo});

  @override
  State<FinTransfersScreen> createState() => _FinTransfersScreenState();
}

class _FinTransfersScreenState extends State<FinTransfersScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<FinTransfer> _items = const [];
  Map<String, FinAccount> _accounts = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final list = await widget.repo.listFinTransfers(from: from, to: to);
    final acc = await widget.repo.finAccountMap();
    if (!mounted) return;
    setState(() {
      _items = list;
      _accounts = acc;
      _loaded = true;
    });
  }

  void _shift(int d) {
    setState(() {
      _month = DateTime(_month.year, _month.month + d);
      _loaded = false;
    });
    _reload();
  }

  Future<void> _add() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => FinTransferScreen(repo: widget.repo)));
    await _reload();
  }

  Future<void> _delete(FinTransfer t) async {
    final ok = await showConfirm(context,
        title: tr.finTransfer, text: tr.finTransferDeleteText, confirmText: tr.delete);
    if (!ok) return;
    await widget.repo.deleteFinTransfer(t.id);
    await _reload();
  }

  String _name(String id) => _accounts[id]?.name ?? '?';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(title: tr.finTransfers, onBack: () => Navigator.pop(context)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    onPressed: () => _shift(-1),
                    icon: Icon(TablerIcons.chevron_left, color: AppColors.text, size: 30)),
                Text(finMonthTitle(_month),
                    style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                    onPressed: () => _shift(1),
                    icon: Icon(TablerIcons.chevron_right, color: AppColors.text, size: 30)),
              ]),
              Expanded(
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                        ? Center(
                            child: Text(tr.finNoTransfers,
                                style: TextStyle(color: AppColors.textMuted, fontSize: 15)))
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                            for (final t in _items)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                                decoration: BoxDecoration(
                                    color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                                child: Row(children: [
                                  Icon(TablerIcons.arrows_left_right, color: AppColors.create, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${_name(t.fromId)} → ${_name(t.toId)}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppColors.text, fontSize: 16)),
                                      Text(
                                          '${finDay(t.date)}${(t.comment ?? '').isEmpty ? '' : ' · ${t.comment}'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                    ]),
                                  ),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(money(t.amount, _accounts[t.fromId]?.currency ?? kFinUah),
                                        style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                    if (t.toAmount != null)
                                      Text('→ ${money(t.toAmount!, _accounts[t.toId]?.currency ?? kFinUah)}',
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                  ]),
                                  IconButton(
                                      onPressed: () => _delete(t),
                                      icon: Icon(TablerIcons.trash, color: AppColors.textMuted)),
                                ]),
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
                  onTap: _add,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Tooltip(
                        message: tr.finTransferNew,
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

/// Новий переказ: з рахунку, на рахунок, сума, дата, коментар.
class FinTransferScreen extends StatefulWidget {
  final Repository repo;
  const FinTransferScreen({super.key, required this.repo});

  @override
  State<FinTransferScreen> createState() => _FinTransferScreenState();
}

class _FinTransferScreenState extends State<FinTransferScreen> {
  List<FinAccount> _accounts = const [];
  String? _from;
  String? _to;
  final _sum = TextEditingController();
  final _toSum = TextEditingController();
  final _comment = TextEditingController();
  Map<String, double> _rates = const {kFinUah: 1};
  Map<String, double> _balances = {};

  /// Сума зарахування виправлена вручну - більше не рахується за курсом.
  bool _toManual = false;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.repo.defaultFinAccountId();
    final list = await widget.repo.listFinAccounts();
    final rates = await widget.repo.finRates();
    final balances = await widget.repo.finAccountBalances();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _balances = balances;
      _rates = rates;
      if (list.isNotEmpty) _from = list.first.id;
      if (list.length > 1) _to = list[1].id;
    });
    // свіжі курси НБУ, якщо є інтернет
    await widget.repo.refreshFinRates();
    final fresh = await widget.repo.finRates();
    if (mounted) setState(() => _rates = fresh);
  }

  FinAccount? _acc(String? id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Рахунки в різних валютах - потрібна ще й сума зарахування.
  bool get _cross {
    final f = _acc(_from), t = _acc(_to);
    return f != null && t != null && f.currency != t.currency;
  }

  /// Сума зарахування за курсом НБУ, поки її не виправили вручну.
  void _autoTo() {
    if (!_cross || _toManual) return;
    final f = _acc(_from)!, t = _acc(_to)!;
    final a = parseAmount(_sum.text);
    final rf = _rates[f.currency], rt = _rates[t.currency];
    if (a == null || rf == null || rt == null) {
      _toSum.text = '';
      return;
    }
    _toSum.text = formatMoney(a * rf / rt);
  }

  @override
  void dispose() {
    _sum.dispose();
    _toSum.dispose();
    _comment.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    final res = await showAppDatePicker(context, formatDdMmYyyy(_date));
    final d = parseDdMmYyyy(res);
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_saving) return;
    final from = _from, to = _to;
    if (from == null || to == null || from == to) {
      await showInfo(context, tr.finPickAccounts);
      return;
    }
    final amount = parseAmount(_sum.text) ?? 0;
    if (!(amount > 0)) {
      await showInfo(context, tr.finEnterSum);
      return;
    }
    final toAmount = _cross ? parseAmount(_toSum.text) : null;
    if (_cross && !(toAmount != null && toAmount > 0)) {
      await showInfo(context, tr.finEnterSum);
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final when = _sameDay(_date, now) ? now : DateTime(_date.year, _date.month, _date.day, 12);
      final note = _comment.text.trim();
      await widget.repo.addFinTransfer(
          fromId: from,
          toId: to,
          amount: amount,
          toAmount: toAmount,
          date: when,
          comment: note.isEmpty ? null : note);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await showInfo(context, tr.saveFailed('$e'), title: tr.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(children: [
            ScreenColumn(children: [
              TopBar(title: tr.finTransferNew, onBack: () => Navigator.pop(context)),
              Expanded(
                child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(children: [
                          Text(tr.sum, style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          TextField(
                            key: const ValueKey('fin-transfer-sum'),
                            controller: _sum,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: thousandsInput,
                            style: TextStyle(
                                color: AppColors.text, fontSize: 34, fontWeight: FontWeight.w700),
                            decoration: InputDecoration(
                              hintText: '0',
                              suffixText: currencySymbol(_acc(_from)?.currency ?? kFinUah),
                              suffixStyle: TextStyle(color: AppColors.create, fontSize: 28),
                              filled: false,
                            ),
                            onChanged: (_) => setState(_autoTo),
                          ),
                        ]),
                      ),
                      FinAccountField(
                        key: const ValueKey('fin-transfer-from'),
                        label: tr.transferFromAccount,
                        account: _acc(_from),
                        balance: _balances[_from],
                        onTap: () async {
                          final id = await pickFinAccount(context,
                              accounts: _accounts,
                              balances: _balances,
                              selected: _from,
                              title: tr.transferFromAccount);
                          if (id != null && mounted) {
                            setState(() {
                              _from = id;
                              _autoTo();
                            });
                          }
                        },
                      ),
                      Center(
                        child: IconButton(
                          key: const ValueKey('fin-transfer-swap'),
                          tooltip: tr.swapAccounts,
                          icon: Icon(TablerIcons.arrows_up_down, color: AppColors.create),
                          onPressed: () => setState(() {
                            final x = _from;
                            _from = _to;
                            _to = x;
                            _toManual = false;
                            _autoTo();
                          }),
                        ),
                      ),
                      FinAccountField(
                        key: const ValueKey('fin-transfer-to-account'),
                        label: tr.transferToAccount,
                        account: _acc(_to),
                        balance: _balances[_to],
                        onTap: () async {
                          final id = await pickFinAccount(context,
                              accounts: _accounts,
                              balances: _balances,
                              selected: _to,
                              title: tr.transferToAccount);
                          if (id != null && mounted) {
                            setState(() {
                              _to = id;
                              _autoTo();
                            });
                          }
                        },
                      ),
                      if (_cross)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: TextField(
                            key: const ValueKey('fin-transfer-to-sum'),
                            controller: _toSum,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: thousandsInput,
                            style: TextStyle(color: AppColors.text, fontSize: 20),
                            decoration: InputDecoration(
                              labelText: tr.finTransferTo(_acc(_to)!.currency),
                              suffixText: currencySymbol(_acc(_to)!.currency),
                            ),
                            onChanged: (_) => _toManual = true,
                          ),
                        ),
                      FinDateRow(
                          date: _date,
                          onChanged: (d) => setState(() => _date = d),
                          onPickCalendar: _pickDate),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: TextField(
                          controller: _comment,
                          style: TextStyle(color: AppColors.text, fontSize: 16),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: tr.comment),
                        ),
                      ),
                    ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: PillButton(
                  text: tr.add,
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
