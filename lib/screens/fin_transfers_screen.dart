import 'package:flutter/material.dart';

import '../data/fin_accounts.dart';
import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/stock_format.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/fin_account_chips.dart';
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
                    icon: Icon(Icons.chevron_left, color: AppColors.text, size: 30)),
                Text(finMonthTitle(_month),
                    style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                    onPressed: () => _shift(1),
                    icon: Icon(Icons.chevron_right, color: AppColors.text, size: 30)),
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
                                  Icon(Icons.swap_horiz, color: AppColors.create, size: 28),
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
                                  Text(uah(t.amount),
                                      style: TextStyle(
                                          color: AppColors.text,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  IconButton(
                                      onPressed: () => _delete(t),
                                      icon: Icon(Icons.delete_outline, color: AppColors.textMuted)),
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
  final _comment = TextEditingController();
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
    if (!mounted) return;
    setState(() {
      _accounts = list;
      if (list.isNotEmpty) _from = list.first.id;
      if (list.length > 1) _to = list[1].id;
    });
  }

  @override
  void dispose() {
    _sum.dispose();
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
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final when = _sameDay(_date, now) ? now : DateTime(_date.year, _date.month, _date.day, 12);
      final note = _comment.text.trim();
      await widget.repo.addFinTransfer(
          fromId: from,
          toId: to,
          amount: amount,
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

  Widget _dateRow() {
    final now = DateTime.now();
    final today = _sameDay(_date, now);
    final yesterday = _sameDay(_date, now.subtract(const Duration(days: 1)));
    Widget chip(String text, bool on, VoidCallback tap) => GestureDetector(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? AppColors.darkBtn : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? AppColors.create : AppColors.darkBtn, width: 1.5),
            ),
            child: Text(text, style: TextStyle(color: AppColors.text, fontSize: 14)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        chip(tr.today, today, () => setState(() => _date = DateTime.now())),
        chip(tr.yesterday, yesterday,
            () => setState(() => _date = DateTime.now().subtract(const Duration(days: 1)))),
        chip(today || yesterday ? tr.otherDate : formatDdMmYyyy(_date), !today && !yesterday, _pickDate),
      ]),
    );
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
                              suffixText: '₴',
                              suffixStyle: TextStyle(color: AppColors.create, fontSize: 28),
                              filled: false,
                            ),
                          ),
                        ]),
                      ),
                      FinAccountChips(
                        label: tr.finFromAccount,
                        accounts: _accounts,
                        selected: _from,
                        onChanged: (id) => setState(() => _from = id),
                      ),
                      FinAccountChips(
                        label: tr.finToAccount,
                        accounts: _accounts,
                        selected: _to,
                        onChanged: (id) => setState(() => _to = id),
                      ),
                      _dateRow(),
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
