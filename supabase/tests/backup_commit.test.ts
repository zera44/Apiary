// Перевірка функції backup-commit без Supabase: справжня база SQLite,
// gzip і фейковий сервер (вхід, таблиця device_backups, сховище файлів).
//
//   node --test supabase/tests/backup_commit.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { gzipSync } from 'node:zlib';

import { checkBackup, handle, toPrune, type BackupRow } from '../functions/backup-commit/index.ts';

/** Справжня база SQLite, як копія з телефона. */
function sqliteBytes(rows = 50): Uint8Array {
  const dir = mkdtempSync(join(tmpdir(), 'vulyk-bk-'));
  try {
    const path = join(dir, 'apiary.db');
    const db = new DatabaseSync(path);
    db.exec('CREATE TABLE apiaries (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
    const ins = db.prepare('INSERT INTO apiaries VALUES (?, ?)');
    for (let i = 0; i < rows; i++) ins.run(`a${i}`, 'Пасіка '.repeat(20) + i);
    db.close();
    return new Uint8Array(readFileSync(path));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const sha = (b: Uint8Array) => createHash('sha256').update(b).digest('hex');
const gz = (b: Uint8Array) => new Uint8Array(gzipSync(b));

test('ціла копія проходить', async () => {
  const db = sqliteBytes();
  const file = gz(db);
  const r = await checkBackup(file, file.length, sha(file));
  assert.deepEqual(r, { ok: true, dbSize: db.length });
});

test('зіпсовані копії не проходять', async () => {
  const db = sqliteBytes();
  const file = gz(db);
  // інший розмір чи хеш (файл пошкодили дорогою)
  assert.equal((await checkBackup(file, file.length + 1, sha(file))).ok, false);
  assert.equal((await checkBackup(file, file.length, sha(gz(sqliteBytes(3))))).ok, false);
  // обрізаний gzip
  const cut = file.subarray(0, file.length - 20);
  const r1 = await checkBackup(cut, cut.length, sha(cut));
  assert.equal(r1.ok, false);
  // обрізана база всередині цілого gzip
  const half = gz(db.subarray(0, db.length - 4096));
  const r2 = await checkBackup(half, half.length, sha(half));
  assert.equal(r2.ok, false);
  // не база взагалі
  const text = gz(new TextEncoder().encode('не база '.repeat(100)));
  const r3 = await checkBackup(text, text.length, sha(text));
  assert.deepEqual(r3.ok ? null : r3.reason, 'усередині не база SQLite');
  // не gzip
  const plain = db;
  assert.equal((await checkBackup(plain, plain.length, sha(plain))).ok, false);
});

test('прибирання: 2 найновіші цілі; зіпсовані й давні недовантажені - геть', () => {
  const now = Date.parse('2026-10-10T03:00:00Z');
  const row = (id: string, status: string, at: string): BackupRow => ({ id, path: `u/${id}.db.gz`, status, created_at: at });
  const rows = [
    row('ok-1', 'ok', '2026-10-07T01:00:00Z'),
    row('ok-2', 'ok', '2026-10-08T01:00:00Z'),
    row('ok-3', 'ok', '2026-10-09T01:00:00Z'),
    row('bad', 'bad', '2026-10-09T02:00:00Z'),
    row('up-old', 'uploading', '2026-10-08T00:00:00Z'),
    row('up-new', 'uploading', '2026-10-10T02:59:00Z'),
  ];
  assert.deepEqual(toPrune(rows, now).map((r) => r.id).sort(), ['bad', 'ok-1', 'up-old']);
  // поки цілих лише дві - жодну не чіпаємо
  assert.deepEqual(toPrune(rows.slice(1, 3), now), []);
});

// ── фейковий сервер ─────────────────────────────────────────────────────
type Row = BackupRow & { user_id: string; size: number; sha256: string; reason?: string | null; verified_at?: string };

function fakeServer() {
  const users: Record<string, string> = { 'token-olena': 'olena', 'token-ivan': 'ivan' };
  const rows: Row[] = [];
  const files = new Map<string, Uint8Array>();
  const service = 'service-key';
  const fetchFn = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = new URL(String(input));
    const headers = new Headers(init.headers);
    const method = init.method ?? 'GET';
    const isAdmin = headers.get('apikey') === service && headers.get('Authorization') === `Bearer ${service}`;
    if (url.pathname === '/auth/v1/user') {
      const uid = users[(headers.get('Authorization') ?? '').replace('Bearer ', '')];
      return uid ? Response.json({ id: uid }) : new Response('{}', { status: 401 });
    }
    assert.ok(isAdmin, `без ключа сервера: ${method} ${url}`);
    if (url.pathname === '/rest/v1/device_backups') {
      const eq = (k: string) => url.searchParams.get(k)?.replace(/^eq\./, '');
      if (method === 'GET') {
        return Response.json(rows.filter((r) => r.user_id === eq('user_id')));
      }
      if (method === 'PATCH') {
        const r = rows.find((x) => x.id === eq('id'))!;
        Object.assign(r, JSON.parse(String(init.body)));
        return new Response(null, { status: 204 });
      }
      if (method === 'DELETE') {
        const ids = url.searchParams.get('id')!.replace(/^in\.\(|\)$/g, '').split(',');
        for (const id of ids) rows.splice(rows.findIndex((x) => x.id === id), 1);
        return new Response(null, { status: 204 });
      }
    }
    if (url.pathname === '/storage/v1/object/backups' && method === 'DELETE') {
      for (const p of (JSON.parse(String(init.body)) as { prefixes: string[] }).prefixes) files.delete(p);
      return Response.json([]);
    }
    if (url.pathname.startsWith('/storage/v1/object/backups/') && method === 'GET') {
      const f = files.get(url.pathname.slice('/storage/v1/object/backups/'.length));
      return f ? new Response(f) : new Response('{}', { status: 404 });
    }
    throw new Error(`неочікуваний запит ${method} ${url}`);
  }) as typeof fetch;
  // телефон заявляє копію й кладе файл
  const upload = (user: string, id: string, at: string, file: Uint8Array, opts: { put?: boolean; sha?: string } = {}) => {
    const path = `${user}/${id}.db.gz`;
    rows.push({ id, user_id: user, path, status: 'uploading', created_at: at, size: file.length, sha256: opts.sha ?? sha(file) });
    if (opts.put ?? true) files.set(path, file);
  };
  return { rows, files, fetchFn, upload, env: { url: 'https://x.supabase.co', anonKey: 'anon', serviceKey: service } };
}

const call = (s: ReturnType<typeof fakeServer>, id: string, token = 'token-olena', now = Date.parse('2026-10-10T03:00:00Z')) =>
  handle(new Request('https://f/backup-commit', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ id }),
  }), s.env, s.fetchFn, now);

test('три ночі поспіль: лишаються дві останні цілі', async () => {
  const s = fakeServer();
  for (const [i, day] of ['07', '08', '09'].entries()) {
    const id = `night-000${i}`;
    s.upload('olena', id, `2026-10-${day}T01:00:00Z`, gz(sqliteBytes(10 + i)));
    const r = await call(s, id);
    assert.equal(r.status, 200);
  }
  assert.deepEqual(s.rows.map((r) => r.id).sort(), ['night-0001', 'night-0002']);
  assert.deepEqual([...s.files.keys()].sort(), ['olena/night-0001.db.gz', 'olena/night-0002.db.gz']);
  assert.ok(s.rows.every((r) => r.status === 'ok' && r.verified_at));
});

test('нова копія зіпсована - старі цілі лишаються, зіпсована видаляється', async () => {
  const s = fakeServer();
  s.upload('olena', 'night-0001', '2026-10-08T01:00:00Z', gz(sqliteBytes()));
  await call(s, 'night-0001', 'token-olena', Date.parse('2026-10-08T01:01:00Z'));
  s.upload('olena', 'night-0002', '2026-10-09T01:00:00Z', gz(sqliteBytes()));
  await call(s, 'night-0002', 'token-olena', Date.parse('2026-10-09T01:01:00Z'));
  const broken = gz(sqliteBytes()).subarray(0, 300);
  s.upload('olena', 'night-0003', '2026-10-10T01:00:00Z', broken);
  const r = await call(s, 'night-0003');
  assert.equal(r.status, 422);
  assert.equal(((await r.json()) as { status: string }).status, 'bad');
  assert.deepEqual(s.rows.filter((x) => x.status === 'ok').map((x) => x.id), ['night-0001', 'night-0002']);
  assert.ok(!s.files.has('olena/night-0003.db.gz'));
  assert.equal(s.files.size, 2);
});

test('чужа копія, без входу, без файлу - відмова; повторний виклик - без шкоди', async () => {
  const s = fakeServer();
  s.upload('olena', 'night-0001', '2026-10-09T01:00:00Z', gz(sqliteBytes()));
  assert.equal((await call(s, 'night-0001', 'token-ivan')).status, 404);
  assert.equal((await call(s, 'night-0001', 'bad-token')).status, 401);
  assert.equal((await call(s, '../../etc')).status, 400);
  s.upload('olena', 'night-0002', '2026-10-10T01:00:00Z', gz(sqliteBytes()), { put: false });
  assert.equal((await call(s, 'night-0002')).status, 409); // файл ще не дійшов
  assert.equal(s.rows.find((r) => r.id === 'night-0002')!.status, 'uploading');
  assert.equal((await call(s, 'night-0001')).status, 200);
  assert.equal((await call(s, 'night-0001')).status, 200); // вдруге - так само
  assert.equal(s.rows.find((r) => r.id === 'night-0001')!.status, 'ok');
});
