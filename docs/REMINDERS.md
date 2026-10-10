# Нагадування

Те, до чого ми домовились повернутися. Нагадувати в кінці кожного етапу
підготовки до синхронізації (Supabase).

## 1. Щоденна копія бази з сервера в приватне сховище

Безкоштовний Supabase сам копій бази не робить. Нічні копії, які шле телефон
(етап 5), лежать на тому ж сервері. Тож якщо зникне сам проєкт Supabase,
зникнуть і вони. Потрібна щоденна копія всієї серверної бази в окреме
приватне сховище. **Повернутися пізніше.**

## 2. Ключі Google для входу — частково

Зроблено: Web client ID створено й додано в секрет GitHub
`APIARY_GOOGLE_SERVER_CLIENT_ID` (10.10.2026). Лишилось: Android-клієнти
(п. 2 нижче) і провайдер Google у Supabase (`supabase/README.md`, крок 4).

Без них вхід, а отже й синхронізація, не запрацюють. Що зробити (один раз):

1. [Google Cloud Console](https://console.cloud.google.com) → створити
   проєкт → «APIs & Services» → «OAuth consent screen»: тип External, назва
   Vulyk, пошта підтримки. Поки застосунок не опубліковано, додати свою
   пошту в «Test users».
2. «Credentials» → «Create credentials» → «OAuth client ID»:
   * **Web application**. Його *Client ID* стане секретом
     `APIARY_GOOGLE_SERVER_CLIENT_ID`. Цей самий *Client ID* і *Client
     secret* треба вставити в Supabase: Authentication → Providers →
     Google (у кожному з двох проєктів, тестовому й робочому).
   * **Android**, по одному на кожен ключ підпису, пакет
     `org.apiary.apiary`:
     * тимчасовий ключ тестових збірок (`tool/debug.keystore`), SHA-1
       `0D:E8:20:13:CC:D7:E3:22:EF:FE:AE:A4:BD:90:6B:D8:52:AB:2B:B7`;
     * робочий ключ (яким підписується реліз з `main`). Його SHA-1 покаже
       `keytool -list -v -keystore <файл-ключа>` або Play Console →
       «Цілісність застосунку».
3. GitHub → Settings → Secrets and variables → Actions → секрет
   `APIARY_GOOGLE_SERVER_CLIENT_ID` (Web client ID).

## 3. Текст політики конфіденційності кількома мовами

Зараз кнопка «Політика конфіденційності» — заглушка (етап 7). Текст буде
пізніше, мовою застосунку (планується кілька мов). Що в ньому описати:
вхід Google (id і пошта), дані й фото на сервері Supabase, нічні копії,
відгуки через Formspree (текст і версія системи), завантаження мовної
моделі для голосового вводу, контакт myapiaryrezvin@gmail.com.
