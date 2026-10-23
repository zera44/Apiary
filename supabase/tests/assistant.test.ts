// Перевірка посередника помічника без Supabase і без Anthropic: замість
// API - фейкова модель із заготовленими відповідями.
//
//   node --test supabase/tests/assistant.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildRequest, type Deps, handle, stepsSinceHuman, stripOldThinking, trimHistory } from '../functions/assistant/index.ts';
import { testTokenAccess, TEST_TOKEN_HEADER } from '../functions/assistant/access.ts';
import { DEFAULT_MODEL, isSimpleRequest, lastHumanText, MAX_STEPS, nextModel, route, routeActive, struggled } from '../functions/assistant/config.ts';

const TOKEN = 'test-token-0123456789abcdef';
const SECRETS: Record<string, string> = {
  ANTHROPIC_API_KEY: 'sk-ant-test',
  APIARY_ASSISTANT_TEST_TOKEN: TOKEN,
};

type Call = { url: string; headers: Record<string, string>; body: any };

function deps(reply: () => Response, env: Record<string, string> = SECRETS) {
  const calls: Call[] = [];
  const logs: string[] = [];
  const d: Deps = {
    env: (n) => env[n],
    fetch: (async (url: string, init: RequestInit) => {
      calls.push({ url, headers: init.headers as Record<string, string>, body: JSON.parse(init.body as string) });
      return reply();
    }) as typeof fetch,
    log: (l) => logs.push(l),
    access: testTokenAccess,
    tools: [
      { name: 'open_screen', description: 'Відкрити екран', input_schema: { type: 'object', properties: {} } },
      { name: 'apiaries_list', description: 'Список пасік', input_schema: { type: 'object', properties: {} } },
    ],
  };
  return { d, calls, logs };
}

const modelReply = (content: unknown[], stop_reason = 'end_turn') => () =>
  new Response(
    JSON.stringify({
      content,
      stop_reason,
      usage: { input_tokens: 120, output_tokens: 30, cache_read_input_tokens: 900, cache_creation_input_tokens: 0 },
    }),
    { status: 200 },
  );

const post = (body: unknown, token: string | null = TOKEN) =>
  new Request('https://x.supabase.co/functions/v1/assistant', {
    method: 'POST',
    headers: token == null ? {} : { [TEST_TOKEN_HEADER]: token },
    body: JSON.stringify(body),
  });

const hello = { messages: [{ role: 'user', content: 'Скільки в мене пасік?' }] };
// складне питання: Пасічник відповідає сам (просте він передає Ведмедику)
const heavy = { messages: [{ role: 'user', content: 'Поясни, чому слабка сім\'я у вулику 5' }] };

test('неправильний чи відсутній тестовий код - відмова, модель не викликається', async () => {
  for (const t of [null, 'wrong', TOKEN + 'x']) {
    const { d, calls } = deps(modelReply([]));
    const r = await handle(post(hello, t), d);
    assert.equal(r.status, 401);
    assert.equal(calls.length, 0);
  }
});

test('код не задано на сервері - не пускає нікого', async () => {
  const { d, calls } = deps(modelReply([]), { ANTHROPIC_API_KEY: 'k' });
  const r = await handle(post(hello, ''), d);
  assert.equal(r.status, 401);
  assert.equal(calls.length, 0);
});

test('немає ключа Anthropic - not_configured', async () => {
  const { d } = deps(modelReply([]), { APIARY_ASSISTANT_TEST_TOKEN: TOKEN });
  const r = await handle(post(hello), d);
  assert.equal(r.status, 500);
  assert.deepEqual(await r.json(), { error: 'not_configured' });
});

test('звичайна відповідь: ключ лише в заголовку до Anthropic, модель, кеш', async () => {
  const { d, calls } = deps(modelReply([{ type: 'text', text: 'У вас 2 пасіки.' }]));
  const r = await handle(post(hello), d);
  assert.equal(r.status, 200);
  const out = await r.json();
  assert.equal(out.stop_reason, 'end_turn');
  assert.equal(out.content[0].text, 'У вас 2 пасіки.');
  assert.equal(JSON.stringify(out).includes('sk-ant'), false);

  assert.equal(calls.length, 1);
  const c = calls[0];
  assert.equal(c.url, 'https://api.anthropic.com/v1/messages');
  assert.equal(c.headers['x-api-key'], 'sk-ant-test');
  assert.equal(c.headers['anthropic-version'], '2023-06-01');
  assert.equal(c.body.model, DEFAULT_MODEL);
  assert.equal(c.body.system[0].cache_control.type, 'ephemeral');
  assert.equal(c.body.tools.at(-1).cache_control.type, 'ephemeral');
  assert.equal(c.body.tools[0].cache_control, undefined);
  assert.deepEqual(c.body.messages, hello.messages);
});

test('модель перевизначається секретом ASSISTANT_MODEL', async () => {
  const { d, calls } = deps(modelReply([]), { ...SECRETS, ASSISTANT_MODEL: 'claude-sonnet-5-5' });
  await handle(post(hello), d);
  assert.equal(calls[0].body.model, 'claude-sonnet-5-5');
});

test('коротка назва: sonnet / haiku; типово - Haiku без запасної моделі', async () => {
  const s = deps(modelReply([]), { ...SECRETS, ASSISTANT_MODEL: 'Sonnet' });
  await handle(post(hello), s.d);
  assert.equal(s.calls[0].body.model, 'claude-sonnet-5-5');
  // Sonnet 5.5: відмова запобіжників - сервер Anthropic сам спробує іншу модель
  assert.equal(s.calls[0].body.fallbacks, 'default');
  assert.equal(s.calls[0].headers['anthropic-beta'], 'server-side-fallback-2026-07-01');

  const h = deps(modelReply([]), { ...SECRETS, ASSISTANT_MODEL: 'haiku' });
  await handle(post(hello), h.d);
  assert.equal(h.calls[0].body.model, DEFAULT_MODEL);
  assert.equal('fallbacks' in h.calls[0].body, false);
  assert.equal(h.calls[0].headers['anthropic-beta'], undefined);
});

test('глибина міркувань - секретом ASSISTANT_EFFORT; невідоме значення - типове', async () => {
  for (const [secret, sent] of [[undefined, 'medium'], ['xhigh', 'xhigh'], ['LOW', 'low'], ['дуже', 'medium']]) {
    const env = { ...SECRETS, ...(secret ? { ASSISTANT_EFFORT: secret } : {}) };
    const { d, calls, logs } = deps(modelReply([{ type: 'text', text: 'ok' }]), env);
    await handle(post(hello), d);
    assert.deepEqual(calls[0].body.output_config, { effort: sent }, String(secret));
    assert.equal(JSON.parse(logs[0]).effort, sent);
  }
});

test('вибір у застосунку: модель і глибина з запиту; персонаж за моделлю', async () => {
  const s = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const out = await (await handle(post({ ...heavy, model: 'sonnet', effort: 'high' }), s.d)).json();
  assert.equal(s.calls[0].body.model, 'claude-sonnet-5-5');
  assert.deepEqual(s.calls[0].body.output_config, { effort: 'high' });
  assert.equal(out.model, 'sonnet');
  assert.match(s.calls[0].body.system[0].text, /«Пасічник»/);

  const h = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const out2 = await (await handle(post({ ...hello, model: 'haiku' }), h.d)).json();
  assert.equal(out2.model, 'haiku');
  assert.match(h.calls[0].body.system[0].text, /«Ведмедик»/);
});

test('невідомий вибір ігнорується; ASSISTANT_CLIENT_CHOICE=off - вибір застосунку не діє', async () => {
  const bad = deps(modelReply([]));
  await handle(post({ ...hello, model: 'claude-opus-5-5', effort: 'turbo' }), bad.d);
  assert.equal(bad.calls[0].body.model, DEFAULT_MODEL);
  assert.deepEqual(bad.calls[0].body.output_config, { effort: 'medium' });

  const off = deps(modelReply([]), { ...SECRETS, ASSISTANT_CLIENT_CHOICE: 'off' });
  await handle(post({ ...hello, model: 'sonnet', effort: 'max' }), off.d);
  assert.equal(off.calls[0].body.model, DEFAULT_MODEL);
  assert.deepEqual(off.calls[0].body.output_config, { effort: 'medium' });
});

// відповіді по черзі: перший запит - перша, другий - друга...
const sequence = (...rs: (() => Response)[]) => {
  let i = 0;
  return () => rs[Math.min(i++, rs.length - 1)]();
};
const textReply = (t: string, stop = 'end_turn') => modelReply([{ type: 'text', text: t }], stop);

test('ознаки «не впорався»: обрізано, порожньо, визнав - так; нормальна відповідь, інструмент, відмова - ні', () => {
  const text = (t: string, stop_reason = 'end_turn') => ({ content: [{ type: 'text', text: t }], stop_reason });
  assert.equal(struggled(text('Не вдалося це зробити.')), 'gave_up');
  assert.equal(struggled(text('На жаль, не можу цього зробити.')), 'gave_up');
  assert.equal(struggled(text('Я не розумію, про що ви.')), 'gave_up');
  assert.equal(struggled(text('Частина відповіді', 'max_tokens')), 'max_tokens');
  assert.equal(struggled({ content: [], stop_reason: 'end_turn' }), 'empty');
  assert.equal(struggled(text('У вас 2 пасіки.')), null);
  assert.equal(struggled(text('Не знайшов таких вуликів.')), null); // порожній результат - не слабкість моделі
  assert.equal(struggled({ content: [{ type: 'tool_use', id: 't' }], stop_reason: 'tool_use' }), null);
  assert.equal(struggled(text('Із цим я не допоможу.', 'refusal')), null);
  assert.equal(nextModel('claude-haiku-5-5'), 'claude-sonnet-5-5');
  assert.equal(nextModel('claude-sonnet-5-5'), 'claude-opus-5-5');
  assert.equal(nextModel('claude-opus-5-5'), null);
  assert.equal(nextModel('щось інше'), null);
});

test('Ведмедик не впорався - Пасічник, потім Робопасічник; застосунок бачить escalated_from', async () => {
  const s = deps(sequence(textReply('Не вдалося зрозуміти запит.'), textReply('Не можу цього зробити.'), textReply('Ось відповідь.')));
  const out = await (await handle(post({ ...hello, model: 'haiku' }), s.d)).json();
  assert.deepEqual(s.calls.map((c) => c.body.model), ['claude-haiku-5-5', 'claude-sonnet-5-5', 'claude-opus-5-5']);
  assert.match(s.calls[1].body.system[0].text, /«Пасічник»/);
  assert.match(s.calls[2].body.system[0].text, /«Робопасічник»/);
  assert.equal(out.model, 'opus');
  assert.equal(out.escalated_from, 'haiku');
  assert.equal(out.content[0].text, 'Ось відповідь.');
  assert.deepEqual(s.calls[2].body.messages, hello.messages); // та сама розмова
  assert.ok(s.logs.some((l) => l.includes('"result":"escalate"') && l.includes('"why":"gave_up"')));
});

test('один рівень, якщо вищий впорався; нормальна відповідь не ескалується', async () => {
  const s = deps(sequence(textReply('Порожня відповідь', 'max_tokens'), textReply('Готово.')));
  const out = await (await handle(post({ ...hello, model: 'haiku' }), s.d)).json();
  assert.equal(s.calls.length, 2);
  assert.equal(out.model, 'sonnet');
  assert.equal(out.escalated_from, 'haiku');

  const ok = deps(textReply('У вас 2 пасіки.'));
  const o2 = await (await handle(post({ ...hello, model: 'haiku' }), ok.d)).json();
  assert.equal(ok.calls.length, 1);
  assert.equal(o2.escalated_from, undefined);
});

test('Робопасічник - найвищий рівень: далі нікуди; ASSISTANT_ESCALATE=off вимикає', async () => {
  const top = deps(textReply('Не вдалося.'));
  const o1 = await (await handle(post({ ...hello, model: 'opus' }), top.d)).json();
  assert.equal(top.calls.length, 1);
  assert.equal(o1.escalated_from, undefined);

  const off = deps(textReply('Не вдалося.'), { ...SECRETS, ASSISTANT_ESCALATE: 'off' });
  await handle(post({ ...hello, model: 'haiku' }), off.d);
  assert.equal(off.calls.length, 1);
});

test('запит інструмента не ескалюється; Haiku, який передали з Пасічника, піднімається назад до нього', async () => {
  const tool = deps(modelReply([{ type: 'tool_use', id: 't1', name: 'open_screen', input: {} }], 'tool_use'));
  await handle(post({ ...hello, model: 'haiku' }), tool.d);
  assert.equal(tool.calls.length, 1);

  // Пасічник обраний, просте питання -> Haiku не впорався -> знову Sonnet: «передав» не показуємо
  const s = deps(sequence(textReply('Не вийшло.'), textReply('Відкрив.')));
  const out = await (await handle(post({ messages: [{ role: 'user', content: 'Відкрий склад' }], model: 'sonnet' }), s.d)).json();
  assert.deepEqual(s.calls.map((c) => c.body.model), ['claude-haiku-5-5', 'claude-sonnet-5-5']);
  assert.equal(out.model, 'sonnet');
  assert.equal(out.routed_from, undefined);
  assert.equal(out.escalated_from, 'haiku');
});

test('просте / складне: що Пасічник передає Ведмедику', () => {
  for (const s of [
    'Скільки в мене пасік?', 'Відкрий фінанси', 'Запиши огляд вулика 5: сила 8', 'покажи склад',
    'Додай прихід цукру 10 кг', 'Нагадай завтра оглянути вулик 3',
  ]) {
    assert.equal(isSimpleRequest(s), true, s);
  }
  for (const s of [
    'Поясни, чому слабка сім\'я', 'Порадь, що робити з варроа', 'Як краще підготувати вулики до зими?',
    'Що написано в книгах про роїння?', 'Відкрий вулик 5 і порадь, чим підгодувати', '', 'Привіт',
    'x'.repeat(300) + ' відкрий',
  ]) {
    assert.equal(isSimpleRequest(s), false, s);
  }
});

test('текст людини для вибору: без службових рядків, повз результати інструментів', () => {
  const msgs = [
    { role: 'user', content: 'Відкрий склад\n\n[Сьогодні: 2026-10-22, четвер]\n[Екран: finance]' },
    { role: 'assistant', content: [{ type: 'tool_use', id: 't', name: 'open_screen', input: {} }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't', content: 'ok' }] },
  ];
  assert.equal(lastHumanText(msgs), 'Відкрий склад');
});

test('Пасічник: просте прохання непомітно йде на Haiku, але застосунок бачить routed_from', async () => {
  const s = deps(modelReply([{ type: 'text', text: 'У вас 2 пасіки.' }]));
  const out = await (await handle(post({ ...hello, model: 'sonnet', effort: 'high' }), s.d)).json();
  assert.equal(s.calls[0].body.model, 'claude-haiku-5-5');
  assert.equal(s.calls[0].body.fallbacks, undefined);
  assert.equal(s.calls[0].headers['anthropic-beta'], undefined);
  assert.match(s.calls[0].body.system[0].text, /«Ведмедик»/);
  assert.equal(out.model, 'haiku'); // хто відповів
  assert.equal(out.routed_from, 'sonnet'); // кого обрала людина
  assert.ok(s.logs.some((l) => l.includes('"routed_from":"sonnet"')));

  // складне лишається Sonnet; routed_from немає
  const c = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const out2 = await (await handle(post({ ...heavy, model: 'sonnet' }), c.d)).json();
  assert.equal(c.calls[0].body.model, 'claude-sonnet-5-5');
  assert.equal(out2.model, 'sonnet');
  assert.equal(out2.routed_from, undefined);
});

test('Робопасічник: простий запит повертає до Ведмедика, звичайний - до обраного, важкий - лишає', async () => {
  // просте на Робопасічнику -> Ведмедик
  const a = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const oa = await (await handle(post({ ...hello, model: 'sonnet', active: 'opus' }), a.d)).json();
  assert.equal(a.calls[0].body.model, 'claude-haiku-5-5');
  assert.equal(oa.model, 'haiku');
  assert.equal(oa.routed_from, 'opus');

  // не просте й не важке -> обраний людиною (Пасічник)
  const plain = { messages: [{ role: 'user', content: 'Дякую, зрозуміло' }] };
  const b = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const ob = await (await handle(post({ ...plain, model: 'sonnet', active: 'opus' }), b.d)).json();
  assert.equal(b.calls[0].body.model, 'claude-sonnet-5-5');
  assert.equal(ob.routed_from, 'opus');

  // важке - лишається Робопасічник
  const c = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const oc = await (await handle(post({ ...heavy, model: 'sonnet', active: 'opus' }), c.d)).json();
  assert.equal(c.calls[0].body.model, 'claude-opus-5-5');
  assert.equal(oc.model, 'opus');
  assert.equal(oc.routed_from, undefined);

  // Ведмедик, піднятий до Пасічника: просте - назад до Ведмедика
  const d2 = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const od = await (await handle(post({ ...hello, model: 'haiku', active: 'sonnet' }), d2.d)).json();
  assert.equal(d2.calls[0].body.model, 'claude-haiku-5-5');
  assert.equal(od.routed_from, 'sonnet');
  assert.equal(routeActive('claude-haiku-5-5', undefined, hello.messages, () => undefined), null);
});

test('весь цикл інструментів одного питання - на одній моделі', async () => {
  const msgs = [
    { role: 'user', content: 'Відкрий склад\n[Сьогодні: 2026-10-22]' },
    { role: 'assistant', content: [{ type: 'tool_use', id: 't1', name: 'open_screen', input: {} }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't1', content: 'ok' }] },
  ];
  const s = deps(modelReply([{ type: 'text', text: 'Відкрив.' }]));
  await handle(post({ messages: msgs, model: 'sonnet' }), s.d);
  assert.equal(s.calls[0].body.model, 'claude-haiku-5-5');
});

test('Ведмедик і Робопасічник не переключаються; ASSISTANT_ROUTING=off вимикає передачу', async () => {
  const b = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const ob = await (await handle(post({ ...hello, model: 'haiku' }), b.d)).json();
  assert.equal(ob.routed_from, undefined);

  const r = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const or = await (await handle(post({ ...hello, model: 'opus', effort: 'high' }), r.d)).json();
  assert.equal(r.calls[0].body.model, 'claude-opus-5-5');
  assert.equal(r.calls[0].body.fallbacks, 'default'); // запасна модель - як у Sonnet
  assert.equal(r.calls[0].headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
  assert.deepEqual(r.calls[0].body.output_config, { effort: 'high' });
  assert.match(r.calls[0].body.system[0].text, /«Робопасічник»/);
  assert.equal(or.model, 'opus');
  assert.equal(or.routed_from, undefined);

  // модель задано секретом (людина не обирала Пасічника) - без передачі
  const sec = deps(modelReply([{ type: 'text', text: 'ok' }]), { ...SECRETS, ASSISTANT_MODEL: 'sonnet' });
  const os = await (await handle(post(hello), sec.d)).json();
  assert.equal(sec.calls[0].body.model, 'claude-sonnet-5-5');
  assert.equal(os.routed_from, undefined);

  const off = deps(modelReply([{ type: 'text', text: 'ok' }]), { ...SECRETS, ASSISTANT_ROUTING: 'off' });
  const oo = await (await handle(post({ ...hello, model: 'sonnet' }), off.d)).json();
  assert.equal(off.calls[0].body.model, 'claude-sonnet-5-5');
  assert.equal(oo.routed_from, undefined);
  assert.deepEqual(route('claude-sonnet-5-5', hello.messages, () => undefined).routedFrom, 'sonnet');
});

test('Anthropic не прийняв «запасну модель» - той самий запит без неї; у журналі - чому', async () => {
  let n = 0;
  const { d, calls, logs } = deps(() => {
    n++;
    return n === 1
      ? new Response(JSON.stringify({ type: 'error', error: { type: 'invalid_request_error', message: 'fallbacks: unknown field' } }), { status: 400 })
      : modelReply([{ type: 'text', text: 'ok' }])();
  }, { ...SECRETS, ASSISTANT_MODEL: 'sonnet' });
  const r = await handle(post(hello), d);
  assert.equal(r.status, 200);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].body.fallbacks, 'default');
  assert.equal('fallbacks' in calls[1].body, false);
  assert.equal(calls[1].headers['anthropic-beta'], undefined);
  assert.match(logs[0], /retry_without_fallback/);
  assert.match(logs[0], /fallbacks: unknown field/);
});

test('помилка Anthropic - у журналі тип і пояснення (без тексту розмови)', async () => {
  const { d, logs } = deps(
    () => new Response(JSON.stringify({ type: 'error', error: { type: 'invalid_request_error', message: 'messages.1: bad' } }), { status: 400 }),
  );
  const r = await handle(post({ messages: [{ role: 'user', content: 'Таємне' }] }), d);
  assert.equal(r.status, 502);
  const line = JSON.parse(logs.at(-1)!);
  assert.equal(line.error_type, 'invalid_request_error');
  assert.equal(line.error_message, 'messages.1: bad');
  assert.doesNotMatch(logs.at(-1)!, /Таємне/);
});

test('відмова запобіжників моделі - звичайна коротка відповідь застосунку', async () => {
  const { d } = deps(modelReply([], 'refusal'));
  const out = await (await handle(post(hello), d)).json();
  assert.equal(out.stop_reason, 'end_turn');
  assert.equal(out.content[0].type, 'text');
  assert.ok(out.content[0].text.length > 0);
});

test('запит інструмента передається застосунку як є', async () => {
  const use = { type: 'tool_use', id: 'tu_1', name: 'apiaries_list', input: {} };
  const { d } = deps(modelReply([{ type: 'thinking', thinking: '', signature: 's' }, use], 'tool_use'));
  const out = await (await handle(post(hello), d)).json();
  assert.equal(out.stop_reason, 'tool_use');
  assert.deepEqual(out.content[1], use);
  assert.equal(out.content[0].type, 'thinking'); // застосунок поверне його без змін
  assert.equal(out.steps_left, MAX_STEPS - 1);
});

// розмова, де модель уже n разів зверталася до інструментів
function conversation(n: number) {
  const m: any[] = [{ role: 'user', content: 'Знайди слабкі вулики' }];
  for (let i = 0; i < n; i++) {
    m.push({ role: 'assistant', content: [{ type: 'tool_use', id: `t${i}`, name: 'find_hives', input: {} }] });
    m.push({ role: 'user', content: [{ type: 'tool_result', tool_use_id: `t${i}`, content: '[]' }] });
  }
  return m;
}

test('кроки рахуються лише після останнього повідомлення людини', () => {
  assert.equal(stepsSinceHuman(conversation(0)), 0);
  assert.equal(stepsSinceHuman(conversation(4)), 4);
  const again = [...conversation(5), { role: 'assistant', content: 'Готово.' }, { role: 'user', content: 'А ще?' }];
  assert.equal(stepsSinceHuman(again), 0);
});

test('після 6 кроків модель не викликається', async () => {
  // нормальна відповідь (порожню модель сервер вважає «не впоралась» і піднімає рівень)
  const { d, calls, logs } = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const below = await handle(post({ messages: conversation(MAX_STEPS - 1) }), d);
  assert.equal(below.status, 200);
  assert.equal(calls.length, 1);
  const r = await handle(post({ messages: conversation(MAX_STEPS) }), d);
  assert.equal(r.status, 422);
  assert.deepEqual(await r.json(), { error: 'step_limit' });
  assert.equal(calls.length, 1);
  assert.match(logs.at(-1)!, /step_limit/);
});

test('неправильна розмова - 400 без виклику моделі', async () => {
  const bad = [
    {},
    { messages: [] },
    { messages: [{ role: 'assistant', content: 'привіт' }] },
    { messages: [{ role: 'user', content: 'a' }, { role: 'user', content: 'b' }] },
    { messages: [{ role: 'system', content: 'a' }] },
    { messages: [{ role: 'user', content: '' }] },
    { messages: [{ role: 'user', content: [{ text: 'без типу' }] }] },
  ];
  for (const b of bad) {
    const { d, calls } = deps(modelReply([]));
    const r = await handle(post(b), d);
    assert.equal(r.status, 400, JSON.stringify(b));
    assert.equal(calls.length, 0);
  }
});

test('перевантаження чи ліміт Anthropic - 503 «спробувати пізніше»; інша помилка - 502', async () => {
  for (const s of [429, 500, 529]) {
    const { d } = deps(() => new Response('{}', { status: s }));
    const r = await handle(post(hello), d);
    assert.equal(r.status, 503);
    assert.deepEqual(await r.json(), { error: 'busy', retry: true });
  }
  const { d } = deps(() => new Response('{}', { status: 400 }));
  assert.equal((await handle(post(hello), d)).status, 502);
});

test('немає зв\'язку з Anthropic - 503', async () => {
  const { d } = deps(() => {
    throw new TypeError('fetch failed');
  });
  assert.equal((await handle(post(hello), d)).status, 503);
});

test('журнал: лише числа - без тексту розмови і без ключа', async () => {
  const { d, logs } = deps(modelReply([{ type: 'text', text: 'Таємна відповідь' }]));
  await handle(post({ messages: [{ role: 'user', content: 'Таємне питання' }] }), d);
  assert.equal(logs.length, 1);
  const line = JSON.parse(logs[0]);
  assert.deepEqual(Object.keys(line).sort(), [
    'cache_creation_input_tokens', 'cache_read_input_tokens', 'effort', 'fn', 'input_tokens', 'messages', 'model', 'output_tokens', 'result', 'steps',
  ]);
  assert.equal(line.input_tokens, 120);
  assert.equal(line.cache_read_input_tokens, 900);
  assert.doesNotMatch(logs[0], /Таємн|sk-ant/);
});

test('без інструментів запит не містить tools', () => {
  const b = buildRequest('m', [{ role: 'user', content: 'x' }], 'sys', []) as Record<string, unknown>;
  assert.equal('tools' in b, false);
  assert.equal((b.system as any[])[0].cache_control.type, 'ephemeral');
});

test('лише POST', async () => {
  const { d } = deps(modelReply([]));
  const r = await handle(new Request('https://x/assistant', { headers: { [TEST_TOKEN_HEADER]: TOKEN } }), d);
  assert.equal(r.status, 405);
});

test('блоки міркувань із попередніх реплік прибираються (Ведмедик <-> Пасічник), поточного циклу - ні', async () => {
  const think = (sig: string) => ({ type: 'thinking', thinking: '', signature: sig });
  const messages: any[] = [
    { role: 'user', content: 'Привіт' },
    { role: 'assistant', content: [think('old-haiku'), { type: 'text', text: 'Добрий день' }] },
    { role: 'user', content: 'Скільки вуликів?' },
    { role: 'assistant', content: [think('old-2'), { type: 'tool_use', id: 't0', name: 'find_hives', input: {} }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't0', content: '[]' }] },
    { role: 'assistant', content: [think('old-3')] },
    { role: 'user', content: 'Відкрий склад' },
    { role: 'assistant', content: [think('current'), { type: 'tool_use', id: 't1', name: 'open_screen', input: { screen: 'stock' } }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't1', content: 'ok' }] },
  ];
  const out = stripOldThinking(messages);
  const sigs = JSON.stringify(out).match(/"signature":"[^"]+"/g);
  assert.deepEqual(sigs, ['"signature":"current"']);
  assert.equal(out[1].content[0].text, 'Добрий день');
  assert.equal(out[3].content[0].type, 'tool_use');
  assert.deepEqual(out[5].content, [{ type: 'text', text: '…' }]);
  assert.deepEqual(out[7], messages[7]);

  const { d, calls } = deps(modelReply([{ type: 'text', text: 'ok' }]));
  await handle(post({ messages: messages.slice(0, 7) }), d);
  assert.doesNotMatch(JSON.stringify(calls[0].body.messages), /old-haiku|old-2|old-3/);
});

// довга розмова: n питань людини, кожне - з одним інструментом і відповіддю
function longChat(n: number) {
  const m: any[] = [];
  for (let i = 0; i < n; i++) {
    m.push({ role: 'user', content: `Питання ${i}` });
    m.push({ role: 'assistant', content: [{ type: 'tool_use', id: `t${i}`, name: 'stock_list', input: {} }] });
    m.push({ role: 'user', content: [{ type: 'tool_result', tool_use_id: `t${i}`, content: '[]' }] });
    m.push({ role: 'assistant', content: [{ type: 'text', text: `Відповідь ${i}` }] });
  }
  m.push({ role: 'user', content: 'Останнє питання' });
  return m;
}

test('довга розмова не ламає помічника: моделі - хвіст від питання людини', async () => {
  const msgs = longChat(40); // 161 повідомлення
  const cut = trimHistory(msgs, 60);
  assert.ok(cut.length <= 60);
  assert.equal(cut[0].role, 'user');
  assert.equal(typeof cut[0].content, 'string'); // починається з питання, не з tool_result
  assert.equal(cut.at(-1).content, 'Останнє питання');
  assert.deepEqual(trimHistory(longChat(3)), longChat(3)); // коротку не чіпає

  const { d, calls, logs } = deps(modelReply([{ type: 'text', text: 'ok' }]));
  const r = await handle(post({ messages: msgs }), d);
  assert.equal(r.status, 200);
  assert.ok(calls[0].body.messages.length <= 60);
  const line = JSON.parse(logs.at(-1)!);
  assert.equal(line.trimmed_from, 161);
});

test('відмова застосунку - у журналі з причиною', async () => {
  const { d, logs } = deps(modelReply([]));
  const r = await handle(post({ messages: [{ role: 'assistant', content: 'x' }] }), d);
  assert.equal(r.status, 400);
  const line = JSON.parse(logs.at(-1)!);
  assert.equal(line.result, 'rejected');
  assert.equal(line.error, 'order');
});
