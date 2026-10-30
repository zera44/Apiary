import 'strings.dart';

/// English.
class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  String get languageCode => 'en';

  @override
  String plural(int n, {required String one, required String few, required String many}) =>
      n.abs() == 1 ? one : many;

  /// «1 hive», «3 hives».
  String _n(int n, String one, String other) => '$n ${n.abs() == 1 ? one : other}';

  // ---- Налаштування ----
  @override
  String get settingsTitle => 'Settings';
  @override
  String get settingsTabMain => 'General';
  @override
  String get settingsTabAccount => 'Account';
  @override
  String get settingsTabTemplates => 'Templates';

  // ---- Синхронізація ----
  @override
  String get syncSection => 'Sync';
  @override
  String get syncDisabled => 'Sync is not set up yet - data is only on this device';
  @override
  String get syncOffline => 'No connection to the server - changes are saved on the device';
  @override
  String syncPending(int n) => 'Waiting to be sent: ${_n(n, 'change', 'changes')}';
  @override
  String syncLastOk(String when) => 'Last sync: $when';
  @override
  String syncError(String details) => 'Sync error: $details';
  @override
  String get syncRunning => 'Syncing…';
  @override
  String get syncWaitingWifi => 'Waiting for Wi-Fi: sync over mobile data is off';
  @override
  String syncRejected(int n) => 'The server did not accept ${_n(n, 'change', 'changes')} (no access)';
  @override
  String get syncNeedsSignIn => 'Sign in with Google to sync data between phones';
  @override
  String get syncNow => 'Sync now';
  @override
  String get syncSignInAgain => 'Sign in again';
  @override
  String get syncSignInAgainHint =>
      'Your server session has ended (for example, if the account was deleted from another phone). '
      'Sign in again to keep syncing.';
  @override
  String get syncDone => 'Synced';
  @override
  String get syncMobile => 'Sync over mobile data';
  @override
  String get syncMobileWarnTitle => 'Mobile data';
  @override
  String get syncMobileWarnText =>
      'Usually sync is a few kilobytes per hour. At night the app sends a full '
      '(compressed) copy of the database and new stock photos to the server - that '
      'can be a few megabytes. If your data plan is limited, turn this off: then '
      'sync happens over Wi-Fi only.';
  @override
  String get serverRestore => 'Download from server';
  @override
  String get serverRestoreChoose => 'Which copy to download?';
  @override
  String get serverBackupsNone => 'There are no copies on the server yet - they appear every night';
  @override
  String serverBackupItem(String when, String size) => '$when · $size';
  @override
  String get serverRestoreTitle => 'Download data from the server?';
  @override
  String serverRestoreText(String when) =>
      'The data on this phone will be replaced with the server copy from $when. Before that, '
      'the app saves a copy of the current data here on the phone (you can see it in '
      '"Backups" and restore it from there).';
  @override
  String get serverRestoring => 'Downloading the copy from the server…';
  @override
  String get serverRestored => 'Data downloaded from the server';
  @override
  String serverRestoreFailed(String details) => 'Could not download: $details';
  @override
  String get firstLoginTitle => 'There is data both on the phone and on the server';
  @override
  String get firstLoginText =>
      'This phone already has apiaries, and so does your account on the server. What should we do with them?';
  @override
  String get firstLoginKeepPhone => 'Keep the phone data';
  @override
  String get firstLoginKeepPhoneHint => 'Server data that is not here will be deleted';
  @override
  String get firstLoginKeepServer => 'Keep the server data';
  @override
  String get firstLoginKeepServerHint =>
      'The server replaces the phone data (a copy is saved here first, in "Backups")';
  @override
  String get firstLoginMerge => 'Merge everything';
  @override
  String get firstLoginMergeHint => 'Everything from both sides is kept';
  @override
  String get firstLoginKeepPhoneConfirm =>
      'Server data that is not on this phone will be deleted - including on your other '
      'phones after they sync. Continue?';
  @override
  String get firstLoginKeepServerConfirm =>
      'The server data will replace the data on this phone. The current phone data is saved '
      'in "Backups" - you can restore it from there. Continue?';
  @override
  String get otherAccountTitle => 'The phone has data from another account';
  @override
  String get otherAccountText =>
      'The data on this phone was synced with another Google account. It cannot be mixed '
      'with this account.';
  @override
  String get otherAccountReplace => 'Download this account\'s data';
  @override
  String get otherAccountSignOut => 'Sign out';
  @override
  String get firstLoginDone => 'Done - data is syncing';
  @override
  String firstLoginFailed(String details) => 'Failed: $details';
  @override
  String get textSizeSection => 'Text size';
  @override
  String get textSizeHint => 'For comfortable reading - across the whole app.';
  @override
  List<String> get textSizeLevels => const ['Normal', 'Larger', 'Large', 'Very large', 'Largest'];
  @override
  String get textSizePreview => 'Hive 12 - inspect today';
  @override
  String get orientationSection => 'Screen orientation';
  @override
  String get orientationHint => 'Auto - follows how the phone is turned.';
  @override
  List<String> get orientationLevels => const ['Auto', 'Portrait', 'Landscape'];
  @override
  String get inviteLinkButton => 'Create an invite link';
  @override
  String get inviteLinkHint =>
      'The link works once and is valid for 7 days. Send it in a messenger - the person opens it on their phone and becomes your helper right away.';
  @override
  String inviteLinkShare(String url) => 'Join my apiary in Vulyk (a Google account is needed):\n$url';
  @override
  String get inviteLinkCopied => 'Link copied - send it to your helper';
  @override
  String get inviteLinkTooMany => 'Too many active links - wait until they are used or expire.';
  @override
  String inviteLinkFailed(String details) => 'Could not create the link: $details';
  @override
  String get joinConfirmTitle => 'Apiary invitation';
  @override
  String get joinConfirmText => 'You have been invited to help with an apiary in Vulyk. Join?';
  @override
  String get joinConfirm => 'Join';
  @override
  String joinDone(String owner, List<String> apiaries) => apiaries.isEmpty
      ? 'Done: you are a helper${owner.isEmpty ? '' : ' ($owner)'}. The apiaries will appear in a minute.'
      : 'Done: you are a helper in ${apiaries.join(', ')}${owner.isEmpty ? '' : ' ($owner)'}. The apiaries will appear in a minute.';
  @override
  String get joinInvalid => 'This link is no longer valid. Ask the owner to create a new one.';
  @override
  String get joinOwn => 'This is your own link - send it to your helper.';
  @override
  String get joinUnavailable => 'Could not join: no connection to the server. Open the link again.';
  @override
  String get accountSection => 'Account';
  @override
  String accountSignedInAs(String email) => 'Signed in as $email';
  @override
  String get accountSignedInVia => 'Signed in with Google';
  @override
  String accountSignedInMail(String email) => 'Signed in: $email. Data is syncing.';
  @override
  String get accountSignOut => 'Sign out';
  @override
  String get accountSignOutTitle => 'Sign out?';
  @override
  String get accountSignOutText =>
      'Apiary data stays on this device. Next you can sign in again or continue without signing in.';
  @override
  String get accountGuest => 'You are not signed in - data is only on this device.';
  @override
  String get accountDelete => 'Delete account and all data';
  @override
  String get accountDeleteTitle => 'Delete account?';
  @override
  String get accountDeleteText =>
      'This permanently deletes your account, all apiaries, hives, inspections, notes, stock, '
      'finances, stock photos and nightly copies - on the server and on this phone, as well as '
      'the backups on the phone. Your helpers lose access. Records you made as a helper in '
      'other people\'s apiaries stay with their owners.';
  @override
  String get accountDeleteContinue => 'Next';
  @override
  String get accountDeleteFinalTitle => 'Really delete?';
  @override
  String get accountDeleteFinalText => 'This cannot be undone. To confirm, type the word DELETE.';
  @override
  String get accountDeleteWord => 'DELETE';
  @override
  String get accountDeleting => 'Deleting…';
  @override
  String get accountDeleted => 'The account and all data have been deleted';
  @override
  String accountDeleteFailed(String details) => 'Could not delete: $details';
  @override
  String get privacyPolicy => 'Privacy policy';
  @override
  String get privacySection => 'Privacy';
  @override
  String get privacySoon => 'The privacy policy text will appear here soon.';

  // ---- Загальне ----
  @override
  String get close => 'Close';

  // ---- Фото складу ----
  @override
  String get photoOpen => 'Open photo';
  @override
  String photoFailed(String details) => 'Could not get the photo: $details';

  // ---- Резервні копії ----
  @override
  String get backupsSection => 'Backups';
  @override
  String get backupsHint => 'A copy of the data is made automatically every 6 hours and kept on this '
      'phone for 2 days. Photos are not included - they stay on the phone.';
  @override
  String backupsLast(String when) => 'Last copy: $when';
  @override
  String get backupsNone => 'No copies yet';
  @override
  String get backupNow => 'Make a copy now';
  @override
  String get backupMade => 'Copy made';
  @override
  String backupFailed(String details) => 'Could not make a copy: $details';
  @override
  String get backupKindAuto => 'automatic';
  @override
  String get backupKindManual => 'made manually';
  @override
  String get backupKindBeforeRestore => 'state before restore';
  @override
  String get backupRestore => 'Restore';
  @override
  String get backupRestoreTitle => 'Restore data from the copy?';
  @override
  String backupRestoreText(String when) =>
      'The data on this phone will be replaced with the copy from $when. The current state is '
      'saved as a separate copy first - the restore can be undone.';
  @override
  String get backupRestored => 'Data restored from the copy';
  @override
  String get backupUndone => 'The data from before the restore is back';
  @override
  String backupRestoreFailed(String details) => 'Could not restore: $details';
  @override
  String get backupSaveToFile => 'Save to file';
  @override
  String get backupSaveDialog => 'Save backup';
  @override
  String get backupShare => 'Share';
  @override
  String get backupSaved => 'Copy saved to file';
  @override
  String get backupSaveCancelled => 'Saving cancelled';
  @override
  String backupSaveFailed(String details) => 'Could not save the file: $details';
  @override
  String get undo => 'Undo';
  @override
  String get cancel => 'Cancel';

  @override
  String fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ---- Помічники й запрошення ----
  @override
  String get helpersTitle => 'Helpers';
  @override
  String get addHelper => 'Add a helper';
  @override
  String get helperLogin => 'User login';
  @override
  String get helperLoginHint => 'Google email, e.g. john@gmail.com';
  @override
  String get accessAll => 'To all apiaries';
  @override
  String get accessOne => 'Only to this apiary';
  @override
  String get accessStock => 'Also stock and finances';
  @override
  String get chooseApiary => 'Choose an apiary';
  @override
  String get sendInvite => 'Send invitation';
  @override
  String inviteSent(String email) => 'Invitation sent: $email';
  @override
  String inviteNoSuchUser(String email) =>
      '$email is not in Vulyk yet. Ask them to sign in to the app with Google first, '
      'then invite them again.';
  @override
  String get inviteInvalidEmail => 'Enter a Google email, e.g. john@gmail.com';
  @override
  String get inviteSelf => 'This is your own email';
  @override
  String inviteAlready(String email) => '$email already has this access';
  @override
  String inviteNeedsStock(String email) =>
      '$email already has access to the apiaries - turn on stock and finances in the helpers list below';
  @override
  String inviteAlreadyPending(String email) => 'An invitation for $email has already been sent and is waiting for a reply';
  @override
  String inviteFailed(String details) => 'Could not send the invitation: $details';
  @override
  String get sharingUnavailable =>
      'You can invite a helper once sync is set up and you are signed in with Google.';
  @override
  String get helpersNone => 'No helpers yet';
  @override
  String get helperAllApiaries => 'all apiaries';
  @override
  String get helperWithStock => 'stock and finances';
  @override
  String get revokeAccess => 'Revoke access';
  @override
  String get revokeTitle => 'Revoke access?';
  @override
  String revokeText(String email) =>
      '$email will no longer see these apiaries. What the helper has already recorded stays.';
  @override
  String get invitesSentTitle => 'Waiting for a reply';
  @override
  String get inviteCancel => 'Cancel invitation';
  @override
  String get invitationsTitle => 'Invitations';
  @override
  String invitationFrom(String who) => 'From: $who';
  @override
  String invitationApiaries(String names) => 'Apiaries: $names';
  @override
  String get invitationAllApiaries => 'All apiaries';
  @override
  String get invitationWithStock => 'together with stock and finances';
  @override
  String get accept => 'Accept';
  @override
  String get decline => 'Decline';
  @override
  String invitesMail(int n) => 'You are invited as a helper: ${_n(n, 'invitation', 'invitations')}';
  @override
  String get inviteAccepted =>
      'Invitation accepted - the apiaries will appear in "My apiaries" after sync';
  @override
  String get inviteDeclined => 'Invitation declined';
  @override
  String get invitationsNone => 'No invitations';

  // ---- Помічник «Пасічник» ----
  @override
  String get assistantTitle => 'Beekeeper';
  @override
  String get assistantOpen => 'Talk to the beekeeper';
  @override
  String get assistantHint => 'Write what to do: "open stock", "record an inspection of hive 5"…';
  @override
  String get assistantGreeting => 'I will help with the app: open what you need, find hives, record an inspection, a stock arrival or an expense. What should I do?';
  @override
  String get assistantSend => 'Send';
  @override
  String get assistantNewChat => 'New conversation';
  @override
  String get assistantConversations => 'Conversations';
  @override
  String get assistantConvUntitled => 'New conversation';
  @override
  String get assistantConvEmpty => 'This conversation is still empty';
  @override
  String get assistantConvDelete => 'Delete the conversation?';
  @override
  String get assistantConvDeleteText => 'The conversation disappears together with the replies. What was recorded in the apiary stays.';
  @override
  String get assistantCopy => 'Copy';
  @override
  String get assistantCopied => 'Copied';
  @override
  String get assistantNewChatConfirm =>
      'Start a new conversation? The previous one disappears from this phone (queued messages stay).';
  @override
  String get assistantOffline => 'No connection - I will send it as soon as there is one';
  @override
  String get assistantWaiting => 'waiting for internet';
  @override
  String get assistantSending => 'sending…';
  @override
  String get assistantFailed => 'not sent';
  @override
  String get assistantRetry => 'Retry';
  @override
  String get assistantDelete => 'Delete';
  @override
  String assistantThinking(String who) => '$who is thinking…';
  @override
  String get assistantCardTitle => 'Record it like this?';
  @override
  String get assistantYes => 'Yes';
  @override
  String get assistantNo => 'No';
  @override
  String get assistantSaved => 'Recorded';
  @override
  String get assistantRejected => 'Not recorded';
  @override
  String get assistantUndo => 'Undo';
  @override
  String get assistantUndone => 'Undone';
  @override
  String assistantOpenTarget(String what) => 'Open: $what';
  @override
  String get assistantUnauthorized => 'The assistant is unavailable: the server did not accept the access code';
  @override
  String get assistantServerError => 'The assistant server did not respond properly';
  @override
  String get assistantDemo => 'Demo mode: the assistant server is not connected';
  @override
  String assistantMail(int n) => 'The beekeeper replied: $n new';
  @override
  String get assistantBear => 'Little Bear';
  @override
  String get assistantBeekeeper => 'Beekeeper';
  @override
  String get assistantBearHint => 'Fast - for simple things';
  @override
  String get assistantBeekeeperHint => 'More experienced - understands complex requests better';
  @override
  String get assistantClose => 'Close';
  @override
  String assistantContextPin(String screen) => 'Talk about "$screen"';
  @override
  String get assistantBearAcc => 'Little Bear';
  @override
  String get assistantBeekeeperAcc => 'Beekeeper';
  @override
  String get assistantRoboAcc => 'Robo-Beekeeper';
  @override
  String get assistantRoboLocked =>
      'Turns on by itself when the Beekeeper could not cope, and turns off when the task is simple';
  @override
  String get assistantRobo => 'Robo-Beekeeper';
  @override
  String get assistantRoboHint => 'The smartest and most expensive - for the hardest tasks';
  @override
  String assistantRouted(String who) => 'This is a simple question - switching to $who';
  @override
  String assistantEscalated(String from, String to) =>
      '$from could not cope with this question - switching to $to';
  @override
  String get assistantWhoHelps => 'Who helps';
  @override
  String get assistantEffort => 'Reasoning depth';
  @override
  String get assistantEffortHintText => 'Higher is more accurate on complex requests, but takes longer';
  @override
  String get assistantEffortLow => 'Low';
  @override
  String get assistantEffortMedium => 'Medium';
  @override
  String get assistantEffortHigh => 'High';
  @override
  String get assistantEffortXhigh => 'Very high';
  @override
  String get assistantNotHeard => 'Did not catch that - try again';
  @override
  String get assistantMicHold => 'Tap and speak';
  @override
  String get assistantListening => 'Listening… Tap the microphone again to finish';
  @override
  String get assistantMicExplainTitle => 'Microphone for the beekeeper';
  @override
  String get assistantMicExplain =>
      'To talk to the beekeeper by voice, the app needs microphone permission. It only listens while you hold the microphone button. The phone will now ask for permission.';
  @override
  String get assistantMicExplainOk => 'Got it';
  @override
  String assistantVoiceModel(int mb) =>
      'To speak without internet, download the voice model once (~$mb MB, preferably over Wi-Fi).';
  @override
  String get assistantVoiceDownload => 'Download';
  @override
  String assistantVoiceDownloading(int percent) => 'Downloading the voice model: $percent%';
  @override
  String get assistantVoiceReady => 'The voice model is ready - hold the button and speak';
  @override
  String get assistantVoiceOffline =>
      'Voice recognition is unavailable without internet: the voice model has not been downloaded yet. Type instead, or download the model when you have Wi-Fi.';
  @override
  String get assistantVoiceUnavailable => 'Voice input is not available on this phone';
  @override
  String get assistantNoMic =>
      'No microphone permission (Phone settings → Apps → Vulyk → Permissions)';
  @override
  String get assistantNoUkVoice =>
      'The phone\'s text-to-speech has no Ukrainian voice - replies will not be read aloud';
  @override
  String get assistantSection => 'Assistant (Little Bear and Beekeeper)';
  @override
  String get assistantSpeakSetting => 'Read replies aloud';

  // ---- Дата й час ----
  @override
  String todayAt(String hm) => 'today $hm';

  // ---- База даних ----
  @override
  String get startupErrorTitle => 'Could not open the apiary data';
  @override
  String get startupErrorHint =>
      'Possible reasons: the app is already running in another window, the disk is full, '
      'or the data file is damaged. Close other copies of the app and try again.';
  @override
  String get startupOpening => 'Opening…';
  @override
  String get retry => 'Try again';
  @override
  String dbTooNew(int found, int supported) =>
      'The data was saved by a newer version of the app (database version $found, this version '
      'supports up to $supported). Please update the app.';

  // ---- Мова ----
  @override
  String get languageSection => 'Language';
  @override
  String get languageName => 'English';
  @override
  String get languageFlag => '🇬🇧';
  @override
  String get languageChange => 'Change language';
  @override
  String get textSizeLetter => 'A';

  // ---- Спільні діалоги й кнопки ----
  @override
  String get menu => 'Menu';
  @override
  String get requiredCharacteristic => 'Required characteristic';
  @override
  String get confirmTitle => 'Confirmation';
  @override
  String get delete => 'Delete';
  @override
  String get ok => 'OK';
  @override
  String get save => 'Save';
  @override
  String get iconHive => 'Hive icon';
  @override
  String get iconObstacle => 'Obstacle icon';
  @override
  String get iconChoose => 'Choose an icon';
  @override
  String get iconDefault => 'Default';
  @override
  String get hives => 'Hives';
  @override
  String get obstacles => 'Obstacles';
  @override
  String get colorChoose => 'Choose a color';
  @override
  String get colorDefault => 'Default';
  @override
  String get undoDelete => 'Undo';
  @override
  List<String> get objectColorNames =>
      const ['Honey orange', 'Amber yellow', 'Terracotta', 'Raspberry red', 'Pink', 'Purple', 'Mustard', 'Coral', 'Burgundy', 'Peach'];
  @override
  String get colorHiveDefault => 'Honey orange';
  @override
  String get colorObstacleDefault => 'Stone beige';
  @override
  String get colorOwn => 'Custom color';

  // ---- Вибір «синя / червона пігулка» ----
  @override
  String get pillBlueLabel => 'The blue pill';
  @override
  String get pillBlueText => ' - you are the master of your life (';
  @override
  String get pillRedLabel => 'the red one';
  @override
  String get pillRedText => ' - I will show you how deep the rabbit hole goes (';
  @override
  String get pillBlueDefault => 'finish the tutorial';
  @override
  String get pillRedDefault => 'continue';
  @override
  String get myApiaries => 'My apiaries';
  @override
  String get pillLead => 'Colleague, I offer you a choice. ';
  @override
  String get pillNoTutorial => 'no tutorial';
  @override
  String get pillTakeTutorial => 'take the tutorial';
  @override
  String get pillBlue => 'Blue';
  @override
  String get pillRed => 'Red';

  // ---- Панель характеристик ----
  @override
  String get hive => 'Hive';
  @override
  String get obstacle => 'Obstacle';
  @override
  String obstacleOf(String v) => 'Obstacle - $v';
  @override
  String get color => 'Color';
  @override
  String get values => 'Values';
  @override
  String get inspect => 'Inspect';
  @override
  String get noChanges => 'No changes';
  @override
  String get parameters => 'Parameters';
  @override
  String get characteristics => 'Characteristics';
  @override
  String get notes => 'Notes';
  @override
  String get qrCode => 'QR code';

  // ---- Голосовий ввід у полях ----
  @override
  String voiceModelOnce(int mb) =>
      'For voice input, download the model once (~$mb MB, preferably over Wi-Fi)';
  @override
  String get voicePreparing => 'Preparing recognition…';
  @override
  String get voiceNoMic => 'No microphone permission (Phone settings → Permissions)';
  @override
  String get voiceModelBroken => 'The voice model is damaged - download it again';
  @override
  String voiceUnavailable(String details) => 'Voice input unavailable: $details';
  @override
  String get voiceModelReady => 'The model is ready - tap the microphone and speak';
  @override
  String get voiceDownloadPaused => 'Download stopped - it will resume next time';
  @override
  String voiceDownloadFailed(String details) => 'Could not download the model: $details';
  @override
  String voiceRecognitionError(String details) => 'Recognition error: $details';
  @override
  String voiceNotNumber(String spoken) => 'Not a number: "$spoken"';
  @override
  String get voiceSpeak => 'Speak…';
  @override
  String get voiceUnpacking => 'Unpacking the model…';
  @override
  String voiceDownloading(int percent) => 'Downloading the voice model: $percent%';
  @override
  String get voiceSayNumber => 'Say a number';
  @override
  String get voiceInput => 'Voice input';
  @override
  String get download => 'Download';

  // ---- Меню навігації ----
  @override
  String get qrHiveNotFound => 'Hive not found';
  @override
  String get qrNotBound => 'This QR code is not linked to any hive yet.';
  @override
  String qrBindAsk(String why, String code) => '$why\n\nCode: $code\n\nLink it to a hive now?';
  @override
  String get qrBindToHive => 'Link to a hive';
  @override
  String get qrCreateApiaryFirst => 'First create an apiary and hives on the map.';
  @override
  String get stock => 'Stock';
  @override
  String get finances => 'Finances';
  @override
  String get history => 'History';
  @override
  String get tutorial => 'Tutorial';
  @override
  String get feedbackTitle => 'Feedback';
  @override
  String get tourApiaries => ' - all your apiaries in one place.';
  @override
  String get tourStock => ' - frames, feed, medicine: arrivals, write-offs and stocktaking.';
  @override
  String get tourFinances =>
      ' - apiary expenses and income: enter them by hand or photograph a receipt.';
  @override
  String get tourHistory =>
      ' - curious how the readings or the stock changed? This is the place.';
  @override
  String get tourQr =>
      ' - a round without records is time wasted. Scan the code on a hive, and link a new one to a hive.';
  @override
  String get tourTutorial => ' - something unclear? Take a dedicated lesson.';
  @override
  String get tourSettings => ' - language, text size, templates, account and backups.';
  @override
  String get tourFeedback => ' - want to share an idea or give feedback? This is the place.';
  @override
  String get gotIt => 'Got it';
  @override
  String get continueAction => 'Continue';
  @override
  String get navMenu => 'Navigation menu';
  @override
  String get scan => 'Scan';
  @override
  String get generate => 'Generate';
  @override
  String get qrBindRow => 'Link in a row';

  // ---- Головний екран ----
  @override
  String get signInFailed => 'Could not sign in. Check the internet and try again.';
  @override
  String get whatsNew => 'What\'s new';
  @override
  String get start => 'Start';
  @override
  String get feedbackShort => 'Feedback';
  @override
  String get dataOnlyHere => 'Data is only on this device';
  @override
  String get signInForSync => 'Sign in with Google to sync';
  @override
  String get scanQr => 'Scan QR code';
  @override
  String get greetNight => 'Good night, beekeeper!';
  @override
  String get greetMorning => 'Good morning, beekeeper!';
  @override
  String get greetDay => 'Good afternoon, beekeeper!';
  @override
  String get greetEvening => 'Good evening, beekeeper!';
  @override
  List<String> get homeTips =>
      const [
      'Hold a hive on the map - and drag it to a new place right away.',
      'Round: the red hives on the map are the ones due for inspection. Walk up to a hive and tap "Scan".',
      'In an inspection, "Save", "No changes" and "Skip" open the next hive right away.',
      'Picked a new parameter from the list and cannot find the "Save" button? That is because all changes are saved automatically.',
      'Hold "Finances" - and a new expense opens right away.',
      'Stick QR labels on - and a hive opens from the camera in a second.',
      'Set a minimum stock level - I will remind you when it is time to buy more.',
      'The apiary report in Excel is in the ☰ menu → "History".',
      'The round interval is set once for the whole apiary - tap the apiary name on the map.',
      'If a hive needs a different round interval, tap "Days until the round" on its panel.',
      ];
  @override
  String get dueToday => 'Inspect today';
  @override
  String get myApiary => 'My apiary';
  @override
  String get showOnMap => 'Show on the map';
  @override
  String get feedbackReplied => 'The developer replied to your feedback';
  @override
  String dueTodayCount(int n) => 'Inspect today: $n';
  @override
  String timeToBuy(String items) => 'Time to buy more: $items';
  @override
  String get tapToGo => 'Tap to go';
  @override
  String get tapNext => 'Tap for next';
  @override
  String get mail => 'Mail';

  // ---- Мої пасіки ----
  @override
  String get apiaryListHello =>
      'Well hello, newbie, sting me a bee! Where is your apiary? That will not do... Tap ';
  @override
  String get createMapQuoted => '"Create a map"';
  @override
  String get deleteApiaryTitle => 'Delete the apiary?';
  @override
  String deleteApiaryText(String name) =>
      'The apiary "$name" will be deleted together with all hives, obstacles and records. This cannot be undone.';
  @override
  String apiaryDeleted(String name) => 'Apiary "$name" deleted';
  @override
  String get noApiariesYet => 'No apiaries yet.\nCreate one with the button below.';
  @override
  String get createMapButton => '+  Create a map';
  @override
  String get open => 'Open';
  @override
  String get qrLabels => 'QR labels';

  // ---- Шаблони ----
  @override
  String get templateRename => 'Rename template';
  @override
  String templateDeleted(String name) => 'Template "$name" deleted';
  @override
  String get templates => 'Templates';
  @override
  String get noTemplatesYet => 'No templates yet';
  @override
  String get templateCreate => 'Create a template';
  @override
  String get rename => 'Rename';

  // ---- Перші підказки ----
  @override
  String get hintHomeA => 'Welcome to the apiary! ';
  @override
  String get hintHomeB =>
      ' opens the map of your apiary. When it is time for an inspection, this is where you will see ';
  @override
  String get hintHomeC => ' - one tap, and you are at the right hive.';
  @override
  String get hintMapA => 'This is the apiary map. Tap a hive - its values open on the right. ';
  @override
  String get editing => 'Editing';
  @override
  String get hintMapB =>
      ' (the switch at the bottom left) - to add hives, move them or change how they look. Holding a hive turns editing on right away.';
  @override
  String get hintPanelA =>
      'Here are the latest values of the hive. Tap a row to see its history. ';
  @override
  String get hintPanelB => ' - record an inspection; ';
  @override
  String get hintPanelC => ' - if nothing has changed.';
  @override
  String get hintFillA => 'Fill in only what has changed - the rest stays as it was. ';
  @override
  String get saveAndNext => 'Save and next';
  @override
  String get hintFillB => ' opens the next hive right away.';
  @override
  String get hintEditA =>
      'Editing mode: choose a template and tap a free cell. A hive can be dragged, or rotated with the button above it. Deleted by mistake? Tap ';
  @override
  String get hintEditB => ' at the bottom. Switch to ';
  @override
  String get workMode => 'Work mode';
  @override
  String get hintEditC => ' to save and exit.';
  @override
  String get hintStockA => 'Stock: ';
  @override
  String get stockIn => 'Arrival';
  @override
  String get hintStockB => ' - what you bought, ';
  @override
  String get stocktake => 'Stocktaking';
  @override
  String get hintStockC =>
      ' - check the balances. Set a minimum level, and the app will tell you when it is time to buy more.';
  @override
  String get skip => 'Skip';

  // ---- Нотатки вулика ----
  @override
  String get today => 'Today';
  @override
  String get yesterday => 'Yesterday';
  @override
  String get noteDeleted => 'Note deleted';
  @override
  String get noteAdd => '+ Note';
  @override
  String get all => 'All';
  @override
  String get notesNone => 'No notes yet.\nWrite down what you noticed at the hive.';
  @override
  String get notesNoneWithLabel => 'No notes with this label.';
  @override
  String get actions => 'Actions';
  @override
  String get edit => 'Edit';
  @override
  String get labelNew => 'New label';
  @override
  String get labelDelete => 'Delete label';
  @override
  String get label => 'Label';
  @override
  String labelExists(String name) => 'The label "$name" already exists.';
  @override
  String get labelDeleteTitle => 'Delete the label?';
  @override
  String get labelDeleteText => 'Notes with this label stay, but without the label.';
  @override
  String get noteEmpty => 'Write the note text.';
  @override
  String get noteNew => 'New note';
  @override
  String get note => 'Note';
  @override
  String get noteHint => 'What you noticed at the hive';
  @override
  String get date => 'Date';
  @override
  String get otherDate => 'Other date';
  @override
  String get noLabel => 'No label';
  @override
  String get labelAdd => '+ Label';
  @override
  String get labelHoldHint => 'Hold a label to rename or delete it.';

  // ---- Історія ----
  @override
  String get apiaryReportExcel => 'Apiary report (Excel)';
  @override
  String get noCharacteristicsYet => 'No characteristics yet.';
  @override
  String get noStockItemsYet => 'No stock items yet.\nAdd them in the menu → "Stock".';
  @override
  String get noArrivalYet => 'No arrivals yet';
  @override
  String balance(String amount) => 'Balance: $amount';
  @override
  String get recordCancelTitle => 'Cancel the record?';
  @override
  String recordCancelText(String title, String date) =>
      '"$title" from $date will be marked as cancelled, and the balance goes back. The record stays in the history.';
  @override
  String get recordCancel => 'Cancel record';
  @override
  String get currency => 'UAH';
  @override
  String get cancelledMark => 'cancelled';
  @override
  String becameAmount(String amount) => 'now: $amount';
  @override
  String historyOf(String name) => 'History: $name';
  @override
  String get stockHistoryEmpty =>
      'No records yet.\nRecords appear after an arrival, write-off or stocktaking.';
  @override
  String get filterObject => 'Filter: object';
  @override
  String get allObjects => 'All objects';
  @override
  String objectOf(String name) => 'Object: $name';
  @override
  String get clearFilter => 'Clear filter';
  @override
  String get nothingToExport => 'There are no records to export.';
  @override
  String paramHistoryEmpty(bool scoped) =>
      'No records for this parameter${scoped ? ' for this object' : ''} yet.\nRecords appear after the "Inspect" button on the map.';
  @override
  String get exportExcel => 'Export to Excel';

  // ---- QR-коди ----
  @override
  String get qrRegenTitle => 'Regenerate the codes?';
  @override
  String qrRegenText(int replacing, int selected) =>
      '$replacing of the $selected selected hives already have a code. They will get new codes, and the old labels will stop working.';
  @override
  String get qrRegen => 'Regenerate';
  @override
  String qrCodesOf(String name) => 'QR codes: $name';
  @override
  String get qrNoHives => 'There are no hives in this apiary yet';
  @override
  String qrLegend(int withCode, int hives) =>
      'Red ring - selected, no code · green - already has a code ($withCode of $hives)';
  @override
  String get qrAllWithoutCode => 'All without a code';
  @override
  String get qrCreating => 'Creating…';
  @override
  String qrGenerateN(int n) => 'Generate ($n)';
  @override
  String printFailed(String details) =>
      'Could not open printing: $details\n\nSave the PDF and print it.';
  @override
  String qrLabelsN(int n) => 'Labels ($n)';
  @override
  String get print => 'Print';
  @override
  String get pleaseWait => 'Please wait…';
  @override
  String get savePdf => 'Save PDF';
  @override
  String get qrManual => 'Enter the code (link) manually';
  @override
  String get qrTabHive => 'Hive code';
  @override
  String get qrTabReceipt => 'Receipt';
  @override
  String get qrFound => 'QR code found - hold the camera still';
  @override
  String get qrReceiptHint => 'Lay the receipt flat on a contrasting background and tap "Shoot"';
  @override
  String get qrHint => 'Point the camera at the hive QR code and hold it for a second or two';
  @override
  String get scanReceipt => 'Scan receipt';
  @override
  String get shoot => 'Shoot';
  @override
  String get phoneCamera => 'With the phone camera';
  @override
  String get fromGallery => 'From the gallery';
  @override
  String get qrEnterManually => 'Enter the code manually';

  // ---- Карта пасіки ----
  @override
  String get mapNoHivesA =>
      'Looks like you have no hives at all, friend. Add some by turning on ';
  @override
  String get editingQuoted => '"Editing"';
  @override
  String get mapNoHivesB => ' at the bottom left';
  @override
  String get mapTapAnywhere => 'Tap anywhere on the map';
  @override
  String get mapWrongPlace =>
      'You put it in quite the wrong place. Drag it to a neighbouring cell';
  @override
  String get mapConfirmA => 'Confirm your choice - switch to ';
  @override
  String get workModeQuoted => '"Work mode"';
  @override
  String get mapGoodStart => 'Here is to an easy start, friend!';
  @override
  String get mapNoRest => 'No time to rest, tap ';
  @override
  String quoted(String s) => '"$s"';
  @override
  String get mapTellShort => 'Let me briefly tell you what we have. ';
  @override
  String get mapOpenNavMenu => 'Open the navigation menu';
  @override
  String get mapTemplatesInA => 'Templates are in ';
  @override
  String get settingsQuoted => '"Settings"';
  @override
  String get mapTemplatesInB =>
      ' in the menu. And put together a hive\'s set of parameters in "Parameters" on its panel: arrange them into groups in the "Builder".';
  @override
  String get mapLessonDone => 'Hive added, round done. ';
  @override
  String get mapShortNotes => 'These are short notes about your hive.';
  @override
  String get mapScrollDown => 'Scroll down and ';
  @override
  String get mapDoInspect => 'inspect the hive';
  @override
  String get mapTapHiveToBind => 'Tap the hive to link the code to';
  @override
  String get mapCellHasOther => 'There is already another object here';
  @override
  String get mapTemplateEmpty => 'The template is empty';
  @override
  String get mapCellBusy => 'The cell is occupied';
  @override
  String mapDueHives(int n) => 'Inspect: ${_n(n, 'hive', 'hives')} (red)';
  @override
  String mapPlaceTemplate(String name) => 'Tap to place "$name", drag to move';
  @override
  String mapGroupN(int n) => 'Group ($n)';
  @override
  String get mapChooseHive => 'Choose a hive';
  @override
  String get mapTemplatesCreatedA => 'I took a little care of you. I created ';
  @override
  String get and => ' and ';
  @override
  String get mapTemplatesCreatedB => '. Choose ';
  @override
  String get mapChooseTemplate => 'Choose a template';
  @override
  String get mapNoTemplate => 'No templates yet.';
  @override
  String get mapNoRoomRotate => 'No room to rotate';
  @override
  String get mapGroupDeleted => 'Group of objects deleted';
  @override
  String get mapObjectDeleted => 'Object deleted';
  @override
  String get mapTemplateDeleted => 'Template deleted';
  @override
  String get mapRenameObject => 'Rename the object';
  @override
  String get mapLinkParamFirst => 'First link at least one parameter';
  @override
  String get notWrittenOff => 'Not written off';
  @override
  String get mapVisitMarked => 'Inspection marked: today';
  @override
  String get mapAllInspected => 'All hives are inspected for today';
  @override
  String get mapRoundDone => 'Round finished';
  @override
  String get mapNextHive => 'Next hive';
  @override
  String qrNotBoundCode(String why, String code) => '$why\n\nCode: $code';
  @override
  String get mapNoMoreOverdue => 'There are no more overdue inspections.';
  @override
  String get done => 'Done';
  @override
  String get daysToRound => 'Days until the round';
  @override
  String get mapAllHaveQr => 'All hives in this apiary already have QR codes.';
  @override
  String get qrCodes => 'QR codes';
  @override
  String get qrInUse => 'The code is already in use';
  @override
  String qrMoveTo(String other, String apiary, String name) =>
      'This QR code is linked to "$other" (apiary "$apiary"). Move it to "$name"?';
  @override
  String qrMoveHere(String other, String apiary) =>
      'This QR code is linked to "$other" (apiary "$apiary"). Move it to this hive?';
  @override
  String get move => 'Move';
  @override
  String qrNumber(String n) => 'QR code No. $n';
  @override
  String get qrOfHive => 'Hive QR code';
  @override
  String get qrOther => 'Another code';
  @override
  String get qrUnlink => 'Unlink';
  @override
  String get qrForHive => 'QR code for the hive';
  @override
  String get qrLinked => 'QR code linked';
  @override
  String get scanHive => 'Scan a hive';
  @override
  String qrNotBoundHowTo(String why, String code) =>
      '$why\n\nCode: $code\n\nTo link it: menu ☰ → "QR code".';
  @override
  String get qrHiveHasCode => 'The hive already has a code';
  @override
  String get qrReplaceAsk => 'Replace this hive\'s current QR code with the scanned one?';
  @override
  String get replace => 'Replace';
  @override
  String get mapMenuHintA =>
      'Here you can manage your apiary. To learn about all the features, ';
  @override
  String get mapTakeTutorial => 'take the tutorial';
  @override
  String get apiarySettings => 'Apiary settings';
  @override
  String get back => 'Back';
  @override
  String get mapFinishAdding => 'Finish adding';
  @override
  String get mapAddObject => 'Add an object';
  @override
  String get mapLastMenuA => 'Finally, let me show you the navigation menu. ';
  @override
  String get mapOpenIt => 'Open it';
  @override
  String get properties => 'Properties';
  @override
  String get rotate => 'Rotate';

  // ---- Склад ----
  @override
  String stockItemDeleted(String name) => 'Item "$name" deleted';
  @override
  String stockActualBad(String name) =>
      '"$name": the actual quantity must be a number, 0 or more';
  @override
  String get notSaved => 'Not saved';
  @override
  String stockWholeFor(String name, String unit) => '"$name": enter a whole number for "$unit"';
  @override
  String get stockNoDiffs => 'No differences - everything matches the records';
  @override
  String stockTakeSaved(int n) => 'Stocktaking saved: items changed - $n';
  @override
  String byRecords(String amount) => 'On record: $amount';
  @override
  String get actually => 'Actual';
  @override
  String get stockInOut => 'Arrivals and write-offs';
  @override
  String get oneByOne => 'One by one';
  @override
  String get asList => 'As a list';
  @override
  String get stockNoItems => 'No stock items yet';
  @override
  String get stockTakeSave => 'Save stocktaking';
  @override
  String get stockItemAdd => 'Add an item';
  @override
  String get writeOff => 'Write off';
  @override
  String get recount => 'Recount';
  @override
  String get timeToBuyShort => 'Time to buy';
  @override
  String get enterName => 'Enter a name';
  @override
  String get enterUnit => 'Enter a unit';
  @override
  String get stockMinBad => 'The minimum level must be a number, 0 or more';
  @override
  String get stockInQtyBad => 'Arrival: the quantity must be a number greater than 0';
  @override
  String get stockInCostBad => 'Arrival: enter the total cost';
  @override
  String get stockItem => 'Item';
  @override
  String get stockItemNew => 'New item';
  @override
  String get name => 'Name';
  @override
  String get unit => 'Unit';
  @override
  String get unitOther => 'other…';
  @override
  String get unitOwn => 'Custom unit';
  @override
  String get stockMin => 'Minimum level';
  @override
  String get stockMinHelper => 'When it gets there - "time to buy"';
  @override
  String get stockInNow => 'Arrival right away (optional)';
  @override
  String get quantity => 'Quantity';
  @override
  String get cost => 'Cost';
  @override
  String get takePhoto => 'Take a photo';
  @override
  String get choosePhoto => 'Choose a photo';
  @override
  String get removePhoto => 'Remove photo';
  @override
  String get stockEnterActual => 'Enter the actual quantity (0 or more)';
  @override
  String get stockEnterQty => 'Enter a quantity greater than 0';
  @override
  String wholeFor(String unit) => 'Enter a whole number for "$unit"';
  @override
  String stockMaxWriteOff(String amount) => 'You can write off at most $amount';
  @override
  String get writeOffNoun => 'Write-off';
  @override
  String get dateColon => 'Date: ';
  @override
  String get actualQuantity => 'Actual quantity';
  @override
  String get totalCostDefault0 => 'Total cost (default 0)';
  @override
  String unitPrice(String price) => 'Unit price: $price';
  @override
  String get commentOptional => 'Comment (optional)';

  // ---- Фінанси ----
  @override
  String get finFromStock => 'Entered in stock';
  @override
  List<String> get monthNames =>
      const ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  @override
  String get noCategory => 'No category';
  @override
  String finEntryText(String name, bool expense, String amount, String rest) =>
      '$name · ${expense ? 'expense' : 'income'} $amount\n$rest';
  @override
  String get finFromStockNote =>
      '\n\nThe arrival was entered in stock. Cancelling it here cancels it in stock too.';
  @override
  String get finLinesNote => '\n\nCancelling also cancels this operation\'s arrivals in stock.';
  @override
  String get finCancelledNote => '\n\nThis record is cancelled.';
  @override
  String get record => 'Record';
  @override
  String get notCancelled => 'Not cancelled';
  @override
  String get finSumBad => 'The amount must be a number, 0 or more';
  @override
  String get finEditRecord => 'Edit the record';
  @override
  String get finSumUah => 'Amount, ₴';
  @override
  String get finSumFromLines => 'The amount is made up of the table rows';
  @override
  String get category => 'Category';
  @override
  String get periodDay => 'Day';
  @override
  String get periodWeek => 'Week';
  @override
  String get periodMonth => 'Month';
  @override
  String get periodYear => 'Year';
  @override
  String get periodCustom => 'Period';
  @override
  String finOperationsOf(String title) => 'Operations · $title';
  @override
  String get finAllOperations => 'All operations';
  @override
  String get expenses => 'Expenses';
  @override
  String get income => 'Income';
  @override
  String get incomes => 'Income';
  @override
  String get earlier => 'Earlier';
  @override
  String get later => 'Later';
  @override
  String finBalance(String v) => 'balance $v';
  @override
  String get finNothingInPeriod => 'Nothing in this period';
  @override
  String get finNewOperation => 'New operation';
  @override
  String get finNoOperations => 'No operations';
  @override
  String get receiptOnPhoneOnly =>
      'Text recognition works on the phone. Fill in the table by hand here.';
  @override
  String get receiptNoRows =>
      'Could not recognize the items. Take a straighter photo in good light, or fill in the table by hand.';
  @override
  String receiptRows(int n) => _n(n, 'row', 'rows');
  @override
  String receiptOk(String rows) =>
      'Receipt recognized · $rows · the total matches the receipt ✓';
  @override
  String receiptMismatch(String rows, String declared, String table) =>
      'Receipt recognized · $rows. The receipt total is $declared, the table has $table - check the rows.';
  @override
  String receiptCheck(String rows) =>
      'Receipt recognized · $rows. Check the table: recognition can make mistakes.';
  @override
  String get receiptFailed => 'Could not recognize the receipt. Fill in the table by hand.';
  @override
  String get finChooseCategory =>
      'Choose a category from the list or create a new one ("+ New").';
  @override
  String finBadRows(int n) =>
      '${n == 1 ? 'One row is' : '$n rows are'} missing a name, a quantity (more than 0; whole for "pcs") or a price. Fix them or delete the row.';
  @override
  String get notRecorded => 'Not recorded';
  @override
  String get finNegative => 'The amount cannot be negative. Enter a positive number.';
  @override
  String get finEnterSum => 'Enter an amount or fill in the table.';
  @override
  String get finSumMismatch => 'The total does not match';
  @override
  String finSumMismatchText(String table, String receipt) =>
      'The table has $table, and the receipt $receipt. Most likely a row was recognized incorrectly. Record anyway?';
  @override
  String get recordAction => 'Record';
  @override
  String get check => 'Check';
  @override
  String recordedToStock(bool expense, int n) =>
      'Recorded · ${expense ? 'to stock' : 'from stock'}: $n';
  @override
  String get recorded => 'Recorded';
  @override
  String recordFailed(String details) => 'Could not record: $details';
  @override
  String finFixedByHand(String table) => 'corrected by hand · table $table';
  @override
  String finDiscount(String v) => ' · discount −$v';
  @override
  String get sum => 'Amount';
  @override
  String get fromTable => '↺ from the table';
  @override
  String get newCategoryShort => '+ New';
  @override
  String get receiptReading => 'Recognizing the receipt…';
  @override
  String get receiptPhotoHint =>
      'Photograph the receipt straight, in good light. All items will go into the table below.';
  @override
  String get receiptPhoto => 'Photograph a receipt';
  @override
  String get photoFromGallery => 'Choose a photo from the gallery';
  @override
  String get reshoot => 'Retake';
  @override
  String get toStock => 'To stock';
  @override
  String get fromStock => 'From stock';
  @override
  String get goods => 'Item';
  @override
  String get qtyShort => 'Qty';
  @override
  String get price => 'Price';
  @override
  String inStockAmount(String amount) => 'in stock · $amount';
  @override
  String willWriteOff(String amount) => 'will write off $amount';
  @override
  String moreThanStock(String amount) => 'more than in stock · adjustment +$amount';
  @override
  String get newGoods => 'new item';
  @override
  String get notInStock => 'not in stock';
  @override
  String checkPrice(String v) => 'check the price · usually $v ₴';
  @override
  String sumOf(String v) => 'total $v';
  @override
  String get putToStock => 'Put in stock';
  @override
  String get writeOffFromStock => 'Write off from stock';
  @override
  String get deleteRow => 'Delete row';
  @override
  String get byHand => 'By hand';
  @override
  String get fromReceipt => 'From a receipt';
  @override
  String get addRow => '+ row';
  @override
  String tableOf(String v) => 'table $v';
  @override
  String get leaveUnsavedTitle => 'Leave without saving?';
  @override
  String get leaveUnsavedText => 'The data you entered will not be recorded.';
  @override
  String get leave => 'Leave';
  @override
  String get stay => 'Stay';
  @override
  String get newExpense => 'New expense';
  @override
  String get newIncome => 'New income';
  @override
  String get add => 'Add';
  @override
  String get unitShort => 'Unit';
  @override
  String get enterCategoryName => 'Enter the category name.';
  @override
  String saveFailed(String details) => 'Could not save: $details';
  @override
  String get error => 'Error';
  @override
  String get categoryDeleteTitle => 'Delete the category?';
  @override
  String get categoryDeleteText =>
      'Old operations keep their category, but no new ones can be created in it.';
  @override
  String get categoryNew => 'New category';
  @override
  String get catGoesToStock => 'Items go to stock';
  @override
  String get catFromStock => 'Items are written off from stock';
  @override
  String get catGoesToStockHint => 'The expense table rows become an arrival';
  @override
  String get catFromStockHint => 'The income table rows write off the balance (a sale)';
  @override
  String get icon => 'Icon';
  @override
  String get categoryDelete => 'Delete category';
  @override
  String get create => 'Create';
  @override
  String finNotInStock(String name) =>
      '"$name" is not in stock - first add an arrival (for example, honey extracted) or untick "from stock".';
  @override
  String finUnitMismatch(String name, String stockUnit, String unit, String density) =>
      '"$name" is kept in stock in "$stockUnit", but sold in "$unit". You can only sell in the same units (kg and l are converted: 1 l = $density kg).';
  @override
  String get finRecordNotFound => 'Record not found';
  @override
  String get finCancelledNotEdited => 'A cancelled record cannot be edited';
  @override
  String get finSumLocked =>
      'The amount cannot be changed: it is made up of the table rows. Cancel the record and enter a new one.';
  @override
  String get finAlreadyCancelled => 'This record is already cancelled';

  // ---- Параметри ----
  @override
  String records(int n) => _n(n, 'record', 'records');
  @override
  String get paramEdit => 'Edit parameter';
  @override
  String get paramNew => 'New parameter';
  @override
  String get paramBaseNameLocked => 'The name of a Base characteristic cannot be changed';
  @override
  String get dataType => 'Data type';
  @override
  String get listOptions => 'List options';
  @override
  String get paramBaseTypeLocked => 'The data type of a Base characteristic cannot be changed';
  @override
  String get paramTypeLocked =>
      'There are records already, so the data type cannot be changed. To change the type, create a new parameter and move the history into it.';
  @override
  String get paramTypeFree => 'The data type can be changed while there are no records.';
  @override
  String get paramMoveHistoryDots => 'Move history…';
  @override
  String get paramDelete => 'Delete parameter';
  @override
  String get paramNeedName => 'That will not work - enter the parameter name';
  @override
  String get paramNeedTwoOptions => 'That will not work - add at least two options';
  @override
  String get paramMoveWhere => 'Where to move the history?';
  @override
  String paramFrom(String name, String type) => 'From "$name" ($type)';
  @override
  String get paramNewDots => '+ New parameter…';
  @override
  String paramMoveText(String from, String to, String type, String records) =>
      '$records of history will be moved from "$from" to "$to" ($type) with the same dates and objects.';
  @override
  String paramMoveSkipped(String records, String type, String from) =>
      '\n\n$records do not fit the type "$type" - they stay in "$from".';
  @override
  String paramMoveReplace(String from, String to) =>
      '\n\nWherever "$from" was, "$to" will appear.';
  @override
  String get paramMoveHistory => 'Move history';
  @override
  String paramMoveAndDelete(String name) => 'Move and delete "$name"';
  @override
  String paramMoved(int moved, int skipped) =>
      'Records moved: $moved.${skipped > 0 ? '\nDid not fit the type and stayed: $skipped.' : ''}';
  @override
  String paramBaseNoDelete(String name) =>
      '"$name" is a Base characteristic, required for the whole class of objects. It cannot be deleted.';
  @override
  String get cannotDelete => 'Cannot delete';
  @override
  String paramDeleted(String name) => 'Parameter "$name" deleted';
  @override
  String get paramTable => 'Parameter table';
  @override
  String get paramCreate => 'Create a parameter';
  @override
  List<String> get paramTabs => const ['List', 'Builder'];
  @override
  String get paramNoneYet => 'No parameters yet.\nCreate one with the "+" button at the top.';
  @override
  String get characteristicCreate => 'Create a characteristic';
  @override
  String get groupNew => 'New group';
  @override
  String groupNameIt(String name) => 'Name the group "$name"';
  @override
  String get groupName => 'Group name';
  @override
  String get groupDelete => 'Delete group';
  @override
  String get dropHere => 'Drop here';
  @override
  String get dragParamsHere => 'Drag parameters here';
  @override
  String get builderEmpty => 'The parameters you choose on the "List" tab will appear here.';
  @override
  String get builderHint => 'Hold a parameter and drag it into a group.';
  @override
  String get groupNewButton => '+ New group';
  @override
  String get chosenNoGroup => 'Chosen, but not in a group yet';
  @override
  String get allGrouped => 'All parameters are in groups.';
  @override
  String get dragToGroup => 'Hold and drag into a group.';
  @override
  String paramHasRecordsNoRename(String name) =>
      '"$name" already has records, so its name cannot be changed. You can create a new parameter and move the history into it.';
  @override
  String get cannotRename => 'Cannot rename';
  @override
  String get requiredSuffix => ' · required';
  @override
  String get editAction => 'Edit';
  @override
  String get scopeHive => 'This hive';
  @override
  String get scopeSame => 'The same ones';
  @override
  String scopeKind(String kind) => 'All "$kind"';
  @override
  String get scopeApiary => 'Whole apiary';
  @override
  String get applyTo => 'Apply to:';

  // ---- Огляд вулика ----
  @override
  String get fillParams => 'Fill in parameters';
  @override
  String get fillLesson0a =>
      'These are the hive parameters. Only the required ones are here now, but you can ';
  @override
  String get fillLesson0b => 'add new ones later';
  @override
  String get fillLesson1 =>
      'My helper checked the hive for you, so write the data into the cells.';
  @override
  String get fillLesson2a => 'Ahem... I will help with ';
  @override
  String get fillLesson2b => 'entering the information';
  @override
  String get fillLesson2c => ' for your hive.';
  @override
  String get fillLesson3a => 'Your queen is marked ';
  @override
  String lessonQueenColor(String v) =>
      const {'Білий': 'white', 'Жовтий': 'yellow', 'Червоний': 'red', 'Зелений': 'green', 'Синій': 'blue'}[v] ?? v.toLowerCase();
  @override
  String get fillLesson4a => 'Inspected today? Tap ';
  @override
  String get fillLesson4b => 'the inspection date';
  @override
  String get fillLesson4c => ' and choose "Today".';
  @override
  String get fillLesson5 => 'Save it, because I am not going back in there.';
  @override
  String get feedNeedQty => 'Feeding: enter the quantity';
  @override
  String feedOnlyInStock(String amount) => 'Feeding: only $amount in stock';
  @override
  String fillWholeFrom0(String name) => '"$name": enter a whole number from 0';
  @override
  String fillNumber(String name) => '"$name": enter a number';
  @override
  String get feedFromStock => 'Feeding from stock';
  @override
  String get dontWriteOff => 'Do not write off';
  @override
  String stockItemHas(String name, String amount) => '$name (have $amount)';
  @override
  String howMuch(String unit) => 'How much, $unit';
  @override
  String get chooseDate => 'Choose a date';
  @override
  String get choose => 'Choose';
  @override
  String get noteOptional => 'Optional: what you noticed';

  // ---- Конструктор шаблону ----
  @override
  String get templateNew => 'New template';
  @override
  String get drawType => 'Type to draw';
  @override
  String get templateAddCell => 'Add at least one cell';
  @override
  String get templateName => 'Template name';
  @override
  String get templateApplyTitle => 'Apply to the hives?';
  @override
  String templateApplyText(String name, int n) =>
      'Hives already placed from the template "$name": $n. Apply the new set of characteristics to them? The value history is kept.';
  @override
  String get apply => 'Apply';
  @override
  String get dontChange => 'Do not change';
  @override
  String get templateLeaveText => 'Changes to the template will be lost.';
  @override
  String templateAdding(String what) => 'Adding: $what   ·   tap a cell to remove it';
  @override
  String get templateDragHint => 'Drag to move · above it - rotate and delete';
  @override
  String get templateMoveHint =>
      'Moving: take an item with your finger and drag (the arrows are only a hint)';
  @override
  String get templateInfoRight => 'Item information is on the right';
  @override
  String get templateTapItem => 'Tap an item to see its information';
  @override
  String get finishMoving => 'Finish moving';
  @override
  String get moving => 'Moving';

  // ---- Чек на склад ----
  @override
  String get receiptNoRowsAdd =>
      'Could not recognize the items. Try a straighter photo in good light, or add rows by hand.';
  @override
  String get receiptCheckTable => 'Check the table: recognition can make mistakes.';
  @override
  String get receiptFailedAdd => 'Could not recognize the receipt. Add rows by hand.';
  @override
  String get listCopied => 'List copied';
  @override
  String get receiptNothingChecked => 'Nothing to record: tick at least one item.';
  @override
  String receiptBadRows(int n) =>
      '${n == 1 ? 'One row is' : '$n rows are'} missing a name, a quantity (more than 0) or a price. Fix them or untick them.';
  @override
  String receiptAdded(int n, int created, int topped) =>
      'Added to stock: $n (new - $created, topped up - $topped)';
  @override
  String get receiptTitle => 'Receipt';
  @override
  String get addRowButton => '+ Add a row';
  @override
  String get totalColon => 'Total: ';
  @override
  String get copyList => 'Copy list';
  @override
  String get addToStock => 'Add to stock';

  // ---- Відгук ----
  @override
  String get feedbackIntro =>
      'Want to share something valuable, suggest an idea or report a problem with the app? Write to us, it means a lot.';
  @override
  String get feedbackTooShort => 'Write at least a few words';
  @override
  String get feedbackThanks => 'Thank you! Your message has been sent.';
  @override
  String get feedbackNotConfigured =>
      'Sending feedback is not set up in this version of the app yet.';
  @override
  String get feedbackSendFailed => 'Could not send. Check the internet and try again.';
  @override
  String get notSent => 'Not sent';
  @override
  String feedbackCopyHint(String reason, bool notConfigured, String email) =>
      '$reason\n\n${notConfigured ? 'Copy' : 'Or copy'} the text and send it to $email';
  @override
  String get copyAction => 'Copy';
  @override
  String feedbackTo(String email, String text) => 'To: $email\n\n$text';
  @override
  String get feedbackCopied => 'Text and address copied';
  @override
  String get yourMessage => 'Your message…';
  @override
  String get sending => 'Sending…';
  @override
  String get send => 'Send';
  @override
  String get feedbackChatHint =>
      'The developer will reply here - you will see a badge on the mailbox hive and get a notification.';
  @override
  String get developer => 'Developer';
  @override
  String get waitingInternet => 'waiting for internet';

  // ---- Навчання (екран) ----
  @override
  String get lessonResumeAsk =>
      'You have already started this lesson. Continue where you stopped, or start over?';
  @override
  String get fromStart => 'Start over';
  @override
  String get lessonSoon => 'This lesson is still being prepared - it will appear soon.';
  @override
  String get lessonBasics => 'The basics';
  @override
  String get soon => 'soon';

  // ---- Вхід ----
  @override
  String get signingIn => 'Signing in…';
  @override
  String get signInGoogle => 'Sign in with Google';
  @override
  String get continueNoSignIn => 'Continue without signing in';
  @override
  String get noSignInHint =>
      'Without signing in, data is stored only on this device. You can sign in and sync it later on the home screen - nothing will be lost.';

  // ---- Що нового ----
  @override
  String whatsNewVersion(String v) => 'What\'s new · $v';
  @override
  String whatsNewMore(int n) => 'Also: $n changes and bug fixes';
  @override
  String get fixed => 'Fixed';
  @override
  String get toWork => 'Get to work';

  // ---- Нова пасіка ----
  @override
  String get enterApiaryName => 'Enter the apiary name';
  @override
  String get newApiary => 'New apiary';
  @override
  String get apiaryName => 'Apiary name';

  // ---- Уроки ----
  @override
  String get lessonParamFallback => 'parameter';
  @override
  String get lp1a =>
      'Hello, friend. Want to learn more about hive rounds? You are just in time, ';
  @override
  String get lp1b => 'tap a hive';
  @override
  String get lp2a => 'As you can see, it is pretty sparse. Let us add new ';
  @override
  String get lp2b => 'parameters';
  @override
  String get lp3a => 'In this menu you can create parameters and add them to the table. Tap ';
  @override
  String get lp3b => '"Create a parameter"';
  @override
  String get lp4 =>
      'Here you can name your parameter, set its data type and, if needed, its unit';
  @override
  String get lp5a => 'Create your parameter. Keep in mind, ';
  @override
  String get lp5b => 'the name and data type';
  @override
  String get lp5c => ' are required.';
  @override
  String get lp6a => 'Do not forget to ';
  @override
  String get lp6b => 'save';
  @override
  String get lp7a => 'Well done. ';
  @override
  String get lp7b => ' has already been added to the table builder. Open it';
  @override
  String get lp8a => 'Goodness, what a mess! Quickly create ';
  @override
  String get lp8b => 'a new group';
  @override
  String get lp9a => 'Name it ';
  @override
  String get lp9b => ' and save your progress!';
  @override
  String get lp10a => 'Drag ';
  @override
  String get lp10b => ' and ';
  @override
  String get lp10c => ' into the new group';
  @override
  String get lp11 => 'If needed, you can apply the changes to just 1 hive or to all of them';
  @override
  String get lp12a => 'See, we did not use everything? ';
  @override
  String get lp12b => 'Turn off everything extra';
  @override
  String get lp13a => 'Let us go back to ';
  @override
  String get lp13b => 'the hive';
  @override
  String get lp14 => 'Wow! Look at the table - it is perfect!';
  @override
  String get lessonTemplateFallback => 'template';
  @override
  String get lt1 =>
      'Friend, it is you again! I like your thirst for knowledge. Today we will learn to create templates - ready-made hives and obstacles that you then place on the map.';
  @override
  String get lt2a => 'Templates live in ';
  @override
  String get lt2b => ' - in the ☰ menu (three lines). I will open them for you now.';
  @override
  String get lt3a => 'This is the ';
  @override
  String get lt3b => ' tab - the general app settings are here.';
  @override
  String get lt4a => 'Just what we need! Tap ';
  @override
  String get templateCreateQuoted => '"Create a template"';
  @override
  String get lt5 => 'Time to draw! Tap ';
  @override
  String get lt6a => 'Here you choose what to draw. Hives are right here, and for obstacles ';
  @override
  String get lt6b => 'swipe the card left';
  @override
  String get lt7a => 'Choose any ';
  @override
  String get lt7b => 'obstacle';
  @override
  String get lt8a => 'Now ';
  @override
  String get lt8b => 'tap the grid';
  @override
  String get lt8c => ' - place one obstacle tile';
  @override
  String get lt9a => 'Place ';
  @override
  String get lt9b => '3 more tiles';
  @override
  String get lt9c => ' next to it - fill a square';
  @override
  String get lt10a => 'Great! To finish drawing, tap ';
  @override
  String get lt10b => 'the red cross';
  @override
  String get lt11a => 'The obstacle can be moved. Turn on ';
  @override
  String get lt11b => 'moving';
  @override
  String get lt12a => 'The arrows around are only a hint, you do not need to tap them. ';
  @override
  String get lt12b => 'Take the obstacle with your finger and drag it';
  @override
  String get lt13a => 'Done! Now ';
  @override
  String get lt13b => 'save';
  @override
  String get lt13c => ' the template';
  @override
  String get lt14a => 'Give the template a name and ';
  @override
  String get lt14b => ' it';
  @override
  String get lt15a => 'Wow, you learn fast! The template ';
  @override
  String get lt15b => ' is already in your templates - place it on the map yourself.';
  @override
  String get lessonParamsTitle => 'Groups and round parameters';

  // ---- Типи даних і дані ----
  @override
  List<String> get dataTypeLabels =>
      const ['Text', 'Whole number', 'Decimal number', 'Date', 'Yes / No', 'List', 'Color'];
  @override
  String get qrThisCode => 'this code';
  @override
  String qrNumberShort(String n) => 'No. $n';
  @override
  String qrWasUnlinked(String label) =>
      '$label was linked before, but has been removed (the label was reissued or the link cancelled).';
  @override
  String qrHiveDeleted(String label) => '$label is linked to a hive that has been deleted.';
  @override
  String qrHiveArchived(String label) => '$label is linked to an archived hive.';
  @override
  String qrNoApiary(String label) => '$label is linked to an object without an apiary.';
  @override
  String qrApiaryDeleted(String label) => '$label is linked to a hive of a deleted apiary.';
  @override
  String qrCannotOpen(String label) => '$label is linked, but the hive could not be opened.';
  @override
  String get deletedGroup => 'Deleted group';
  @override
  String get deletedObject => 'Deleted object';
  @override
  String hiveN(int n) => 'Hive $n';
  @override
  String get stockItemNotFound => 'Item not found';
  @override
  String get cancelCannotBeCancelled => 'A cancellation cannot be cancelled';
  @override
  String get overwrittenCannotBeCancelled => 'An old "overwritten" record cannot be cancelled';
  @override
  String cannotCancelPartlyWrittenOff(String left) =>
      'Cannot cancel: part has already been written off (balance: $left)';
  @override
  String cannotWriteOffMore(String left) =>
      'You cannot write off more than there is in stock (balance: $left)';

  // ---- Звіт, налаштування пасіки, календар, уроки ----
  @override
  String apiaryReportOf(String name) => 'Apiary report "$name"';
  @override
  String get apiaryReportHint =>
      'Excel: the latest values of all hives and the whole record history';
  @override
  String get apiaryReportEmpty => 'There are no hives in this apiary yet - the report is empty.';
  @override
  String get roundEvery => 'Do a round every … days';
  @override
  String get roundEveryHint => 'empty - no reminders';
  @override
  String get roundEveryNote =>
      'Applies to all hives in the apiary. A hive can have its own in the "Inspect" form.';
  @override
  List<String> get weekdaysShort => const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  @override
  String get chooseDateTitle => 'Choose a date';
  @override
  String get finishTutorialLower => 'finish the tutorial';
  @override
  String get finish => 'Finish';
  @override
  String get postbox => 'Mailbox hive';
  @override
  String postboxN(int n) => 'Mailbox hive: $n messages';
  @override
  String get textTypeIcon => 'Aa';
  @override
  String get optionAddHint => 'Add an option (for example, "Strong")';
  @override
  String get optionAdd => 'Add option';

  // ---- Сповіщення ----
  @override
  String get remindersChannel => 'Round reminders';
  @override
  String get remindersChannelText =>
      'Reminds you to inspect hives at the set interval: in the morning and, if the round is not done, at 14:00';
  @override
  String get feedbackChannel => 'Developer replies';
  @override
  String get feedbackChannelText => 'A reply to your feedback in the app';
  @override
  String get reminder => 'Reminder';
  @override
  String hiveListMore(String names, int n) => '$names and $n more';
  @override
  String roundInspect(int n, String list) => 'Inspect ${_n(n, 'hive', 'hives')}: $list';
  @override
  String roundLeft(int n, String list) => '${_n(n, 'hive', 'hives')} left to inspect: $list';

  // ---- Склад: назви операцій ----
  @override
  String get moveOut => 'Written off';
  @override
  String moveOutReason(String reason) => 'Written off: $reason';
  @override
  String get moveInvShort => 'Stocktaking: shortage';
  @override
  String get moveInvOver => 'Stocktaking: surplus';
  @override
  String get moveInvSame => 'Stocktaking: no differences';
  @override
  String get moveCancel => 'Record cancellation';
  @override
  String get moveSet => 'Overwritten (old record)';

  // ---- Файли й Excel ----
  @override
  String fileBuildFailed(String details) => 'Could not build the file:\n$details';
  @override
  String get saveHistory => 'Save history';
  @override
  String get saveCancelled => 'Saving cancelled.';
  @override
  String savedAt(String path) => 'Saved:\n$path';
  @override
  String get saved => 'Saved.';
  @override
  String savedFallback(String path) =>
      'Could not open the save dialog - the file was saved here:\n$path';
  @override
  String fileSaveFailed(String details) => 'Could not save the file:\n$details';
  @override
  String get saveReport => 'Save report';
  @override
  String shareFailed(String details) => 'Could not share the file:\n$details';
  @override
  String get sheetLatest => 'Latest values';
  @override
  String get dateTime => 'Date and time';
  @override
  String get parameter => 'Parameter';
  @override
  String get value => 'Value';
  @override
  String get objectOrGroup => 'Object / group';
  @override
  String get saveLabels => 'Save labels';
  @override
  String get hiveQrCodes => 'Hive QR codes';

  // ---- Помилки зв'язку й копій ----
  @override
  String get errNoServer => 'no connection to the server';
  @override
  String errNoServerDetails(String d) => 'no connection to the server ($d)';
  @override
  String get errServerNoAnswer => 'the server is not responding';
  @override
  String get errTls => 'could not establish a secure connection';
  @override
  String errServerBusy(int s) => 'the server is temporarily unavailable ($s)';
  @override
  String errServerRejected(int s, String m) => 'the server rejected it ($s): $m';
  @override
  String get errSignInAgain => 'you need to sign in again';
  @override
  String get errOtherAccount => 'the phone has data from another Google account';
  @override
  String get errNeedsChoice =>
      'waiting for your choice: what to do with the phone and server data';
  @override
  String get errNoServerLater => 'no connection to the server - try later';
  @override
  String get errSyncRunning => 'sync is in progress - try again in a minute';
  @override
  String errBackupTooBig(int mb) => 'the copy is too big for the server ($mb MB)';
  @override
  String get errBackupArrivedBroken => 'the copy arrived damaged - try again';
  @override
  String get errBackupBrokenNotSaved => 'the copy is damaged - not saved';
  @override
  String get errSnapshotBroken => 'the database snapshot is damaged';
  @override
  String get errInMemory => 'the database is in memory - nothing to copy';
  @override
  String get errBackupBroken => 'the copy is damaged';
  @override
  String get errBackupGone => 'the copy no longer exists';
  @override
  String get errLoginServerOdd => 'the sign-in server returned an unexpected response';
  @override
  String get errGoogleNotConfigured => 'Google sign-in is not set up in this build';
  @override
  String get errServerNotConfigured => 'The server is not set up in this build';

  // ---- Помічник: підказки, картки ----
  @override
  String get assistantReplyLanguageHint => '\n[Interface language: English - reply in English]';
  @override
  String get assistantWhatCanYouDo => 'What can you do?';
  @override
  String get sugSpentMonth => 'How much did I spend this month?';
  @override
  String get sugAddExpense => 'Add an expense';
  @override
  String get sugLowStock => 'What is running low in stock?';
  @override
  String get sugAddSugar => 'Add a sugar arrival';
  @override
  String get sugDueHives => 'Which hives need inspecting?';
  @override
  String get sugHowManyHives => 'How many hives do I have?';
  @override
  String get sugLastRecord => 'What did I record last?';
  @override
  String get sugOpenStock => 'Open stock';
  @override
  String get assistantDemoReply => 'Demo mode for now: the assistant server is not connected.';
  @override
  String get assistantLimitText =>
      'Could not answer in a few steps. Please ask in a simpler way.';
  @override
  Map<String, String> get screenLabels =>
      const {'finance': 'Finances', 'finance_add': 'New record', 'stock': 'Stock', 'apiaries': 'My apiaries', 'history': 'History', 'parameters': 'Parameters', 'templates': 'Templates', 'settings': 'Settings', 'helpers': 'Helpers', 'backups': 'Backups', 'receipt': 'Receipt', 'lessons': 'Tutorial', 'lesson': 'Tutorial', 'feedback': 'Feedback'};
  @override
  String mapOf(String name) => 'Map: $name';
  @override
  String cardInspection(String hive, String apiary) => 'Inspection: $hive ($apiary)';
  @override
  String cardInspectionUndo(String hive) => 'Inspection: $hive';
  @override
  String get visitDate => 'Round date';
  @override
  String cardStockMove(bool receive, String name) =>
      '${receive ? 'Arrival' : 'Write-off'}: $name';
  @override
  String quantityIn(String unit) => 'Quantity ($unit)';
  @override
  String get sumUah => 'Amount, UAH';
  @override
  String get comment => 'Comment';
  @override
  String cardNewStockItem(String name) => 'Arrival: $name (new stock item)';
  @override
  String cardStockIn(String name) => 'Arrival: $name';
  @override
  String get expense => 'Expense';
  @override
  String finUndo(bool income, String amount) => '${income ? 'Income' : 'Expense'} $amount UAH';
  @override
  String get text => 'Text';
  @override
  String get when => 'When';

  // Merged from main: linking labels in a row, rounds, finances
  @override
  String finCancelText(String name, String amount, String date) =>
      '"$name" $amount from $date will be marked as cancelled '
      'and won\'t count in the totals. The record stays in the history.';
  @override
  String get bindPickHint =>
      'Tap a hive to select or deselect it';
  @override
  String roundSkipped(String name) =>
      '"$name" skipped';
  @override
  String roundNoChange(String name, int done) =>
      '"$name": no changes · inspected $done';
  @override
  String roundSaved(String name, int done) =>
      '"$name" saved · inspected $done';
  @override
  String inspectionSaved(String name) =>
      'Inspection of "$name" saved';
  @override
  String inspectionSavedCount(String name, int done) =>
      'Inspection of "$name" saved. Inspected: $done';
  @override
  String get feedNotReturned =>
      'Feed not returned';
  @override
  String get inspectionUndone =>
      'Inspection undone';
  @override
  String get hiveHasQr =>
      'This hive already has a QR code';
  @override
  String get bindLabels =>
      'Link labels';
  @override
  String get bindAllLinked =>
      'All linked';
  @override
  String bindLinkedCount(int n) =>
      'Labels linked: $n';
  @override
  String bindAllDone(int n) =>
      'Labels linked: $n. All selected hives have QR codes.';
  @override
  String bindPartly(int linked, int skipped, int left) =>
      'Linked: $linked\nSkipped: $skipped\nLeft: $left\n\n'
      'Everything is saved. You can continue now or later: "Link in a row" '
      'will show only hives without a code.';
  @override
  String bindBarCount(int noCode, int chosen) =>
      'Without a code: $noCode · selected: $chosen';
  @override
  String get bindDeselect =>
      'Deselect';
  @override
  String get bindSelectAll =>
      'Select all without a code';
  @override
  String scanCount(int n) =>
      'Scan ($n)';
  @override
  String bindLinked(String name) =>
      'Linked: $name';
  @override
  String bindWithoutLabel(int n) =>
      'Without a label: $n';
  @override
  String get bindSearch =>
      'Search by name or number';
  @override
  String get bindNow =>
      'now';
  @override
  String get bindSkippedMark =>
      'skipped';
  @override
  String bindProgress(int done, int n, int linked, int skipped) =>
      '$done of $n · linked $linked · skipped $skipped';
  @override
  String bindLabelFor(String name) =>
      'Label for: $name';
  @override
  String get bindPrevHive =>
      'Previous hive';
  @override
  String get bindNextHive =>
      'Next hive';
  @override
  String get bindAimHint =>
      'Point the camera at this hive\'s label';
  @override
  String get bindList =>
      '☰ List';
}
