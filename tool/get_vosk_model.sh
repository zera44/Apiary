#!/usr/bin/env bash
# Скачати українську модель Vosk у assets/vosk/model.zip (для збірки APK).
set -euo pipefail
MODEL="${VOSK_MODEL:-vosk-model-small-uk-v3-small}"
cd "$(dirname "$0")/.."
out=assets/vosk/model.zip
if [ -s "$out" ]; then echo "вже є: $out"; exit 0; fi
curl -fL --retry 5 --retry-delay 5 -o "$out.part" "https://alphacephei.com/vosk/models/$MODEL.zip"
unzip -tq "$out.part" >/dev/null
mv "$out.part" "$out"
ls -l "$out"
