import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../l10n/l10n.dart';

/// Створення нової пасіки: поки що лише назва (вибір місця на карті
/// тимчасово прибрано).
class NewApiaryScreen extends StatefulWidget {
  final Repository repo;
  const NewApiaryScreen({super.key, required this.repo});
  @override
  State<NewApiaryScreen> createState() => _NewApiaryScreenState();
}

class _NewApiaryScreenState extends State<NewApiaryScreen> {
  final _nameCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr.enterApiaryName);
      return;
    }
    if (_saving) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final id = await widget.repo.addApiary(name);
      final apiary = await widget.repo.getApiary(id);
      if (!mounted || apiary == null) return;
      // повертаємо створену пасіку списку — він сам відкриє карту й, після
      // повернення, оновить мініатюри (раніше вони лишались порожніми)
      Navigator.of(context).pop(apiary);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: tr.newApiary, onBack: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: TextStyle(color: AppColors.text),
                decoration: InputDecoration(hintText: tr.apiaryName),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
              ),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PillButton(
                text: _saving ? tr.qrCreating : 'OK',
                bg: AppColors.accent,
                height: 50,
                radius: 16,
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
}
