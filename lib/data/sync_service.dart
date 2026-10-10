import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../services/app_config.dart';
import 'repository.dart';

/// Стан синхронізації для рядка стану (головний екран, Налаштування → «Головне»).
class SyncInfo {
  /// Коли востаннє все вивантажено (null - ще не було).
  final DateTime? lastOk;

  /// Скільки змін ще чекає відправки.
  final int pending;

  /// Немає зв'язку із сервером.
  final bool offline;

  /// Синхронізацію не налаштовано (немає адреси й ключа сервера).
  final bool disabled;

  /// Текст останньої помилки (null - помилки не було).
  final String? error;

  const SyncInfo(
      {this.lastOk, this.pending = 0, this.offline = false, this.disabled = false, this.error});
}

/// Синхронізація із сервером (Supabase).
///
/// Поки адресу й ключ не задано під час збірки (див. [AppConfig]),
/// синхронізація вимкнена й НІЧОГО не робить із даними: записи лишаються
/// в черзі (synced = 0), позначки «видалено» не стираються - їх отримає
/// сервер, коли синхронізацію буде увімкнено (інакше видалене могло б
/// «воскреснути» з іншого телефона).
///
/// Сам обмін із сервером (розклад, пакети, конфлікти) - етап 5.
class SyncService {
  /// Поточна служба (її можна смикнути одразу після входу).
  static SyncService? current;
  static final ValueNotifier<SyncInfo> info = ValueNotifier(const SyncInfo(disabled: true));

  /// Синхронізувати зараз (наприклад, одразу після входу).
  static Future<void> now() async {
    await current?.syncOnce();
  }

  final Repository repo;
  final AppConfig _config;

  SyncService(this.repo, {AppConfig? config}) : _config = config ?? AppConfig.current;

  /// Чи налаштовано сервер.
  bool get configured => _config.syncConfigured;

  void start() {
    current = this;
    unawaited(syncOnce());
  }

  void stop() {
    if (identical(current, this)) current = null;
  }

  /// Одна спроба. Повертає (успішно відправлено, всього в черзі).
  ///
  /// Обміну із сервером ще немає (етап 5), тож навіть із налаштованим
  /// сервером - «вимкнено»: дані лишаються в черзі, нічого не позначається
  /// і не стирається.
  Future<(int, int)> syncOnce() async {
    info.value = const SyncInfo(disabled: true);
    return (0, 0);
  }
}
