# Модель розпізнавання мови (Vosk)

Сюди кладеться `model.zip` - українська модель Vosk
(`vosk-model-small-uk-v3-small`, ~133 МБ, Apache-2.0). У git її немає
(GitHub не приймає файли понад 100 МБ): збірка на GitHub скачує її сама,
локально - `bash tool/get_vosk_model.sh`.

Без `model.zip` застосунок працює як раніше, лише без кнопки мікрофона.
Нова модель - змініть назву в `tool/get_vosk_model.sh` і `kVoskModelVersion`
у `lib/services/voice_input.dart`: на телефоні вона розпакується заново.
