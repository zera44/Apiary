// Фото чеків для довчання моделі розпізнавання.
//
// Застосунок (лише після згоди людини; без входу, за device_id):
//   {device_id, photo_b64} - JPEG у base64, до 4 МБ.
// Функція перевіряє розмір і підпис JPEG, не приймає той самий знімок двічі
// (ім'я містить хеш) і не більше DAILY_LIMIT знімків за добу від одного
// встановлення. Знімок лежить у закритому сховищі receipt-training; журнал -
// лише коди й розмір, БЕЗ вмісту.
//
// Публічна для шлюзу Supabase (--no-verify-jwt): доступ перевіряє сама.
// Без залежностей: той самий файл перевіряє тест на Node
// (tests/receipt_photo.test.ts).

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

export const MAX_BYTES = 4 * 1024 * 1024;
/** Знімків від одного встановлення за добу. */
export const DAILY_LIMIT = 30;
const BUCKET = 'receipt-training';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type Env = (name: string) => string | undefined;

export interface Store {
  /** Скільки знімків під префіксом (за добу). */
  count(prefix: string): Promise<number>;
  /** 'created' або 'exists' (той самий знімок уже є). */
  put(path: string, bytes: Uint8Array): Promise<'created' | 'exists'>;
}

export type Deps = {
  store: Store;
  log: (line: string) => void;
  now: () => number;
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS },
  });
}
const fail = (status: number, error: string) => json({ error }, status);

async function sha256Hex(b: Uint8Array): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', b));
  return Array.from(d, (x) => x.toString(16).padStart(2, '0')).join('');
}

function fromBase64(s: string): Uint8Array | null {
  try {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return fail(405, 'method');

  let b: Record<string, unknown>;
  try {
    const text = await req.text();
    // base64 більший за файл на третину
    if (text.length > Math.ceil((MAX_BYTES * 4) / 3) + 1000) return fail(413, 'too_large');
    b = JSON.parse(text);
  } catch {
    return fail(400, 'json');
  }
  const deviceId = typeof b.device_id === 'string' ? b.device_id.toLowerCase() : '';
  if (!UUID.test(deviceId)) return fail(400, 'device');
  const bytes = typeof b.photo_b64 === 'string' ? fromBase64(b.photo_b64) : null;
  if (!bytes || bytes.length < 1000) return fail(400, 'photo');
  if (bytes.length > MAX_BYTES) return fail(413, 'too_large');
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) return fail(415, 'not_jpeg');

  const day = new Date(deps.now()).toISOString().slice(0, 10).replaceAll('-', '');
  if ((await deps.store.count(`${deviceId}/${day}-`)) >= DAILY_LIMIT) return fail(429, 'limit');
  const hash = (await sha256Hex(bytes)).slice(0, 24);
  const result = await deps.store.put(`${deviceId}/${day}-${hash}.jpg`, bytes);
  deps.log(JSON.stringify({ fn: 'receipt-photo', result, bytes: bytes.length }));
  return json({ ok: true, duplicate: result === 'exists' });
}

/** Справжнє сховище: Storage REST зі службовим ключем. */
export class RestStore implements Store {
  base: string;
  key: string;
  f: typeof fetch;
  constructor(base: string, key: string, f: typeof fetch = fetch) {
    this.base = base;
    this.key = key;
    this.f = f;
  }
  headers(extra: Record<string, string> = {}) {
    return { Authorization: `Bearer ${this.key}`, apikey: this.key, ...extra };
  }
  async count(prefix: string): Promise<number> {
    const slash = prefix.indexOf('/');
    const dir = prefix.slice(0, slash), start = prefix.slice(slash + 1);
    const res = await this.f(`${this.base}/storage/v1/object/list/${BUCKET}`, {
      method: 'POST',
      headers: this.headers({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ prefix: dir, limit: 1000, search: start }),
    });
    if (!res.ok) throw new Error(`list ${res.status}`);
    const items = (await res.json()) as { name: string }[];
    return items.filter((i) => i.name.startsWith(start)).length;
  }
  async put(path: string, bytes: Uint8Array): Promise<'created' | 'exists'> {
    const res = await this.f(`${this.base}/storage/v1/object/${BUCKET}/${path}`, {
      method: 'POST',
      headers: this.headers({ 'Content-Type': 'image/jpeg', 'x-upsert': 'false' }),
      body: bytes,
    });
    if (res.ok) return 'created';
    const t = await res.text();
    if (res.status === 409 || /duplicate|already exists/i.test(t)) return 'exists';
    throw new Error(`put ${res.status}`);
  }
}

/** Сховище в пам'яті - для тестів. */
export class MemoryStore implements Store {
  files = new Map<string, Uint8Array>();
  async count(prefix: string) {
    return [...this.files.keys()].filter((k) => k.startsWith(prefix)).length;
  }
  async put(path: string, bytes: Uint8Array) {
    if (this.files.has(path)) return 'exists' as const;
    this.files.set(path, bytes);
    return 'created' as const;
  }
}

if (typeof Deno !== 'undefined' && Deno.env.get('SUPABASE_URL')) {
  const store = new RestStore(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  Deno.serve((req) => {
    return handle(req, { store, log: (l) => console.log(l), now: () => Date.now() }).catch((e) => {
      console.log(JSON.stringify({ fn: 'receipt-photo', result: 'error', message: String(e).slice(0, 120) }));
      return fail(500, 'server');
    });
  });
}
