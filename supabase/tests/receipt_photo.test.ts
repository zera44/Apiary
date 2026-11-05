// Перевірка функції receipt-photo без Supabase: сховище в пам'яті.
//
//   node --test supabase/tests/receipt_photo.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { type Deps, DAILY_LIMIT, handle, MAX_BYTES, MemoryStore } from '../functions/receipt-photo/index.ts';

const DEVICE = '3f2c1a9e-8b4d-4c11-9a52-0d6e7b8c9f10';

function jpeg(size = 5000, seed = 1): Uint8Array {
  const b = new Uint8Array(size);
  b[0] = 0xff; b[1] = 0xd8; b[2] = 0xff;
  for (let i = 3; i < size; i++) b[i] = (i * seed) & 255;
  return b;
}
const b64 = (b: Uint8Array) => Buffer.from(b).toString('base64');

function setup() {
  const now = Date.parse('2026-11-05T12:00:00Z');
  const store = new MemoryStore();
  const logs: string[] = [];
  const deps: Deps = { store, log: (l) => logs.push(l), now: () => now };
  return { store, logs, deps };
}
const post = (body: unknown) =>
  new Request('https://x/functions/v1/receipt-photo', { method: 'POST', body: JSON.stringify(body) });

test('знімок зберігається під device_id і датою', async () => {
  const { deps, store, logs } = setup();
  const r = await handle(post({ device_id: DEVICE, photo_b64: b64(jpeg()) }), deps);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).duplicate, false);
  const [path] = [...store.files.keys()];
  assert.match(path, new RegExp(`^${DEVICE}/20261105-[0-9a-f]{24}\\.jpg$`));
  assert.ok(!logs.join('').includes('photo_b64'));
});

test('той самий знімок удруге - дубль, не зберігається', async () => {
  const { deps, store } = setup();
  const body = { device_id: DEVICE, photo_b64: b64(jpeg()) };
  await handle(post(body), deps);
  const r = await handle(post(body), deps);
  assert.equal((await r.json()).duplicate, true);
  assert.equal(store.files.size, 1);
});

test('не JPEG, завеликий і чужий формат device_id відхиляються', async () => {
  const { deps } = setup();
  const png = jpeg(); png[0] = 0x89;
  assert.equal((await handle(post({ device_id: DEVICE, photo_b64: b64(png) }), deps)).status, 415);
  assert.equal((await handle(post({ device_id: DEVICE, photo_b64: b64(jpeg(MAX_BYTES + 1)) }), deps)).status, 413);
  assert.equal((await handle(post({ device_id: 'x', photo_b64: b64(jpeg()) }), deps)).status, 400);
  assert.equal((await handle(post({ device_id: DEVICE, photo_b64: '!!!' }), deps)).status, 400);
});

test('добовий ліміт від одного встановлення', async () => {
  const { deps } = setup();
  for (let i = 0; i < DAILY_LIMIT; i++) {
    const r = await handle(post({ device_id: DEVICE, photo_b64: b64(jpeg(5000 + i, i + 2)) }), deps);
    assert.equal(r.status, 200);
  }
  const r = await handle(post({ device_id: DEVICE, photo_b64: b64(jpeg(9000, 99)) }), deps);
  assert.equal(r.status, 429);
});
