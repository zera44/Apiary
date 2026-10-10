import 'database.dart';
import 'repository.dart' show kSyncTables;

/// Колонки, що існують лише на телефоні (на сервер не йдуть).
const kLocalOnlyColumns = {'synced'};

/// Рядок для сервера: без службових колонок телефона і з версією схеми
/// ([AppDatabase.schemaVersion]) - щоб стара й нова версії застосунку
/// працювали з одним сервером (сервер знає, якою версією записано рядок,
/// і не губить колонки, яких старий застосунок не знає).
Map<String, Object?> toServerRow(String table, Map<String, Object?> row) {
  if (!kSyncTables.contains(table)) {
    throw ArgumentError.value(table, 'table', 'не таблиця синхронізації');
  }
  return {
    for (final e in row.entries)
      if (!kLocalOnlyColumns.contains(e.key)) e.key: e.value,
    'schema_v': AppDatabase.schemaVersion,
  };
}

/// Рядок із сервера - у локальний: лише відомі цій версії колонки [known]
/// (новіша версія застосунку могла додати свої), позначка «з сервера»
/// (synced = 1), без службових полів сервера.
Map<String, Object?> fromServerRow(Map<String, Object?> row, Set<String> known) => {
      for (final e in row.entries)
        if (known.contains(e.key) && !kLocalOnlyColumns.contains(e.key)) e.key: e.value,
      'synced': 1,
    };
