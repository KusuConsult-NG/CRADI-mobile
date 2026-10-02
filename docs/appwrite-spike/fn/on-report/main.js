/** Stands in for the AFTER triggers: reports_after_insert and friends. */
export default async ({ req, res, log }) => {
  const evt = req.headers['x-appwrite-event'] ?? '(none)';
  let doc = {}; try { doc = JSON.parse(req.bodyRaw || '{}'); } catch {}
  log(`EVENT ${evt} doc=${doc.$id ?? '?'} ward=${doc.ward ?? '?'} status=${doc.status ?? '?'}`);
  return res.json({ saw: evt, id: doc.$id ?? null });
};
