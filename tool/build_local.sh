#!/usr/bin/env bash
# Зібрати тестовий APK на своєму комп'ютері - ті самі кроки, що в CI
# (.github/workflows/build.yml), без GitHub Actions.
#
# Потрібно: Flutter 3.47.5, Android Studio (Android SDK) і bash.
# Ключі - у файлі tool/local.env (його немає в git):
#
#   SUPABASE_URL=https://<ref>.supabase.co
#   SUPABASE_ANON_KEY=sb_publishable_...
#   GOOGLE_SERVER_CLIENT_ID=....apps.googleusercontent.com
#   FEEDBACK_URL=            # необов'язково
#
# Запуск (з кореня проєкту):  bash tool/build_local.sh
# Готовий файл: build/app/outputs/flutter-apk/app-release.apk
#
# APK підписано тим самим тестовим ключем, що й збірки гілок у CI, тож він
# встановлюється поверх тестової збірки (дані лишаються).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f tool/local.env ]; then
  set -a
  # shellcheck disable=SC1091
  . tool/local.env
  set +a
fi
SUPABASE_URL=${SUPABASE_URL:-}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}
GOOGLE_SERVER_CLIENT_ID=${GOOGLE_SERVER_CLIENT_ID:-}
FEEDBACK_URL=${FEEDBACK_URL:-}
[ -z "$SUPABASE_URL" ] && echo "! SUPABASE_URL не задано - синхронізація в APK буде вимкнена"
[ -z "$GOOGLE_SERVER_CLIENT_ID" ] && echo "! GOOGLE_SERVER_CLIENT_ID не задано - вхід через Google не працюватиме"

# pubspec тимчасово змінюється (див. нижче) - наприкінці повертаємо як був
cp pubspec.yaml /tmp/apiary-pubspec.yaml.bak 2>/dev/null || cp pubspec.yaml pubspec.yaml.bak
cp pubspec.lock /tmp/apiary-pubspec.lock.bak 2>/dev/null || cp pubspec.lock pubspec.lock.bak
restore() {
  if [ -f /tmp/apiary-pubspec.yaml.bak ]; then
    cp /tmp/apiary-pubspec.yaml.bak pubspec.yaml
    cp /tmp/apiary-pubspec.lock.bak pubspec.lock
  else
    mv -f pubspec.yaml.bak pubspec.yaml
    mv -f pubspec.lock.bak pubspec.lock
  fi
  flutter pub get >/dev/null 2>&1 || true
}
trap restore EXIT

echo "== Залежності"
flutter pub get --enforce-lockfile

echo "== Платформні файли Android"
flutter create --no-pub --platforms=android --org org.apiary --project-name apiary .
APIARY_SIGNING=1 dart run tool/patch_platforms.dart

echo "== Без власної SQLite в APK (на Android - системна)"
flutter pub remove sqlite3_flutter_libs
cat >> pubspec.yaml <<'EOF2'

hooks:
  user_defines:
    sqlite3:
      source: system
EOF2

echo "== Збірка APK (10-20 хвилин уперше)"
export APIARY_KEYSTORE_PATH="$PWD/tool/debug.keystore" APIARY_KEY_ALIAS=androiddebugkey
export APIARY_KEYSTORE_PASSWORD=android APIARY_KEY_PASSWORD=android
flutter build apk --release --target-platform android-arm,android-arm64 \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=APIARY_FEEDBACK_URL="$FEEDBACK_URL" \
  --dart-define=APIARY_GOOGLE_SERVER_CLIENT_ID="$GOOGLE_SERVER_CLIENT_ID" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo
echo "✓ Готово: build/app/outputs/flutter-apk/app-release.apk"
echo "  Скопіюйте на телефон і відкрийте (або: adb install -r build/app/outputs/flutter-apk/app-release.apk)"
