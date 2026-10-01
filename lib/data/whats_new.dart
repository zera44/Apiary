/// «Що нового» в стилі кайдзен: кожна зміна — як картка покращення на
/// дошці Toyota: яку втрату (муда) прибрали, як було → як стало.
class KaizenItem {
  /// Що змінилось (коротко, дієсловом).
  final String title;

  /// Як було / як стало — натискання чи дії (наприклад, «90 натискань»).
  final String before;
  final String after;

  /// Вид втрати (муда), яку прибрали.
  final String muda;

  /// Головне оновлення (≈20% змін, що дають основний виграш, — за Парето):
  /// показується одразу; решта — у гортальній стрічці нижче.
  final bool key;
  const KaizenItem(this.title, this.before, this.after, this.muda, {this.key = false});
}

class KaizenGroup {
  final String title;
  final List<KaizenItem> items;
  const KaizenGroup(this.title, this.items);
}

class Release {
  final String version;

  /// Головна цифра оновлення.
  final String headline;
  final String headlineNote;
  final List<KaizenGroup> groups;
  const Release(this.version, this.headline, this.headlineNote, this.groups);

  List<KaizenItem> get keyItems => [for (final g in groups) ...g.items.where((i) => i.key)];
  List<KaizenItem> get otherItems => [for (final g in groups) ...g.items.where((i) => !i.key)];
}

/// Види втрат (муда) — мовою пасічника.
abstract final class Muda {
  static const motion = 'Зайві рухи';
  static const search = 'Пошук очима';
  static const rework = 'Подвійна робота';
  static const waiting = 'Очікування';
  static const inventory = 'Нестача запасів';
  static const overprocessing = 'Зайві кроки';
}

/// Найновіше — першим. Перша версія в списку = поточна.
const kReleases = <Release>[
  Release(
    '0.3.0',
    '−61%',
    'натискань за типовий тиждень на пасіці з 30 вуликів',
    [
      KaizenGroup('Щоденний обхід', [
        KaizenItem('«Зберегти й далі» відкриває наступний вулик', '30 вуликів: 90 натискань',
            '31 натискання', Muda.motion, key: true),
        KaizenItem('Наліпка QR одразу відкриває огляд', '3 натискання', '2', Muda.overprocessing),
        KaizenItem('«Оглянуто, змін немає» на панелі вулика', '2 натискання', '1', Muda.overprocessing),
        KaizenItem('«Сьогодні оглянути: N» на головному, прострочені — червоним на карті',
            'шукати на карті', 'видно одразу', Muda.search, key: true),
        KaizenItem('Нагадування веде просто до вулика з формою', '≈6 натискань і пошук', '2',
            Muda.search),
        KaizenItem('«Почати» відкриває останню пасіку', '2 натискання', '1', Muda.motion),
      ]),
      KaizenGroup('Склад', [
        KaizenItem('Підгодівля у формі вулика сама списується зі складу', 'записати двічі',
            'один раз', Muda.rework),
        KaizenItem('Мінімальний залишок і «Час докупити»', 'нестача — раптом',
            'нагадування заздалегідь', Muda.inventory),
        KaizenItem('Інвентаризація списком', '2 натискання на позицію', '1 на весь склад',
            Muda.overprocessing),
        KaizenItem('Новий товар одразу з кількістю й вартістю', '2 кроки', '1', Muda.overprocessing),
      ]),
      KaizenGroup('Налаштування й облік', [
        KaizenItem('Періодичність обходу — одна на всю пасіку', '30 вуликів × 4 натискання',
            'одне налаштування', Muda.rework, key: true),
        KaizenItem('Наліпки QR прив\'язуються підряд', '30 вуликів: 60 натискань', '1 + скани',
            Muda.search),
        KaizenItem('Друк наліпок просто із застосунку', 'зберегти PDF і шукати', '«Друк»',
            Muda.waiting),
        KaizenItem('Звіт по пасіці одним файлом Excel', 'файл на кожен параметр', 'один файл',
            Muda.rework),
        KaizenItem('Видалення одразу, з «Відмінити»', '2 натискання', '1', Muda.overprocessing),
        KaizenItem('Готові шаблони «Вулик» і «Лежак»', 'перший вулик: ≈15 натискань', '8',
            Muda.overprocessing),
        KaizenItem('Довгий дотик переміщує вулик', '5 натискань', '2', Muda.motion),
      ]),
    ],
  ),
];
