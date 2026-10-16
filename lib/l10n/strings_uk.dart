import 'strings.dart';

/// Українська (типова мова застосунку).
class AppStringsUk extends AppStrings {
  const AppStringsUk();

  @override
  String get languageCode => 'uk';

  @override
  String plural(int n, {required String one, required String few, required String many}) =>
      pluralUk(n, one: one, few: few, many: many);

  // ---- Налаштування ----
  @override
  String get settingsTitle => 'Налаштування';
  @override
  String get settingsTabMain => 'Головне';
  @override
  String get settingsTabAccount => 'Акаунт';
  @override
  String get settingsTabTemplates => 'Шаблони';

  // ---- Синхронізація ----
  @override
  String get syncSection => 'Синхронізація';
  @override
  String get syncDisabled => 'Синхронізацію ще не налаштовано - дані лише на цьому пристрої';
  @override
  String get syncOffline => 'Немає зв\'язку із сервером - зміни збережено на пристрої';
  @override
  String syncPending(int n) =>
      'Очікує відправки: $n ${plural(n, one: 'зміна', few: 'зміни', many: 'змін')}';
  @override
  String syncLastOk(String when) => 'Остання синхронізація: $when';
  @override
  String syncError(String details) => 'Помилка синхронізації: $details';
  @override
  String get syncRunning => 'Синхронізація…';
  @override
  String get syncWaitingWifi => 'Чекає Wi-Fi: синхронізацію через мобільний інтернет вимкнено';
  @override
  String syncRejected(int n) =>
      'Сервер не прийняв $n ${plural(n, one: 'зміну', few: 'зміни', many: 'змін')} (немає доступу)';
  @override
  String get syncNeedsSignIn => 'Увійдіть через Google, щоб синхронізувати дані між телефонами';
  @override
  String get syncNow => 'Синхронізувати зараз';
  @override
  String get syncSignInAgain => 'Увійти знову';
  @override
  String get syncSignInAgainHint =>
      'Вхід на сервер закінчився (зокрема, якщо акаунт видалили з іншого телефона). '
      'Щоб синхронізувати далі, увійдіть знову.';
  @override
  String get syncDone => 'Синхронізовано';
  @override
  String get syncMobile => 'Синхронізувати через мобільний інтернет';
  @override
  String get syncMobileWarnTitle => 'Мобільний інтернет';
  @override
  String get syncMobileWarnText =>
      'Зазвичай синхронізація - це кілька кілобайт на годину. Уночі застосунок '
      'відправляє на сервер повну копію бази (стиснену) і нові фото складу - це '
      'може бути кілька мегабайт. Якщо трафік обмежений, вимкніть: тоді '
      'синхронізація - лише через Wi-Fi.';
  @override
  String get serverRestore => 'Завантажити з сервера';
  @override
  String get serverRestoreChoose => 'Яку копію завантажити?';
  @override
  String get serverBackupsNone => 'На сервері ще немає копій - вони з\'являються щоночі';
  @override
  String serverBackupItem(String when, String size) => '$when · $size';
  @override
  String get serverRestoreTitle => 'Завантажити дані з сервера?';
  @override
  String serverRestoreText(String when) =>
      'Дані на цьому телефоні буде замінено копією з сервера від $when. Перед цим '
      'застосунок збереже копію поточних даних тут, на телефоні (її видно в '
      '«Резервних копіях» - звідти можна повернути).';
  @override
  String get serverRestoring => 'Завантаження копії з сервера…';
  @override
  String get serverRestored => 'Дані завантажено з сервера';
  @override
  String serverRestoreFailed(String details) => 'Не вдалося завантажити: $details';
  @override
  String get firstLoginTitle => 'Дані є і на телефоні, і на сервері';
  @override
  String get firstLoginText =>
      'На цьому телефоні вже є пасіки, а у вашому акаунті на сервері - теж. Що з ними зробити?';
  @override
  String get firstLoginKeepPhone => 'Залишити дані телефона';
  @override
  String get firstLoginKeepPhoneHint => 'Дані з сервера, яких тут немає, буде видалено';
  @override
  String get firstLoginKeepServer => 'Залишити дані сервера';
  @override
  String get firstLoginKeepServerHint =>
      'Дані телефона замінить сервер (перед тим - копія тут, у «Резервних копіях»)';
  @override
  String get firstLoginMerge => 'Злити все разом';
  @override
  String get firstLoginMergeHint => 'Лишиться все з обох боків';
  @override
  String get firstLoginKeepPhoneConfirm =>
      'Дані на сервері, яких немає на цьому телефоні, буде видалено - зокрема на інших '
      'ваших телефонах після синхронізації. Продовжити?';
  @override
  String get firstLoginKeepServerConfirm =>
      'Дані на цьому телефоні замінять дані з сервера. Поточні дані телефона збережуться '
      'в «Резервних копіях» - звідти їх можна повернути. Продовжити?';
  @override
  String get otherAccountTitle => 'На телефоні - дані іншого акаунта';
  @override
  String get otherAccountText =>
      'Дані на цьому телефоні синхронізувались з іншим акаунтом Google. Змішувати їх з '
      'цим акаунтом не можна.';
  @override
  String get otherAccountReplace => 'Завантажити дані цього акаунта';
  @override
  String get otherAccountSignOut => 'Вийти';
  @override
  String get firstLoginDone => 'Готово - дані синхронізуються';
  @override
  String firstLoginFailed(String details) => 'Не вдалося: $details';
  @override
  String get textSizeSection => 'Розмір шрифту';
  @override
  String get textSizeHint => 'Для зручного читання - в усьому застосунку.';
  @override
  List<String> get textSizeLevels => const ['Звичайний', 'Більший', 'Великий', 'Дуже великий'];
  @override
  String get textSizePreview => 'Вулик 12 - сьогодні оглянути';
  @override
  String get inviteLinkButton => 'Створити посилання-запрошення';
  @override
  String get inviteLinkHint =>
      'Посилання одноразове й діє 7 днів. Надішліть його в месенджері - людина відкриє його на телефоні й одразу стане вашим помічником.';
  @override
  String inviteLinkShare(String url) => 'Приєднуйтесь до моєї пасіки у Vulyk (потрібен Google-акаунт):\n$url';
  @override
  String get inviteLinkCopied => 'Посилання скопійовано - надішліть його помічнику';
  @override
  String get inviteLinkTooMany => 'Забагато діючих посилань - зачекайте, поки ними скористаються чи вони застаріють.';
  @override
  String inviteLinkFailed(String details) => 'Не вдалося створити посилання: $details';
  @override
  String get joinConfirmTitle => 'Запрошення до пасіки';
  @override
  String get joinConfirmText => 'Вас запросили допомагати з пасікою у Vulyk. Приєднатися?';
  @override
  String get joinConfirm => 'Приєднатися';
  @override
  String joinDone(String owner, List<String> apiaries) => apiaries.isEmpty
      ? 'Готово: ви помічник${owner.isEmpty ? '' : ' ($owner)'}. Пасіки з\'являться за хвилину.'
      : 'Готово: ви помічник у ${apiaries.join(', ')}${owner.isEmpty ? '' : ' ($owner)'}. Пасіки з\'являться за хвилину.';
  @override
  String get joinInvalid => 'Це посилання вже не діє. Попросіть власника створити нове.';
  @override
  String get joinOwn => 'Це ваше власне посилання - надішліть його помічнику.';
  @override
  String get joinUnavailable =>
      'Не вдалося приєднатися: немає зв\'язку із сервером. Відкрийте посилання ще раз.';
  @override
  String get accountSection => 'Акаунт';
  @override
  String accountSignedInAs(String email) => 'Ви увійшли як $email';
  @override
  String get accountSignedInVia => 'Вхід через Google';
  @override
  String accountSignedInMail(String email) => 'Вхід виконано: $email. Дані синхронізуються.';
  @override
  String get accountSignOut => 'Вийти';
  @override
  String get accountSignOutTitle => 'Вийти?';
  @override
  String get accountSignOutText =>
      'Дані пасік лишаються на цьому пристрої. Далі - знову увійти або продовжити без входу.';
  @override
  String get accountGuest => 'Ви не увійшли - дані лише на цьому пристрої.';
  @override
  String get accountDelete => 'Видалити акаунт і всі дані';
  @override
  String get accountDeleteTitle => 'Видалити акаунт?';
  @override
  String get accountDeleteText =>
      'Буде видалено назавжди: ваш акаунт, усі пасіки, вулики, огляди, нотатки, склад, '
      'фінанси, фото складу й нічні копії - на сервері й на цьому телефоні, а також '
      'резервні копії на телефоні. Ваші помічники втратять доступ. Записи, які ви '
      'робили як помічник у чужих пасіках, лишаються в їхніх власників.';
  @override
  String get accountDeleteContinue => 'Далі';
  @override
  String get accountDeleteFinalTitle => 'Точно видалити?';
  @override
  String get accountDeleteFinalText =>
      'Повернути буде неможливо. Щоб підтвердити, напишіть слово ВИДАЛИТИ.';
  @override
  String get accountDeleteWord => 'ВИДАЛИТИ';
  @override
  String get accountDeleting => 'Видалення…';
  @override
  String get accountDeleted => 'Акаунт і всі дані видалено';
  @override
  String accountDeleteFailed(String details) => 'Не вдалося видалити: $details';
  @override
  String get privacyPolicy => 'Політика конфіденційності';
  @override
  String get privacySection => 'Конфіденційність';
  @override
  String get privacySoon => 'Текст політики конфіденційності скоро з\'явиться тут.';

  // ---- Загальне ----
  @override
  String get close => 'Закрити';

  // ---- Фото складу ----
  @override
  String get photoOpen => 'Відкрити фото';
  @override
  String photoFailed(String details) => 'Не вдалося отримати фото: $details';

  // ---- Резервні копії ----
  @override
  String get backupsSection => 'Резервні копії';
  @override
  String get backupsHint => 'Копія даних робиться сама кожні 6 годин і зберігається на цьому '
      'телефоні 2 дні. Фото в копію не входять - вони лишаються на телефоні.';
  @override
  String backupsLast(String when) => 'Остання копія: $when';
  @override
  String get backupsNone => 'Ще немає жодної копії';
  @override
  String get backupNow => 'Зробити копію зараз';
  @override
  String get backupMade => 'Копію зроблено';
  @override
  String backupFailed(String details) => 'Не вдалося зробити копію: $details';
  @override
  String get backupKindAuto => 'автоматична';
  @override
  String get backupKindManual => 'зроблена вручну';
  @override
  String get backupKindBeforeRestore => 'стан перед відновленням';
  @override
  String get backupRestore => 'Відновити';
  @override
  String get backupRestoreTitle => 'Відновити дані з копії?';
  @override
  String backupRestoreText(String when) =>
      'Дані на цьому телефоні замінить копія від $when. Поточний стан спершу збережеться '
      'окремою копією - відновлення можна буде скасувати.';
  @override
  String get backupRestored => 'Дані відновлено з копії';
  String get backupUndone => 'Повернуто дані, що були до відновлення';
  @override
  String backupRestoreFailed(String details) => 'Не вдалося відновити: $details';
  @override
  String get backupSaveToFile => 'Зберегти у файл';
  @override
  String get backupSaveDialog => 'Зберегти резервну копію';
  @override
  String get backupShare => 'Поділитися';
  @override
  String get backupSaved => 'Копію збережено у файл';
  @override
  String get backupSaveCancelled => 'Збереження скасовано';
  @override
  String backupSaveFailed(String details) => 'Не вдалося зберегти файл: $details';
  @override
  String get undo => 'Скасувати';
  @override
  String get cancel => 'Скасувати';

  @override
  String fileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} МБ';
  }

  // ---- Помічники й запрошення ----
  @override
  String get helpersTitle => 'Помічники';
  @override
  String get addHelper => 'Додати помічника';
  @override
  String get helperLogin => 'Логін користувача';
  @override
  String get helperLoginHint => 'пошта Google, напр. ivan@gmail.com';
  @override
  String get accessAll => 'До всіх пасік';
  @override
  String get accessOne => 'Лише до цієї пасіки';
  @override
  String get accessStock => 'Також склад і фінанси';
  @override
  String get chooseApiary => 'Оберіть пасіку';
  @override
  String get sendInvite => 'Надіслати запрошення';
  @override
  String inviteSent(String email) => 'Запрошення надіслано: $email';
  @override
  String inviteNoSuchUser(String email) =>
      'Користувача $email ще немає у Vulyk. Попросіть його спершу увійти в застосунок '
      'через Google - тоді запросіть ще раз.';
  @override
  String get inviteInvalidEmail => 'Вкажіть пошту Google, напр. ivan@gmail.com';
  @override
  String get inviteSelf => 'Це ваша власна пошта';
  @override
  String inviteAlready(String email) => '$email уже має цей доступ';
  @override
  String inviteNeedsStock(String email) =>
      '$email уже має доступ до пасік - склад і фінанси увімкніть у списку помічників нижче';
  @override
  String inviteAlreadyPending(String email) => 'Запрошення для $email уже надіслано й чекає відповіді';
  @override
  String inviteFailed(String details) => 'Не вдалося надіслати запрошення: $details';
  @override
  String get sharingUnavailable =>
      'Запросити помічника можна, коли налаштовано синхронізацію і ви увійшли через Google.';
  @override
  String get helpersNone => 'Помічників ще немає';
  @override
  String get helperAllApiaries => 'усі пасіки';
  @override
  String get helperWithStock => 'склад і фінанси';
  @override
  String get revokeAccess => 'Забрати доступ';
  @override
  String get revokeTitle => 'Забрати доступ?';
  @override
  String revokeText(String email) =>
      '$email більше не бачитиме цих пасік. Те, що помічник уже записав, лишиться.';
  @override
  String get invitesSentTitle => 'Чекають відповіді';
  @override
  String get inviteCancel => 'Скасувати запрошення';
  @override
  String get invitationsTitle => 'Запрошення';
  @override
  String invitationFrom(String who) => 'Від: $who';
  @override
  String invitationApiaries(String names) => 'Пасіки: $names';
  @override
  String get invitationAllApiaries => 'Усі пасіки';
  @override
  String get invitationWithStock => 'разом зі складом і фінансами';
  @override
  String get accept => 'Прийняти';
  @override
  String get decline => 'Відхилити';
  @override
  String invitesMail(int n) =>
      'Вас запрошують помічником: $n ${plural(n, one: 'запрошення', few: 'запрошення', many: 'запрошень')}';
  @override
  String get inviteAccepted =>
      'Запрошення прийнято - пасіки з\'являться в «Мої пасіки» після синхронізації';
  @override
  String get inviteDeclined => 'Запрошення відхилено';
  @override
  String get invitationsNone => 'Запрошень немає';

  // ---- Помічник «Пасічник» ----
  @override
  String get assistantTitle => 'Пасічник';
  @override
  String get assistantOpen => 'Поговорити з пасічником';
  @override
  String get assistantHint => 'Напишіть, що зробити: «відкрий склад», «запиши огляд 5-го вулика»…';
  @override
  String get assistantGreeting => 'Я допоможу із застосунком: відкрити потрібне, знайти вулики, записати огляд, прихід на склад чи витрату. Що зробити?';
  @override
  String get assistantSend => 'Надіслати';
  @override
  String get assistantNewChat => 'Нова розмова';
  @override
  String get assistantNewChatConfirm =>
      'Почати нову розмову? Попередня зникне з цього телефона (повідомлення в черзі лишаться).';
  @override
  String get assistantOffline => "Немає зв'язку - надішлю, щойно з'явиться";
  @override
  String get assistantWaiting => 'чекає на інтернет';
  @override
  String get assistantSending => 'надсилаю…';
  @override
  String get assistantFailed => 'не надіслано';
  @override
  String get assistantRetry => 'Повторити';
  @override
  String get assistantDelete => 'Видалити';
  @override
  String get assistantThinking => 'Пасічник думає…';
  @override
  String get assistantCardTitle => 'Записати так?';
  @override
  String get assistantYes => 'Так';
  @override
  String get assistantNo => 'Ні';
  @override
  String get assistantSaved => 'Записано';
  @override
  String get assistantRejected => 'Не записано';
  @override
  String get assistantUndo => 'Скасувати';
  @override
  String get assistantUndone => 'Скасовано';
  @override
  String assistantOpenTarget(String what) => 'Відкрити: $what';
  @override
  String get assistantUnauthorized => 'Помічник недоступний: сервер не прийняв код доступу';
  @override
  String get assistantServerError => 'Сервер помічника не відповів як слід';
  @override
  String get assistantDemo => 'Демо-режим: сервер помічника не підключено';
  @override
  String assistantMail(int n) =>
      'Пасічник відповів: $n ${plural(n, one: 'нове', few: 'нові', many: 'нових')}';
  @override
  String get assistantMicHold => "Тримайте кнопку й говоріть";
  @override
  String get assistantListening => "Говоріть… (відпустіть - надішлю)";
  @override
  String get assistantMicExplainTitle => "Мікрофон для пасічника";
  @override
  String get assistantMicExplain =>
      "Щоб говорити з пасічником голосом, застосунку потрібен дозвіл на мікрофон. Він слухає лише, поки ви тримаєте кнопку з мікрофоном. Зараз телефон спитає дозвіл.";
  @override
  String get assistantMicExplainOk => "Зрозуміло";
  @override
  String assistantVoiceModel(int mb) =>
      "Щоб говорити без інтернету, один раз завантажте модель голосу (~$mb МБ, краще через Wi-Fi).";
  @override
  String get assistantVoiceDownload => "Завантажити";
  @override
  String assistantVoiceDownloading(int percent) => "Завантажую модель голосу: $percent%";
  @override
  String get assistantVoiceReady => "Модель голосу готова - тримайте кнопку й говоріть";
  @override
  String get assistantVoiceOffline =>
      "Без інтернету розпізнавання голосу недоступне: модель голосу ще не завантажена. Напишіть текстом або завантажте модель, коли буде Wi-Fi.";
  @override
  String get assistantVoiceUnavailable => "Голосовий ввід на цьому телефоні недоступний";
  @override
  String get assistantNoMic =>
      "Немає дозволу на мікрофон (Налаштування телефону → Застосунки → Vulyk → Дозволи)";
  @override
  String get assistantNoUkVoice =>
      "У синтезаторі мови телефону немає української - відповіді не читатимуться вголос";
  @override
  String get assistantSection => "Пасічник-помічник";
  @override
  String get assistantSpeakSetting => "Читати відповіді вголос";

  // ---- Дата й час ----
  @override
  String todayAt(String hm) => 'сьогодні $hm';

  // ---- База даних ----
  @override
  String get startupErrorTitle => 'Не вдалося відкрити дані пасіки';
  @override
  String get startupErrorHint =>
      'Можливі причини: програму вже запущено в іншому вікні, закінчилось місце на диску '
      'або файл даних пошкоджено. Закрийте інші копії програми й спробуйте ще раз.';
  @override
  String get startupOpening => 'Відкриваємо…';
  @override
  String get retry => 'Спробувати ще раз';
  @override
  String dbTooNew(int found, int supported) =>
      'Дані збережено новішою версією застосунку (версія бази $found, ця версія '
      'знає до $supported). Оновіть застосунок.';
}
