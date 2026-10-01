import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Один запис «Що нового» — з історії git (tool/whats_new.py збирає рядки
/// «Нове:» / «Виправлено:» з описів комітів у assets/whats_new.json).
class NewsEntry {
  /// Порядковий номер коміту (більший — новіший).
  final int n;

  /// Порядок рядка в описі коміту.
  final int i;

  /// Версія застосунку в цьому коміті.
  final String version;
  final bool isFix;

  /// Вага 1..5: що більша, то вище в переліку.
  final int weight;
  final String text;

  const NewsEntry({
    required this.n,
    this.i = 0,
    required this.version,
    required this.isFix,
    this.weight = 1,
    required this.text,
  });

  factory NewsEntry.fromJson(Map<String, dynamic> j) => NewsEntry(
        n: j['n'] as int,
        i: (j['i'] as int?) ?? 0,
        version: j['v'] as String,
        isFix: j['t'] == 'fix',
        weight: (j['w'] as int?) ?? 1,
        text: j['text'] as String,
      );
}

/// Що показати на екрані: функції — від найзначнішої; одразу видно лише
/// 20% (Парето), решта й виправлені помилки — у «Ще».
class Release {
  final String version;
  final List<String> features;
  final List<String> fixes;
  const Release(this.version, this.features, this.fixes);

  bool get isEmpty => features.isEmpty && fixes.isEmpty;

  int get _top => features.isEmpty ? 0 : (features.length * 0.2).round().clamp(1, features.length);
  List<String> get topFeatures => features.take(_top).toList();
  List<String> get moreFeatures => features.skip(_top).toList();

  /// Зібрати з записів: найважчі першими, за рівної ваги — новіші.
  factory Release.fromEntries(Iterable<NewsEntry> entries) {
    final list = entries.toList();
    final feats = list.where((e) => !e.isFix).toList()
      ..sort((a, b) {
        if (a.weight != b.weight) return b.weight.compareTo(a.weight);
        if (a.n != b.n) return b.n.compareTo(a.n);
        return a.i.compareTo(b.i);
      });
    final fixes = list.where((e) => e.isFix).toList()
      ..sort((a, b) => a.n != b.n ? b.n.compareTo(a.n) : a.i.compareTo(b.i));
    var v = '';
    for (final e in list) {
      if (compareVersions(e.version, v) > 0) v = e.version;
    }
    return Release(v, [for (final e in feats) e.text], [for (final e in fixes) e.text]);
  }
}

/// «1.10.0» > «1.9.2».
int compareVersions(String a, String b) {
  List<int> parts(String s) => [for (final p in s.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var k = 0; k < 3; k++) {
    final d = (k < x.length ? x[k] : 0).compareTo(k < y.length ? y[k] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Усі записи з assets/whats_new.json (порожньо, якщо файла немає).
Future<List<NewsEntry>> loadNews() async {
  try {
    final raw = jsonDecode(await rootBundle.loadString('assets/whats_new.json'));
    return [
      for (final e in (raw['entries'] as List)) NewsEntry.fromJson(e as Map<String, dynamic>)
    ];
  } catch (_) {
    return const [];
  }
}
