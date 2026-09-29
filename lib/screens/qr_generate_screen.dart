import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/merge_layout.dart';
import '../services/qr_labels.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/theme.dart';

/// Назва вулика для наліпки. Вулики однієї групи мають спільну назву, тож
/// до неї додається порядковий номер у групі (зверху вниз, зліва направо).
String hiveLabelName(MapElement el, List<MapElement> all) {
  final base = (el.label != null && el.label!.isNotEmpty) ? el.label! : 'Вулик';
  if (el.groupId == null) return base;
  final hives = [
    for (final e in all)
      if (e.groupId == el.groupId && e.isHive) e
  ]..sort((a, b) => a.y != b.y ? b.y.compareTo(a.y) : a.x.compareTo(b.x));
  if (hives.length < 2) return base;
  return '$base · ${hives.indexWhere((e) => e.id == el.id) + 1}';
}

/// "Генерувати QR-коди": карта пасіки, де вулики з кодом мають зелений
/// ободок. Тап обирає/знімає вулики (кілька), "Згенерувати" створює код для
/// кожного обраного й показує наліпки.
class QrGenerateScreen extends StatefulWidget {
  final Repository repo;
  final Apiary apiary;
  const QrGenerateScreen({super.key, required this.repo, required this.apiary});
  @override
  State<QrGenerateScreen> createState() => _QrGenerateScreenState();
}

class _QrGenerateScreenState extends State<QrGenerateScreen> {
  final grid = GridController(cellSize: 34, minCell: 14, maxCell: 56);
  List<MapElement> elements = [];
  Set<String> linked = {};
  final Set<String> selected = {};
  bool _busy = false;

  List<SceneCell>? _cells;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    grid.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _reload();
    if (elements.isNotEmpty) {
      var minX = elements.first.x, maxX = minX, minY = elements.first.y, maxY = minY;
      for (final e in elements) {
        if (e.x < minX) minX = e.x;
        if (e.x > maxX) maxX = e.x;
        if (e.y < minY) minY = e.y;
        if (e.y > maxY) maxY = e.y;
      }
      grid.centerOnGrid((minX + maxX + 1) / 2, (minY + maxY + 1) / 2);
    }
  }

  Future<void> _reload() async {
    final els = await widget.repo.listElements(widget.apiary.id);
    final l = await widget.repo.elementIdsWithQr(widget.apiary.id);
    if (!mounted) return;
    setState(() {
      elements = els;
      linked = l;
      selected.removeWhere((id) => !els.any((e) => e.id == id));
      _cells = null;
    });
  }

  List<SceneCell> _scene() => _cells ??= buildScene<String>(
        items: [
          for (final e in elements)
            MergeItem<String>(
              e.id,
              e.x,
              e.y,
              '${e.groupId ?? e.id}|${e.type}|${e.isHive ? '' : (e.variant ?? '')}|${e.icon ?? ''}|${e.color ?? ''}',
            )
        ],
        look: {
          for (final e in elements) e.id: (type: e.type, variant: e.variant, icon: e.icon, color: e.color)
        },
        selected: selected,
        outlined: linked,
      );

  void _onTap(GridPress p) {
    if (_busy) return;
    final el = elements.where((e) => e.x == p.cell.$1 && e.y == p.cell.$2).firstOrNull;
    if (el == null || !el.isHive) return; // коди — лише для вуликів
    setState(() {
      if (!selected.remove(el.id)) selected.add(el.id);
      _cells = null;
    });
  }

  void _selectAllWithout() {
    setState(() {
      selected
        ..clear()
        ..addAll([for (final e in elements) if (e.isHive && !linked.contains(e.id)) e.id]);
      _cells = null;
    });
  }

  Future<void> _generate() async {
    if (_busy || selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final chosen = [for (final e in elements) if (selected.contains(e.id)) e]
        ..sort((a, b) => a.y != b.y ? b.y.compareTo(a.y) : a.x.compareTo(b.x));
      final codes = await widget.repo.generateQrForElements(chosen);
      final byId = {for (final e in chosen) e.id: e};
      final labels = [
        for (final c in codes)
          QrLabel(code: c.code, name: hiveLabelName(byId[c.elementId]!, elements), number: c.number)
      ];
      if (!mounted) return;
      setState(() {
        selected.clear();
        _cells = null;
      });
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => QrLabelsScreen(labels: labels, apiaryName: widget.apiary.name),
      ));
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hives = elements.where((e) => e.isHive).length;
    final withCode = elements.where((e) => e.isHive && linked.contains(e.id)).length;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar(title: 'QR-коди: ${widget.apiary.name}', onBack: () => Navigator.pop(context)),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: InfiniteGrid(
                  controller: grid,
                  cells: _scene(),
                  maskSelected: false,
                  onTap: _onTap,
                ),
              ),
              const Positioned.fill(child: ScreenFrame()),
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: CapsuleLabel(
                      elements.isEmpty
                          ? 'На цій пасіці ще немає вуликів'
                          : 'Зелений ободок — код уже є ($withCode з $hives) · тапайте вулики',
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Column(children: [
                  PillButton(
                      text: '+',
                      bg: AppColors.roundBtn,
                      fg: AppColors.text,
                      width: 40,
                      height: 40,
                      radius: 20,
                      fontSize: 18,
                      onPressed: () => grid.zoomBy(4)),
                  const SizedBox(height: 6),
                  PillButton(
                      text: '−',
                      bg: AppColors.roundBtn,
                      fg: AppColors.text,
                      width: 40,
                      height: 40,
                      radius: 20,
                      fontSize: 18,
                      onPressed: () => grid.zoomBy(-4)),
                ]),
              ),
            ]),
          ),
          Container(
            color: AppColors.panel,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: PillButton(
                  text: 'Усі без коду',
                  bg: AppColors.darkBtn,
                  fg: AppColors.text,
                  height: 46,
                  fontSize: 13,
                  onPressed: _busy || hives == withCode ? null : _selectAllWithout,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PillButton(
                  text: _busy ? 'Створюємо…' : 'Згенерувати (${selected.length})',
                  bg: AppColors.accent,
                  height: 46,
                  fontSize: 14,
                  onPressed: _busy || selected.isEmpty ? null : _generate,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Готові наліпки: перегляд і збереження PDF для друку.
class QrLabelsScreen extends StatefulWidget {
  final List<QrLabel> labels;
  final String apiaryName;
  const QrLabelsScreen({super.key, required this.labels, required this.apiaryName});
  @override
  State<QrLabelsScreen> createState() => _QrLabelsScreenState();
}

class _QrLabelsScreenState extends State<QrLabelsScreen> {
  List<Uint8List>? _pngs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    final out = <Uint8List>[];
    for (final l in widget.labels) {
      out.add(await renderLabelPng(l));
    }
    if (mounted) setState(() => _pngs = out);
  }

  Future<void> _savePdf() async {
    final pngs = _pngs;
    if (pngs == null || _saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await buildLabelsPdf(pngs);
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final safe = widget.apiaryName
          .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final name = 'qr_${safe.isEmpty ? 'pasika' : safe}_'
          '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
      final msg = await saveLabelsPdf(bytes, name);
      if (mounted) await showInfo(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pngs = _pngs;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            TopBar(
                title: 'Наліпки (${widget.labels.length})', onBack: () => Navigator.pop(context)),
            Expanded(
              child: pngs == null
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: kLabelW / kLabelH,
                      ),
                      itemCount: pngs.length,
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(pngs[i], fit: BoxFit.contain, gaplessPlayback: true),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: PillButton(
                text: _saving ? 'Зберігаємо…' : 'Зберегти PDF для друку',
                bg: AppColors.accent,
                height: 48,
                radius: 16,
                width: double.infinity,
                onPressed: pngs == null || _saving ? null : _savePdf,
              ),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
