/**
 * A fake Appwrite API, so the Functions can be tested without one.
 *
 * Every call these Functions make goes through one `fetch` in
 * `lib/appwrite.js`, so stubbing that is enough to exercise the whole
 * handler — including the parts that matter most, which are the ones that
 * decide what the server stores regardless of what the client sent.
 */
const ENDPOINT = 'https://test.appwrite.local/v1';
process.env.APPWRITE_ENDPOINT = ENDPOINT;
process.env.APPWRITE_FUNCTION_API_ENDPOINT = ENDPOINT;
process.env.APPWRITE_PROJECT = 'test';
process.env.APPWRITE_FUNCTION_PROJECT_ID = 'test';
process.env.APPWRITE_API_KEY = 'test-key';
process.env.APPWRITE_DATABASE_ID = 'cradi';

export function fakeAppwrite({ rows = {}, users = [], fail = {} } = {}) {
  const calls = [];
  const store = structuredClone(rows);
  const sentMessages = {};

  globalThis.fetch = async (url, init = {}) => {
    const path = String(url).slice(ENDPOINT.length);
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(init.body) : undefined;
    calls.push({ path, method, body });

    for (const [pattern, response] of Object.entries(fail)) {
      if (path.includes(pattern)) return json(response.status, response.body);
    }

    // rows: /tablesdb/{db}/tables/{table}/rows[/{id}]
    const row = path.match(/^\/tablesdb\/[^/]+\/tables\/([^/?]+)\/rows(?:\/([^/?]+))?/);
    if (row) {
      const [, table, id] = row;
      store[table] ??= {};
      if (method === 'GET' && id) {
        const found = store[table][decodeURIComponent(id)];
        return found
          ? json(200, found)
          : json(404, { message: 'not found', type: 'document_not_found' });
      }
      if (method === 'GET') {
        const all = Object.values(store[table]);
        return json(200, { total: all.length, rows: all });
      }
      if (method === 'POST') {
        const key = body.rowId === 'unique()' ? `gen-${Object.keys(store[table]).length}` : body.rowId;
        if (store[table][key]) {
          return json(409, { message: 'exists', type: 'document_already_exists' });
        }
        store[table][key] = stamp(key, body.data, body.permissions);
        return json(201, store[table][key]);
      }
      // Bulk PATCH: `{ queries, data }` with no id, which is the atomic
      // compare-and-set `write.js` uses for `expect`. A fake that ignored
      // the queries and updated everything would make every
      // optimistic-lock test vacuous — and is exactly what the real
      // server does when the queries are put in the query string.
      if (method === 'PATCH' && !id) {
        const matches = Object.entries(store[table]).filter(([key, value]) =>
          (body.queries ?? []).every((raw) => {
            const q = typeof raw === 'string' ? JSON.parse(raw) : raw;
            const actual = q.attribute === '$id' ? key : value[q.attribute];
            if (q.method === 'isNull') return actual === null || actual === undefined;
            if (q.method === 'equal') return q.values.includes(actual);
            throw new Error(`fake: unsupported bulk query ${q.method}`);
          }),
        );
        for (const [key, value] of matches) {
          store[table][key] = stamp(key, { ...value, ...body.data });
        }
        return json(200, {
          total: matches.length,
          rows: matches.map(([key]) => store[table][key]),
        });
      }
      if (method === 'PUT' || method === 'PATCH') {
        const key = decodeURIComponent(id);
        const base = store[table][key];
        if (!base && method === 'PATCH') {
          return json(404, { message: 'not found', type: 'document_not_found' });
        }
        store[table][key] = stamp(key, { ...(base ?? {}), ...body.data }, body.permissions);
        return json(200, store[table][key]);
      }
      if (method === 'DELETE') {
        const key = decodeURIComponent(id);
        if (!store[table][key]) return json(404, { message: 'not found' });
        delete store[table][key];
        return json(204, null);
      }
    }

    if (path.startsWith('/users?')) {
      const wanted = decodeURIComponent(path).match(/"values":\["([^"]+)"\]/)?.[1];
      return json(200, { users: users.filter((u) => u.email === wanted) });
    }
    if (path === '/users' && method === 'POST') {
      if (users.some((u) => u.email === body.email)) {
        return json(409, { message: 'exists', type: 'user_already_exists' });
      }
      const user = { $id: `u-${users.length + 1}`, email: body.email, name: body.name };
      users.push(user);
      return json(201, user);
    }
    const tokens = path.match(/^\/users\/([^/]+)\/tokens$/);
    if (tokens) {
      if (method === 'GET') return json(200, { tokens: [] });
      return json(201, { secret: '251152', userId: tokens[1] });
    }
    const labels = path.match(/^\/users\/([^/]+)\/labels$/);
    if (labels && method === 'PUT') {
      const id = decodeURIComponent(labels[1]);
      const user = users.find((u) => u.$id === id) ?? { $id: id };
      if (!users.includes(user)) users.push(user);
      user.labels = body.labels;
      return json(200, user);
    }
    if (/^\/users\/[^/]+\/verification$/.test(path)) return json(200, {});
    if (/^\/users\/[^/]+\/password$/.test(path)) return json(200, {});
    if (path === '/account/sessions/token') {
      return json(201, { $id: 's1', secret: 'session-secret', userId: body.userId });
    }
    const message = path.match(/^\/messaging\/messages\/(email|push)$/);
    if (message) {
      // Appwrite refuses a duplicate messageId with 409, and that refusal
      // is what the whole drain design uses instead of a lock. A fake
      // that always accepted would make every idempotency test vacuous.
      sentMessages[body.messageId] ??= 0;
      if (sentMessages[body.messageId] > 0) {
        return json(409, { message: 'exists', type: 'document_already_exists' });
      }
      sentMessages[body.messageId] += 1;
      return json(201, { $id: body.messageId });
    }
    if (path.startsWith('/teams/')) return json(200, { $id: path.split('/')[2] });
    if (path === '/teams') return json(201, { $id: body.teamId });

    return json(404, { message: `unstubbed ${method} ${path}` });
  };

  return { calls, store, users, sentMessages };
}

const stamp = (id, data, permissions) => ({
  $id: id,
  $createdAt: '2026-10-02T00:00:00.000+00:00',
  $updatedAt: '2026-10-02T00:00:00.000+00:00',
  ...(permissions ? { $permissions: permissions } : {}),
  ...data,
});

const json = (status, body) =>
  // `null`, not `''`: a 204 may not carry a body at all and `Response`
  // throws if given one. Appwrite really does answer 204 to a delete, so
  // the harness says 204 too rather than smoothing it to 200 — code that
  // tested for an exact status would otherwise pass here and fail live.
  new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: body === null ? {} : { 'content-type': 'application/json' },
  });

/** The `{req, res, log, error}` an Appwrite Function is called with. */
export function context(body, { userId = 'u1', path = '/' } = {}) {
  const captured = {};
  const logs = [];
  return {
    captured,
    /** What the Function logged, for the warnings it must not swallow. */
    logs,
    req: {
      bodyRaw: JSON.stringify(body),
      path,
      headers: userId ? { 'x-appwrite-user-id': userId } : {},
    },
    res: {
      json: (payload, status = 200) => {
        captured.status = status;
        captured.body = payload;
        return { payload, status };
      },
    },
    log: (m) => {
      logs.push(String(m));
    },
    error: (m) => {
      captured.error = m;
    },
  };
}

export const profile = (over = {}) => ({
  $id: 'u1',
  name: 'Amina',
  role: 'user',
  isApproved: true,
  isDisabled: false,
  ...over,
});
