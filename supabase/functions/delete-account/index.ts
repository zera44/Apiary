// «Видалити акаунт і всі дані» (вимога Google Play).
//
// Видаляє все, що належить користувачу, який викликає функцію:
//   * файли: stock-photos/<user>/..., backups/<user>/...;
//   * записи про доступ - позначками «видалено» (телефони помічників і
//     власників дізнаються й приберуть чужі дані), запрошення від нього й
//     на його пошту - геть (delete_account_prepare);
//   * сам акаунт (Auth) - а з ним пасіки, вулики, огляди, склад, фінанси,
//     помічники, облік копій.
// Записи, які він робив як помічник у чужих пасіках, належать власникам
// цих пасік і лишаються в них.
//
// Без залежностей (лише fetch): той самий файл перевіряє тест на Node
// (tests/delete_account.test.ts).

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

export type Env = { url: string; anonKey: string; serviceKey: string };

const BUCKETS = ['stock-photos', 'backups'];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

export async function handle(req: Request, env: Env, fetchFn: typeof fetch = fetch): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'лише POST' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'потрібен вхід' }, 401);
  const who = await fetchFn(`${env.url}/auth/v1/user`, { headers: { apikey: env.anonKey, Authorization: auth } });
  if (!who.ok) return json({ error: 'потрібен вхід' }, 401);
  const user = (await who.json()) as { id?: string; email?: string };
  const id = user.id;
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'потрібен вхід' }, 401);

  const admin = { apikey: env.serviceKey, Authorization: `Bearer ${env.serviceKey}` };

  // 1. доступ (помічники й власники) - позначками «видалено», щоб їхні
  //    телефони прибрали чужі дані; запрошення - геть
  const prep = await fetchFn(`${env.url}/rest/v1/rpc/delete_account_prepare`, {
    method: 'POST',
    headers: { ...admin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_user: id }),
  });
  if (!prep.ok) return json({ error: `доступ: ${prep.status}` }, 502);

  // 2. акаунт - а з ним усі його рядки бази. Після цього нові файли від
  //    нього сховище не прийме (правило account_alive), тож прибирання файлів
  //    нижче - остаточне
  const gone = await fetchFn(`${env.url}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: admin });
  if (!gone.ok && gone.status !== 404) return json({ error: `акаунт: ${gone.status}` }, 502);

  // 3. файли (сторінками: список - видалити - знову, доки не порожньо)
  for (const bucket of BUCKETS) {
    for (let round = 0; round < 1000; round++) {
      const list = await fetchFn(`${env.url}/storage/v1/object/list/${bucket}`, {
        method: 'POST',
        headers: { ...admin, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefix: `${id}/`, limit: 100, offset: 0, sortBy: { column: 'name', order: 'asc' } }),
      });
      if (!list.ok) return json({ error: `файли (${bucket}): ${list.status}` }, 502);
      const names = ((await list.json()) as { name: string }[]).map((x) => `${id}/${x.name}`);
      if (names.length === 0) break;
      const del = await fetchFn(`${env.url}/storage/v1/object/${bucket}`, {
        method: 'DELETE',
        headers: { ...admin, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: names }),
      });
      if (!del.ok) return json({ error: `файли (${bucket}): ${del.status}` }, 502);
    }
  }
  return json({ status: 'deleted' });
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
