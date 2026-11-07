# Еталон для перевірки fz2 на Dart

`lib/logic/fz2/fz2.dart` - перенесення нечіткої розмітки `coursework/fuzzy_v2/fz2.py`.
Тест `test/fz2_test.dart` вимагає, щоб Dart давав ті самі класи, що й Python,
на кожному фрагменті розмічених чеків.

Тексти чеків у публічний репозиторій не кладуться, тому еталон генерується
окремо (Python 3, numpy, pandas):

    cd coursework/fuzzy_v2
    python3 /шлях/до/Apiary/tool/fz2/gen_fixture.py raw16.csv test_new/rawDr.csv /tmp/fz2_fixture.json
    cd /шлях/до/Apiary
    FZ2_FIXTURE=/tmp/fz2_fixture.json flutter test test/fz2_test.dart

Без `FZ2_FIXTURE` тест пропускається. Змінивши правила у fz2.py, перенесіть ту
саму зміну в fz2.dart і перегенеруйте еталон.
