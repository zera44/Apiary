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
  List<String> get textSizeLevels => const ['Звичайний', 'Більший', 'Великий', 'Дуже великий', 'Найбільший'];
  @override
  String get textSizePreview => 'Вулик 12 - сьогодні оглянути';
  @override
  String get orientationSection => 'Орієнтація екрана';
  @override
  String get orientationHint => 'Авто - як повернуто телефон.';
  @override
  List<String> get orientationLevels => const ['Авто', 'Вертикальна', 'Горизонтальна'];
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
  String get assistantConversations => 'Розмови';
  @override
  String get assistantConvUntitled => 'Нова розмова';
  @override
  String get assistantConvEmpty => 'Ця розмова ще порожня';
  @override
  String get assistantConvDelete => 'Видалити розмову?';
  @override
  String get assistantConvDeleteText => 'Розмова зникне разом з відповідями. Записане в пасіку лишиться.';
  @override
  String get assistantCopy => 'Копіювати';
  @override
  String get assistantCopied => 'Скопійовано';
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
  String assistantThinking(String who) => '$who думає…';
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
  String get assistantBear => 'Ведмедик';
  @override
  String get assistantBeekeeper => 'Пасічник';
  @override
  String get assistantBearHint => 'Швидкий - для простих справ';
  @override
  String get assistantBeekeeperHint => 'Досвідченіший - краще розуміє складні прохання';
  @override
  String get assistantClose => 'Закрити';
  @override
  String assistantContextPin(String screen) => 'Говорити про «$screen»';
  @override
  String get assistantBearAcc => 'Ведмедика';
  @override
  String get assistantBeekeeperAcc => 'Пасічника';
  @override
  String get assistantRoboAcc => 'Робопасічника';
  @override
  String get assistantRoboLocked =>
      'Вмикається сам, коли Пасічник не впорався, і вимикається, коли задача проста';
  @override
  String get assistantRobo => 'Робопасічник';
  @override
  String get assistantRoboHint => 'Найрозумніший і найдорожчий - для найскладнішого';
  @override
  String assistantRouted(String who) => 'Це просте питання - переходжу на $who';
  @override
  String assistantEscalated(String from, String to) =>
      '$from не впорався з цим питанням - переходжу на $to';
  @override
  String get assistantWhoHelps => 'Хто допомагає';
  @override
  String get assistantEffort => 'Глибина міркувань';
  @override
  String get assistantEffortHintText => 'Вище - точніше на складних проханнях, але довше чекати';
  @override
  String get assistantEffortLow => 'Низька';
  @override
  String get assistantEffortMedium => 'Середня';
  @override
  String get assistantEffortHigh => 'Висока';
  @override
  String get assistantEffortXhigh => 'Дуже висока';
  @override
  String get assistantNotHeard => 'Не розчув - спробуйте ще раз';
  @override
  String get assistantMicHold => 'Натисніть і говоріть';
  @override
  String get assistantListening => 'Слухаю… Натисніть мікрофон ще раз, щоб закінчити';
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
  String get assistantSection => 'Помічник (Ведмедик і Пасічник)';
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

  // ---- Мова ----
  @override
  String get languageSection => 'Мова';
  @override
  String get languageName => 'Українська';
  @override
  String get languageFlag => '🇺🇦';
  @override
  String get languageChange => 'Змінити мову';
  @override
  String get textSizeLetter => 'А';

  // ---- Спільні діалоги й кнопки ----
  @override
  String get menu => 'Меню';
  @override
  String get requiredCharacteristic => 'Обов\'язкова характеристика';
  @override
  String get confirmTitle => 'Підтвердження';
  @override
  String get delete => 'Видалити';
  @override
  String get ok => 'Гаразд';
  @override
  String get save => 'Зберегти';
  @override
  String get iconHive => 'Іконка вулика';
  @override
  String get iconObstacle => 'Іконка перешкоди';
  @override
  String get iconChoose => 'Обрати іконку';
  @override
  String get iconDefault => 'Типова';
  @override
  String get hives => 'Вулики';
  @override
  String get obstacles => 'Перешкоди';
  @override
  String get colorChoose => 'Обрати колір';
  @override
  String get colorDefault => 'Типовий';
  @override
  String get undoDelete => 'Відмінити';
  @override
  List<String> get objectColorNames =>
      const ['Медовий оранжевий', 'Бурштиновий жовтий', 'Теракотовий', 'Малиновий червоний', 'Рожевий', 'Пурпуровий', 'Гірчичний', 'Кораловий', 'Бордовий', 'Персиковий'];
  @override
  String get colorHiveDefault => 'Медовий оранжевий';
  @override
  String get colorObstacleDefault => 'Кам\'яно-бежевий';
  @override
  String get colorOwn => 'Власний колір';

  // ---- Вибір «синя / червона пігулка» ----
  @override
  String get pillBlueLabel => 'Синя пігулка';
  @override
  String get pillBlueText => ' - ти власник свого життя (';
  @override
  String get pillRedLabel => 'червона';
  @override
  String get pillRedText => ' - я покажу, як глибока ця нора (';
  @override
  String get pillBlueDefault => 'завершити навчання';
  @override
  String get pillRedDefault => 'продовжити';
  @override
  String get myApiaries => 'Мої пасіки';
  @override
  String get pillLead => 'Колего, пропоную тобі вибір. ';
  @override
  String get pillNoTutorial => 'без навчання';
  @override
  String get pillTakeTutorial => 'пройти навчання';
  @override
  String get pillBlue => 'Синя';
  @override
  String get pillRed => 'Червона';

  // ---- Панель характеристик ----
  @override
  String get hive => 'Вулик';
  @override
  String get obstacle => 'Перешкода';
  @override
  String obstacleOf(String v) => 'Перешкода - $v';
  @override
  String get color => 'Колір';
  @override
  String get values => 'Значення';
  @override
  String get inspect => 'Оглянути';
  @override
  String get noChanges => 'Змін немає';
  @override
  String get parameters => 'Параметри';
  @override
  String get characteristics => 'Характеристики';
  @override
  String get notes => 'Нотатки';
  @override
  String get qrCode => 'QR-код';

  // ---- Голосовий ввід у полях ----
  @override
  String voiceModelOnce(int mb) =>
      'Для голосу один раз завантажте модель ~$mb МБ (краще через Wi-Fi)';
  @override
  String get voicePreparing => 'Готую розпізнавання…';
  @override
  String get voiceNoMic => 'Немає дозволу на мікрофон (Налаштування телефону → Дозволи)';
  @override
  String get voiceModelBroken => 'Модель голосу пошкоджена - завантажте її ще раз';
  @override
  String voiceUnavailable(String details) => 'Голосовий ввід недоступний: $details';
  @override
  String get voiceModelReady => 'Модель готова - натисніть мікрофон і говоріть';
  @override
  String get voiceDownloadPaused => 'Скачування зупинено - наступного разу докачається';
  @override
  String voiceDownloadFailed(String details) => 'Не вдалося скачати модель: $details';
  @override
  String voiceRecognitionError(String details) => 'Помилка розпізнавання: $details';
  @override
  String voiceNotNumber(String spoken) => 'Не число: «$spoken»';
  @override
  String get voiceSpeak => 'Говоріть…';
  @override
  String get voiceUnpacking => 'Розпаковую модель…';
  @override
  String voiceDownloading(int percent) => 'Завантажую модель голосу: $percent %';
  @override
  String get voiceSayNumber => 'Скажіть число';
  @override
  String get voiceInput => 'Голосовий ввід';
  @override
  String get download => 'Завантажити';

  // ---- Меню навігації ----
  @override
  String get qrHiveNotFound => 'Вулик не знайдено';
  @override
  String get qrNotBound => 'Цей QR-код ще не прив\'язаний до жодного вулика.';
  @override
  String qrBindAsk(String why, String code) =>
      '$why\n\nКод: $code\n\nПрив\'язати його до вулика зараз?';
  @override
  String get qrBindToHive => 'Прив\'язати до вулика';
  @override
  String get qrCreateApiaryFirst => 'Спершу створіть пасіку й вулики на карті.';
  @override
  String get stock => 'Склад';
  @override
  String get finances => 'Фінанси';
  @override
  String get history => 'Історія';
  @override
  String get tutorial => 'Навчання';
  @override
  String get feedbackTitle => 'Зворотний зв\'язок';
  @override
  String get tourApiaries => ' - усі твої пасіки в одному місці.';
  @override
  String get tourStock => ' - рамки, корми, ліки: прихід, списання й переоблік.';
  @override
  String get tourFinances => ' - витрати й доходи пасіки: записуй вручну або фотографуй чек.';
  @override
  String get tourHistory => ' - цікаво глянути зміни показників чи в складі? Тобі сюди.';
  @override
  String get tourQr =>
      ' - обхід без записів - час на вітер. Скануй код з вулика, а новий - прив\'язуй до вулика.';
  @override
  String get tourTutorial => ' - щось не зрозумів? Пройди спеціалізоване навчання.';
  @override
  String get tourSettings => ' - мова, розмір шрифту, шаблони, акаунт і резервні копії.';
  @override
  String get tourFeedback => ' - хочеш поділитись ідеєю чи дати зворотний зв\'язок? Тобі сюди.';
  @override
  String get gotIt => 'Зрозуміло';
  @override
  String get continueAction => 'Продовжити';
  @override
  String get navMenu => 'Меню навігації';
  @override
  String get scan => 'Сканувати';
  @override
  String get generate => 'Генерувати';
  @override
  String get qrBindRow => 'Прив\'язати підряд';

  // ---- Головний екран ----
  @override
  String get signInFailed => 'Не вдалося увійти. Перевірте інтернет і спробуйте ще раз.';
  @override
  String get whatsNew => 'Що нового';
  @override
  String get start => 'Почати';
  @override
  String get feedbackShort => 'Відгук';
  @override
  String get dataOnlyHere => 'Дані лише на цьому пристрої';
  @override
  String get signInForSync => 'Увійти через Google для синхронізації';
  @override
  String get scanQr => 'Сканувати QR-код';
  @override
  String get greetNight => 'Доброї ночі, пасічнику!';
  @override
  String get greetMorning => 'Доброго ранку, пасічнику!';
  @override
  String get greetDay => 'Доброго дня, пасічнику!';
  @override
  String get greetEvening => 'Доброго вечора, пасічнику!';
  @override
  List<String> get homeTips =>
      const [
      'Утримайте вулик на карті - і одразу перетягуйте його на нове місце.',
      'Обхід: на карті червоні - ті, кого пора оглянути. Підійдіть до вулика й натисніть «Сканувати».',
      'В огляді «Зберегти», «Змін немає» і «Пропустити» одразу відкривають наступний вулик.',
      'Обрали новий параметр зі списку і не знаходите кнопку «Зберегти»? Це тому, що всі зміни зберігаються автоматично.',
      'Утримайте «Фінанси» - і одразу відкриється нова витрата.',
      'Наклейте QR-наліпки - і вулик відкриється з камери за секунду.',
      'Задайте мінімальний залишок на складі - я нагадаю, коли час докупити.',
      'Звіт по пасіці в Excel - у меню ☰ → «Історія».',
      'Періодичність обходу задається одна на всю пасіку - торкніться назви пасіки на карті.',
      'Якщо для вулика треба інший час обходу - торкніться «Кількість днів до обходу» на його панелі.',
      ];
  @override
  String get dueToday => 'Сьогодні оглянути';
  @override
  String get myApiary => 'Моя пасіка';
  @override
  String get showOnMap => 'Показати на карті';
  @override
  String get feedbackReplied => 'Розробник відповів на ваш відгук';
  @override
  String dueTodayCount(int n) => 'Сьогодні оглянути: $n';
  @override
  String timeToBuy(String items) => 'Час докупити: $items';
  @override
  String get tapToGo => 'Натисніть - перейти';
  @override
  String get tapNext => 'Натисніть - далі';
  @override
  String get mail => 'Пошта';

  // ---- Мої пасіки ----
  @override
  String get apiaryListHello =>
      'Здоров був, новачок, укуси мене бджола! А де твоя пасіка? Непорядок... Натисни ';
  @override
  String get createMapQuoted => '«Створити карту»';
  @override
  String get deleteApiaryTitle => 'Видалити пасіку?';
  @override
  String deleteApiaryText(String name) =>
      'Пасіку «$name» буде видалено разом з усіма вуликами, перешкодами й записами. Цю дію не можна скасувати.';
  @override
  String apiaryDeleted(String name) => 'Пасіку «$name» видалено';
  @override
  String get noApiariesYet => 'Ще немає жодної пасіки.\nСтвори її кнопкою нижче.';
  @override
  String get createMapButton => '+  Створити карту';
  @override
  String get open => 'Відкрити';
  @override
  String get qrLabels => 'QR-наліпки';

  // ---- Шаблони ----
  @override
  String get templateRename => 'Перейменувати шаблон';
  @override
  String templateDeleted(String name) => 'Шаблон «$name» видалено';
  @override
  String get templates => 'Шаблони';
  @override
  String get noTemplatesYet => 'Ще немає жодного шаблону';
  @override
  String get templateCreate => 'Створити шаблон';
  @override
  String get rename => 'Перейменувати';

  // ---- Перші підказки ----
  @override
  String get hintHomeA => 'Вітаю на пасіці! ';
  @override
  String get hintHomeB =>
      ' відкриває карту вашої пасіки. Коли настане час огляду, тут з\'явиться ';
  @override
  String get hintHomeC => ' - одне натискання, і ви вже біля потрібного вулика.';
  @override
  String get hintMapA =>
      'Це карта пасіки. Натисніть на вулик - праворуч відкриються його значення. ';
  @override
  String get editing => 'Редагування';
  @override
  String get hintMapB =>
      ' (перемикач унизу ліворуч) - щоб додати вулики, переставити їх чи змінити вигляд. Утримання вулика одразу вмикає редагування.';
  @override
  String get hintPanelA =>
      'Тут останні значення вулика. Натисніть на рядок - побачите історію. ';
  @override
  String get hintPanelB => ' - записати огляд; ';
  @override
  String get hintPanelC => ' - якщо змін немає.';
  @override
  String get hintFillA => 'Заповніть лише те, що змінилось - решта лишиться як була. ';
  @override
  String get saveAndNext => 'Зберегти й далі';
  @override
  String get hintFillB => ' одразу відкриє наступний вулик.';
  @override
  String get hintEditA =>
      'Режим редагування: оберіть шаблон і натисніть на вільну клітинку. Вулик можна перетягнути, повернути кнопкою над ним. Видалили помилково - ';
  @override
  String get hintEditB => ' внизу. Перемикач у ';
  @override
  String get workMode => 'Робочий режим';
  @override
  String get hintEditC => ' - зберегти й вийти.';
  @override
  String get hintStockA => 'Склад: ';
  @override
  String get stockIn => 'Прихід';
  @override
  String get hintStockB => ' - що купили, ';
  @override
  String get stocktake => 'Переоблік';
  @override
  String get hintStockC =>
      ' - звірити залишки. Задайте мінімальний залишок, і застосунок підкаже, коли час докупити.';
  @override
  String get skip => 'Пропустити';

  // ---- Нотатки вулика ----
  @override
  String get today => 'Сьогодні';
  @override
  String get yesterday => 'Вчора';
  @override
  String get noteDeleted => 'Нотатку видалено';
  @override
  String get noteAdd => '+ Нотатка';
  @override
  String get all => 'Усі';
  @override
  String get notesNone => 'Нотаток ще немає.\nЗапишіть, що помітили біля вулика.';
  @override
  String get notesNoneWithLabel => 'Немає нотаток із цією міткою.';
  @override
  String get actions => 'Дії';
  @override
  String get edit => 'Змінити';
  @override
  String get labelNew => 'Нова мітка';
  @override
  String get labelDelete => 'Видалити мітку';
  @override
  String get label => 'Мітка';
  @override
  String labelExists(String name) => 'Мітка «$name» вже є.';
  @override
  String get labelDeleteTitle => 'Видалити мітку?';
  @override
  String get labelDeleteText => 'Нотатки з цією міткою залишаться, але без мітки.';
  @override
  String get noteEmpty => 'Напишіть текст нотатки.';
  @override
  String get noteNew => 'Нова нотатка';
  @override
  String get note => 'Нотатка';
  @override
  String get noteHint => 'Що помітили біля вулика';
  @override
  String get date => 'Дата';
  @override
  String get otherDate => 'Інша дата';
  @override
  String get noLabel => 'Без мітки';
  @override
  String get labelAdd => '+ Мітка';
  @override
  String get labelHoldHint => 'Утримуйте мітку, щоб перейменувати чи видалити.';

  // ---- Історія ----
  @override
  String get apiaryReportExcel => 'Звіт по пасіці (Excel)';
  @override
  String get noCharacteristicsYet => 'Ще немає жодної характеристики.';
  @override
  String get noStockItemsYet => 'Ще немає жодної номенклатури.\nДодайте її в меню → «Склад».';
  @override
  String get noArrivalYet => 'Ще не було приходу';
  @override
  String balance(String amount) => 'Залишок: $amount';
  @override
  String get recordCancelTitle => 'Скасувати запис?';
  @override
  String recordCancelText(String title, String date) =>
      '«$title» від $date буде позначено як скасований, а залишок повернеться назад. Запис лишиться в історії.';
  @override
  String get recordCancel => 'Скасувати запис';
  @override
  String get currency => 'грн';
  @override
  String get cancelledMark => 'скасовано';
  @override
  String becameAmount(String amount) => 'стало: $amount';
  @override
  String historyOf(String name) => 'Історія: $name';
  @override
  String get stockHistoryEmpty =>
      'Ще немає жодного запису.\nЗаписи з\'являються після приходу, списання чи переобліку на складі.';
  @override
  String get filterObject => 'Фільтр: об\'єкт';
  @override
  String get allObjects => 'Усі об\'єкти';
  @override
  String objectOf(String name) => 'Об\'єкт: $name';
  @override
  String get clearFilter => 'Очистити фільтр';
  @override
  String get nothingToExport => 'Немає жодного запису для експорту.';
  @override
  String paramHistoryEmpty(bool scoped) =>
      'Ще немає жодного запису для цього параметра${scoped ? " у цього об'єкта" : ''}.\nЗаписи з\'являються після кнопки «Оглянути» на карті.';
  @override
  String get exportExcel => 'Експортувати в Excel';

  // ---- QR-коди ----
  @override
  String get qrRegenTitle => 'Перегенерувати коди?';
  @override
  String qrRegenText(int replacing, int selected) =>
      'У $replacing з $selected обраних вуликів уже є код. Вони отримають нові коди, а старі наліпки перестануть працювати.';
  @override
  String get qrRegen => 'Перегенерувати';
  @override
  String qrCodesOf(String name) => 'QR-коди: $name';
  @override
  String get qrNoHives => 'На цій пасіці ще немає вуликів';
  @override
  String qrLegend(int withCode, int hives) =>
      'Червоний ободок - обрано, коду немає · зелений - код уже є ($withCode з $hives)';
  @override
  String get qrAllWithoutCode => 'Усі без коду';
  @override
  String get qrCreating => 'Створюємо…';
  @override
  String qrGenerateN(int n) => 'Згенерувати ($n)';
  @override
  String printFailed(String details) =>
      'Не вдалося відкрити друк: $details\n\nЗбережіть PDF і надрукуйте його.';
  @override
  String qrLabelsN(int n) => 'Наліпки ($n)';
  @override
  String get print => 'Друк';
  @override
  String get pleaseWait => 'Зачекайте…';
  @override
  String get savePdf => 'Зберегти PDF';
  @override
  String get qrManual => 'Введіть код (посилання) вручну';
  @override
  String get qrTabHive => 'Код вулика';
  @override
  String get qrTabReceipt => 'Чек';
  @override
  String get qrFound => 'QR-код знайдено - тримайте камеру нерухомо';
  @override
  String get qrReceiptHint => 'Покладіть чек рівно на контрастний фон і натисніть «Зняти»';
  @override
  String get qrHint => 'Наведіть камеру на QR-код вулика і потримайте секунду-дві';
  @override
  String get scanReceipt => 'Сканувати чек';
  @override
  String get shoot => 'Зняти';
  @override
  String get phoneCamera => 'Камерою телефона';
  @override
  String get fromGallery => 'З галереї';
  @override
  String get qrEnterManually => 'Ввести код вручну';

  // ---- Карта пасіки ----
  @override
  String get mapNoHivesA =>
      'Щось у тебе, друже, і вуликів то нема. Додай нові, увімкнувши режим ';
  @override
  String get editingQuoted => '«Редагування»';
  @override
  String get mapNoHivesB => ' унизу ліворуч';
  @override
  String get mapTapAnywhere => 'Натисни на карту в будь-якому місці';
  @override
  String get mapWrongPlace =>
      'Щось ти геть не туди поставив. Перемісти перетягуванням на сусідню клітинку';
  @override
  String get mapConfirmA => 'Підтверди вибір - перемкни в ';
  @override
  String get workModeQuoted => '«Робочий режим»';
  @override
  String get mapGoodStart => 'З легким стартом, друже!';
  @override
  String get mapNoRest => 'Не час відпочивати, натисни на ';
  @override
  String quoted(String s) => '«$s»';
  @override
  String get mapTellShort => 'Розкажу коротко, що ми маємо. ';
  @override
  String get mapOpenNavMenu => 'Відкрий меню навігації';
  @override
  String get mapTemplatesInA => 'Шаблони - у ';
  @override
  String get settingsQuoted => '«Налаштуваннях»';
  @override
  String get mapTemplatesInB =>
      ' меню. А набір параметрів вулика збирай у «Параметрах» його панелі: у «Конструкторі» розклади їх по групах.';
  @override
  String get mapLessonDone => 'Вулик додав, обхід зробив. ';
  @override
  String get mapShortNotes => 'Це короткі замітки про твій вулик.';
  @override
  String get mapScrollDown => 'Прокрути донизу й ';
  @override
  String get mapDoInspect => 'проведи огляд вулика';
  @override
  String get mapTapHiveToBind => 'Торкніться вулика, до якого прив\'язати код';
  @override
  String get mapCellHasOther => 'Тут уже є інший об\'єкт';
  @override
  String get mapTemplateEmpty => 'Шаблон порожній';
  @override
  String get mapCellBusy => 'Клітинка зайнята';
  @override
  String mapDueHives(int n) =>
      'Оглянути: $n ${plural(n, one: 'вулик', few: 'вулики', many: 'вуликів')} (червоні)';
  @override
  String mapPlaceTemplate(String name) => 'Тапай - ставити «$name», тягни - перемістити';
  @override
  String mapGroupN(int n) => 'Група ($n)';
  @override
  String get mapChooseHive => 'Оберіть вулик';
  @override
  String get mapTemplatesCreatedA => 'Я трохи про тебе потурбувався. Створив ';
  @override
  String get and => ' і ';
  @override
  String get mapTemplatesCreatedB => '. Обери ';
  @override
  String get mapChooseTemplate => 'Оберіть шаблон';
  @override
  String get mapNoTemplate => 'Ще немає жодного шаблону.';
  @override
  String get mapNoRoomRotate => 'Немає місця для повороту';
  @override
  String get mapGroupDeleted => 'Групу об\'єктів видалено';
  @override
  String get mapObjectDeleted => 'Об\'єкт видалено';
  @override
  String get mapTemplateDeleted => 'Шаблон видалено';
  @override
  String get mapRenameObject => 'Перейменувати об\'єкт';
  @override
  String get mapLinkParamFirst => 'Спершу прив\'яжіть хоча б один параметр';
  @override
  String get notWrittenOff => 'Не списано';
  @override
  String get mapVisitMarked => 'Огляд відмічено: сьогодні';
  @override
  String get mapAllInspected => 'Усі вулики на сьогодні оглянуто';
  @override
  String get mapRoundDone => 'Обхід завершено';
  @override
  String get mapNextHive => 'Наступний вулик';
  @override
  String qrNotBoundCode(String why, String code) => '$why\n\nКод: $code';
  @override
  String get mapNoMoreOverdue => 'Прострочених оглядів більше немає.';
  @override
  String get done => 'Готово';
  @override
  String get daysToRound => 'Кількість днів до обходу';
  @override
  String get mapAllHaveQr => 'У всіх вуликів цієї пасіки вже є QR-коди.';
  @override
  String get qrCodes => 'QR-коди';
  @override
  String get qrInUse => 'Код уже використовується';
  @override
  String qrMoveTo(String other, String apiary, String name) =>
      'Цей QR-код прив\'язаний до «$other» (пасіка «$apiary»). Перенести його на «$name»?';
  @override
  String qrMoveHere(String other, String apiary) =>
      'Цей QR-код прив\'язаний до «$other» (пасіка «$apiary»). Перенести його на цей вулик?';
  @override
  String get move => 'Перенести';
  @override
  String qrNumber(String n) => 'QR-код № $n';
  @override
  String get qrOfHive => 'QR-код вулика';
  @override
  String get qrOther => 'Інший код';
  @override
  String get qrUnlink => 'Відв\'язати';
  @override
  String get qrForHive => 'QR-код для вулика';
  @override
  String get qrLinked => 'QR-код прив\'язано';
  @override
  String get scanHive => 'Сканувати вулик';
  @override
  String qrNotBoundHowTo(String why, String code) =>
      '$why\n\nКод: $code\n\nПрив\'язати: меню ☰ → «QR-код».';
  @override
  String get qrHiveHasCode => 'У вулика вже є код';
  @override
  String get qrReplaceAsk => 'Замінити поточний QR-код цього вулика на відсканований?';
  @override
  String get replace => 'Замінити';
  @override
  String get mapMenuHintA =>
      'Тут ти зможеш керувати своєю пасікою. Щоб дізнатися про всі функції - ';
  @override
  String get mapTakeTutorial => 'пройди навчання';
  @override
  String get apiarySettings => 'Налаштування пасіки';
  @override
  String get back => 'Назад';
  @override
  String get mapFinishAdding => 'Завершити додавання';
  @override
  String get mapAddObject => 'Додати об\'єкт';
  @override
  String get mapLastMenuA => 'Наостанок покажу меню навігації. ';
  @override
  String get mapOpenIt => 'Відкрий його';
  @override
  String get properties => 'Властивості';
  @override
  String get rotate => 'Повернути';

  // ---- Склад ----
  @override
  String stockItemDeleted(String name) => 'Номенклатуру «$name» видалено';
  @override
  String stockActualBad(String name) => '«$name»: фактична кількість - число, не менше 0';
  @override
  String get notSaved => 'Не збережено';
  @override
  String stockWholeFor(String name, String unit) => '«$name»: для «$unit» вкажіть ціле число';
  @override
  String get stockNoDiffs => 'Розбіжностей немає - усе збігається з обліком';
  @override
  String stockTakeSaved(int n) => 'Переоблік збережено: змінено позицій - $n';
  @override
  String byRecords(String amount) => 'За обліком: $amount';
  @override
  String get actually => 'Фактично';
  @override
  String get stockInOut => 'Прихід і списання';
  @override
  String get oneByOne => 'По одному';
  @override
  String get asList => 'Списком';
  @override
  String get stockNoItems => 'Ще немає жодної номенклатури';
  @override
  String get stockTakeSave => 'Зберегти переоблік';
  @override
  String get stockItemAdd => 'Додати номенклатуру';
  @override
  String get writeOff => 'Списати';
  @override
  String get recount => 'Перерахувати';
  @override
  String get timeToBuyShort => 'Час докупити';
  @override
  String get enterName => 'Вкажіть назву';
  @override
  String get enterUnit => 'Вкажіть одиницю виміру';
  @override
  String get stockMinBad => 'Мінімальний залишок - число, не менше 0';
  @override
  String get stockInQtyBad => 'Прихід: кількість - число більше 0';
  @override
  String get stockInCostBad => 'Прихід: вкажіть загальну вартість';
  @override
  String get stockItem => 'Номенклатура';
  @override
  String get stockItemNew => 'Нова номенклатура';
  @override
  String get name => 'Назва';
  @override
  String get unit => 'Одиниця виміру';
  @override
  String get unitOther => 'інша…';
  @override
  String get unitOwn => 'Своя одиниця';
  @override
  String get stockMin => 'Мінімальний залишок';
  @override
  String get stockMinHelper => 'Дійде до нього - «час докупити»';
  @override
  String get stockInNow => 'Одразу прихід (необов\'язково)';
  @override
  String get quantity => 'Кількість';
  @override
  String get cost => 'Вартість';
  @override
  String get takePhoto => 'Зробити фото';
  @override
  String get choosePhoto => 'Обрати фото';
  @override
  String get removePhoto => 'Прибрати фото';
  @override
  String get stockEnterActual => 'Введіть фактичну кількість (0 або більше)';
  @override
  String get stockEnterQty => 'Введіть кількість більше 0';
  @override
  String wholeFor(String unit) => 'Для «$unit» вкажіть ціле число';
  @override
  String stockMaxWriteOff(String amount) => 'Можна списати не більше $amount';
  @override
  String get writeOffNoun => 'Списання';
  @override
  String get dateColon => 'Дата: ';
  @override
  String get actualQuantity => 'Фактична кількість';
  @override
  String get totalCostDefault0 => 'Загальна вартість (за замовч. 0)';
  @override
  String unitPrice(String price) => 'Ціна за одиницю: $price';
  @override
  String get commentOptional => 'Коментар (необов\'язково)';

  // ---- Фінанси ----
  @override
  String get finFromStock => 'Внесено на складі';
  @override
  List<String> get monthNames =>
      const ['', 'Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень', 'Липень', 'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень'];
  @override
  String get noCategory => 'Без категорії';
  @override
  String finEntryText(String name, bool expense, String amount, String rest) =>
      '$name · ${expense ? 'витрата' : 'дохід'} $amount\n$rest';
  @override
  String get finFromStockNote =>
      '\n\nПрихід внесено на складі. Скасування тут скасує його й на складі.';
  @override
  String get finBoughtTitle => 'Куплено:';
  @override
  String get finLinesNote => '\n\nСкасування скасує й приходи цієї операції на складі.';
  @override
  String get finCancelledNote => '\n\nЦей запис скасовано.';
  @override
  String get record => 'Запис';
  @override
  String get notCancelled => 'Не скасовано';
  @override
  String get finSumBad => 'Сума — число, не менше 0';
  @override
  String get finEditRecord => 'Змінити запис';
  @override
  String get finSumUah => 'Сума, ₴';
  @override
  String get finSumFromLines => 'Сума складається з рядків таблиці';
  @override
  String get category => 'Категорія';
  @override
  String get periodDay => 'День';
  @override
  String get periodWeek => 'Тиждень';
  @override
  String get periodMonth => 'Місяць';
  @override
  String get periodYear => 'Рік';
  @override
  String get periodCustom => 'Період';
  @override
  String finOperationsOf(String title) => 'Операції · $title';
  @override
  String get finAllOperations => 'Усі операції';
  @override
  String get expenses => 'Витрати';
  @override
  String get income => 'Дохід';
  @override
  String get incomes => 'Доходи';
  @override
  String get earlier => 'Раніше';
  @override
  String get later => 'Пізніше';
  @override
  String finBalance(String v) => 'баланс $v';
  @override
  String get finNothingInPeriod => 'За цей період нічого немає';
  @override
  String get finNewOperation => 'Нова операція';
  @override
  String get finNoOperations => 'Операцій немає';
  @override
  String get receiptOnPhoneOnly =>
      'Розпізнавання тексту працює на телефоні. Тут заповніть таблицю вручну.';
  @override
  String get receiptNoRows =>
      'Не вдалося розпізнати позиції. Сфотографуйте рівніше й при гарному світлі або заповніть таблицю вручну.';
  @override
  String receiptRows(int n) => '$n ${plural(n, one: 'рядок', few: 'рядки', many: 'рядків')}';
  @override
  String receiptOk(String rows) => 'Чек розпізнано · $rows · сума збігається з чеком ✓';
  @override
  String receiptMismatch(String rows, String declared, String table) =>
      'Чек розпізнано · $rows. Сума на чеку $declared, у таблиці $table - перевірте рядки.';
  @override
  String receiptRest(String rows, String rest) =>
      'Чек розпізнано · $rows. Ще $rest з чека не розпізнано - додано окремим рядком, уточніть назву й ціну.';
  @override
  String get receiptRestName => 'Не розпізнано';
  @override
  String receiptCheck(String rows) =>
      'Чек розпізнано · $rows. Перевірте таблицю: розпізнавання може помилятися.';
  @override
  String get receiptFailed => 'Не вдалося розпізнати чек. Заповніть таблицю вручну.';
  @override
  String get finChooseCategory => 'Оберіть категорію зі списку або створіть нову («+ Нова»).';
  @override
  String finBadRows(int n) =>
      'У ${n == 1 ? 'одному рядку' : '$n рядках'} не вистачає назви, кількості (більше 0; для «шт» — ціле) або ціни. Виправте їх чи видаліть рядок.';
  @override
  String get notRecorded => 'Не записано';
  @override
  String get finNegative => 'Сума не може бути від\'ємною. Введіть додатне число.';
  @override
  String get finEnterSum => 'Введіть суму або заповніть таблицю.';
  @override
  String get finSumMismatch => 'Сума не збігається';
  @override
  String finSumMismatchText(String table, String receipt) =>
      'У таблиці $table, а на чеку $receipt. Скоріш за все, якийсь рядок розпізнано неправильно. Записати все одно?';
  @override
  String get recordAction => 'Записати';
  @override
  String get check => 'Перевірити';
  @override
  String recordedToStock(bool expense, int n) =>
      'Записано · ${expense ? 'на склад' : 'зі складу'}: $n';
  @override
  String get recorded => 'Записано';
  @override
  String recordFailed(String details) => 'Не вдалося записати: $details';
  @override
  String finFixedByHand(String table) => 'виправлено вручну · таблиця $table';
  @override
  String finDiscount(String v) => ' · знижка −$v';
  @override
  String get sum => 'Сума';
  @override
  String get fromTable => '↺ з таблиці';
  @override
  String get newCategoryShort => '+ Нова';
  @override
  String get receiptReading => 'Розпізнаю чек…';
  @override
  String get receiptPhotoHint =>
      'Сфотографуйте чек рівно, при гарному світлі. Усі позиції потраплять у таблицю нижче.';
  @override
  String get receiptPhoto => 'Сфотографувати чек';
  @override
  String get photoFromGallery => 'Обрати фото з галереї';
  @override
  String get reshoot => 'Перезняти';
  @override
  String get toStock => 'На склад';
  @override
  String get fromStock => 'Зі складу';
  @override
  String get goods => 'Товар';
  @override
  String get qtyShort => 'К-сть';
  @override
  String get price => 'Ціна';
  @override
  String inStockAmount(String amount) => 'є на складі · $amount';
  @override
  String willWriteOff(String amount) => 'спише $amount';
  @override
  String moreThanStock(String amount) => 'більше за залишок · коригування +$amount';
  @override
  String get newGoods => 'новий товар';
  @override
  String get notInStock => 'немає на складі';
  @override
  String checkPrice(String v) => 'перевір ціну · зазвичай $v ₴';
  @override
  String sumOf(String v) => 'сума $v';
  @override
  String get putToStock => 'Покласти на склад';
  @override
  String get writeOffFromStock => 'Списати зі складу';
  @override
  String get deleteRow => 'Видалити рядок';
  @override
  String get byHand => 'Вручну';
  @override
  String get fromReceipt => 'З чека';
  @override
  String get addRow => '+ рядок';
  @override
  String tableOf(String v) => 'таблиця $v';
  @override
  String get leaveUnsavedTitle => 'Вийти без збереження?';
  @override
  String get leaveUnsavedText => 'Введені дані не буде записано.';
  @override
  String get leave => 'Вийти';
  @override
  String get stay => 'Залишитись';
  @override
  String get newExpense => 'Нова витрата';
  @override
  String get newIncome => 'Новий дохід';
  @override
  String get add => 'Додати';
  @override
  String get unitShort => 'Одиниця';
  @override
  String get enterCategoryName => 'Введіть назву категорії.';
  @override
  String saveFailed(String details) => 'Не вдалося зберегти: $details';
  @override
  String get error => 'Помилка';
  @override
  String get categoryDeleteTitle => 'Видалити категорію?';
  @override
  String get categoryDeleteText =>
      'Старі операції збережуть свою категорію, але нову з неї створити не можна.';
  @override
  String get categoryNew => 'Нова категорія';
  @override
  String get catGoesToStock => 'Позиції йдуть на склад';
  @override
  String get catFromStock => 'Позиції списуються зі складу';
  @override
  String get catGoesToStockHint => 'Рядки таблиці витрати стануть приходом';
  @override
  String get catFromStockHint => 'Рядки таблиці доходу спишуть залишок (продаж)';
  @override
  String get icon => 'Значок';
  @override
  String get categoryDelete => 'Видалити категорію';
  @override
  String get create => 'Створити';
  @override
  String finNotInStock(String name) =>
      '«$name» немає на складі - спершу додайте прихід (наприклад, відкачали мед) або зніміть позначку «зі складу».';
  @override
  String finUnitMismatch(String name, String stockUnit, String unit, String density) =>
      '«$name» на складі в одиницях «$stockUnit», а в продажі «$unit». Продавати можна в тих самих одиницях (кг і л перераховуються: 1 л = $density кг).';
  @override
  String get finRecordNotFound => 'Запис не знайдено';
  @override
  String get finCancelledNotEdited => 'Скасований запис не змінюють';
  @override
  String get finSumLocked =>
      'Суму не можна змінити: вона складається з рядків таблиці. Скасуйте запис і внесіть новий.';
  @override
  String get finAlreadyCancelled => 'Цей запис уже скасовано';

  // ---- Параметри ----
  @override
  String records(int n) => '$n ${plural(n, one: 'запис', few: 'записи', many: 'записів')}';
  @override
  String get paramEdit => 'Редагувати параметр';
  @override
  String get paramNew => 'Новий параметр';
  @override
  String get paramBaseNameLocked => 'Назву Базової характеристики змінити не можна';
  @override
  String get dataType => 'Тип даних';
  @override
  String get listOptions => 'Варіанти списку';
  @override
  String get paramBaseTypeLocked => 'Тип даних Базової характеристики змінити не можна';
  @override
  String get paramTypeLocked =>
      'Записи вже є, тож тип даних змінити не можна. Щоб змінити тип - створіть новий параметр і перенесіть у нього історію.';
  @override
  String get paramTypeFree => 'Тип даних можна змінити, поки немає жодного запису.';
  @override
  String get paramMoveHistoryDots => 'Перенести історію…';
  @override
  String get paramDelete => 'Видалити параметр';
  @override
  String get paramNeedName => 'Так не можна - вкажіть назву параметра';
  @override
  String get paramNeedTwoOptions => 'Так не можна - додайте щонайменше два варіанти';
  @override
  String get paramMoveWhere => 'Куди перенести історію?';
  @override
  String paramFrom(String name, String type) => 'З «$name» ($type)';
  @override
  String get paramNewDots => '+ Новий параметр…';
  @override
  String paramMoveText(String from, String to, String type, String records) =>
      'З «$from» у «$to» ($type) буде перенесено $records історії з тими самими датами й об\'єктами.';
  @override
  String paramMoveSkipped(String records, String type, String from) =>
      '\n\n$records не підходять до типу «$type» - вони лишаться в «$from».';
  @override
  String paramMoveReplace(String from, String to) => '\n\nДе був «$from», там з\'явиться «$to».';
  @override
  String get paramMoveHistory => 'Перенести історію';
  @override
  String paramMoveAndDelete(String name) => 'Перенести й видалити «$name»';
  @override
  String paramMoved(int moved, int skipped) =>
      'Перенесено записів: $moved.${skipped > 0 ? '\nНе підійшли до типу й лишились: $skipped.' : ''}';
  @override
  String paramBaseNoDelete(String name) =>
      '«$name» - Базова характеристика, обов\'язкова для усього класу об\'єктів. Її не можна видалити.';
  @override
  String get cannotDelete => 'Не можна видалити';
  @override
  String paramDeleted(String name) => 'Параметр «$name» видалено';
  @override
  String get paramTable => 'Таблиця параметрів';
  @override
  String get paramCreate => 'Створити параметр';
  @override
  List<String> get paramTabs => const ['Список', 'Конструктор'];
  @override
  String get paramNoneYet => 'Ще немає жодного параметра.\nСтвори його кнопкою «+» вгорі.';
  @override
  String get characteristicCreate => 'Створити характеристику';
  @override
  String get groupNew => 'Нова група';
  @override
  String groupNameIt(String name) => 'Назви групу «$name»';
  @override
  String get groupName => 'Назва групи';
  @override
  String get groupDelete => 'Видалити групу';
  @override
  String get dropHere => 'Відпусти тут';
  @override
  String get dragParamsHere => 'Перетягни сюди параметри';
  @override
  String get builderEmpty => 'Тут з\'являться параметри, які ви оберете у вкладці «Список».';
  @override
  String get builderHint => 'Затисни параметр і веди в потрібну групу.';
  @override
  String get groupNewButton => '+ Нова група';
  @override
  String get chosenNoGroup => 'Обрані, але ще без групи';
  @override
  String get allGrouped => 'Усі параметри розкладено по групах.';
  @override
  String get dragToGroup => 'Затисни й перетягни в групу.';
  @override
  String paramHasRecordsNoRename(String name) =>
      'У «$name» уже є записи, тож назву змінити не можна. Можна створити новий параметр і перенести в нього історію.';
  @override
  String get cannotRename => 'Не можна перейменувати';
  @override
  String get requiredSuffix => ' · обов\'язкова';
  @override
  String get editAction => 'Редагувати';
  @override
  String get scopeHive => 'Цей вулик';
  @override
  String get scopeSame => 'Такі самі';
  @override
  String scopeKind(String kind) => 'Усі «$kind»';
  @override
  String get scopeApiary => 'Уся пасіка';
  @override
  String get applyTo => 'Застосувати до:';

  // ---- Огляд вулика ----
  @override
  String get fillParams => 'Заповнити параметри';
  @override
  String get fillLesson0a =>
      'Це параметри вулика. Зараз тут тільки обов\'язкові, але ти зможеш ';
  @override
  String get fillLesson0b => 'додати нові згодом';
  @override
  String get fillLesson1 => 'Мій помічник перевірив вулик за тебе, тож запиши дані в комірки.';
  @override
  String get fillLesson2a => 'Кхе, кхе... Я допоможу зі ';
  @override
  String get fillLesson2b => 'внесенням інформації';
  @override
  String get fillLesson2c => ' до твого вулика.';
  @override
  String get fillLesson3a => 'В тебе матка ';
  @override
  String lessonQueenColor(String v) =>
      const {'Білий': 'біла', 'Жовтий': 'жовта', 'Червоний': 'червона', 'Зелений': 'зелена', 'Синій': 'синя'}[v] ?? v.toLowerCase();
  @override
  String get fillLesson4a => 'Оглянув сьогодні? Торкнись ';
  @override
  String get fillLesson4b => 'дати огляду';
  @override
  String get fillLesson4c => ' й обери «Сьогодні».';
  @override
  String get fillLesson5 => 'Збережи, бо я більше туди не полізу.';
  @override
  String get feedNeedQty => 'Підгодівля: вкажіть кількість';
  @override
  String feedOnlyInStock(String amount) => 'Підгодівля: на складі лише $amount';
  @override
  String fillWholeFrom0(String name) => '«$name»: введіть ціле число від 0';
  @override
  String fillNumber(String name) => '«$name»: введіть число';
  @override
  String get feedFromStock => 'Підгодівля зі складу';
  @override
  String get dontWriteOff => 'Не списувати';
  @override
  String stockItemHas(String name, String amount) => '$name (є $amount)';
  @override
  String howMuch(String unit) => 'Скільки, $unit';
  @override
  String get chooseDate => 'Обрати дату';
  @override
  String get choose => 'Обрати';
  @override
  String get noteOptional => 'Необов\'язково: що помітили';

  // ---- Конструктор шаблону ----
  @override
  String get templateNew => 'Новий шаблон';
  @override
  String get drawType => 'Тип для малювання';
  @override
  String get templateAddCell => 'Додайте хоча б одну клітинку';
  @override
  String get templateName => 'Назва шаблону';
  @override
  String get templateApplyTitle => 'Застосувати до вуликів?';
  @override
  String templateApplyText(String name, int n) =>
      'З шаблону «$name» уже поставлено вуликів: $n. Застосувати до них новий набір характеристик? Історія значень збережеться.';
  @override
  String get apply => 'Застосувати';
  @override
  String get dontChange => 'Не змінювати';
  @override
  String get templateLeaveText => 'Зміни в шаблоні буде втрачено.';
  @override
  String templateAdding(String what) => 'Додаємо: $what   ·   торкніться клітинки, щоб прибрати';
  @override
  String get templateDragHint => 'Перетягніть, щоб перемістити · над ним - поворот і видалення';
  @override
  String get templateMoveHint =>
      'Переміщення: візьміть екземпляр пальцем і тягніть (стрілки - лише підказка)';
  @override
  String get templateInfoRight => 'Інформація про екземпляр - справа';
  @override
  String get templateTapItem => 'Торкніться екземпляра, щоб побачити інформацію';
  @override
  String get finishMoving => 'Завершити переміщення';
  @override
  String get moving => 'Переміщення';

  // ---- Чек на склад ----
  @override
  String get receiptNoRowsAdd =>
      'Не вдалося розпізнати позиції. Спробуйте сфотографувати рівніше й при гарному світлі або додайте рядки вручну.';
  @override
  String get receiptCheckTable => 'Перевірте таблицю: розпізнавання може помилятися.';
  @override
  String get receiptFailedAdd => 'Не вдалося розпізнати чек. Додайте рядки вручну.';
  @override
  String get listCopied => 'Список скопійовано';
  @override
  String get receiptNothingChecked => 'Немає позицій для запису: позначте хоча б одну.';
  @override
  String receiptBadRows(int n) =>
      'У ${n == 1 ? 'одному рядку' : '$n рядках'} не вистачає назви, кількості (більше 0) або ціни. Виправте їх чи зніміть галочку.';
  @override
  String receiptAdded(int n, int created, int topped) =>
      'Додано на склад: $n (нових - $created, поповнено - $topped)';
  @override
  String get receiptTitle => 'Чек';
  @override
  String get addRowButton => '+ Додати рядок';
  @override
  String get totalColon => 'Разом: ';
  @override
  String get copyList => 'Копіювати список';
  @override
  String get addToStock => 'Додати на склад';

  // ---- Відгук ----
  @override
  String get feedbackIntro =>
      'Бажаєте поділитись чимось цінним, запропонувати ідею чи поскаржитися на проблеми з додатком? Напишіть, для нас це цінно.';
  @override
  String get feedbackTooShort => 'Напишіть хоча б кілька слів';
  @override
  String get feedbackThanks => 'Дякуємо! Ваше повідомлення надіслано.';
  @override
  String get feedbackNotConfigured =>
      'Надсилання відгуків ще не налаштовано в цій версії застосунку.';
  @override
  String get feedbackSendFailed =>
      'Не вдалося надіслати. Перевірте інтернет і спробуйте ще раз.';
  @override
  String get notSent => 'Не надіслано';
  @override
  String feedbackCopyHint(String reason, bool notConfigured, String email) =>
      '$reason\n\n${notConfigured ? 'Скопіюйте' : 'Або скопіюйте'} текст і надішліть його на $email';
  @override
  String get copyAction => 'Скопіювати';
  @override
  String feedbackTo(String email, String text) => 'Кому: $email\n\n$text';
  @override
  String get feedbackCopied => 'Текст і адресу скопійовано';
  @override
  String get yourMessage => 'Ваше повідомлення…';
  @override
  String get sending => 'Надсилаємо…';
  @override
  String get send => 'Надіслати';
  @override
  String get feedbackChatHint =>
      'Розробник відповість тут - ви побачите значок на вулику-поштоматі й отримаєте сповіщення.';
  @override
  String get developer => 'Розробник';
  @override
  String get waitingInternet => 'чекає на інтернет';

  // ---- Навчання (екран) ----
  @override
  String get lessonResumeAsk =>
      'Ти вже починав цей урок. Продовжити з місця, де зупинився, чи почати спочатку?';
  @override
  String get fromStart => 'Спочатку';
  @override
  String get lessonSoon => 'Цей урок ще готується - скоро з\'явиться.';
  @override
  String get lessonBasics => 'Базові поняття';
  @override
  String get soon => 'скоро';

  // ---- Вхід ----
  @override
  String get signingIn => 'Входимо…';
  @override
  String get signInGoogle => 'Увійти через Google';
  @override
  String get continueNoSignIn => 'Продовжити без входу';
  @override
  String get noSignInHint =>
      'Без входу дані зберігаються лише на цьому пристрої. Увійти й синхронізувати їх можна пізніше на головному екрані - нічого не загубиться.';

  // ---- Що нового ----
  @override
  String whatsNewVersion(String v) => 'Що нового · $v';
  @override
  String whatsNewMore(int n) => 'Ще: $n змін і виправлення помилок';
  @override
  String get fixed => 'Виправлено';
  @override
  String get toWork => 'До роботи';

  // ---- Нова пасіка ----
  @override
  String get enterApiaryName => 'Введіть назву пасіки';
  @override
  String get newApiary => 'Нова пасіка';
  @override
  String get apiaryName => 'Назва пасіки';

  // ---- Уроки ----
  @override
  String get lessonParamFallback => 'параметр';
  @override
  String get lp1a => 'Друже, вітаю тебе. Хочеш більше дізнатись про обходи вуликів? Ти вчасно, ';
  @override
  String get lp1b => 'натисни на вулик';
  @override
  String get lp2a => 'Як бачиш - геть не густо. Додаймо нові ';
  @override
  String get lp2b => 'параметри';
  @override
  String get lp3a =>
      'В цьому меню ти можеш створювати параметри й додавати їх до таблиці. Натисни на ';
  @override
  String get lp3b => '«Створити параметр»';
  @override
  String get lp4 =>
      'Тут ти можеш назвати свій параметр, вказати його тип даних та за потреби одиниці виміру';
  @override
  String get lp5a => 'Створи свій параметр. Май на увазі, ';
  @override
  String get lp5b => 'назва та тип даних';
  @override
  String get lp5c => ' - обов\'язково вказуємо.';
  @override
  String get lp6a => 'Не забудь ';
  @override
  String get lp6b => 'зберегти';
  @override
  String get lp7a => 'Молодець. ';
  @override
  String get lp7b => ' вже додано до конструктора таблиці. Відкрий його';
  @override
  String get lp8a => 'Боже, який безлад! Швиденько створи ';
  @override
  String get lp8b => 'нову групу';
  @override
  String get lp9a => 'Назви її ';
  @override
  String get lp9b => ' та збережи свій прогрес!';
  @override
  String get lp10a => 'Перетягни ';
  @override
  String get lp10b => ' та ';
  @override
  String get lp10c => ' до нової групи';
  @override
  String get lp11 =>
      'За потреби можна застосувати зміни як лише до 1 вулика, так і до всіх загалом';
  @override
  String get lp12a => 'Бачив, ми не все використали? ';
  @override
  String get lp12b => 'Вимкни все зайве';
  @override
  String get lp13a => 'Повернімось до ';
  @override
  String get lp13b => 'вулика';
  @override
  String get lp14 => 'Ого! Глянь на таблицю — вона ідеальна!';
  @override
  String get lessonTemplateFallback => 'шаблон';
  @override
  String get lt1 =>
      'Друже, це знову ти! Мені подобається твоя жага до знань. Сьогодні навчимося створювати шаблони - заготовки вуликів і перешкод, які потім ставиш на карту.';
  @override
  String get lt2a => 'Шаблони живуть у ';
  @override
  String get lt2b => ' - вони в меню ☰ (три смужки). Зараз відкрию їх для тебе.';
  @override
  String get lt3a => 'Це вкладка ';
  @override
  String get lt3b => ' - тут загальні налаштування застосунку.';
  @override
  String get lt4a => 'Те, що треба! Натисни ';
  @override
  String get templateCreateQuoted => '«Створити шаблон»';
  @override
  String get lt5 => 'Час малювати! Натисни ';
  @override
  String get lt6a => 'Тут обираєш, що малювати. Вулики - одразу тут, а до перешкод ';
  @override
  String get lt6b => 'свайпни картку вліво';
  @override
  String get lt7a => 'Обери будь-яку ';
  @override
  String get lt7b => 'перешкоду';
  @override
  String get lt8a => 'Тепер ';
  @override
  String get lt8b => 'торкнись поля';
  @override
  String get lt8c => ' - постав одну плитку перешкоди';
  @override
  String get lt9a => 'Постав поруч ще ';
  @override
  String get lt9b => '3 плитки';
  @override
  String get lt9c => ' - заповни квадрат';
  @override
  String get lt10a => 'Чудово! Щоб закінчити малювання, натисни ';
  @override
  String get lt10b => 'червоний хрестик';
  @override
  String get lt11a => 'Перешкоду можна пересунути. Увімкни ';
  @override
  String get lt11b => 'переміщення';
  @override
  String get lt12a => 'Стрілки навколо - лише підказка, натискати їх не треба. ';
  @override
  String get lt12b => 'Візьми перешкоду пальцем і перетягни';
  @override
  String get lt13a => 'Готово! Тепер ';
  @override
  String get lt13b => 'збережи';
  @override
  String get lt13c => ' шаблон';
  @override
  String get lt14a => 'Дай шаблону назву і ';
  @override
  String get lt14b => ' його';
  @override
  String get lt15a => 'Вау, швидко вчишся! Шаблон ';
  @override
  String get lt15b => ' вже у твоїх шаблонах - розміщуй його на карті сам.';
  @override
  String get lessonParamsTitle => 'Групи і параметри обходу';

  // ---- Типи даних і дані ----
  @override
  List<String> get dataTypeLabels =>
      const ['Текст', 'Ціле число', 'Дробове число', 'Дата', 'Так / Ні', 'Список', 'Колір'];
  @override
  String get qrThisCode => 'цей код';
  @override
  String qrNumberShort(String n) => '№ $n';
  @override
  String qrWasUnlinked(String label) =>
      '$label був прив\'язаний раніше, але зараз знятий (наліпку перевидано чи прив\'язку скасовано).';
  @override
  String qrHiveDeleted(String label) => '$label прив\'язаний до вулика, якого вже видалено.';
  @override
  String qrHiveArchived(String label) => '$label прив\'язаний до вулика в архіві.';
  @override
  String qrNoApiary(String label) => '$label прив\'язаний до об\'єкта без пасіки.';
  @override
  String qrApiaryDeleted(String label) => '$label прив\'язаний до вулика видаленої пасіки.';
  @override
  String qrCannotOpen(String label) => '$label прив\'язаний, але вулик не вдалося відкрити.';
  @override
  String get deletedGroup => 'Видалена група';
  @override
  String get deletedObject => 'Видалений об\'єкт';
  @override
  String hiveN(int n) => 'Вулик $n';
  @override
  String get stockItemNotFound => 'Номенклатуру не знайдено';
  @override
  String get cancelCannotBeCancelled => 'Скасування не можна скасувати';
  @override
  String get overwrittenCannotBeCancelled => 'Старий запис «перезаписано» не можна скасувати';
  @override
  String cannotCancelPartlyWrittenOff(String left) =>
      'Не можна скасувати: частину вже списано (залишок: $left)';
  @override
  String cannotWriteOffMore(String left) =>
      'Не можна списати більше, ніж є на складі (залишок: $left)';

  // ---- Звіт, налаштування пасіки, календар, уроки ----
  @override
  String apiaryReportOf(String name) => 'Звіт по пасіці «$name»';
  @override
  String get apiaryReportHint => 'Excel: останні значення всіх вуликів і вся історія записів';
  @override
  String get apiaryReportEmpty => 'На цій пасіці ще немає вуликів - звіт порожній.';
  @override
  String get roundEvery => 'Обходити кожні … днів';
  @override
  String get roundEveryHint => 'порожньо - без нагадувань';
  @override
  String get roundEveryNote =>
      'Діє для всіх вуликів пасіки. Вулику можна задати іншу у формі «Оглянути».';
  @override
  List<String> get weekdaysShort => const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];
  @override
  String get chooseDateTitle => 'Оберіть дату';
  @override
  String get finishTutorialLower => 'завершити навчання';
  @override
  String get finish => 'Завершити';
  @override
  String get postbox => 'Вулик-поштомат';
  @override
  String postboxN(int n) => 'Вулик-поштомат: повідомлень $n';
  @override
  String get textTypeIcon => 'Аа';
  @override
  String get optionAddHint => 'Додати варіант (наприклад, «Сильна»)';
  @override
  String get optionAdd => 'Додати варіант';

  // ---- Сповіщення ----
  @override
  String get remindersChannel => 'Нагадування про обхід';
  @override
  String get remindersChannelText =>
      'Нагадує оглянути вулики за заданою періодичністю: вранці і, якщо обхід не зроблено, о 14:00';
  @override
  String get feedbackChannel => 'Відповіді розробника';
  @override
  String get feedbackChannelText => 'Відповідь на ваш відгук у застосунку';
  @override
  String get reminder => 'Нагадування';
  @override
  String hiveListMore(String names, int n) => '$names і ще $n';
  @override
  String roundInspect(int n, String list) =>
      'Оглянути $n ${plural(n, one: 'вулик', few: 'вулики', many: 'вуликів')}: $list';
  @override
  String roundLeft(int n, String list) =>
      'Лишилось оглянути $n ${plural(n, one: 'вулик', few: 'вулики', many: 'вуликів')}: $list';

  // ---- Склад: назви операцій ----
  @override
  String get moveOut => 'Списано';
  @override
  String moveOutReason(String reason) => 'Списано: $reason';
  @override
  String get moveInvShort => 'Переоблік: нестача';
  @override
  String get moveInvOver => 'Переоблік: надлишок';
  @override
  String get moveInvSame => 'Переоблік: без розбіжностей';
  @override
  String get moveCancel => 'Скасування запису';
  @override
  String get moveSet => 'Перезаписано (старий запис)';

  // ---- Файли й Excel ----
  @override
  String fileBuildFailed(String details) => 'Не вдалось сформувати файл:\n$details';
  @override
  String get saveHistory => 'Зберегти історію';
  @override
  String get saveCancelled => 'Збереження скасовано.';
  @override
  String savedAt(String path) => 'Збережено:\n$path';
  @override
  String get saved => 'Збережено.';
  @override
  String savedFallback(String path) =>
      'Не вдалось відкрити діалог збереження - файл збережено тут:\n$path';
  @override
  String fileSaveFailed(String details) => 'Не вдалось зберегти файл:\n$details';
  @override
  String get saveReport => 'Зберегти звіт';
  @override
  String shareFailed(String details) => 'Не вдалось поділитися файлом:\n$details';
  @override
  String get sheetLatest => 'Останні значення';
  @override
  String get dateTime => 'Дата й час';
  @override
  String get parameter => 'Параметр';
  @override
  String get value => 'Значення';
  @override
  String get objectOrGroup => 'Об\'єкт / група';
  @override
  String get saveLabels => 'Зберегти наліпки';
  @override
  String get hiveQrCodes => 'QR-коди вуликів';

  // ---- Помилки зв'язку й копій ----
  @override
  String get errNoServer => 'немає зв\'язку із сервером';
  @override
  String errNoServerDetails(String d) => 'немає зв\'язку із сервером ($d)';
  @override
  String get errServerNoAnswer => 'сервер не відповідає';
  @override
  String get errTls => 'не вдалося встановити захищене з\'єднання';
  @override
  String errServerBusy(int s) => 'сервер тимчасово недоступний ($s)';
  @override
  String errServerRejected(int s, String m) => 'сервер відхилив ($s): $m';
  @override
  String get errSignInAgain => 'потрібно знову увійти';
  @override
  String get errOtherAccount => 'на телефоні дані іншого акаунта Google';
  @override
  String get errNeedsChoice => 'чекає вашого вибору: що робити з даними телефона й сервера';
  @override
  String get errNoServerLater => 'немає зв\'язку із сервером - спробуйте пізніше';
  @override
  String get errSyncRunning => 'саме йде синхронізація - спробуйте за хвилину';
  @override
  String errBackupTooBig(int mb) => 'копія завелика для сервера ($mb МБ)';
  @override
  String get errBackupArrivedBroken => 'копія дійшла пошкодженою - спробуйте ще раз';
  @override
  String get errBackupBrokenNotSaved => 'копія пошкоджена - не збережено';
  @override
  String get errSnapshotBroken => 'знімок бази пошкоджений';
  @override
  String get errInMemory => 'база в пам\'яті - копіювати нічого';
  @override
  String get errBackupBroken => 'копія пошкоджена';
  @override
  String get errBackupGone => 'копії вже немає';
  @override
  String get errLoginServerOdd => 'сервер входу повернув незрозумілу відповідь';
  @override
  String get errGoogleNotConfigured => 'Вхід через Google не налаштовано в цій збірці';
  @override
  String get errServerNotConfigured => 'Сервер не налаштовано в цій збірці';

  // ---- Помічник: підказки, картки ----
  @override
  String get assistantReplyLanguageHint => '';
  @override
  String get assistantWhatCanYouDo => 'Що ти вмієш?';
  @override
  String get sugSpentMonth => 'Скільки я витратив цього місяця?';
  @override
  String get sugAddExpense => 'Додай витрату';
  @override
  String get sugLowStock => 'Чого мало на складі?';
  @override
  String get sugAddSugar => 'Додай прихід цукру';
  @override
  String get sugDueHives => 'Які вулики треба оглянути?';
  @override
  String get sugHowManyHives => 'Скільки в мене вуликів?';
  @override
  String get sugLastRecord => 'Що я записував останнім?';
  @override
  String get sugOpenStock => 'Відкрий склад';
  @override
  String get assistantDemoReply => 'Поки що демо-режим: сервер помічника не підключено.';
  @override
  String get assistantLimitText =>
      'Не вийшло відповісти за кілька кроків. Спитайте, будь ласка, простіше.';
  @override
  Map<String, String> get screenLabels =>
      const {'finance': 'Фінанси', 'finance_add': 'Новий запис', 'stock': 'Склад', 'apiaries': 'Мої пасіки', 'history': 'Історія', 'parameters': 'Параметри', 'templates': 'Шаблони', 'settings': 'Налаштування', 'helpers': 'Помічники', 'backups': 'Резервні копії', 'receipt': 'Чек', 'lessons': 'Навчання', 'lesson': 'Навчання', 'feedback': 'Відгук'};
  @override
  String mapOf(String name) => 'Карта: $name';
  @override
  String cardInspection(String hive, String apiary) => 'Огляд: $hive ($apiary)';
  @override
  String cardInspectionUndo(String hive) => 'Огляд: $hive';
  @override
  String get visitDate => 'Дата обходу';
  @override
  String cardStockMove(bool receive, String name) => '${receive ? 'Прихід' : 'Списання'}: $name';
  @override
  String quantityIn(String unit) => 'Кількість ($unit)';
  @override
  String get sumUah => 'Сума, грн';
  @override
  String get comment => 'Коментар';
  @override
  String cardNewStockItem(String name) => 'Прихід: $name (нова позиція складу)';
  @override
  String cardStockIn(String name) => 'Прихід: $name';
  @override
  String get expense => 'Витрата';
  @override
  String finUndo(bool income, String amount) => '${income ? 'Дохід' : 'Витрата'} $amount грн';
  @override
  String get text => 'Текст';
  @override
  String get when => 'Коли';

  // Злиття main: прив'язка наліпок підряд, обхід, фінанси
  @override
  String finCancelText(String name, String amount, String date) =>
      '«$name» $amount від $date буде позначено як скасований '
      'і не рахуватиметься в підсумках. Запис лишиться в історії.';
  @override
  String get bindPickHint =>
      'Торкніться вулика, щоб обрати або зняти вибір';
  @override
  String roundSkipped(String name) =>
      '«$name» пропущено';
  @override
  String roundNoChange(String name, int done) =>
      '«$name»: змін немає · оглянуто $done';
  @override
  String roundSaved(String name, int done) =>
      '«$name» збережено · оглянуто $done';
  @override
  String inspectionSaved(String name) =>
      'Огляд «$name» збережено';
  @override
  String inspectionSavedCount(String name, int done) =>
      'Огляд «$name» збережено. Оглянуто: $done';
  @override
  String get feedNotReturned =>
      'Підгодівлю не повернуто';
  @override
  String get inspectionUndone =>
      'Огляд відмінено';
  @override
  String get hiveHasQr =>
      'У цього вулика вже є QR-код';
  @override
  String get bindLabels =>
      'Прив\'язати наліпки';
  @override
  String get bindAllLinked =>
      'Усе прив\'язано';
  @override
  String bindLinkedCount(int n) =>
      'Прив\'язано наліпок: $n';
  @override
  String bindAllDone(int n) =>
      'Прив\'язано наліпок: $n. Усі обрані вулики мають QR-коди.';
  @override
  String bindPartly(int linked, int skipped, int left) =>
      'Прив\'язано: $linked\nПропущено: $skipped\nЛишилось: $left\n\n'
      'Усе збережено. Продовжити можна зараз або пізніше: «Прив\'язати підряд» '
      'покаже лише вулики без коду.';
  @override
  String bindBarCount(int noCode, int chosen) =>
      'Без коду: $noCode · обрано: $chosen';
  @override
  String get bindDeselect =>
      'Зняти вибір';
  @override
  String get bindSelectAll =>
      'Обрати всі без коду';
  @override
  String scanCount(int n) =>
      'Сканувати ($n)';
  @override
  String bindLinked(String name) =>
      'Прив\'язано: $name';
  @override
  String bindWithoutLabel(int n) =>
      'Без наліпки: $n';
  @override
  String get bindSearch =>
      'Пошук за назвою або номером';
  @override
  String get bindNow =>
      'зараз';
  @override
  String get bindSkippedMark =>
      'пропущено';
  @override
  String bindProgress(int done, int n, int linked, int skipped) =>
      '$done з $n · прив\'язано $linked · пропущено $skipped';
  @override
  String bindLabelFor(String name) =>
      'Наліпка для: $name';
  @override
  String get bindPrevHive =>
      'Попередній вулик';
  @override
  String get bindNextHive =>
      'Наступний вулик';
  @override
  String get bindAimHint =>
      'Наведіть камеру на наліпку цього вулика';
  @override
  String get bindList =>
      '☰ Список';
}
