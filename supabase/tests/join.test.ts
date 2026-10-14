// Перевірка функції join (запрошувальне посилання) без Supabase.
//
//   node --test supabase/tests/join.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handle, PACKAGE } from '../functions/join/index.ts';

const T = 'ab'.repeat(32);
const android = { 'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/129 Mobile' };
const get = (q: string, headers: Record<string, string> = android) =>
  handle(new Request(`https://x.supabase.co/functions/v1/join${q}`, { headers }), 'https://dl.example/apk');

test('Android - одразу у застосунок; немає застосунку - сторінка завантаження', () => {
  const r = get(`?t=${T}`);
  assert.equal(r.status, 302);
  const loc = r.headers.get('Location') ?? '';
  assert.ok(loc.startsWith(`intent://join?t=${T}#Intent;scheme=vulyk;package=${PACKAGE};`));
  assert.ok(loc.includes(`S.browser_fallback_url=${encodeURIComponent('https://dl.example/apk')}`));
  assert.ok(loc.endsWith(';end'));
});

test('інший пристрій - підказка текстом (не HTML)', async () => {
  const r = get(`?t=${T}`, { 'User-Agent': 'Mozilla/5.0 (iPhone)' });
  assert.equal(r.status, 200);
  assert.match(r.headers.get('Content-Type') ?? '', /^text\/plain/);
  assert.match(await r.text(), /Android/);
});

test('пошкоджений чи чужий код - без перенаправлення', () => {
  for (const q of ['', '?t=abc', `?t=${T}x`, `?t=${T.toUpperCase()}`, '?t=../../x', `?t=${T};end;S.x=1`]) {
    const r = get(q);
    assert.equal(r.status, 400, q);
    assert.equal(r.headers.get('Location'), null);
  }
  assert.equal(handle(new Request(`https://x/join?t=${T}`, { method: 'POST' })).status, 405);
});
