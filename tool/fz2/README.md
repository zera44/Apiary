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

## Два етапи розмітки

Нечіткий висновок для чисел і для тексту (бази А і Б) виконується як один етап, чіткі
правила корекції чисел і тексту (К1-К33) - як другий. Тому нечіткий висновок для тексту
бере класи чисел до чітких правил (`role0` у `fz2.dart`). `coursework/fuzzy_v2/fz2.py`
(курсова) не змінювався: щоб еталон збігався з Dart, застосуйте до його копії
`stages_5_7.patch` (`patch -p1 < /шлях/до/Apiary/tool/fz2/stages_5_7.patch`) і згенеруйте
еталон з цієї копії. На 130 чеках розробки й 14 контрольних класи не змінюються.
