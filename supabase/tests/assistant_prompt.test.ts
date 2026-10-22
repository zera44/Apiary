// Перевірка системного промпта помічника.
//
//   node --test supabase/tests/assistant_prompt.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BEAR_PROMPT, ROBOT_PROMPT, SCREENS, SYSTEM_PROMPT, systemPromptFor } from '../functions/assistant/prompt.ts';

test('описано кожен екран навігатора', () => {
  for (const s of SCREENS) {
    assert.match(SYSTEM_PROMPT, new RegExp(`^- ${s} - `, 'm'), s);
  }
  // і нічого зайвого: кожен описаний екран є в списку
  const described = [...SYSTEM_PROMPT.matchAll(/^- ([a-z_]+) - /gm)].map((m) => m[1]);
  assert.deepEqual([...described].sort(), [...SCREENS].sort());
});

test('характер і що робить', () => {
  for (const must of [
    'Пасічник', '1-4 речення', 'НІЧОГО не вигадуй', 'Записати так?', 'підтверджено', 'інструментом навігації',
  ]) {
    assert.ok(SYSTEM_PROMPT.includes(must), must);
  }
});

test('завжди українською; у записи - лише сказане; знає про «Скасувати»', () => {
  assert.match(SYSTEM_PROMPT, /Завжди українською/);
  assert.match(SYSTEM_PROMPT, /не вигадуй коментарів/);
  assert.match(SYSTEM_PROMPT, /\[Скасовано: …\]/);
});

test('шукає, як зробити, і розуміє з півслова', () => {
  assert.match(SYSTEM_PROMPT, /Шукай, як зробити, а не причину відмовити/);
  assert.match(SYSTEM_PROMPT, /«синя матка»/);
  assert.match(SYSTEM_PROMPT, /інструмент створить нову/);
});

test('поки немає книг - порад з бджільництва не дає', () => {
  assert.match(SYSTEM_PROMPT, /Порад з бджільництва .* поки НЕ даєш/);
  assert.match(SYSTEM_PROMPT, /порадник з'явиться згодом/);
  // жодних порад про лікування в самому промпті
  assert.doesNotMatch(SYSTEM_PROMPT, /ветеринар|дозуванн|акарицид/);
  // і на майбутнє: поради - лише з книг, із цитатою й джерелом
  assert.match(SYSTEM_PROMPT, /лише з них: кожна - з цитатою й джерелом/);
  assert.match(SYSTEM_PROMPT, /З власних знань порад не давай ніколи/);
});

test('рядок «[Екран: …]» - людина пише з цього екрана', () => {
  assert.match(SYSTEM_PROMPT, /\[Екран: …\]/);
  assert.match(SYSTEM_PROMPT, /Рядка немає - говоримо про весь застосунок/);
});

test('описано поняття застосунку', () => {
  for (const c of [
    'Пасіка', 'Карта пасіки', 'Вулик', 'Параметри', 'Групи параметрів', 'Огляд', 'Нотатки', 'Шаблони',
    'Склад', 'Фінанси', 'Історія', 'Сканер', 'Помічники', 'Навчання', 'поштомат',
  ]) {
    assert.ok(SYSTEM_PROMPT.includes(c), c);
  }
});

test('промпт незмінний між запитами (кешується): без дат і підстановок', () => {
  assert.doesNotMatch(SYSTEM_PROMPT, /\$\{|\{\{|\d{4}-\d{2}-\d{2}/);
  // достатньо довгий для кешу (від ~512 токенів) і не роздутий
  assert.ok(SYSTEM_PROMPT.length > 2500 && SYSTEM_PROMPT.length < 12000, String(SYSTEM_PROMPT.length));
});

test('два персонажі: Haiku - Ведмедик, Sonnet - Пасічник; решта промпту однакова', () => {
  assert.match(BEAR_PROMPT, /«Ведмедик»/);
  assert.doesNotMatch(BEAR_PROMPT, /Ти - «Пасічник»/);
  assert.equal(systemPromptFor('claude-haiku-5-5'), BEAR_PROMPT);
  assert.equal(systemPromptFor('claude-sonnet-5-5'), SYSTEM_PROMPT);
  assert.equal(systemPromptFor('claude-opus-5-5'), ROBOT_PROMPT);
  assert.match(ROBOT_PROMPT, /«Робопасічник», робот-помічник/);
  const tail = (p: string) => p.slice(p.indexOf('# Як відповідати'));
  assert.equal(tail(BEAR_PROMPT), tail(SYSTEM_PROMPT));
  assert.equal(tail(ROBOT_PROMPT), tail(SYSTEM_PROMPT));
});

test('словник мови застосунку, посилання, двоє помічників', () => {
  for (const term of [
    '«Характеристики»', '«Оглянути»', '«Робочий режим»', '«Редагування»', '«Номенклатура»',
    '«Внесено на складі»', '«Перешкоди»', '«кр код»',
  ]) {
    assert.ok(SYSTEM_PROMPT.includes(term), term);
  }
  assert.match(SYSTEM_PROMPT, /\[склад\]\(stock\)/);
  assert.match(SYSTEM_PROMPT, /\(hive:id вулика\)/);
  assert.match(SYSTEM_PROMPT, /# Помічники/);
  assert.match(SYSTEM_PROMPT, /Пасічник передає Ведмедику/);
  assert.match(SYSTEM_PROMPT, /не вибачайся/);
  // у промпті Ведмедика - те саме, лише ім'я інше
  assert.ok(BEAR_PROMPT.includes('# Мова застосунку (словник)'));
});
