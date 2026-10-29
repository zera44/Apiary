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
}
