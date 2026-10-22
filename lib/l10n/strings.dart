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
  String get settingsTabAccount;

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
  String get syncSignInAgain;
  String get syncSignInAgainHint;
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
  String get textSizeSection;
  String get textSizeHint;
  List<String> get textSizeLevels;
  String get textSizePreview;
  String get inviteLinkButton;
  String get inviteLinkHint;
  String inviteLinkShare(String url);
  String get inviteLinkCopied;
  String get inviteLinkTooMany;
  String inviteLinkFailed(String details);
  String get joinConfirmTitle;
  String get joinConfirmText;
  String get joinConfirm;
  String joinDone(String owner, List<String> apiaries);
  String get joinInvalid;
  String get joinOwn;
  String get joinUnavailable;
  String get accountSection;
  String accountSignedInAs(String email);
  String get accountSignedInVia;
  String accountSignedInMail(String email);
  String get accountSignOut;
  String get accountSignOutTitle;
  String get accountSignOutText;
  String get accountGuest;
  String get accountDelete;
  String get accountDeleteTitle;
  String get accountDeleteText;
  String get accountDeleteContinue;
  String get accountDeleteFinalTitle;
  String get accountDeleteFinalText;
  String get accountDeleteWord;
  String get accountDeleting;
  String get accountDeleted;
  String accountDeleteFailed(String details);
  String get privacyPolicy;
  String get privacySection;
  String get privacySoon;

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

  // ---- Помічник «Пасічник» ----
  String get assistantTitle;
  String get assistantOpen;
  String get assistantHint;
  String get assistantGreeting;
  String get assistantSend;
  String get assistantNewChat;
  String get assistantNewChatConfirm;
  String get assistantConversations;
  String get assistantConvUntitled;
  String get assistantConvEmpty;
  String get assistantConvDelete;
  String get assistantConvDeleteText;
  String get assistantCopy;
  String get assistantCopied;
  String get assistantOffline;
  String get assistantWaiting;
  String get assistantSending;
  String get assistantFailed;
  String get assistantRetry;
  String get assistantDelete;
  String assistantThinking(String who);
  String get assistantCardTitle;
  String get assistantYes;
  String get assistantNo;
  String get assistantSaved;
  String get assistantRejected;
  String get assistantUndo;
  String get assistantUndone;
  String assistantOpenTarget(String what);
  String get assistantUnauthorized;
  String get assistantServerError;
  String get assistantDemo;
  String assistantMail(int n);
  String get assistantBear;
  String get assistantBeekeeper;
  String get assistantBearHint;
  String get assistantBeekeeperHint;
  String get assistantClose;
  String assistantContextPin(String screen);
  String get assistantRobo;
  String get assistantRoboHint;
  String assistantRouted(String who);
  String get assistantWhoHelps;
  String get assistantEffort;
  String get assistantEffortHintText;
  String get assistantEffortLow;
  String get assistantEffortMedium;
  String get assistantEffortHigh;
  String get assistantEffortXhigh;
  String get assistantMicHold;
  String get assistantNotHeard;
  String get assistantListening;
  String get assistantMicExplainTitle;
  String get assistantMicExplain;
  String get assistantMicExplainOk;
  String assistantVoiceModel(int mb);
  String get assistantVoiceDownload;
  String assistantVoiceDownloading(int percent);
  String get assistantVoiceReady;
  String get assistantVoiceOffline;
  String get assistantVoiceUnavailable;
  String get assistantNoMic;
  String get assistantNoUkVoice;
  String get assistantSection;
  String get assistantSpeakSetting;

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
