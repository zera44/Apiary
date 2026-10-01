import 'package:apiary/data/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NewsEntry feat(int n, String t, {int w = 1, String v = '0.3.0'}) =>
      NewsEntry(n: n, version: v, isFix: false, weight: w, text: t);

  test('«Що нового»: найважчі першими, одразу 20%, решта й виправлення - у «Ще»', () {
    final r = Release.fromEntries([
      for (var i = 1; i <= 8; i++) feat(i, 'ф$i'),
      feat(9, 'головна', w: 3),
      feat(10, 'друга', w: 2),
      const NewsEntry(n: 11, version: '0.4.0', isFix: true, text: 'баг'),
    ]);
    expect(r.version, '0.4.0');
    expect(r.topFeatures, ['головна', 'друга']); // 20% від 10
    expect(r.moreFeatures.first, 'ф8'); // за рівної ваги — новіші
    expect(r.fixes, ['баг']);
  });

  test('порівняння версій', () {
    expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareVersions('0.3.0', '0.3.0'), 0);
    expect(compareVersions('', '0.1.0'), lessThan(0));
  });

  test('assets/whats_new.json читається', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final news = await loadNews();
    expect(news, isNotEmpty);
  });
}
