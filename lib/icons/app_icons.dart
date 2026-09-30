import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'svg_icon.dart';

/// Реєстр іконок застосунку. Самі іконки — SVG-файли в `assets/icons/`
/// (за категоріями), а перелік, назви й категорії — у `assets/icons/icons.json`.
/// Докладніше — `assets/icons/README.md`.

/// Шлях до папки з іконками в ресурсах застосунку.
const kIconsDir = 'assets/icons';

/// Запис реєстру.
class AppIconEntry {
  final String id;
  final String file;
  final String label;
  final String category;

  /// Чи пропонується іконка в діалозі "Обрати іконку" для об'єкта.
  final bool pickable;

  /// Якщо задано — іконка є варіантом перешкоди, а це її назва в списку
  /// варіантів (порядок — як у реєстрі).
  final String? variantLabel;

  const AppIconEntry({
    required this.id,
    required this.file,
    required this.label,
    required this.category,
    this.pickable = false,
    this.variantLabel,
  });
}

/// Розібраний реєстр разом із розібраними іконками.
class IconSet {
  final List<AppIconEntry> entries;
  final Map<String, SvgIconData> icons;

  /// Проблеми, знайдені під час завантаження (для тесту й журналу).
  final List<String> problems;
  const IconSet(this.entries, this.icons, this.problems);
}

/// Розбирає реєстр [manifestJson]; вміст файлу іконки повертає [readFile]
/// (за відносним шляхом із реєстру). Нічого не кидає: усе, що не так,
/// потрапляє в [IconSet.problems], а іконка з проблемою просто не
/// реєструється.
IconSet buildIconSet(String manifestJson, String? Function(String file) readFile) {
  final problems = <String>[];
  final entries = <AppIconEntry>[];
  final icons = <String, SvgIconData>{};
  Object? root;
  try {
    root = jsonDecode(manifestJson);
  } catch (e) {
    return IconSet(const [], const {}, ['icons.json не розібрано: $e']);
  }
  final list = root is Map ? root['icons'] : null;
  final cats = root is Map && root['categories'] is Map ? (root['categories'] as Map).keys.toSet() : <Object?>{};
  if (list is! List) {
    return IconSet(const [], const {}, ['icons.json: немає списку "icons"']);
  }
  for (final raw in list) {
    if (raw is! Map) {
      problems.add('icons.json: запис не є об\'єктом: $raw');
      continue;
    }
    final id = raw['id'];
    final file = raw['file'];
    final label = raw['label'];
    final category = raw['category'];
    if (id is! String || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      problems.add('icons.json: некоректний "id": $id (малі латинські літери, цифри, "_")');
      continue;
    }
    if (icons.containsKey(id) || entries.any((e) => e.id == id)) {
      problems.add('icons.json: повторний id "$id"');
      continue;
    }
    if (file is! String || label is! String || category is! String) {
      problems.add('icons.json: "$id" має мати рядкові "file", "label" і "category"');
      continue;
    }
    if (cats.isNotEmpty && !cats.contains(category)) {
      problems.add('icons.json: "$id" — невідома категорія "$category"');
    }
    final variant = raw['variantLabel'];
    final entry = AppIconEntry(
      id: id,
      file: file,
      label: label,
      category: category,
      pickable: raw['pickable'] == true,
      variantLabel: variant is String ? variant : null,
    );
    final text = readFile(file);
    if (text == null) {
      problems.add('$id: файл "$file" не знайдено');
      continue;
    }
    try {
      icons[id] = parseSvgIcon(text, onWarning: (m) => problems.add('$id ($file): $m'));
      entries.add(entry);
    } on FormatException catch (e) {
      problems.add('$id ($file): ${e.message}');
    }
  }
  return IconSet(entries, icons, problems);
}

/// Завантажені іконки. Викликати [load] один раз на старті (див. main.dart).
class AppIcons {
  AppIcons._();

  static IconSet _set = const IconSet([], {}, []);

  static bool get isLoaded => _set.icons.isNotEmpty;
  static List<String> get problems => _set.problems;
  static List<AppIconEntry> get entries => _set.entries;

  /// Читає реєстр і всі SVG із ресурсів застосунку. Помилки не кидає (одна
  /// зіпсована іконка не повинна вимикати весь застосунок) — лише пише в журнал.
  static Future<void> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    try {
      final manifest = await b.loadString('$kIconsDir/icons.json');
      final files = <String, String?>{};
      final decoded = jsonDecode(manifest);
      final list = decoded is Map ? decoded['icons'] : null;
      if (list is List) {
        await Future.wait([
          for (final e in list)
            if (e is Map && e['file'] is String)
              () async {
                final f = e['file'] as String;
                try {
                  files[f] = await b.loadString('$kIconsDir/$f');
                } catch (_) {
                  files[f] = null;
                }
              }()
        ]);
      }
      install(buildIconSet(manifest, (f) => files[f]));
    } catch (e) {
      debugPrint('Іконки: не вдалося завантажити: $e');
    }
  }

  /// Підставляє готовий набір (для [load] і для тестів).
  static void install(IconSet set) {
    _set = set;
    for (final p in set.problems) {
      debugPrint('Іконки: $p');
    }
  }

  static bool has(String id) => _set.icons.containsKey(id);

  /// Намалювати іконку [id] по центру [center] у квадраті зі стороною
  /// min(w, h). Колір [color] замінює кольори з файлу.
  static void paint(Canvas canvas, String id, Offset center, double w, double h, Color color) {
    final icon = _set.icons[id];
    if (icon == null) return;
    final side = w < h ? w : h;
    final scale = side / icon.size;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-icon.viewBox.center.dx, -icon.viewBox.center.dy);
    for (final s in icon.shapes) {
      s.draw(canvas, color);
    }
    canvas.restore();
  }

  /// Іконки, які можна обрати для об'єкта: (id, назва) — у порядку реєстру.
  static List<(String, String)> get pickable =>
      [for (final e in _set.entries) if (e.pickable) (e.id, e.label)];

  /// Варіанти перешкоди: (id, назва) — у порядку реєстру.
  static List<(String, String)> get obstacleVariants =>
      [for (final e in _set.entries) if (e.variantLabel != null) (e.id, e.variantLabel!)];
}
