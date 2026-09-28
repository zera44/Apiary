import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'map_screen.dart';
import 'new_apiary_screen.dart';

/// Список пасік застосунку: тап відкриває карту, "+" — створює нову.
class ApiaryListScreen extends StatefulWidget {
  final Repository repo;
  const ApiaryListScreen({super.key, required this.repo});
  @override
  State<ApiaryListScreen> createState() => _ApiaryListScreenState();
}

class _ApiaryListScreenState extends State<ApiaryListScreen> {
  List<Apiary>? apiaries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.listApiaries();
    if (mounted) setState(() => apiaries = list);
  }

  Future<void> _open(Apiary a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(repo: widget.repo, apiary: a),
    ));
    await _reload();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Apiary>(MaterialPageRoute(
      builder: (_) => NewApiaryScreen(repo: widget.repo),
    ));
    if (created == null) return;
    await _reload();
  }

  Future<void> _rename(Apiary a) async {
    final name = await showTextPrompt(context, title: 'Перейменувати пасіку', initial: a.name);
    if (name == null) return;
    await widget.repo.updateApiary(a.id, name: name);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = apiaries;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            const TopBar(title: 'Мої пасіки'),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодної пасіки.\nСтвори її кнопкою нижче.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _card(list[i]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PillButton(
                text: '+  Створити карту',
                bg: AppColors.accent,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: _create,
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _card(Apiary a) {
    return ListCard(
      height: 66,
      child: Row(children: [
        Material(
          color: AppColors.hive,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(a),
            child: const AppIcon('beehive', color: Colors.white, size: 46),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
              Text(
                a.hasLocation
                    ? '${a.lat!.toStringAsFixed(4)}, ${a.lon!.toStringAsFixed(4)}'
                    : 'Місце не обране',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        CircleIconButton(
            icon: 'pencil',
            bg: AppColors.rename,
            size: 38,
            tooltip: 'Перейменувати',
            onPressed: () => _rename(a)),
        const SizedBox(width: 6),
        CircleIconButton(
            icon: 'eye',
            bg: AppColors.darkBtn,
            iconColor: AppColors.text,
            size: 38,
            tooltip: 'Відкрити',
            onPressed: () => _open(a)),
      ]),
    );
  }
}
