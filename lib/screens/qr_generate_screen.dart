import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../logic/hive_objects.dart';
import '../logic/merge_layout.dart';
import '../services/qr_labels.dart';
import '../ui/common.dart';
import '../ui/grid_view.dart';
import '../ui/theme.dart';

/// Назва вулика для наліпки. Вулики однієї групи мають спільну назву, тож
/// до неї додається порядковий номер вулика-об'єкта в групі (зверху вниз,
/// зліва направо). Злиті клітинки одного вулика — один номер.
String hiveLabelName(MapElement el, List<MapElement> all) {
  final base = (el.label != null && el.label!.isNotEmpty) ? el.label! : 'Вулик';
  if (el.groupId == null) return base;
  final objs = hiveObjects([for (final e in all) if (e.groupId == el.groupId) e]);
  if (objs.length < 2) return base;
  return '$base · ${objs.indexWhere((o) => o.any((e) => e.id == el.id)) + 1}';
}

/// "Генерувати QR-коди": карта пасіки, де вулики з кодом мають зелений
/// ободок. Тап обирає/знімає вулики (кілька; вулик на кілька клітинок —
/// цілком), "Згенерувати" створює НОВИЙ код для кожного обраного (старий
/// код вулика, якщо був, вимикається) і показує наліпки.
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

  /// Вулики-об'єкти (злиті клітинки одного вулика — один об'єкт).
  List<List<MapElement>> objects = [];

  /// Id головних клітинок об'єктів, що вже мають код.
  Set<String> linked = {};

  /// Id головних клітинок обраних об'єктів.
  final Set<String> selected = {};

  Set<String> _members(Set<String> heads) => {
        for (final o in objects)
          if (heads.contains(o.first.id)) ...o.map((e) => e.id)
      };
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
    // одразу обрано всі вулики без коду — найчастіший випадок
    if (mounted && selected.isEmpty) _selectAllWithout();
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
    final objs = hiveObjects(els);
    setState(() {
      elements = els;
      objects = objs;
      linked = {
        for (final o in objs)
          if (o.any((e) => l.contains(e.id))) o.first.id
      };
      selected.removeWhere((id) => !objs.any((o) => o.first.id == id));
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
              mergeKeyOf(e),
            )
        ],
        look: {
          for (final e in elements) e.id: (type: e.type, variant: e.variant, icon: e.icon, color: e.color)
        },
        selected: _members(selected),
        outlined: _members(linked),
      );

  void _onTap(GridPress p) {
    if (_busy) return;
    final el = elements.where((e) => e.x == p.cell.$1 && e.y == p.cell.$2).firstOrNull;
    if (el == null || !el.isHive) return; // коди — лише для вуликів
    final head = objects.firstWhere((o) => o.any((e) => e.id == el.id), orElse: () => [el]).first;
    setState(() {
      if (!selected.remove(head.id)) selected.add(head.id);
      _cells = null;
    });
  }

  void _selectAllWithout() {
    setState(() {
      selected
        ..clear()
        ..addAll([for (final o in objects) if (!linked.contains(o.first.id)) o.first.id]);
      _cells = null;
    });
  }

  Future<void> _generate() async {
    if (_busy || selected.isEmpty) return;
    final replacing = selected.where(linked.contains).length;
    if (replacing > 0) {
      final ok = await showConfirm(context,
          title: 'Перегенерувати коди?',
          text: 'У $replacing з ${selected.length} обраних вуликів уже є код. Вони отримають '
              'нові коди, а старі наліпки перестануть працювати.',
          confirmText: 'Перегенерувати');
      if (!ok || !mounted || _busy) return;
    }
    setState(() => _busy = true);
    try {
      // objects уже впорядковані зверху вниз, зліва направо
      final chosen = [for (final o in objects) if (selected.contains(o.first.id)) o];
      final codes = await widget.repo.generateQrForObjects(chosen);
      final byId = {for (final o in chosen) o.first.id: o.first};
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
    final hives = objects.length;
    final withCode = objects.where((o) => linked.contains(o.first.id)).length;
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
                  showMoveHints: false, // тут нічого не переміщується
                  selectColor: const Color(0xFF1E5E2E), // вибір для коду - темно-зелений
                  selectWidth: 5,
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
                          : 'Зелений ободок - код уже є ($withCode з $hives) · тапайте вулики',
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

  /// «Друк»: системне вікно друку телефона/комп'ютера, без збереження файлу.
  Future<void> _print() async {
    final pngs = _pngs;
    if (pngs == null || _saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await buildLabelsPdf(pngs);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName());
    } catch (e) {
      if (mounted) await showInfo(context, 'Не вдалося відкрити друк: $e\n\nЗбережіть PDF і надрукуйте його.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final safe = widget.apiaryName
        .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'qr_${safe.isEmpty ? 'pasika' : safe}_'
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
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
              child: Row(children: [
                Expanded(
                  child: PillButton(
                    text: 'Друк',
                    bg: AppColors.accent,
                    height: 48,
                    radius: 16,
                    onPressed: pngs == null || _saving ? null : _print,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    text: _saving ? 'Зачекайте…' : 'Зберегти PDF',
                    bg: AppColors.darkBtn,
                    fg: AppColors.text,
                    height: 48,
                    radius: 16,
                    onPressed: pngs == null || _saving ? null : _savePdf,
                  ),
                ),
              ]),
            ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
