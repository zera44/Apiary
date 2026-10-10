import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;

import '../l10n/l10n.dart';

/// Відкриття локальної SQLite-бази. Усі дані спочатку завжди пишуться
/// сюди (offline-first); поле `synced` показує, чи запис уже відправлений
/// на сервер.
/// Крок міграції бази (див. [AppDatabase.migrations]).
typedef Migration = Future<void> Function(Database db);

/// Базу збережено новішою версією застосунку, ніж ця.
class DatabaseTooNewException implements Exception {
  final int found;
  final int supported;
  const DatabaseTooNewException(this.found, this.supported);

  @override
  String toString() => tr.dbTooNew(found, supported);
}

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
  static const schemaVersion = 1;

  /// Кроки міграції: версія -> як дійти до неї з попередньої. Крок має
  /// зберігати всі наявні дані (лише доповнювати чи перетворювати) і
  /// виконується рівно один раз - коли базу вперше відкриває новіша версія.
  /// Нові таблиці й колонки окремого кроку не потребують: їх доповнює
  /// [ensureSchema] (він виконується до кроків і після них).
  static final Map<int, Migration> migrations = {};

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
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        // база старішої версії: спершу доповнити схему, потім по черзі
        // кроки від її версії до поточної (усе в одній транзакції)
        onUpgrade: (db, from, to) async {
          await ensureSchema(db);
          for (var v = from + 1; v <= to; v++) {
            await plan[v]?.call(db);
          }
        },
        // база новішої версії (напр., відновили копію з новішого
        // застосунку): не відкриваємо, щоб не зіпсувати незнайомі дані
        onDowngrade: (db, from, to) => throw DatabaseTooNewException(from, to),
        // схему доповнюємо при КОЖНОМУ відкритті (як і раніше) — так само
        // відкривається і стара база з Python-версії; нова база одразу
        // отримує найновішу схему, кроки міграції їй не потрібні
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

    await db.execute('CREATE INDEX IF NOT EXISTS idx_el_group ON elements(group_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_el_apiary ON elements(apiary_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ep_owner ON element_parameters(group_id, element_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pr_owner ON parameter_records(parameter_id, group_id, element_id)');
  }

  static Future<void> _ensureColumn(
      Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => c['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
