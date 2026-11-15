import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../data/repository.dart';
import '../l10n/l10n.dart';
import '../logic/notify_schedule.dart';
import '../services/reminders.dart';
import '../ui/common.dart';
import '../ui/date_picker.dart';
import '../ui/theme.dart';

/// Налаштування → «Сповіщення»: час нагадування про обхід і повторного,
/// графік днів (щодня, 5/2, 2/2, довільно) з календарем.
class NotifySettingsScreen extends StatefulWidget {
  final Repository repo;
  const NotifySettingsScreen({super.key, required this.repo});

  @override
  State<NotifySettingsScreen> createState() => _NotifySettingsScreenState();
}

class _NotifySettingsScreenState extends State<NotifySettingsScreen> {
  NotifySchedule? _s;
  late DateTime _month = NotifySchedule.day(DateTime.now());

  @override
  void initState() {
    super.initState();
    NotifySchedule.load(widget.repo).then((s) {
      if (!mounted) return;
      setState(() {
        _s = s;
        final last = s.custom.isEmpty ? null : (s.custom.toList()..sort()).last;
        if (s.mode == NotifyMode.custom && last != null && last.isAfter(DateTime.now())) {
          _month = DateTime(last.year, last.month);
        }
      });
    });
  }

  String _hhmm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pickTime(int current, void Function(int) set) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null && mounted) setState(() => set(t.hour * 60 + t.minute));
  }

  Future<void> _pickStart() async {
    final s = _s!;
    final cur = s.start ?? NotifySchedule.day(DateTime.now());
    final res = await showAppDatePicker(context, formatDdMmYyyy(cur));
    final d = parseDdMmYyyy(res);
    if (d != null && mounted) {
      setState(() {
        _s = s.copyWith(start: d);
        _month = DateTime(d.year, d.month);
      });
    }
  }

  void _setMode(NotifyMode m) {
    final s = _s!;
    setState(() {
      _s = s.copyWith(mode: m, start: s.start ?? NotifySchedule.day(DateTime.now()));
    });
  }

  void _toggleDay(DateTime d) {
    final s = _s!;
    final set = {...s.custom};
    if (!set.remove(d)) set.add(d);
    setState(() => _s = s.copyWith(custom: set));
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    await s.save(widget.repo);
    unawaited(ReminderService.instance.reschedule().catchError((Object _) {}));
    if (mounted) Navigator.pop(context);
  }

  Widget _card(List<Widget> children, {EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _timeRow(String name, String hint, int value, void Function(int) set, {Key? key}) {
    return InkWell(
      key: key,
      onTap: () => _pickTime(value, set),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(color: AppColors.text, fontSize: 15)),
              Text(hint, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBtn)),
            child: Text(_hhmm(value),
                style: TextStyle(
                    color: AppColors.create, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Widget _modeChips(NotifySchedule s) {
    final names = {
      NotifyMode.daily: tr.notifDaily,
      NotifyMode.w52: '5/2',
      NotifyMode.w22: '2/2',
      NotifyMode.custom: tr.notifCustom,
    };
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final e in names.entries)
        GestureDetector(
          key: ValueKey('notif-mode-${e.key.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _setMode(e.key),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: e.key == s.mode ? AppColors.create : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: e.key == s.mode ? AppColors.create : AppColors.darkBtn),
            ),
            child: Text(e.value,
                style: TextStyle(
                    color: e.key == s.mode ? const Color(0xFF1D1611) : AppColors.text,
                    fontWeight: e.key == s.mode ? FontWeight.w700 : FontWeight.w400)),
          ),
        ),
    ]);
  }

  Widget _calendar(NotifySchedule s) {
    final editable = s.mode == NotifyMode.custom;
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final today = NotifySchedule.day(DateTime.now());
    final cells = <Widget>[
      for (final w in tr.weekdaysShort)
        Center(child: Text(w, style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var n = 1; n <= days; n++)
        Builder(builder: (_) {
          final d = DateTime(_month.year, _month.month, n);
          final on = editable ? s.custom.contains(d) : s.allows(d);
          final isStart = !editable && s.start != null && NotifySchedule.day(s.start!) == d;
          return GestureDetector(
            key: ValueKey('notif-day-$n'),
            behavior: HitTestBehavior.opaque,
            onTap: editable ? () => _toggleDay(d) : null,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppColors.create : Colors.transparent,
                  border: isStart
                      ? Border.all(color: AppColors.text, width: 1.5)
                      : d == today
                          ? Border.all(color: AppColors.darkBtn, width: 1.5)
                          : null,
                ),
                child: Text('$n',
                    style: TextStyle(
                        color: on ? const Color(0xFF1D1611) : AppColors.text,
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
          );
        }),
    ];
    return Column(children: [
      Row(children: [
        IconButton(
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            icon: Icon(TablerIcons.chevron_left, color: AppColors.text)),
        Expanded(
          child: Text('${tr.monthNames[_month.month]} ${_month.year}',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
        ),
        IconButton(
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            icon: Icon(TablerIcons.chevron_right, color: AppColors.text)),
      ]),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.15,
        children: cells,
      ),
      if (editable)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${tr.notifDaysChosen} ${s.custom.length}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ScreenColumn(children: [
            TopBar(title: tr.notifTitle, onBack: () => Navigator.pop(context)),
            if (s == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              Expanded(
                child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                  _card([
                    Row(children: [
                      Expanded(
                          child: Text(tr.notifEnabled,
                              style: TextStyle(color: AppColors.text, fontSize: 15))),
                      Switch(
                          key: const ValueKey('notif-enabled'),
                          value: s.enabled,
                          onChanged: (v) => setState(() => _s = s.copyWith(enabled: v))),
                    ]),
                    if (!s.enabled)
                      Text(tr.notifOffNote,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ]),
                  _card([
                    Text(tr.notifWhen, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    _timeRow(tr.notifRound, tr.notifRoundHint, s.morning,
                        (m) => _s = s.copyWith(morning: m),
                        key: const ValueKey('notif-morning')),
                    _timeRow(tr.notifRepeatName, tr.notifRepeatHint, s.repeat,
                        (m) => _s = s.copyWith(repeat: m),
                        key: const ValueKey('notif-repeat')),
                  ]),
                  _card([
                    Text(tr.notifDays, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    _modeChips(s),
                    const SizedBox(height: 10),
                    Text(
                        switch (s.mode) {
                          NotifyMode.daily => tr.notifHintDaily,
                          NotifyMode.w52 => tr.notifHint52,
                          NotifyMode.w22 => tr.notifHint22,
                          NotifyMode.custom => tr.notifHintCustom,
                        },
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    if (s.mode == NotifyMode.w52 || s.mode == NotifyMode.w22)
                      InkWell(
                        key: const ValueKey('notif-start'),
                        onTap: _pickStart,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            Expanded(
                                child: Text(tr.notifStartFrom,
                                    style: TextStyle(color: AppColors.text, fontSize: 15))),
                            Text(formatDdMmYyyy(s.start ?? DateTime.now()),
                                style: TextStyle(
                                    color: AppColors.create,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                  ]),
                  // будь-який режим зафарбовує дні календаря
                  _card([_calendar(s)]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: PillButton(
                  key: const ValueKey('notif-save'),
                  text: tr.notifSave,
                  bg: AppColors.accent,
                  height: 52,
                  radius: 26,
                  fontSize: 17,
                  width: double.infinity,
                  onPressed: _save,
                ),
              ),
            ],
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
