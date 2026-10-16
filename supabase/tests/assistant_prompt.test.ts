// Перевірка системного промпта помічника.
//
//   node --test supabase/tests/assistant_prompt.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { SCREENS, SYSTEM_PROMPT } from '../functions/assistant/prompt.ts';

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

test('поки немає книг - порад з бджільництва не дає', () => {
  assert.match(SYSTEM_PROMPT, /Порад з бджільництва .* поки НЕ даєш/);
  assert.match(SYSTEM_PROMPT, /порадник з'явиться згодом/);
  // жодних порад про лікування в самому промпті
  assert.doesNotMatch(SYSTEM_PROMPT, /ветеринар|дозуванн|акарицид/);
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
