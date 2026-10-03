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
  // Seeded rows get a `$createdAt` of now unless the fixture sets one.
  // The real server always has one, and the sweeps filter on it: a row
  // without it matches no window, which made the reconcile test pass
  // against an empty result for a while.
  const now = new Date().toISOString();
  const store = structuredClone(rows);
  for (const table of Object.values(store)) {
    for (const seeded of Object.values(table ?? {})) {
      if (seeded && typeof seeded === 'object') {
        seeded.$createdAt ??= now;
        seeded.$updatedAt ??= now;
      }
    }
  }
  const sentMessages = {};

  globalThis.fetch = async (url, init = {}) => {
    const path = String(url).slice(ENDPOINT.length);
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(init.body) : undefined;
    calls.push({ path, method, body });

    // `fail` keys are path substrings, optionally prefixed with a method
    // — `'PATCH /tables/reports/rows/r1'` — because a read and a write
    // of the same row share a path, and failing both when the test meant
    // one of them is a different test from the one that was written.
    for (const [pattern, response] of Object.entries(fail)) {
      const [verb, rest] = pattern.includes(' ') ? pattern.split(/ +/, 2) : [null, pattern];
      if (verb && verb !== method) continue;
      if (path.includes(rest)) return json(response.status, response.body);
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
        // Queries are honoured, because a fake that answers every list
        // with every row makes the test that counts a report's
        // confirmations count the whole table and pass for the wrong
        // reason. `total` ignores limit/offset, as the real server's
        // does — the confirmation count reads exactly that.
        const queries = [...new URLSearchParams(String(url).split('?')[1] ?? '')]
          .filter(([key]) => key.startsWith('queries'))
          .map(([, value]) => JSON.parse(value));
        let rows = Object.entries(store[table])
          .filter(([key, value]) => queries.every((q) => matches(q, key, value)))
          .map(([, value]) => value);
        const total = rows.length;
        for (const q of queries) {
          if (q.method === 'orderAsc') rows = sortBy(rows, q.attribute, 1);
          if (q.method === 'orderDesc') rows = sortBy(rows, q.attribute, -1);
        }
        const offset = queries.find((q) => q.method === 'offset')?.values[0] ?? 0;
        const limit = queries.find((q) => q.method === 'limit')?.values[0] ?? 25;
        return json(200, { total, rows: rows.slice(offset, offset + limit) });
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
        const hit = Object.entries(store[table]).filter(([key, value]) =>
          (body.queries ?? []).every((raw) =>
            matches(typeof raw === 'string' ? JSON.parse(raw) : raw, key, value),
          ),
        );
        for (const [key, value] of hit) {
          store[table][key] = stamp(key, { ...value, ...body.data });
        }
        return json(200, {
          total: hit.length,
          rows: hit.map(([key]) => store[table][key]),
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

/** Whether one Appwrite query matches a stored row. */
function matches(q, key, value) {
  const actual = q.attribute === '$id' ? key : value[q.attribute];
  switch (q.method) {
    case 'equal':
      return q.values.includes(actual);
    case 'notEqual':
      return !q.values.includes(actual);
    case 'isNull':
      return actual === null || actual === undefined;
    case 'isNotNull':
      return actual !== null && actual !== undefined;
    case 'lessThan':
      return actual < q.values[0];
    case 'lessThanEqual':
      return actual <= q.values[0];
    case 'greaterThan':
      return actual > q.values[0];
    case 'greaterThanEqual':
      return actual >= q.values[0];
    case 'limit':
    case 'offset':
    case 'orderAsc':
    case 'orderDesc':
      return true;
    default:
      // Louder than ignoring it: an unsupported query that silently
      // matches everything turns a filtered read into an unfiltered one
      // while the test still passes.
      throw new Error(`fake: unsupported query ${q.method}`);
  }
}

function sortBy(rows, attribute, direction) {
  return [...rows].sort((a, b) => {
    const x = a[attribute];
    const y = b[attribute];
    if (x === y) return 0;
    return (x > y ? 1 : -1) * direction;
  });
}

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
export function context(body, { userId = 'u1', path = '/', event = null } = {}) {
  const captured = {};
  const logs = [];
  return {
    captured,
    /** What the Function logged, for the warnings it must not swallow. */
    logs,
    req: {
      bodyRaw: JSON.stringify(body),
      path,
      headers: {
        ...(userId ? { 'x-appwrite-user-id': userId } : {}),
        // Set by Appwrite only for an event delivery; `worker.js` routes
        // on its presence.
        ...(event ? { 'x-appwrite-event': event } : {}),
      },
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
