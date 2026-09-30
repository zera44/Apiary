import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'template_editor_screen.dart';

/// Екран "Шаблони": список збережених конфігурацій + "Додати".
class TemplatesScreen extends StatefulWidget {
  final Repository repo;
  const TemplatesScreen({super.key, required this.repo});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<ApiaryTemplate>? templates;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.listTemplates();
    if (mounted) setState(() => templates = list);
  }

  Future<void> _open(String? id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemplateEditorScreen(repo: widget.repo, templateId: id),
    ));
    await _reload();
  }

  Future<void> _rename(ApiaryTemplate t) async {
    final name = await showTextPrompt(context, title: 'Перейменувати шаблон', initial: t.name);
    if (name == null) return;
    await widget.repo.updateTemplate(t.id, name: name);
    await _reload();
  }

  Future<void> _delete(ApiaryTemplate t) async {
    final ok = await showConfirm(context, text: 'Видалити шаблон «${t.name}»?');
    if (!ok) return;
    await widget.repo.deleteTemplate(t.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = templates;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(title: 'Шаблони', onBack: () => Navigator.pop(context)),
            Expanded(
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text('Ще немає жодного шаблону',
                              style: TextStyle(color: AppColors.textMuted)))
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
                text: 'Створити шаблон',
                bg: AppColors.accent,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: () => _open(null),
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }

  Widget _card(ApiaryTemplate t) {
    return ListCard(
      height: 66,
      child: Row(children: [
        Material(
          color: AppColors.hive,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(t.id),
            child: const AppIcon('beehive', color: Colors.white, size: 46),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
              Text('${t.width}×${t.height}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        CircleIconButton(
            icon: 'pencil',
            bg: AppColors.rename,
            size: 38,
            tooltip: 'Перейменувати',
            onPressed: () => _rename(t)),
        const SizedBox(width: 6),
        CircleIconButton(
            icon: 'eye',
            bg: AppColors.darkBtn,
            iconColor: AppColors.text,
            size: 38,
            tooltip: 'Відкрити',
            onPressed: () => _open(t.id)),
        const SizedBox(width: 6),
        CircleIconButton(
            icon: 'trash',
            bg: AppColors.danger,
            size: 38,
            tooltip: 'Видалити',
            onPressed: () => _delete(t)),
      ]),
    );
  }
}
