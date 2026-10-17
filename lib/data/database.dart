import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;

import '../l10n/l10n.dart';
import 'repository.dart' show Repository, kSyncTables;

/// Крок міграції бази (див. [AppDatabase.migrations]).
typedef Migration = Future<void> Function(DatabaseExecutor db);

/// Базу збережено новішою версією застосунку, ніж ця.
class DatabaseTooNewException implements Exception {
  final int found;
  final int supported;
  const DatabaseTooNewException(this.found, this.supported);

  @override
  String toString() => tr.dbTooNew(found, supported);
}

/// Відкриття локальної SQLite-бази. Усі дані спочатку завжди пишуться
/// сюди (offline-first); поле `synced` показує, чи запис уже відправлений
/// на сервер.
class AppDatabase {
  static const fileName = 'apiary.db';

  /// На телефоні - sqflite; на комп'ютері (тести, Linux/macOS) SQLite
  /// працює через FFI.
  static DatabaseFactory get platformFactory {
    if (Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  static Future<Database> openDefault() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return open(platformFactory, p.join(dir.path, fileName));
  }

  /// Тимчасова база в пам'яті для режиму навчання: щоразу нова й порожня,
  /// справжні пасіки користувача не зачіпає; зникає після закриття.
  static Future<Database> openSandbox([DatabaseFactory? factory]) =>
      open(factory ?? platformFactory, inMemoryDatabasePath, singleInstance: false);

  /// Версія схеми бази (зберігається в самій базі, PRAGMA user_version).
  /// Нова версія = новий крок у [migrations] з тим самим номером.
  ///  * 1 - схема до етапу 0;
  ///  * 2 - позначки «відправлено» скинуто (див. [_requeueAll]);
  ///  * 3 - спільний доступ: пасіка в кожному записі, власник довідників,
  ///    сталі ключі типових записів, групи «Конструктора» - таблицею
  ///    (див. [_sharing]);
  ///  * 4 - журнали синхронізації (sync_deletions, sync_photos).
  static const schemaVersion = 4;

  /// Кроки міграції: версія -> як дійти до неї з попередньої. Кожен крок
  /// виконується рівно один раз для бази, і всі разом - в одній транзакції
  /// (збій - база лишається попередньої версії).
  ///
  /// Крок завжди бачить уже найновішу схему: таблиці й колонки доповнює
  /// [ensureSchema] перед кроками, тож крок лише перетворює дані. Кроки
  /// виконуються й для зовсім нової бази (і пісочниці уроку) - там вони
  /// нічого не знаходять і нічого не роблять, - і для старої бази з
  /// Python-версії (версія 0). Тому крок має бути безпечним і на порожній
  /// базі, і на повній, і не губити наявні дані.
  static final Map<int, Migration> migrations = {
    2: _requeueAll,
    3: _sharing,
    4: _noop, // журнали синхронізації (sync_deletions, sync_photos) - у ensureSchema
  };

  /// Версія 3: записам, що належать пасіці через вулик, - пасіка прямо
  /// (зокрема видаленим - сервер має знати про їхнє видалення); групи
  /// «Конструктора» - у свою таблицю; типовим записам - сталі ключі.
  static Future<void> _sharing(DatabaseExecutor db) async {
    await backfillApiaryIds(db);
    await Repository.moveParamGroupsToTable(db);
    await Repository.assignSeedKeys(db);
  }

  /// Записам вуликів без пасіки - пасіку з їхнього вулика (групи чи
  /// об'єкта). Безпечно повторювати: чіпає лише рядки з порожньою пасікою.
  static Future<void> backfillApiaryIds(DatabaseExecutor db) async {
    for (final t in apiaryLinkedTables) {
      await db.rawUpdate('''
        UPDATE $t SET apiary_id = (
          SELECT e.apiary_id FROM elements e
          WHERE ($t.element_id IS NOT NULL AND e.id = $t.element_id)
             OR ($t.group_id IS NOT NULL AND e.group_id = $t.group_id)
          LIMIT 1)
        WHERE apiary_id IS NULL''');
    }
  }

  static Future<void> _noop(DatabaseExecutor db) async {}

  /// Стара заглушка синхронізації (до етапу 0) позначала всі записи
  /// «відправленими», хоча сервера не було. Скидаємо позначку - сервер
  /// отримає все, коли синхронізацію буде налаштовано.
  static Future<void> _requeueAll(DatabaseExecutor db) async {
    for (final t in kSyncTables) {
      await db.rawUpdate('UPDATE $t SET synced = 0 WHERE synced != 0');
    }
  }

  /// [path] може бути [inMemoryDatabasePath] (тести). [version] і
  /// [steps] - лише для тестів міграцій.
  static Future<Database> open(DatabaseFactory factory, String path,
      {bool singleInstance = true, int? version, Map<int, Migration>? steps}) async {
    final target = version ?? schemaVersion;
    final plan = steps ?? migrations;
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: target,
        singleInstance: singleInstance,
        // базу відкривають двоє в одному процесі (застосунок і фонове
        // завдання): відкриття не має відкочувати чужу незавершену
        // транзакцію (так sqflite робить у налагоджувальній збірці)
        rollbackActiveTransactionOnOpen: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        // база старішої версії (зокрема нова - її версія 0): спершу
        // доповнити схему, потім по черзі кроки від її версії до поточної
        // (усе в одній транзакції)
        onUpgrade: (db, from, to) async {
          await ensureSchema(db);
          for (var v = from + 1; v <= to; v++) {
            await plan[v]?.call(db);
          }
        },
        // база новішої версії (напр., відновили копію з новішого
        // застосунку): не відкриваємо, щоб не зіпсувати незнайомі дані
        onDowngrade: (db, from, to) => throw DatabaseTooNewException(from, to),
        // схему доповнюємо й при КОЖНОМУ відкритті (як і раніше)
        onOpen: ensureSchema,
      ),
    );
    return db;
  }

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS elements (
        id TEXT PRIMARY KEY,
        x INTEGER NOT NULL,
        y INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'hive',
        label TEXT,
        rotation INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await _ensureColumn(db, 'elements', 'group_id', 'TEXT');
    await _ensureColumn(db, 'elements', 'variant', 'TEXT');
    await _ensureColumn(db, 'elements', 'icon', 'TEXT');
    await _ensureColumn(db, 'elements', 'color', 'TEXT');
    // НОВЕ: кожен елемент належить конкретній пасіці (декілька карт).
    await _ensureColumn(db, 'elements', 'apiary_id', 'TEXT');

    // НОВЕ: пасіки — кілька окремих карт в одному застосунку.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS apiaries (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lat REAL,
        lon REAL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');

    // періодичність обходу всієї пасіки (днів) і коли її задали — точка
    // відліку для вуликів без дати останнього обходу
    await _ensureColumn(db, 'apiaries', 'visit_period', 'INTEGER');
    await _ensureColumn(db, 'apiaries', 'visit_period_at', 'REAL');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        size INTEGER NOT NULL,
        cells TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await _ensureColumn(db, 'templates', 'width', 'INTEGER');
    await _ensureColumn(db, 'templates', 'height', 'INTEGER');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS parameters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT,
        data_type TEXT NOT NULL DEFAULT 'text',
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await _ensureColumn(db, 'parameters', 'is_base', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'parameters', 'base_type', 'TEXT');
    // НОВЕ: стабільний ключ "Базової характеристики". Раніше вони
    // шукались за назвою, тож перейменування створювало дубль.
    await _ensureColumn(db, 'parameters', 'base_key', 'TEXT');
    // варіанти для типу «Список» (JSON-масив)
    await _ensureColumn(db, 'parameters', 'options', 'TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS element_parameters (
        id TEXT PRIMARY KEY,
        group_id TEXT,
        element_id TEXT,
        parameter_id TEXT NOT NULL,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await _ensureColumn(db, 'element_parameters', 'sort_order', 'INTEGER NOT NULL DEFAULT 0');
    // НОВЕ: м'яке видалення прив'язок, щоб і їх можна було синхронізувати.
    await _ensureColumn(db, 'element_parameters', 'deleted', 'INTEGER NOT NULL DEFAULT 0');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS parameter_records (
        id TEXT PRIMARY KEY,
        group_id TEXT,
        element_id TEXT,
        parameter_id TEXT NOT NULL,
        value TEXT,
        created_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');

    // НОВЕ: QR-коди вуликів. Код (зазвичай посилання) прив'язаний рівно до
    // однієї сутності — групи або окремого об'єкта; один об'єкт — один код.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS qr_codes (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        group_id TEXT,
        element_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    // номер наліпки (для кодів, згенерованих застосунком) — друкується під
    // кодом і дозволяє знайти вулик, ввівши номер вручну
    await _ensureColumn(db, 'qr_codes', 'number', 'INTEGER');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_qr_code ON qr_codes(code)');
    // службові позначки застосунку (не синхронізуються): напр., що типові
    // шаблони вже додавались і повторно їх додавати не треба
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    // склад: номенклатура (quantity NULL — ще жодного разу не заповнювали)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity REAL,
        photo TEXT,
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    // кожне заповнення: kind = 'set' (перезаписати) або 'add' (додати)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_moves (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        quantity_after REAL NOT NULL,
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    // kind: 'in' (прихід), 'out' (вибуття), 'inv' (переоблік, amount —
    // різниця зі знаком), 'cancel' (скасування запису); 'set'/'add' — старі записи
    // op_date — дата операції (не дата введення), price — ціна за одиницю
    // приходу, reason — причина списання
    await _ensureColumn(db, 'stock_moves', 'op_date', 'REAL');
    await _ensureColumn(db, 'stock_moves', 'price', 'REAL');
    await _ensureColumn(db, 'stock_moves', 'reason', 'TEXT');
    await _ensureColumn(db, 'stock_moves', 'comment', 'TEXT');
    // total — загальна вартість приходу (price = total / amount);
    // cancelled = 1 — запис скасовано (лишається в історії); ref_id — для
    // записів kind = 'cancel': який запис скасовано
    await _ensureColumn(db, 'stock_moves', 'total', 'REAL');
    await _ensureColumn(db, 'stock_moves', 'cancelled', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'stock_moves', 'ref_id', 'TEXT');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sm_item ON stock_moves(item_id)');
    // мінімальний залишок: досягли — «час докупити»
    await _ensureColumn(db, 'stock_items', 'min_quantity', 'REAL');

    // фінанси: довідник категорій, операції (витрата/дохід) і рядки таблиці
    // операції. Гроші склад не дублює: рядок із stock_move_id - це той самий
    // прихід, що лежить у stock_moves.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fin_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        to_stock INTEGER NOT NULL DEFAULT 0,
        icon TEXT,
        color TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fin_ops (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        category_id TEXT,
        amount REAL NOT NULL,
        op_date REAL NOT NULL,
        comment TEXT,
        cancelled INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fin_lines (
        id TEXT PRIMARY KEY,
        op_id TEXT NOT NULL,
        name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit TEXT NOT NULL,
        price REAL NOT NULL,
        to_stock INTEGER NOT NULL DEFAULT 0,
        stock_item_id TEXT,
        stock_move_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fl_op ON fin_lines(op_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fl_move ON fin_lines(stock_move_id)');

    // Нотатки вуликів: прив'язка як у parameter_records (група або об'єкт),
    // дата нотатки (можна заднім числом) і власна мітка (note_labels).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_labels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hive_notes (
        id TEXT PRIMARY KEY,
        group_id TEXT,
        element_id TEXT,
        text TEXT NOT NULL,
        note_date REAL NOT NULL,
        label_id TEXT,
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_hn_owner ON hive_notes(group_id, element_id)');

    // Разові нагадування («нагадай 5 травня підгодувати 3-й вулик»; ставить
    // помічник «Пасічник»). Лише на цьому телефоні - не синхронізуються.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_reminders (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        due_at REAL NOT NULL,
        group_id TEXT,
        element_id TEXT,
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');

    // Помічник «Пасічник»: стрічка чату (повідомлення, черга без інтернету,
    // картки «Записати так?») і розмова для моделі. Лише на цьому
    // телефоні - не синхронізуються.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assistant_chat (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT '',
        attempts INTEGER NOT NULL DEFAULT 0,
        next_try REAL,
        error TEXT,
        data TEXT,
        queued INTEGER NOT NULL DEFAULT 0,
        unread INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assistant_history (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        msg TEXT NOT NULL
      )''');

    // «Відгук»: розмова з розробником (лише на цьому телефоні, не
    // синхронізується). remote_seq - номер повідомлення на сервері.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feedback_chat (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_seq INTEGER UNIQUE,
        from_dev INTEGER NOT NULL DEFAULT 0,
        body TEXT NOT NULL,
        at REAL NOT NULL,
        pending INTEGER NOT NULL DEFAULT 0,
        unread INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_el_group ON elements(group_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_el_apiary ON elements(apiary_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ep_owner ON element_parameters(group_id, element_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pr_owner ON parameter_records(parameter_id, group_id, element_id)');
    await _ensureSharingSchema(db);
    await _ensureSyncSchema(db);
  }

  /// Таблиці, де кожен запис належить пасіці через свій вулик (група чи
  /// окремий об'єкт): тут пасіка проставляється й прямо (права доступу на
  /// сервері перевіряються за пасікою).
  static const apiaryLinkedTables = [
    'element_parameters',
    'parameter_records',
    'qr_codes',
    'hive_notes',
  ];

  /// Довідники й облік власника (не прив'язані до однієї пасіки): власник -
  /// owner_id (NULL - власник цього телефона, тобто «мій»).
  static const ownerTables = [
    'apiaries',
    'parameters',
    'templates',
    'note_labels',
    'stock_items',
    'stock_moves',
    'fin_categories',
    'fin_ops',
    'fin_lines',
    'param_groups',
  ];

  /// Записи, що застосунок створює сам (базові характеристики, типові
  /// шаблони, категорії фінансів, мітка «Огляд»): seed_key - їхня стала
  /// «назва», щоб однакові з різних телефонів злились в один.
  static const seededTables = ['parameters', 'templates', 'fin_categories', 'note_labels'];

  /// Службове для синхронізації (етап 5) - лише на цьому телефоні, на
  /// сервер саме не йде й у резервних копіях нічого не важить:
  ///   sync_deletions - записи історії значень, прибрані з телефона
  ///       (відновлення копії): сервер позначить їх видаленими;
  ///   sync_photos - фото складу, вже вивантажені на сервер.
  static Future<void> _ensureSyncSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_deletions (
        tbl TEXT NOT NULL,
        id TEXT NOT NULL,
        at REAL NOT NULL,
        PRIMARY KEY (tbl, id)
      )''');
    await db.execute('CREATE TABLE IF NOT EXISTS sync_photos (name TEXT PRIMARY KEY)');
  }

  /// Спільний доступ (етап 3): власник, учасники, запрошення; групи
  /// «Конструктора» - окремою таблицею (раніше - у службових позначках).
  static Future<void> _ensureSharingSchema(Database db) async {
    // учасники: помічник [user_id]/[email] бачить пасіку [apiary_id]
    // власника [owner_id] (apiary_id NULL - усі пасіки власника, зокрема
    // майбутні); stock_access - ще й склад і фінанси
    await db.execute('''
      CREATE TABLE IF NOT EXISTS apiary_members (
        id TEXT PRIMARY KEY,
        owner_id TEXT,
        apiary_id TEXT,
        user_id TEXT,
        email TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'helper',
        stock_access INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    // запрошення: від кого, кому (пошта), на які пасіки (JSON-масив id;
    // NULL - усі), стан: pending / accepted / declined / revoked
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invitations (
        id TEXT PRIMARY KEY,
        from_user_id TEXT,
        from_email TEXT,
        from_name TEXT,
        to_email TEXT NOT NULL,
        apiary_ids TEXT,
        apiary_names TEXT,
        stock_access INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS param_groups (
        id TEXT PRIMARY KEY,
        owner_id TEXT,
        name TEXT NOT NULL,
        ids TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )''');
    for (final t in ownerTables) {
      await _ensureColumn(db, t, 'owner_id', 'TEXT');
    }
    for (final t in seededTables) {
      await _ensureColumn(db, t, 'seed_key', 'TEXT');
    }
    for (final t in apiaryLinkedTables) {
      await _ensureColumn(db, t, 'apiary_id', 'TEXT');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_apiary ON $t(apiary_id)');
      // пасіку проставляє сама база: з вулика (групи чи об'єкта) запису -
      // і для нових записів, і коли запис перенесли на інший вулик
      final fill = '''
        UPDATE $t SET apiary_id = (
          SELECT e.apiary_id FROM elements e
          WHERE (NEW.element_id IS NOT NULL AND e.id = NEW.element_id)
             OR (NEW.group_id IS NOT NULL AND e.group_id = NEW.group_id)
          LIMIT 1)
        WHERE id = NEW.id;''';
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_apiary_ins AFTER INSERT ON $t
        WHEN NEW.apiary_id IS NULL BEGIN $fill END''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_apiary_upd AFTER UPDATE OF group_id, element_id ON $t
        BEGIN $fill END''');
    }
  }

  static Future<void> _ensureColumn(
      Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => c['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
