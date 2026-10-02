/**
 * The guarded report write, as a Function.
 *
 * This is what replaces `reports_insert`'s WITH CHECK and the
 * `reports_before_insert` trigger. The collection is closed to clients, so
 * this is the only way a report is created — which is the whole point: a
 * client cannot set status, verification_count or escalated itself.
 */
const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT;
const KEY = process.env.APPWRITE_API_KEY;

const api = async (path, init = {}) => {
  const r = await fetch(`${EP}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY, ...(init.headers ?? {}) },
  });
  return { status: r.status, body: await r.json().catch(() => null) };
};

const wardTeam = (state, lga, ward) =>
  `ward-${[state, lga, ward].map((p) => String(p).toLowerCase().replace(/[^a-z0-9]+/g, '-')).join('-')}`;

export default async ({ req, res, log, error }) => {
  let payload;
  try { payload = JSON.parse(req.bodyRaw || '{}'); } catch { return res.json({ error: 'bad json' }, 400); }

  const userId = req.headers['x-appwrite-user-id'] || payload.userId;
  if (!userId) return res.json({ error: 'unauthenticated' }, 401);

  // is_enabled_user(): the profile decides, never the client.
  const prof = await api(`/databases/cradi/collections/profiles/documents/${userId}`);
  if (prof.status !== 200) return res.json({ error: 'no profile' }, 403);
  if (prof.body.is_disabled) return res.json({ error: 'account disabled' }, 403);

  const { hazard_type, description, state, lga, ward } = payload;
  if (!hazard_type || !state || !lga || !ward) return res.json({ error: 'missing fields' }, 400);

  // The WITH CHECK, enforced here because Appwrite cannot: the client does
  // not get to choose any of these.
  const doc = {
    user_id: userId, hazard_type, title: payload.title ?? hazard_type,
    description: description ?? '',
    state, lga, ward,
    status: 'pending', verification_count: 0, escalated: false,
  };

  const team = wardTeam(state, lga, ward);
  const created = await api('/databases/cradi/collections/reports/documents', {
    method: 'POST',
    body: JSON.stringify({
      documentId: 'unique()',
      data: doc,
      permissions: [`read("user:${userId}")`, `read("team:${team}")`, 'read("label:ewv")'],
    }),
  });
  if (created.status >= 400) { error(JSON.stringify(created.body)); return res.json({ error: 'create failed', detail: created.body?.message }, 500); }
  log(`report ${created.body.$id} stamped for ${team}`);
  return res.json({ id: created.body.$id, team, status: created.body.status }, 201);
};
