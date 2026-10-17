// Сховище відгуків: інтерфейс, версія в пам'яті (тести) і версія для
// Supabase (PostgREST зі службовим ключем).

export type Thread = {
  id: string;
  device_id: string;
  secret_hash: string;
  platform: string | null;
  created_at: string;
  last_at: string;
  dev_unread: boolean;
};

export type Message = { seq: number; id: string; thread_id: string; from_dev: boolean; body: string; created_at: string };

export interface Store {
  threadByDevice(deviceId: string): Promise<Thread | null>;
  threadById(id: string): Promise<Thread | null>;
  createThread(deviceId: string, secretHash: string, platform: string | null): Promise<Thread>;
  addMessage(threadId: string, fromDev: boolean, body: string): Promise<Message>;
  messages(threadId: string, afterSeq?: number): Promise<Message[]>;
  /** Скільки повідомлень людини за останню добу (ліміт). */
  userMessagesSince(threadId: string, sinceIso: string): Promise<number>;
  setDevUnread(threadId: string, unread: boolean): Promise<void>;
  /** Усі треди, від новіших, з останнім повідомленням. */
  threads(): Promise<(Thread & { last: Message | null })[]>;
}

export class MemoryStore implements Store {
  threadsList: Thread[] = [];
  msgs: Message[] = [];
  private n = 0;
  private clock = () => new Date().toISOString();
  constructor(clock?: () => string) {
    if (clock) this.clock = clock;
  }
  async threadByDevice(d: string) {
    return this.threadsList.find((t) => t.device_id === d) ?? null;
  }
  async threadById(id: string) {
    return this.threadsList.find((t) => t.id === id) ?? null;
  }
  async createThread(deviceId: string, secretHash: string, platform: string | null) {
    const t: Thread = {
      id: crypto.randomUUID(), device_id: deviceId, secret_hash: secretHash, platform,
      created_at: this.clock(), last_at: this.clock(), dev_unread: true,
    };
    this.threadsList.push(t);
    return t;
  }
  async addMessage(threadId: string, fromDev: boolean, body: string) {
    const m: Message = { seq: ++this.n, id: crypto.randomUUID(), thread_id: threadId, from_dev: fromDev, body, created_at: this.clock() };
    this.msgs.push(m);
    const t = this.threadsList.find((x) => x.id === threadId)!;
    t.last_at = m.created_at;
    if (!fromDev) t.dev_unread = true;
    return m;
  }
  async messages(threadId: string, afterSeq = 0) {
    return this.msgs.filter((m) => m.thread_id === threadId && m.seq > afterSeq);
  }
  async userMessagesSince(threadId: string, sinceIso: string) {
    return this.msgs.filter((m) => m.thread_id === threadId && !m.from_dev && m.created_at >= sinceIso).length;
  }
  async setDevUnread(threadId: string, unread: boolean) {
    const t = this.threadsList.find((x) => x.id === threadId);
    if (t) t.dev_unread = unread;
  }
  async threads() {
    return [...this.threadsList]
      .sort((a, b) => b.last_at.localeCompare(a.last_at))
      .map((t) => ({ ...t, last: [...this.msgs].reverse().find((m) => m.thread_id === t.id) ?? null }));
  }
}

/** PostgREST: SUPABASE_URL/rest/v1 зі службовим ключем. */
export class RestStore implements Store {
  // (без «параметрів-полів» у конструкторі: Node у режимі зняття типів
  // їх не розуміє, а цей файл перевіряють тести на Node)
  private url: string;
  private key: string;
  private fetchFn: typeof fetch;
  constructor(url: string, key: string, fetchFn: typeof fetch = fetch) {
    this.url = url;
    this.key = key;
    this.fetchFn = fetchFn;
  }

  private async call(path: string, init: RequestInit = {}) {
    const res = await this.fetchFn(`${this.url}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: this.key,
        Authorization: `Bearer ${this.key}`,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
        ...(init.headers ?? {}),
      },
    });
    if (!res.ok) throw new Error(`db ${res.status}`);
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  async threadByDevice(d: string) {
    const r = await this.call(`feedback_threads?device_id=eq.${encodeURIComponent(d)}&limit=1`);
    return r[0] ?? null;
  }
  async threadById(id: string) {
    const r = await this.call(`feedback_threads?id=eq.${encodeURIComponent(id)}&limit=1`);
    return r[0] ?? null;
  }
  async createThread(deviceId: string, secretHash: string, platform: string | null) {
    const r = await this.call('feedback_threads', {
      method: 'POST',
      body: JSON.stringify({ device_id: deviceId, secret_hash: secretHash, platform }),
    });
    return r[0];
  }
  async addMessage(threadId: string, fromDev: boolean, body: string) {
    const r = await this.call('feedback_messages', {
      method: 'POST',
      body: JSON.stringify({ thread_id: threadId, from_dev: fromDev, body }),
    });
    await this.call(`feedback_threads?id=eq.${encodeURIComponent(threadId)}`, {
      method: 'PATCH',
      body: JSON.stringify({ last_at: new Date().toISOString(), ...(fromDev ? {} : { dev_unread: true }) }),
    });
    return r[0];
  }
  async messages(threadId: string, afterSeq = 0) {
    return await this.call(
      `feedback_messages?thread_id=eq.${encodeURIComponent(threadId)}&seq=gt.${afterSeq}&order=seq.asc&limit=500`,
    );
  }
  async userMessagesSince(threadId: string, sinceIso: string) {
    const r = await this.call(
      `feedback_messages?select=seq&thread_id=eq.${encodeURIComponent(threadId)}&from_dev=eq.false&created_at=gte.${encodeURIComponent(sinceIso)}`,
    );
    return r.length;
  }
  async setDevUnread(threadId: string, unread: boolean) {
    await this.call(`feedback_threads?id=eq.${encodeURIComponent(threadId)}`, {
      method: 'PATCH',
      body: JSON.stringify({ dev_unread: unread }),
    });
  }
  async threads() {
    const ts: Thread[] = await this.call('feedback_threads?order=last_at.desc&limit=200');
    const out = [];
    for (const t of ts) {
      const m = await this.call(`feedback_messages?thread_id=eq.${t.id}&order=seq.desc&limit=1`);
      out.push({ ...t, last: (m[0] ?? null) as Message | null });
    }
    return out;
  }
}
