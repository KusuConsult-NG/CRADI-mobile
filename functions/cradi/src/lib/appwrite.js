/**
 * The Appwrite REST API, over `fetch`, with a server key.
 *
 * Deliberately not the Node SDK. Phase 4 measured a 735 ms cold start on
 * an idle box with no network in the way, and on a quiet night in a quiet
 * ward the first report of the morning pays it. Every dependency added
 * here is paid again on every cold start, and these Functions need
 * perhaps a dozen endpoints.
 */

// Read per call, not at module load. Appwrite injects
// APPWRITE_FUNCTION_API_ENDPOINT and APPWRITE_FUNCTION_PROJECT_ID into the
// runtime; capturing them in a top-level const also makes the module
// untestable, because the import is evaluated before any test can set
// them.
/**
 * An explicitly set `APPWRITE_ENDPOINT` wins over Appwrite's injected
 * `APPWRITE_FUNCTION_API_ENDPOINT`.
 *
 * That order looks backwards and is not. Appwrite injects the project's
 * **public** endpoint — `https://localhost/v1` on a self-hosted stack,
 * built from `_APP_DOMAIN` — and a Function runs in a container on the
 * runtimes network, where that name does not resolve and port 443 is
 * nothing. Every call failed with `connect ECONNREFUSED 127.0.0.1:443`.
 *
 * Overriding the injected variable does not work: Appwrite reserves the
 * name and sets it after any Function variable of the same name. So the
 * override has to be a different variable, and it has to take
 * precedence. On Cloud nothing sets `APPWRITE_ENDPOINT` and the injected
 * value is used, which is correct there.
 */
const endpoint = () =>
  process.env.APPWRITE_ENDPOINT ?? process.env.APPWRITE_FUNCTION_API_ENDPOINT;
const project = () =>
  process.env.APPWRITE_FUNCTION_PROJECT_ID ?? process.env.APPWRITE_PROJECT;

export const databaseId = () => process.env.APPWRITE_DATABASE_ID ?? 'cradi';

/** One API call. Never throws on a 4xx — the caller decides. */
export async function api(path, { method = 'GET', body, headers } = {}) {
  const url = `${endpoint()}${path}`;
  let response;
  try {
    response = await fetch(url, {
      method,
      headers: {
        'content-type': 'application/json',
        'x-appwrite-project': project(),
        'x-appwrite-key': process.env.APPWRITE_API_KEY,
        ...(headers ?? {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  } catch (cause) {
    // `fetch` throws a bare "TypeError: fetch failed" with no URL, which
    // in a Function's error log is indistinguishable between a wrong
    // endpoint, a DNS failure and a dead API. Naming the URL turns a
    // whole debugging session into one line.
    const e = new Error(`${method} ${url} did not complete: ${cause?.cause?.message ?? cause?.message ?? cause}`);
    e.cause = cause;
    throw e;
  }
  const text = await response.text();
  let parsed = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { message: text };
    }
  }
  return { status: response.status, body: parsed, ok: response.ok };
}

/** As [api], but a non-2xx becomes an [ApiError]. */
export async function apiOrThrow(path, init) {
  const result = await api(path, init);
  if (!result.ok) throw new ApiError(result);
  return result.body;
}

export class ApiError extends Error {
  constructor({ status, body }) {
    super(body?.message ?? `Appwrite answered ${status}`);
    this.status = status;
    this.type = body?.type ?? null;
    this.body = body;
  }
}

// ───────────────────────────── rows ─────────────────────────────────────
//
// `/tablesdb/...`, not `/databases/.../collections/...`: the document API
// is deprecated as of Appwrite 1.8 and the client SDK uses TablesDB. The
// spike ran against 1.6.2, which has neither — these will not run against
// it.

const rowsPath = (table) => `/tablesdb/${databaseId()}/tables/${table}/rows`;

export const getRow = (table, rowId) =>
  api(`${rowsPath(table)}/${encodeURIComponent(rowId)}`);

export const listRows = (table, queries = []) =>
  api(
    `${rowsPath(table)}?${queries
      .map((query) => `queries[]=${encodeURIComponent(query)}`)
      .join('&')}`,
  );

/** As [listRows], but throws rather than letting a failure read as "none". */
export async function listRowsOrThrow(table, queries = []) {
  const result = await listRows(table, queries);
  if (!result.ok) throw new ApiError(result);
  return result.body?.rows ?? [];
}

export const createRow = (table, rowId, data, permissions) =>
  api(rowsPath(table), {
    method: 'POST',
    body: { rowId, data, ...(permissions ? { permissions } : {}) },
  });

export const upsertRow = (table, rowId, data, permissions) =>
  api(`${rowsPath(table)}/${encodeURIComponent(rowId)}`, {
    method: 'PUT',
    body: { data, ...(permissions ? { permissions } : {}) },
  });

export const updateRow = (table, rowId, data, permissions) =>
  api(`${rowsPath(table)}/${encodeURIComponent(rowId)}`, {
    method: 'PATCH',
    body: { data, ...(permissions ? { permissions } : {}) },
  });

/**
 * Updates the row only while [queries] still match it, and reports how
 * many rows that was.
 *
 * The atomic compare-and-set a Postgres `WHERE` clause gave us, which
 * `updateRow` cannot do: an admin deciding a report must not overwrite a
 * decision somebody else made while the page was open.
 *
 * The queries go in the **body**. Passed as `?queries[]=` they are
 * silently ignored and *every row in the table* is updated — measured on
 * 1.9.6, and the kind of mistake that is invisible until it is a
 * disaster.
 */
export const updateRowsWhere = (table, queries, data) =>
  api(rowsPath(table), { method: 'PATCH', body: { queries, data } });

export const deleteRow = (table, rowId) =>
  api(`${rowsPath(table)}/${encodeURIComponent(rowId)}`, { method: 'DELETE' });

// ───────────────────────────── queries ──────────────────────────────────

const q = (method, attribute, values) =>
  JSON.stringify({ method, ...(attribute ? { attribute } : {}), values });

export const Query = {
  equal: (attribute, values) => q('equal', attribute, [].concat(values)),
  notEqual: (attribute, value) => q('notEqual', attribute, [value]),
  lessThan: (attribute, value) => q('lessThan', attribute, [value]),
  lessThanEqual: (attribute, value) => q('lessThanEqual', attribute, [value]),
  greaterThan: (attribute, value) => q('greaterThan', attribute, [value]),
  greaterThanEqual: (attribute, value) => q('greaterThanEqual', attribute, [value]),
  isNull: (attribute) => q('isNull', attribute, []),
  isNotNull: (attribute) => q('isNotNull', attribute, []),
  orderAsc: (attribute) => q('orderAsc', attribute, []),
  orderDesc: (attribute) => q('orderDesc', attribute, []),
  limit: (value) => q('limit', null, [value]),
  offset: (value) => q('offset', null, [value]),
};

// ───────────────────────────── teams ────────────────────────────────────

/**
 * The ward team id, which is also the ACL subject every ward-scoped
 * document names.
 *
 * Phase 0's finding rests on this being a pure function of the three
 * names: a document's ACL names the *team*, so moving an agent between
 * wards is a membership change and not a rewrite of every document they
 * can see. It must match `migrate/migrate.mjs`'s `wardTeam` exactly or the
 * migrated documents point at teams nobody is in.
 */
export function wardTeam(state, lga, ward) {
  const slug = [state, lga, ward]
    .map((part) => String(part ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-'))
    .join('-');
  const id = `ward-${slug}`;
  if (id.length <= MAX_ID) return id;
  // 35 of the 584 wards overflow, up to 50 characters —
  // `ward-plateau-langtang-north-langtang-north-central` is the worst.
  // Appwrite rejects those outright, so Phase 0's plain slug would have
  // failed for 6% of the country and only once a report was filed there.
  //
  // Keep as much of the slug as fits beside a digest of the whole thing:
  // 'ward-' + 14 + '-' + 16 = 36. The short ids stay exactly as Phase 0
  // verified them, so nothing already designed around them moves.
  const head = slug.slice(0, 14).replace(/-+$/, '');
  return `ward-${head}-${fnv1a64(slug)}`;
}

/** Appwrite's limit for a team, document or file id. */
export const MAX_ID = 36;

/**
 * FNV-1a, 64 bit, as 16 hex characters.
 *
 * Not a security hash and does not need to be: it distinguishes names we
 * generate ourselves. Written out rather than taking a dependency, which
 * would be paid again on every cold start.
 */
export function fnv1a64(input) {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (const byte of new TextEncoder().encode(input)) {
    hash = ((hash ^ BigInt(byte)) * prime) & mask;
  }
  return hash.toString(16).padStart(16, '0');
}

/** Creates the ward team if it is not there yet, and returns its id. */
export async function ensureWardTeam(state, lga, ward) {
  const teamId = wardTeam(state, lga, ward);
  const existing = await api(`/teams/${teamId}`);
  if (existing.ok) return teamId;
  const created = await api('/teams', {
    method: 'POST',
    body: { teamId, name: `${ward}, ${lga}, ${state}` },
  });
  // A concurrent write may have created it between the two calls.
  if (!created.ok && created.status !== 409) throw new ApiError(created);
  return teamId;
}
