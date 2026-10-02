export default async ({ req, res, log }) => {
  log('entered');
  const out = { env: { ep: process.env.APPWRITE_ENDPOINT ?? null, proj: process.env.APPWRITE_PROJECT ?? null, hasKey: Boolean(process.env.APPWRITE_API_KEY) } };
  try {
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), 6000);
    const r = await fetch(`${process.env.APPWRITE_ENDPOINT}/health/version`, { signal: c.signal, headers: { 'x-appwrite-project': process.env.APPWRITE_PROJECT, 'x-appwrite-key': process.env.APPWRITE_API_KEY } });
    clearTimeout(t);
    out.fetch = { status: r.status, body: (await r.text()).slice(0, 80) };
  } catch (e) { out.fetch = { error: String(e).slice(0, 120) }; }
  log('leaving');
  return res.json(out);
};
