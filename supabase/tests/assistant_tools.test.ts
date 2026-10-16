// Перевірка опису інструментів помічника (виконує їх застосунок:
// lib/assistant/assistant_tools.dart, тест test/assistant_tools_test.dart
// звіряє назви).
//
//   node --test supabase/tests/assistant_tools.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { READ_TOOLS, TOOLS, WRITE_TOOLS } from '../functions/assistant/tools.ts';
import { SCREENS } from '../functions/assistant/prompt.ts';
import { buildRequest } from '../functions/assistant/index.ts';

test('кожен інструмент - або читання, або запис; назви унікальні', () => {
  const names = TOOLS.map((t) => t.name);
  assert.equal(new Set(names).size, names.length);
  assert.deepEqual([...names].sort(), [...READ_TOOLS, ...WRITE_TOOLS].sort());
});

test('схеми - об\'єкти без зайвих полів, обов\'язкові поля описано', () => {
  for (const t of TOOLS) {
    const s = t.input_schema as { type: string; properties: Record<string, unknown>; required: string[]; additionalProperties: boolean };
    assert.equal(s.type, 'object', t.name);
    assert.equal(s.additionalProperties, false, t.name);
    for (const r of s.required) assert.ok(r in s.properties, `${t.name}.${r}`);
    assert.ok(t.description.length > 10, t.name);
  }
});

test('open_screen знає саме ті екрани, що описано в промпті', () => {
  const open = TOOLS.find((t) => t.name === 'open_screen')!;
  const screen = (open.input_schema as any).properties.screen;
  assert.deepEqual(screen.enum, [...SCREENS]);
});

test('інструменти запису кажуть про підтвердження', () => {
  for (const n of WRITE_TOOLS) {
    assert.match(TOOLS.find((t) => t.name === n)!.description, /підтверджує/, n);
  }
});

test('у запиті до моделі кеш - на останньому інструменті', () => {
  const b = buildRequest('m', [{ role: 'user', content: 'x' }], 'sys', TOOLS) as any;
  assert.equal(b.tools.length, TOOLS.length);
  assert.equal(b.tools.at(-1).cache_control.type, 'ephemeral');
  assert.equal(b.tools.filter((t: any) => t.cache_control).length, 1);
});
