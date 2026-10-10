// Нічна повна копія бази телефона: перевірити й зберегти.
//
// Телефон: 1) заявляє копію в device_backups (status 'uploading', розмір і
// SHA-256 стисненого файлу), 2) кладе файл у backups/<user>/<id>.db.gz,
// 3) викликає цю функцію з {id}. Функція:
//   * перевіряє файл: розмір і SHA-256 збігаються, gzip розпаковується
//     повністю, усередині - база SQLite цілої довжини;
//   * зіпсований - позначає 'bad' і видаляє файл (старі копії не чіпає);
//   * цілий - позначає 'ok' і ЛИШЕ ПІСЛЯ ЦЬОГО прибирає зайве: лишаються
//     2 найновіші цілі копії; зіпсовані й недовантажені (старші за добу) -
//     видаляються.
//
// Без залежностей (лише fetch і Web API): той самий файл перевіряють тести
// на Node (tests/backup_commit.test.ts).

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

/** Скільки цілих копій тримати на кожного користувача. */
export const KEEP = 2;

/** Недовантажена копія, старша за це, - сміття. */
const STALE_MS = 24 * 60 * 60 * 1000;

const SQLITE_MAGIC = 'SQLite format 3\u0000';

export type Check = { ok: true; dbSize: number } | { ok: false; reason: string };

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(d, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Чи цілий стиснений файл копії [gz]. */
export async function checkBackup(gz: Uint8Array, size: number, sha256: string): Promise<Check> {
  if (gz.length !== size) return { ok: false, reason: `розмір ${gz.length}, очікували ${size}` };
  if ((await sha256Hex(gz)) !== sha256.toLowerCase()) return { ok: false, reason: 'SHA-256 не збігається' };
  // розпаковуємо потоком: у пам'яті - лише заголовок і лічильник
  const head = new Uint8Array(100);
  let got = 0;
  let total = 0;
  try {
    const reader = new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip')).getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (got < head.length) {
        const n = Math.min(head.length - got, value.length);
        head.set(value.subarray(0, n), got);
        got += n;
      }
      total += value.length;
    }
  } catch (e) {
    return { ok: false, reason: `не розпаковується: ${e}` };
  }
  if (got < head.length || new TextDecoder().decode(head.subarray(0, 16)) !== SQLITE_MAGIC) {
    return { ok: false, reason: 'усередині не база SQLite' };
  }
  // розмір сторінки (1 означає 65536) і кількість сторінок із заголовка
  const raw = (head[16] << 8) | head[17];
  const pageSize = raw === 1 ? 65536 : raw;
  if (pageSize < 512 || pageSize > 65536 || (pageSize & (pageSize - 1)) !== 0) {
    return { ok: false, reason: `дивний розмір сторінки ${raw}` };
  }
  const view = new DataView(head.buffer);
  const pages = view.getUint32(28);
  const counterValid = view.getUint32(92) === view.getUint32(24);
  if (total % pageSize !== 0 || total === 0) {
    return { ok: false, reason: `обрізана база (${total} байт)` };
  }
  if (counterValid && pages !== 0 && pages * pageSize !== total) {
    return { ok: false, reason: `обрізана база: ${total} байт замість ${pages * pageSize}` };
  }
  return { ok: true, dbSize: total };
}

export type BackupRow = { id: string; path: string; status: string; created_at: string };

/** Що прибрати після того, як нову копію перевірено. */
export function toPrune(rows: BackupRow[], now: number, keep = KEEP): BackupRow[] {
  const ok = rows
    .filter((r) => r.status === 'ok')
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
  return [
    ...ok.slice(keep),
    ...rows.filter((r) => r.status === 'bad'),
    ...rows.filter((r) => r.status === 'uploading' && now - Date.parse(r.created_at) > STALE_MS),
  ];
}

export type Env = { url: string; anonKey: string; serviceKey: string };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

/** Обробка запиту. [fetchFn] - звичайний fetch (тести підставляють свій). */
export async function handle(req: Request, env: Env, fetchFn: typeof fetch = fetch, now = Date.now()): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'лише POST' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'потрібен вхід' }, 401);
  // хто викликає - питаємо в сервера входу за його ж токеном
  const who = await fetchFn(`${env.url}/auth/v1/user`, { headers: { apikey: env.anonKey, Authorization: auth } });
  if (!who.ok) return json({ error: 'потрібен вхід' }, 401);
  const userId = ((await who.json()) as { id?: string }).id;
  if (!userId) return json({ error: 'потрібен вхід' }, 401);

  let id = '';
  try {
    id = String(((await req.json()) as { id?: unknown }).id ?? '');
  } catch {
    // нижче - «немає id»
  }
  if (!/^[0-9A-Za-z-]{8,64}$/.test(id)) return json({ error: 'немає id копії' }, 400);

  const admin = { apikey: env.serviceKey, Authorization: `Bearer ${env.serviceKey}` };
  const rest = (q: string, init: RequestInit = {}) =>
    fetchFn(`${env.url}/rest/v1/${q}`, { ...init, headers: { ...admin, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  const removeFiles = async (paths: string[]) => {
    if (paths.length === 0) return;
    const r = await fetchFn(`${env.url}/storage/v1/object/backups`, {
      method: 'DELETE',
      headers: { ...admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: paths }),
    });
    if (!r.ok) throw new Error(`не вдалося видалити файли: ${r.status}`);
  };

  const rowsResp = await rest(`device_backups?select=*&user_id=eq.${userId}&order=created_at.desc`);
  if (!rowsResp.ok) return json({ error: `облік копій: ${rowsResp.status}` }, 502);
  const rows = (await rowsResp.json()) as (BackupRow & { size: number; sha256: string })[];
  const row = rows.find((r) => r.id === id);
  if (!row) return json({ error: 'такої копії немає' }, 404);

  if (row.status !== 'ok') {
    const file = await fetchFn(`${env.url}/storage/v1/object/backups/${row.path}`, { headers: admin });
    if (!file.ok) return json({ error: 'файл копії ще не завантажено' }, 409);
    const check = await checkBackup(new Uint8Array(await file.arrayBuffer()), Number(row.size), row.sha256);
    if (!check.ok) {
      await rest(`device_backups?id=eq.${id}`, {
        method: 'PATCH',
        body: JSON.stringify({ status: 'bad', reason: check.reason }),
      });
      await removeFiles([row.path]);
      return json({ status: 'bad', reason: check.reason }, 422);
    }
    const mark = await rest(`device_backups?id=eq.${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ status: 'ok', verified_at: new Date(now).toISOString(), reason: null }),
    });
    if (!mark.ok) return json({ error: `не вдалося позначити копію: ${mark.status}` }, 502);
    row.status = 'ok';
  }

  // нову перевірено - тепер можна прибрати зайве
  const drop = toPrune(rows, now);
  if (drop.length > 0) {
    await removeFiles(drop.map((r) => r.path));
    await rest(`device_backups?id=in.(${drop.map((r) => r.id).join(',')})`, { method: 'DELETE' });
  }
  return json({ status: 'ok', kept: rows.filter((r) => r.status === 'ok' && !drop.includes(r)).map((r) => r.id) });
}

if (typeof Deno !== 'undefined') {
  Deno.serve((req) =>
    handle(req, {
      url: Deno.env.get('SUPABASE_URL') ?? '',
      anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    })
  );
}
