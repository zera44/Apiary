/// Тексти інтерфейсу, готові до кількох мов.
///
/// Кожен текст - окремий ключ цього класу. Мова - клас, що реалізує
/// [AppStrings] (поки лише [AppStringsUk]); компілятор не дасть додати мову,
/// де якогось ключа бракує. Звертатися - через [tr] (працює й без
/// BuildContext: у службах, сповіщеннях, фоновій синхронізації).
///
/// Усі НОВІ тексти - лише сюди. Старі (вписані прямо в екрани) переносяться
/// поступово, екран за екраном.
///
/// Не для перекладу: назви, що зберігаються в базі й шукаються за назвою
/// (базові характеристики, «Так»/«Ні», типові шаблони) - це дані, не тексти.
abstract class AppStrings {
  const AppStrings();

  /// Код мови (uk, en…).
  String get languageCode;

  /// Множина за правилами мови: «1 запис», «2 записи», «5 записів».
  String plural(int n, {required String one, required String few, required String many});

  // ---- Налаштування ----
  String get settingsTitle;
  String get settingsTabMain;
  String get settingsTabTemplates;

  // ---- Синхронізація ----
  String get syncSection;
  String get syncDisabled;
  String get syncOffline;
  String syncPending(int n);
  String syncLastOk(String when);
  String syncError(String details);
  String get syncRunning;
  String get syncWaitingWifi;
  String syncRejected(int n);
  String get syncNeedsSignIn;
  String get syncNow;
  String get syncDone;
  String get syncMobile;
  String get syncMobileWarnTitle;
  String get syncMobileWarnText;
  String get serverRestore;
  String get serverRestoreChoose;
  String get serverBackupsNone;
  String serverBackupItem(String when, String size);
  String get serverRestoreTitle;
  String serverRestoreText(String when);
  String get serverRestoring;
  String get serverRestored;
  String serverRestoreFailed(String details);
  String get firstLoginTitle;
  String get firstLoginText;
  String get firstLoginKeepPhone;
  String get firstLoginKeepPhoneHint;
  String get firstLoginKeepServer;
  String get firstLoginKeepServerHint;
  String get firstLoginMerge;
  String get firstLoginMergeHint;
  String get firstLoginKeepPhoneConfirm;
  String get firstLoginKeepServerConfirm;
  String get otherAccountTitle;
  String get otherAccountText;
  String get otherAccountReplace;
  String get otherAccountSignOut;
  String get firstLoginDone;
  String firstLoginFailed(String details);

  // ---- Загальне ----
  String get close;

  // ---- Фото складу ----
  String get photoOpen;
  String photoFailed(String details);

  // ---- Резервні копії ----
  String get backupsSection;
  String get backupsHint;
  String backupsLast(String when);
  String get backupsNone;
  String get backupNow;
  String get backupMade;
  String backupFailed(String details);
  String get backupKindAuto;
  String get backupKindManual;
  String get backupKindBeforeRestore;
  String get backupRestore;
  String get backupRestoreTitle;
  String backupRestoreText(String when);
  String get backupRestored;
  String get backupUndone;
  String backupRestoreFailed(String details);
  String get backupSaveToFile;
  String get backupSaveDialog;
  String get backupShare;
  String get backupSaved;
  String get backupSaveCancelled;
  String backupSaveFailed(String details);
  String get undo;
  String get cancel;

  /// Розмір файлу: «850 КБ», «1,2 МБ».
  String fileSize(int bytes);

  // ---- Помічники й запрошення ----
  String get helpersTitle;
  String get addHelper;
  String get helperLogin;
  String get helperLoginHint;
  String get accessAll;
  String get accessOne;
  String get accessStock;
  String get chooseApiary;
  String get sendInvite;
  String inviteSent(String email);
  String inviteNoSuchUser(String email);
  String get inviteInvalidEmail;
  String get inviteSelf;
  String inviteAlready(String email);
  String inviteNeedsStock(String email);
  String inviteAlreadyPending(String email);
  String inviteFailed(String details);
  String get sharingUnavailable;
  String get helpersNone;
  String get helperAllApiaries;
  String get helperWithStock;
  String get revokeAccess;
  String get revokeTitle;
  String revokeText(String email);
  String get invitesSentTitle;
  String get inviteCancel;
  String get invitationsTitle;
  String invitationFrom(String who);
  String invitationApiaries(String names);
  String get invitationAllApiaries;
  String get invitationWithStock;
  String get accept;
  String get decline;
  String invitesMail(int n);
  String get inviteAccepted;
  String get inviteDeclined;
  String get invitationsNone;

  // ---- Дата й час ----
  /// «сьогодні 14:05»
  String todayAt(String hm);

  // ---- База даних ----
  String dbTooNew(int found, int supported);
  String get startupErrorTitle;
  String get startupErrorHint;
  String get startupOpening;
  String get retry;
}

/// Множина в українській: 1, 21, 31… - [one]; 2-4, 22-24… - [few]; решта - [many].
String pluralUk(int n, {required String one, required String few, required String many}) {
  final a = n.abs();
  final d = a % 10, h = a % 100;
  if (d == 1 && h != 11) return one;
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
  return many;
}
