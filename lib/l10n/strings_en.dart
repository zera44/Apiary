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
  String get qrHint => 'Point the camera at the hive QR code and hold it for a few seconds';
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
  String mapLeftWithoutCode(int n) => 'Left without a code (skipped): $n.';
  @override
  String mapLinkedLabels(int linked, int skipped) =>
      'Labels linked: $linked.${skipped == 0 ? ' Now all hives have QR codes.' : ' Skipped: $skipped.'}';
  @override
  String get qrCodes => 'QR codes';
  @override
  String get hiveLower => 'hive';
  @override
  String mapLabelFor(String name) => 'Label for: $name';
  @override
  String get mapSkipThisHive => 'Skip this hive';
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
  String mapLinkedName(String name) => 'Linked: $name';
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
}
